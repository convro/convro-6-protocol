//
//  C6PRegistrationService.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Production registration orchestrator for Convro/C6P.
//
//  UI flow you specified:
//   1) choose unique @username (optional alias, but UI may require step)
//   2) first/last name (optional)
//   3) avatar selection + initials preview (avatar stored as backend mediaId)
//   4) generate +99 virtual number (VN) + bind identity keys (device keys created locally)
//   5) finalize account -> ready
//
//  Security posture:
//   - device private keys are generated locally and stored in Keychain
//   - backend receives public keys only
//   - VN canonical format: "+99" + 6 digits (payload), UI formats "+99 xxx xxx"
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PRegistrationError: Error, CustomStringConvertible {
    case onboardingAlreadyCompleted
    case usernameNotProvided
    case usernameNotReserved
    case virtualNumberNotAssigned
    case deviceIdentityMissing
    case invalidState(String)

    case apiReturnedInvalidData(String)

    var description: String {
        switch self {
        case .onboardingAlreadyCompleted:
            return "C6PRegistrationError.onboardingAlreadyCompleted"
        case .usernameNotProvided:
            return "C6PRegistrationError.usernameNotProvided"
        case .usernameNotReserved:
            return "C6PRegistrationError.usernameNotReserved"
        case .virtualNumberNotAssigned:
            return "C6PRegistrationError.virtualNumberNotAssigned"
        case .deviceIdentityMissing:
            return "C6PRegistrationError.deviceIdentityMissing"
        case .invalidState(let msg):
            return "C6PRegistrationError.invalidState(\(msg))"
        case .apiReturnedInvalidData(let msg):
            return "C6PRegistrationError.apiReturnedInvalidData(\(msg))"
        }
    }
}

// MARK: - Identity API Client (transport abstraction, no mocks)

/// Production contract for your networking layer.
/// Implement this with real HTTP/gRPC/WebSocket — but this service stays transport-agnostic.
protocol C6PIdentityAPIClient {

    // Username
    func checkUsernameAvailability(_ req: C6PUsernameCheckRequest) async throws -> C6PUsernameCheckResponse
    func reserveUsername(_ req: C6PUsernameReserveRequest) async throws -> C6PUsernameReserveResponse

    // VN assignment
    func assignVirtualNumber(_ req: C6PAssignVirtualNumberRequest) async throws -> C6PAssignVirtualNumberResponse

    // Final account creation
    func createAccount(_ req: C6PCreateAccountRequest) async throws -> C6PCreateAccountResponse

    // Optional: device registration (if backend models it separately)
    func registerDevice(_ req: C6PRegisterDeviceRequest) async throws -> C6PRegisterDeviceResponse
}

// MARK: - Registration Draft (in-memory v1)

/// v1 onboarding is short-lived; draft is kept in-memory by default.
/// If you want crash-resume later: we can persist draft in Keychain under separate key.
struct C6PRegistrationDraft: Sendable {

    // Step 1: username
    var username: C6PUsernameHandle?
    var usernameReservationToken: String?

    // Step 2: name
    var profileName: C6PProfileName = try! C6PProfileName(firstName: nil, lastName: nil)

    // Step 3: avatar
    var avatar: C6PAvatarContractRef = .none

    // Step 4: VN assigned
    var virtualNumber: C6PVirtualNumberString?

    // Device context for upload
    var deviceName: String?
    var platform: String?
    var appVersion: String?

    // Derived after device identity exists
    var localDeviceId: C6PDeviceId?
}

// MARK: - Registration Service

/// Actor = race-free onboarding state.
actor C6PRegistrationService {

    // MARK: Dependencies

    private let api: C6PIdentityAPIClient
    private let keychain: C6PIdentityKeychainStore

    // MARK: State

    private var draft = C6PRegistrationDraft()

    // MARK: Init

    init(apiClient: C6PIdentityAPIClient, keychainStore: C6PIdentityKeychainStore) {
        self.api = apiClient
        self.keychain = keychainStore
    }

    // MARK: - Public: Draft inspection

    func currentDraft() -> C6PRegistrationDraft {
        draft
    }

    // MARK: - Step 0: guard

    /// If account identity already exists in Keychain, onboarding should not run again.
    func assertOnboardingNotCompleted() throws {
        if keychain.loadAccountIdentity() != nil {
            throw C6PRegistrationError.onboardingAlreadyCompleted
        }
    }

    // MARK: - Step 1: Username

    /// Validates + checks availability on backend.
    func checkUsername(_ raw: String) async throws -> C6PUsernameCheckResponse {
        try assertOnboardingNotCompleted()
        let handle = try C6PUsernameHandle(raw.hasPrefix("@") ? String(raw.dropFirst()) : raw)
        let req = C6PUsernameCheckRequest(username: handle)
        return try await api.checkUsernameAvailability(req)
    }

    /// Reserves username to prevent races during onboarding.
    /// Stores reservation token in draft.
    func reserveUsername(_ raw: String) async throws -> C6PUsernameReserveResponse {
        try assertOnboardingNotCompleted()
        let handle = try C6PUsernameHandle(raw.hasPrefix("@") ? String(raw.dropFirst()) : raw)
        let req = C6PUsernameReserveRequest(username: handle)
        let resp = try await api.reserveUsername(req)

        if resp.reserved == true {
            draft.username = handle
            draft.usernameReservationToken = resp.reservationToken
        } else {
            // keep draft clean if reserve fails
            draft.username = nil
            draft.usernameReservationToken = nil
        }

        return resp
    }

    /// Allows UI to skip username (if you want it optional).
    /// If you want it mandatory, do NOT call this and enforce reserveUsername() in UI.
    func skipUsername() throws {
        try assertOnboardingNotCompleted()
        draft.username = nil
        draft.usernameReservationToken = nil
    }

    // MARK: - Step 2: Name

    func setProfileName(firstName: String?, lastName: String?) throws {
        try assertOnboardingNotCompleted()
        draft.profileName = try C6PProfileName(firstName: firstName, lastName: lastName)
    }

    // MARK: - Step 3: Avatar (backend mediaId ref)

    func setAvatarNone() throws {
        try assertOnboardingNotCompleted()
        draft.avatar = .none
    }

    func setAvatarMediaId(_ mediaId: String) throws {
        try assertOnboardingNotCompleted()
        let trimmed = mediaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed.count <= 256 else {
            throw C6PIdentityContractError.invalidAvatarReference
        }
        draft.avatar = .mediaId(trimmed)
    }

    // MARK: - Step 4: Device identity (local) + VN assignment

    /// Generates device identity (private keys) locally if missing.
    /// Saves it into Keychain and sets activeDeviceId.
    ///
    /// This is designed to happen at your “Assigning +99 …” screen:
    /// - keys are created now
    /// - then VN is requested
    /// - UI can show dynamic “binding” state safely
    func ensureLocalDeviceIdentity(
        deviceName: String?,
        platform: String?,
        appVersion: String?
    ) async throws -> C6PDeviceId {

        try assertOnboardingNotCompleted()

        draft.deviceName = deviceName
        draft.platform = platform
        draft.appVersion = appVersion

        // If active device id exists, we expect identity to exist too.
        if let active = keychain.loadActiveDeviceId() {
            if keychain.loadDeviceIdentity(deviceId: active) == nil {
                // corrupted state -> hard fail (no silent fallback)
                throw C6PRegistrationError.deviceIdentityMissing
            }
            draft.localDeviceId = active
            return active
        }

        // Create new device identity
        let newDeviceId = try C6PDeviceId.random()

        // CryptoKit key generation
        let edPriv = Curve25519.Signing.PrivateKey()
        let xPriv = Curve25519.KeyAgreement.PrivateKey()

        // Build C6PDeviceIdentity (expected to exist in your project)
        // This object should carry raw private keys + deviceId and allow deriving public keys.
        let deviceIdentity = try C6PDeviceIdentity(
            deviceId: newDeviceId,
            ed25519PrivateKeyRaw: edPriv.rawRepresentation,
            x25519PrivateKeyRaw: xPriv.rawRepresentation,
            createdAt: Date()
        )

        // Persist
        keychain.saveDeviceIdentity(deviceIdentity)
        keychain.saveActiveDeviceId(newDeviceId)

        draft.localDeviceId = newDeviceId
        return newDeviceId
    }

    /// Requests +99 VN from backend (server authoritative).
    /// Stores VN in draft (canonical: "+99" + 6 digits).
    func assignVirtualNumber() async throws -> C6PAssignVirtualNumberResponse {
        try assertOnboardingNotCompleted()

        // Ensure device identity exists before VN binding step.
        _ = try await ensureLocalDeviceIdentity(
            deviceName: draft.deviceName,
            platform: draft.platform,
            appVersion: draft.appVersion
        )

        let req = C6PAssignVirtualNumberRequest()
        let resp = try await api.assignVirtualNumber(req)

        // Contract ensures canonical VN, but we still guard.
        guard C6PVirtualNumberString.isValidCanonical(resp.virtualNumber.value) else {
            throw C6PRegistrationError.apiReturnedInvalidData("VN not canonical: \(resp.virtualNumber.value)")
        }

        draft.virtualNumber = resp.virtualNumber
        return resp
    }

    // MARK: - Step 5: Finalize account creation

    /// Final step: creates account on backend and stores full identity locally in Keychain.
    ///
    /// Requirements:
    /// - device identity exists (private keys in Keychain)
    /// - VN assigned
    /// - if username was chosen -> reservation token recommended
    func finalizeAccountCreation() async throws -> C6PCreateAccountResponse {
        try assertOnboardingNotCompleted()

        guard let vn = draft.virtualNumber else {
            throw C6PRegistrationError.virtualNumberNotAssigned
        }

        guard let deviceId = keychain.loadActiveDeviceId() else {
            throw C6PRegistrationError.deviceIdentityMissing
        }

        guard let deviceIdentity = keychain.loadDeviceIdentity(deviceId: deviceId) else {
            throw C6PRegistrationError.deviceIdentityMissing
        }

        // Build device public identity contract for backend
        let pub = try C6PDevicePublicIdentityContract(
            deviceIdHex: deviceId.hexString,
            ed25519PublicKey: deviceIdentity.ed25519PublicKeyRaw,
            x25519PublicKey: deviceIdentity.x25519PublicKeyRaw,
            deviceName: draft.deviceName,
            platform: draft.platform,
            appVersion: draft.appVersion
        )

        let createReq = C6PCreateAccountRequest(
            virtualNumber: vn,
            username: draft.username,
            usernameReservationToken: draft.usernameReservationToken,
            profileName: draft.profileName,
            avatar: draft.avatar,
            primaryDevice: pub
        )

        let resp = try await api.createAccount(createReq)

        // Backend ack VN must match
        guard resp.virtualNumber.value == vn.value else {
            throw C6PRegistrationError.apiReturnedInvalidData("createAccount VN mismatch")
        }

        // Store account identity locally (expected to exist in your project)
        let accountIdentity = try C6PAccountIdentity(
            virtualNumber: vn.value,                 // canonical "+99######"
            username: resp.username?.value,          // canonical handle without "@"
            firstName: draft.profileName.firstName,
            lastName: draft.profileName.lastName,
            avatar: mapAvatarToLocalRef(draft.avatar),
            createdAt: resp.createdAt,
            devices: [
                C6PAccountDevice(
                    deviceId: deviceId,
                    ed25519PublicKeyRaw: deviceIdentity.ed25519PublicKeyRaw,
                    x25519PublicKeyRaw: deviceIdentity.x25519PublicKeyRaw,
                    deviceName: draft.deviceName,
                    platform: draft.platform,
                    appVersion: draft.appVersion,
                    addedAt: resp.createdAt,
                    isPrimary: true
                )
            ]
        )

        keychain.saveAccountIdentity(accountIdentity)

        // Clear draft (optional)
        draft = C6PRegistrationDraft()

        return resp
    }

    // MARK: - Maintenance

    /// Hard reset of registration state (does NOT wipe Keychain identity automatically).
    /// Use only for UI restarts; if you want wipe, call keychain.wipeAllIdentity(...)
    func resetDraft() {
        draft = C6PRegistrationDraft()
    }

    // MARK: - Helpers

    private func mapAvatarToLocalRef(_ avatar: C6PAvatarContractRef) -> C6PAvatarRef {
        // Expected local type from your C6PAccountIdentity.swift
        // Keep it minimal: no URLs in v1.
        switch avatar {
        case .none:
            return .none
        case .mediaId(let id):
            return .mediaId(id)
        }
    }
}
