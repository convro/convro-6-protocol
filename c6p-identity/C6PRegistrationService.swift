//
//  C6PRegistrationService.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Production registration orchestrator for Convro/C6P.
//
//  UI flow (v1):
//   1) check/reserve @username (optional alias)
//   2) first/last name (optional)
//   3) avatar selection (backend mediaId ref)
//   4) create local device identity (Keychain) + request VN (+99######)
//   5) finalize account -> persist account identity in Keychain
//
//  Security:
//   - device private keys generated locally & stored in Keychain
//   - backend receives public keys only
//

import Foundation
import CryptoKit

// MARK: - Errors

public enum C6PRegistrationError: Error, CustomStringConvertible {
    case onboardingAlreadyCompleted
    case onboardingNotCompleted
    case virtualNumberNotAssigned
    case deviceIdentityMissing
    case apiReturnedInvalidData(String)

    public var description: String {
        switch self {
        case .onboardingAlreadyCompleted:
            return "C6PRegistrationError.onboardingAlreadyCompleted"
        case .onboardingNotCompleted:
            return "C6PRegistrationError.onboardingNotCompleted"
        case .virtualNumberNotAssigned:
            return "C6PRegistrationError.virtualNumberNotAssigned"
        case .deviceIdentityMissing:
            return "C6PRegistrationError.deviceIdentityMissing"
        case .apiReturnedInvalidData(let msg):
            return "C6PRegistrationError.apiReturnedInvalidData(\(msg))"
        }
    }
}

// MARK: - Identity API Client (transport abstraction)

public protocol C6PIdentityAPIClient {
    // Username
    func checkUsernameAvailability(_ req: C6PUsernameCheckRequest) async throws -> C6PUsernameCheckResponse
    func reserveUsername(_ req: C6PUsernameReserveRequest) async throws -> C6PUsernameReserveResponse

    // VN assignment
    func assignVirtualNumber(_ req: C6PAssignVirtualNumberRequest) async throws -> C6PAssignVirtualNumberResponse

    // Final account creation
    func createAccount(_ req: C6PCreateAccountRequest) async throws -> C6PCreateAccountResponse

    // Optional
    func registerDevice(_ req: C6PRegisterDeviceRequest) async throws -> C6PRegisterDeviceResponse
}

// MARK: - Registration Draft (in-memory v1)

public struct C6PRegistrationDraft: Sendable {
    // Step 1: username
    public var username: C6PUsernameHandle?
    public var usernameReservationToken: String?

    // Step 2: name (raw; validated when building request)
    public var firstName: String?
    public var lastName: String?

    // Step 3: avatar
    public var avatar: C6PAvatarContractRef = .none

    // Step 4: VN assigned
    public var virtualNumber: C6PVirtualNumberString?

    // Device context (metadata only)
    public var deviceName: String?
    public var platform: String?
    public var appVersion: String?

    // Derived
    public var localDeviceId: C6PDeviceId?

    public init() {}
}

// MARK: - Registration Service

public actor C6PRegistrationService {

    // MARK: Dependencies
    private let api: C6PIdentityAPIClient
    private let keychain: C6PIdentityKeychainStore

    // MARK: State
    private var draft = C6PRegistrationDraft()

    // MARK: Init
    public init(apiClient: C6PIdentityAPIClient, keychainStore: C6PIdentityKeychainStore) {
        self.api = apiClient
        self.keychain = keychainStore
    }

    // MARK: - Draft
    public func currentDraft() -> C6PRegistrationDraft { draft }

    public func resetDraft() { draft = C6PRegistrationDraft() }

    // MARK: - Completion guard
    public func isOnboardingCompleted() -> Bool {
        do {
            _ = try keychain.loadAccountIdentity()
            return true
        } catch let e as C6PIdentityKeychainStoreError {
            if case .notFound = e { return false }
            return false
        } catch {
            return false
        }
    }

    private func assertOnboardingNotCompleted() throws {
        if isOnboardingCompleted() {
            throw C6PRegistrationError.onboardingAlreadyCompleted
        }
    }

    // MARK: - Step 1: Username

    public func checkUsername(_ raw: String) async throws -> C6PUsernameCheckResponse {
        try assertOnboardingNotCompleted()
        let handle = try C6PUsernameHandle(Self.normalizeUsername(raw))
        return try await api.checkUsernameAvailability(C6PUsernameCheckRequest(username: handle))
    }

    public func reserveUsername(_ raw: String) async throws -> C6PUsernameReserveResponse {
        try assertOnboardingNotCompleted()
        let handle = try C6PUsernameHandle(Self.normalizeUsername(raw))
        let resp = try await api.reserveUsername(C6PUsernameReserveRequest(username: handle))

        if resp.reserved {
            draft.username = handle
            draft.usernameReservationToken = resp.reservationToken
        } else {
            draft.username = nil
            draft.usernameReservationToken = nil
        }
        return resp
    }

    public func skipUsername() throws {
        try assertOnboardingNotCompleted()
        draft.username = nil
        draft.usernameReservationToken = nil
    }

    private static func normalizeUsername(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("@") { return String(t.dropFirst()) }
        return t
    }

    // MARK: - Step 2: Name

    public func setProfileName(firstName: String?, lastName: String?) throws {
        try assertOnboardingNotCompleted()
        draft.firstName = firstName
        draft.lastName = lastName
    }

    private func buildProfileName() throws -> C6PProfileName {
        // validates + trims per contract rules
        return try C6PProfileName(firstName: draft.firstName, lastName: draft.lastName)
    }

    // MARK: - Step 3: Avatar

    public func setAvatarNone() throws {
        try assertOnboardingNotCompleted()
        draft.avatar = .none
    }

    public func setAvatarMediaId(_ mediaId: String) throws {
        try assertOnboardingNotCompleted()
        let trimmed = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 256 else {
            throw C6PIdentityContractError.invalidAvatarReference
        }
        draft.avatar = .mediaId(trimmed)
    }

    // MARK: - Step 4: Device identity (local) + VN assignment

    /// Ensures local device identity exists in Keychain and activeDeviceId is set.
    /// Returns active deviceId.
    public func ensureLocalDeviceIdentity(
        deviceName: String?,
        platform: String?,
        appVersion: String?
    ) throws -> C6PDeviceId {
        try assertOnboardingNotCompleted()

        draft.deviceName = deviceName
        draft.platform = platform
        draft.appVersion = appVersion

        // If active device exists, identity MUST exist
        if let active = try? keychain.loadActiveDeviceId() {
            _ = try keychain.loadDeviceIdentity(deviceId: active) // throws if missing
            draft.localDeviceId = active
            return active
        }

        // Create fresh device identity
        let newDeviceId = try C6PDeviceId.random()
        let identity = C6PDeviceIdentity.generate(deviceId: newDeviceId)

        try keychain.saveDeviceIdentity(identity)
        try keychain.saveActiveDeviceId(newDeviceId)

        draft.localDeviceId = newDeviceId
        return newDeviceId
    }

    /// Requests VN from backend (server authoritative) after local device identity exists.
    public func assignVirtualNumber() async throws -> C6PAssignVirtualNumberResponse {
        try assertOnboardingNotCompleted()

        _ = try ensureLocalDeviceIdentity(
            deviceName: draft.deviceName,
            platform: draft.platform,
            appVersion: draft.appVersion
        )

        let resp = try await api.assignVirtualNumber(C6PAssignVirtualNumberRequest())

        guard C6PVirtualNumberString.isValidCanonical(resp.virtualNumber.value) else {
            throw C6PRegistrationError.apiReturnedInvalidData("VN not canonical: \(resp.virtualNumber.value)")
        }

        draft.virtualNumber = resp.virtualNumber
        return resp
    }

    // MARK: - Step 5: Finalize

    public func finalizeAccountCreation() async throws -> C6PCreateAccountResponse {
        try assertOnboardingNotCompleted()

        guard let vn = draft.virtualNumber else {
            throw C6PRegistrationError.virtualNumberNotAssigned
        }

        let deviceId: C6PDeviceId
        do {
            deviceId = try keychain.loadActiveDeviceId()
        } catch {
            throw C6PRegistrationError.deviceIdentityMissing
        }

        let deviceIdentity: C6PDeviceIdentity
        do {
            deviceIdentity = try keychain.loadDeviceIdentity(deviceId: deviceId)
        } catch {
            throw C6PRegistrationError.deviceIdentityMissing
        }

        let profileName = try buildProfileName()

        // Build device public identity for backend
        let primaryDevice = try C6PDevicePublicIdentityContract(
            deviceIdHex: deviceId.hexString,
            ed25519PublicKey: deviceIdentity.ed25519PrivateKey.publicKey.rawRepresentation,
            x25519PublicKey: deviceIdentity.x25519PrivateKey.publicKey.rawRepresentation,
            deviceName: draft.deviceName,
            platform: draft.platform,
            appVersion: draft.appVersion
        )

        let createReq = C6PCreateAccountRequest(
            virtualNumber: vn,
            username: draft.username,
            usernameReservationToken: draft.usernameReservationToken,
            profileName: profileName,
            avatar: draft.avatar,
            primaryDevice: primaryDevice
        )

        let resp = try await api.createAccount(createReq)

        // Server ack must match assigned VN (fail-closed)
        guard resp.virtualNumber.value == vn.value else {
            throw C6PRegistrationError.apiReturnedInvalidData("createAccount VN mismatch")
        }

        // Persist account identity locally (your project already defines C6PAccountIdentity/C6PAccountDevice/C6PAvatarRef)
        // Keep it minimal and auditable.
        let stored = try Self.buildLocalAccountIdentity(
            response: resp,
            draft: draft,
            deviceId: deviceId,
            deviceIdentity: deviceIdentity
        )
        try keychain.saveAccountIdentity(stored)

        // Clear short-lived draft
        draft = C6PRegistrationDraft()

        return resp
    }

    // MARK: - Local identity mapping

    private static func buildLocalAccountIdentity(
        response: C6PCreateAccountResponse,
        draft: C6PRegistrationDraft,
        deviceId: C6PDeviceId,
        deviceIdentity: C6PDeviceIdentity
    ) throws -> C6PAccountIdentity {

        let avatarLocal: C6PAvatarRef
        switch draft.avatar {
        case .none:
            avatarLocal = .none
        case .mediaId(let id):
            avatarLocal = .mediaId(id)
        }

        let dev = C6PAccountDevice(
            deviceId: deviceId,
            ed25519PublicKeyRaw: deviceIdentity.ed25519PrivateKey.publicKey.rawRepresentation,
            x25519PublicKeyRaw: deviceIdentity.x25519PrivateKey.publicKey.rawRepresentation,
            deviceName: draft.deviceName,
            platform: draft.platform,
            appVersion: draft.appVersion,
            addedAt: response.createdAt,
            isPrimary: true
        )

        return C6PAccountIdentity(
            virtualNumber: response.virtualNumber.value,     // canonical "+99######"
            username: response.username?.value,              // handle without "@"
            firstName: draft.firstName,
            lastName: draft.lastName,
            avatar: avatarLocal,
            createdAt: response.createdAt,
            devices: [dev]
        )
    }
}

