//
//  C6PIdentityKeychainStore.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Production Keychain-backed storage for C6P identity material.
//
//  Stores:
//  - Active device id (this installation)
//  - Device private identity (Ed25519 + X25519) per deviceId
//  - Account identity (profile metadata, non-secret but protected)
//
//  Security posture (v1):
//  - kSecAttrAccessibleWhenUnlockedThisDeviceOnly (default)
//  - synchronizable = false (default)
//  - private keys never leave device
//

import Foundation
import Security
import CryptoKit

// MARK: - Errors

public enum C6PIdentityKeychainStoreError: Error, CustomStringConvertible {
    case keychainError(status: OSStatus, operation: String)
    case notFound
    case decodeFailed
    case encodeFailed
    case invalidData
    case deviceIdentityMismatch

    public var description: String {
        switch self {
        case .keychainError(let status, let op):
            return "C6PIdentityKeychainStoreError.keychainError(status=\(status), operation=\(op))"
        case .notFound:
            return "C6PIdentityKeychainStoreError.notFound"
        case .decodeFailed:
            return "C6PIdentityKeychainStoreError.decodeFailed"
        case .encodeFailed:
            return "C6PIdentityKeychainStoreError.encodeFailed"
        case .invalidData:
            return "C6PIdentityKeychainStoreError.invalidData"
        case .deviceIdentityMismatch:
            return "C6PIdentityKeychainStoreError.deviceIdentityMismatch"
        }
    }
}

// MARK: - Keychain configuration

public struct C6PKeychainConfig: Hashable {
    /// Keychain service namespace (bundle-unique recommended).
    public let service: String

    /// Optional Keychain access group (for app + extensions sharing).
    public let accessGroup: String?

    /// Accessibility class.
    public let accessible: CFString

    /// Whether items should be synchronizable via iCloud Keychain.
    public let synchronizable: Bool

    public init(
        service: String = "pl.convro.c6p.identity",
        accessGroup: String? = nil,
        accessible: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        synchronizable: Bool = false
    ) {
        self.service = service
        self.accessGroup = accessGroup
        self.accessible = accessible
        self.synchronizable = synchronizable
    }
}

// MARK: - Store

public final class C6PIdentityKeychainStore {

    private let config: C6PKeychainConfig
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // Keychain "accounts" (namespaced keys)
    private enum KCKey {
        static func deviceIdentity(deviceId: C6PDeviceId) -> String { "device.identity.\(deviceId.hexString)" }
        static let activeDeviceId = "device.active.id"
        static let accountIdentity = "account.identity"
    }

    public init(config: C6PKeychainConfig = C6PKeychainConfig()) {
        self.config = config
        self.jsonEncoder = C6PJSON.makeEncoder()
        self.jsonDecoder = C6PJSON.makeDecoder()
    }

    // MARK: - Active Device Id

    public func saveActiveDeviceId(_ deviceId: C6PDeviceId) throws {
        try upsertData(deviceId.data, account: KCKey.activeDeviceId)
    }

    public func loadActiveDeviceId() throws -> C6PDeviceId {
        let data = try loadData(account: KCKey.activeDeviceId)
        return try C6PDeviceId(data: data)
    }

    public func deleteActiveDeviceId() throws {
        try deleteItem(account: KCKey.activeDeviceId)
    }

    // MARK: - Device Identity (private keys)

    public func saveDeviceIdentity(_ identity: C6PDeviceIdentity) throws {
        let payload = try encodeDeviceIdentity(identity)
        try upsertData(payload, account: KCKey.deviceIdentity(deviceId: identity.deviceId))
    }

    public func loadDeviceIdentity(deviceId: C6PDeviceId) throws -> C6PDeviceIdentity {
        let data = try loadData(account: KCKey.deviceIdentity(deviceId: deviceId))
        let identity = try decodeDeviceIdentity(data)

        guard identity.deviceId == deviceId else {
            throw C6PIdentityKeychainStoreError.deviceIdentityMismatch
        }
        return identity
    }

    public func deleteDeviceIdentity(deviceId: C6PDeviceId) throws {
        try deleteItem(account: KCKey.deviceIdentity(deviceId: deviceId))
    }

    // MARK: - Account Identity (secured metadata)

    public func saveAccountIdentity(_ identity: C6PAccountIdentity) throws {
        guard let data = try? jsonEncoder.encode(identity) else {
            throw C6PIdentityKeychainStoreError.encodeFailed
        }
        try upsertData(data, account: KCKey.accountIdentity)
    }

    public func loadAccountIdentity() throws -> C6PAccountIdentity {
        let data = try loadData(account: KCKey.accountIdentity)
        guard let obj = try? jsonDecoder.decode(C6PAccountIdentity.self, from: data) else {
            throw C6PIdentityKeychainStoreError.decodeFailed
        }
        return obj
    }

    public func deleteAccountIdentity() throws {
        try deleteItem(account: KCKey.accountIdentity)
    }

    // MARK: - Wipe

    /// Best-effort wipe for identity material (no-throw on missing items).
    public func wipeAllIdentity() {
        // device identity (if we know active device id)
        if let did = try? loadActiveDeviceId() {
            try? deleteDeviceIdentity(deviceId: did)
        }
        try? deleteAccountIdentity()
        try? deleteActiveDeviceId()
    }

    // MARK: - Encoding: Device Identity payload

    private struct StoredDeviceIdentityV1: Codable {
        let v: UInt8
        let deviceIdHex: String
        let ed25519PrivB64u: String
        let x25519PrivB64u: String
    }

    private func encodeDeviceIdentity(_ identity: C6PDeviceIdentity) throws -> Data {
        let edPriv = identity.ed25519PrivateKey.rawRepresentation
        let xPriv = identity.x25519PrivateKey.rawRepresentation

        let model = StoredDeviceIdentityV1(
            v: 1,
            deviceIdHex: identity.deviceId.hexString,
            ed25519PrivB64u: C6PEncoding.base64URLEncode(edPriv),
            x25519PrivB64u: C6PEncoding.base64URLEncode(xPriv)
        )

        guard let data = try? jsonEncoder.encode(model) else {
            throw C6PIdentityKeychainStoreError.encodeFailed
        }
        return data
    }

    private func decodeDeviceIdentity(_ data: Data) throws -> C6PDeviceIdentity {
        guard let model = try? jsonDecoder.decode(StoredDeviceIdentityV1.self, from: data) else {
            throw C6PIdentityKeychainStoreError.decodeFailed
        }
        guard model.v == 1 else { throw C6PIdentityKeychainStoreError.invalidData }

        let deviceId = try C6PDeviceId(hexString: model.deviceIdHex)
        let edPrivData = try C6PEncoding.base64URLDecode(model.ed25519PrivB64u)
        let xPrivData = try C6PEncoding.base64URLDecode(model.x25519PrivB64u)

        let edPriv = try Curve25519.Signing.PrivateKey(rawRepresentation: edPrivData)
        let xPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: xPrivData)

        return C6PDeviceIdentity(
            deviceId: deviceId,
            ed25519PrivateKey: edPriv,
            x25519PrivateKey: xPriv
        )
    }

    // MARK: - Keychain Core Ops

    private func matchQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.service,
            kSecAttrAccount as String: account,
            // IMPORTANT: synchronizable must be present on match too
            kSecAttrSynchronizable as String: (config.synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!)
        ]

        if let ag = config.accessGroup {
            q[kSecAttrAccessGroup as String] = ag
        }

        return q
    }

    private func addAttributes(data: Data) -> [String: Any] {
        return [
            kSecValueData as String: data,
            kSecAttrAccessible as String: config.accessible,
            kSecAttrSynchronizable as String: (config.synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!)
        ]
    }

    private func upsertData(_ data: Data, account: String) throws {
        // update first
        let q = matchQuery(account: account)
        let attrs: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess { return }

        if updateStatus != errSecItemNotFound {
            throw C6PIdentityKeychainStoreError.keychainError(status: updateStatus, operation: "SecItemUpdate(\(account))")
        }

        // add
        var addQ = q
        for (k, v) in addAttributes(data: data) { addQ[k] = v }

        let addStatus = SecItemAdd(addQ as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw C6PIdentityKeychainStoreError.keychainError(status: addStatus, operation: "SecItemAdd(\(account))")
        }
    }

    private func loadData(account: String) throws -> Data {
        var q = matchQuery(account: account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw C6PIdentityKeychainStoreError.notFound
        }
        guard status == errSecSuccess else {
            throw C6PIdentityKeychainStoreError.keychainError(status: status, operation: "SecItemCopyMatching(\(account))")
        }

        guard let data = result as? Data else {
            throw C6PIdentityKeychainStoreError.invalidData
        }
        return data
    }

    private func deleteItem(account: String) throws {
        let q = matchQuery(account: account)
        let status = SecItemDelete(q as CFDictionary)

        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw C6PIdentityKeychainStoreError.keychainError(status: status, operation: "SecItemDelete(\(account))")
        }
    }
}

