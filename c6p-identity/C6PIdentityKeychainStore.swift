//
//  C6PIdentityKeychainStore.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Secure Keychain-backed storage for C6P identity material.
//
//  Stores:
//  - Device private keys (Ed25519 + X25519) for THIS device
//  - Account identity profile (VN + username + devices public identities)
//
//  Security posture (v1):
//  - kSecAttrAccessibleWhenUnlockedThisDeviceOnly
//  - synchronizable = false
//  - no plaintext private keys in Codable files
//

import Foundation
import Security
import CryptoKit

// MARK: - Errors

enum C6PIdentityKeychainStoreError: Error, CustomStringConvertible {
    case keychainError(status: OSStatus, operation: String)
    case notFound
    case decodeFailed
    case encodeFailed
    case invalidData
    case deviceIdentityMismatch

    var description: String {
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
            return "C6PIdentityKeychainStoreError.deviceIdentityMismatch – stored deviceId does not match expected deviceId"
        }
    }
}

// MARK: - Keychain configuration

struct C6PKeychainConfig: Hashable {
    /// Keychain service namespace (bundle-unique recommended).
    let service: String

    /// Optional Keychain access group (for app + extensions sharing).
    let accessGroup: String?

    /// Accessibility class (v1 strict default).
    let accessible: CFString

    /// Whether items should be synchronizable via iCloud Keychain.
    /// v1 default: false
    let synchronizable: Bool

    init(
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

/// Keychain store for identity material.
/// This object is synchronous and thread-safe at call-level (Keychain is serialized by OS),
/// but we still keep operations deterministic and explicit.
final class C6PIdentityKeychainStore {

    private let config: C6PKeychainConfig
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder

    // Keychain "accounts" (namespaced keys)
    private enum KCKey {
        static func deviceIdentity(deviceId: C6PDeviceId) -> String { "device.identity.\(deviceId.hexString)" }
        static let activeDeviceId = "device.active.id"
        static let accountIdentity = "account.identity"
    }

    init(config: C6PKeychainConfig = C6PKeychainConfig()) {
        self.config = config
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.jsonEncoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.jsonDecoder = dec
    }

    // MARK: - Public API: Active Device Id

    /// Persist which deviceId is "this device" for the app installation.
    /// v1 assumes one local device identity per installation.
    func saveActiveDeviceId(_ deviceId: C6PDeviceId) throws {
        try upsertData(deviceId.data, account: KCKey.activeDeviceId)
    }

    func loadActiveDeviceId() throws -> C6PDeviceId {
        let data = try loadData(account: KCKey.activeDeviceId)
        return try C6PDeviceId(data: data)
    }

    func deleteActiveDeviceId() throws {
        try deleteItem(account: KCKey.activeDeviceId)
    }

    // MARK: - Public API: Device Identity (private keys)

    /// Stores full private device identity (Ed25519 + X25519) under deviceId.
    /// This is the most sensitive object in v1 identity storage.
    func saveDeviceIdentity(_ identity: C6PDeviceIdentity) throws {
        let payload = try encodeDeviceIdentity(identity)
        try upsertData(payload, account: KCKey.deviceIdentity(deviceId: identity.deviceId))
    }

    /// Loads device identity for a given deviceId.
    func loadDeviceIdentity(deviceId: C6PDeviceId) throws -> C6PDeviceIdentity {
        let data = try loadData(account: KCKey.deviceIdentity(deviceId: deviceId))
        let identity = try decodeDeviceIdentity(data)

        guard identity.deviceId == deviceId else {
            throw C6PIdentityKeychainStoreError.deviceIdentityMismatch
        }
        return identity
    }

    func deleteDeviceIdentity(deviceId: C6PDeviceId) throws {
        try deleteItem(account: KCKey.deviceIdentity(deviceId: deviceId))
    }

    // MARK: - Public API: Account Identity (profile + device bindings)

    /// Stores account identity in Keychain (secured).
    /// Note: this is not a secret like private keys, but user asked for "secured protocol" baseline.
    func saveAccountIdentity(_ identity: C6PAccountIdentity) throws {
        guard let data = try? jsonEncoder.encode(identity) else {
            throw C6PIdentityKeychainStoreError.encodeFailed
        }
        try upsertData(data, account: KCKey.accountIdentity)
    }

    func loadAccountIdentity() throws -> C6PAccountIdentity {
        let data = try loadData(account: KCKey.accountIdentity)
        guard let obj = try? jsonDecoder.decode(C6PAccountIdentity.self, from: data) else {
            throw C6PIdentityKeychainStoreError.decodeFailed
        }
        return obj
    }

    func deleteAccountIdentity() throws {
        try deleteItem(account: KCKey.accountIdentity)
    }

    // MARK: - Wipe

    /// Wipes identity material (device identity, account identity, active device id).
    /// Use in Panic Mode / logout / local key wipe.
    func wipeAllIdentity(for deviceId: C6PDeviceId) throws {
        // Best-effort wipe: if something missing -> ignore notFound
        try? deleteDeviceIdentity(deviceId: deviceId)
        try? deleteAccountIdentity()
        try? deleteActiveDeviceId()
    }

    // MARK: - Encoding: Device Identity payload

    /// We store device identity as a compact, versioned JSON blob:
    /// - v: 1
    /// - deviceId: hex
    /// - ed25519Priv: base64url
    /// - x25519Priv: base64url
    ///
    /// Why JSON?
    /// - explicit versioning
    /// - easier migration later
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
        guard model.v == 1 else {
            throw C6PIdentityKeychainStoreError.invalidData
        }

        let deviceId = try C6PDeviceId(hexString: model.deviceIdHex)

        let edPrivData = try C6PEncoding.base64URLDecode(model.ed25519PrivB64u)
        let xPrivData = try C6PEncoding.base64URLDecode(model.x25519PrivB64u)

        // CryptoKit raw representations:
        let edPriv = try Curve25519.Signing.PrivateKey(rawRepresentation: edPrivData)
        let xPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: xPrivData)

        return C6PDeviceIdentity(
            deviceId: deviceId,
            ed25519PrivateKey: edPriv,
            x25519PrivateKey: xPriv
        )
    }

    // MARK: - Keychain Core Ops

    private func baseQuery(account: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: config.service,
            kSecAttrAccount as String: account
        ]

        if let ag = config.accessGroup {
            q[kSecAttrAccessGroup as String] = ag
        }

        q[kSecAttrAccessible as String] = config.accessible

        // Explicitly disable sync unless asked
        q[kSecAttrSynchronizable as String] = config.synchronizable ? kCFBooleanTrue! : kCFBooleanFalse!

        return q
    }

    private func upsertData(_ data: Data, account: String) throws {
        // Try update first
        var q = baseQuery(account: account)
        let attrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        if updateStatus != errSecItemNotFound {
            throw C6PIdentityKeychainStoreError.keychainError(status: updateStatus, operation: "SecItemUpdate(\(account))")
        }

        // Add new item
        q[kSecValueData as String] = data
        let addStatus = SecItemAdd(q as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw C6PIdentityKeychainStoreError.keychainError(status: addStatus, operation: "SecItemAdd(\(account))")
        }
    }

    private func loadData(account: String) throws -> Data {
        var q = baseQuery(account: account)
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
        let q = baseQuery(account: account)
        let status = SecItemDelete(q as CFDictionary)

        if status == errSecItemNotFound {
            // treat as success for delete
            return
        }
        guard status == errSecSuccess else {
            throw C6PIdentityKeychainStoreError.keychainError(status: status, operation: "SecItemDelete(\(account))")
        }
    }
}
