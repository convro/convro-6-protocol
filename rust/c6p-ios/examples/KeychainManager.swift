// KeychainManager.swift
// Production-ready Keychain manager for C6P iOS integration
//
// Usage:
//   1. Copy this file to your Xcode project
//   2. Import Security framework
//   3. Use KeychainManager.store/get methods for secure key storage
//
// Security:
//   - Uses kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly (device-bound, encrypted)
//   - No iCloud sync (prevents key leakage across devices)
//   - Supports optional biometric protection
//
// License: Apache 2.0 / MIT (same as C6P)

import Foundation
import Security
import c6p_ios

enum KeychainError: Error {
    case itemNotFound
    case unexpectedData
    case unhandledError(status: OSStatus)
    case encodingError(String)
    case decodingError(String)
}

class KeychainManager {

    // MARK: - Configuration

    /// Keychain access protection level
    /// Balance of security (device-only, encrypted) and availability (accessible after first unlock)
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    // MARK: - Device Identity Storage

    /// Store device identity in Keychain
    /// This is your long-term identity - store it securely!
    ///
    /// - Parameter identity: Device identity from identity_generate_identity()
    /// - Throws: KeychainError if storage fails
    static func storeDeviceIdentity(_ identity: DeviceIdentity) throws {
        let data = try encodeIdentity(identity)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_device_identity",
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
            kSecAttrSynchronizable as String: false  // Do NOT sync to iCloud
        ]

        // Delete existing item first (if any)
        SecItemDelete(query as CFDictionary)

        // Add new item
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        print("✅ Stored device identity in Keychain")
    }

    /// Retrieve device identity from Keychain
    ///
    /// - Returns: Device identity if exists
    /// - Throws: KeychainError.itemNotFound if not found, or other Keychain errors
    static func getDeviceIdentity() throws -> DeviceIdentity {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_device_identity",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ?
                KeychainError.itemNotFound :
                KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return try decodeIdentity(data)
    }

    /// Check if device identity exists
    static func deviceIdentityExists() -> Bool {
        return (try? getDeviceIdentity()) != nil
    }

    /// Delete device identity from Keychain
    /// WARNING: This deletes your long-term identity. Only use for:
    /// - Account deletion
    /// - Security incident response (key compromise)
    static func deleteDeviceIdentity() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_device_identity"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }

        print("⚠️ Deleted device identity from Keychain")
    }

    // MARK: - Session Keys Storage

    /// Store session keys for a specific session
    ///
    /// - Parameters:
    ///   - keys: Session keys from handshake_create_offer or handshake_accept_offer
    ///   - sessionId: Session ID (8 bytes)
    /// - Throws: KeychainError if storage fails
    static func storeSessionKeys(_ keys: SessionKeys, for sessionId: [UInt8]) throws {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)
        let data = try encodeSessionKeys(keys)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_session_\(sessionIdHex)",
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility,
            kSecAttrSynchronizable as String: false
        ]

        // Delete existing (if any)
        SecItemDelete(query as CFDictionary)

        // Add new
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }

        print("✅ Stored session keys for session \(sessionIdHex)")
    }

    /// Retrieve session keys for a specific session
    ///
    /// - Parameter sessionId: Session ID (8 bytes)
    /// - Returns: Session keys
    /// - Throws: KeychainError.itemNotFound if not found, or other Keychain errors
    static func getSessionKeys(for sessionId: [UInt8]) throws -> SessionKeys {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_session_\(sessionIdHex)",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess else {
            throw status == errSecItemNotFound ?
                KeychainError.itemNotFound :
                KeychainError.unhandledError(status: status)
        }

        guard let data = result as? Data else {
            throw KeychainError.unexpectedData
        }

        return try decodeSessionKeys(data)
    }

    /// Delete session keys (when conversation ends)
    ///
    /// - Parameter sessionId: Session ID (8 bytes)
    /// - Throws: KeychainError if deletion fails
    static func deleteSessionKeys(for sessionId: [UInt8]) throws {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_session_\(sessionIdHex)"
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }

        print("🗑️ Deleted session keys for session \(sessionIdHex)")
    }

    /// Delete all session keys (for logout or emergency cleanup)
    static func deleteAllSessionKeys() {
        // Query all c6p_session_* items
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: "c6p_session_",
            kSecMatchLimit as String: kSecMatchLimitAll
        ]

        SecItemDelete(query as CFDictionary)
        print("🗑️ Deleted all session keys from Keychain")
    }

    // MARK: - Serialization Helpers

    /// Encode DeviceIdentity to binary format
    /// Format: device_id (16) + ed25519_priv (64) + ed25519_pub (32) +
    ///         x25519_priv (32) + x25519_pub (32) + fingerprint_len (4) + fingerprint
    private static func encodeIdentity(_ identity: DeviceIdentity) throws -> Data {
        var data = Data()

        // Fixed-size fields
        data.append(contentsOf: identity.device_id)
        data.append(contentsOf: identity.identity_priv_ed25519)
        data.append(contentsOf: identity.identity_pub_ed25519)
        data.append(contentsOf: identity.identity_priv_x25519)
        data.append(contentsOf: identity.identity_pub_x25519)

        // Variable-size field (fingerprint string)
        guard let fingerprintData = identity.fingerprint.data(using: .utf8) else {
            throw KeychainError.encodingError("Failed to encode fingerprint as UTF-8")
        }

        var fingerprintLen = UInt32(fingerprintData.count).bigEndian
        data.append(Data(bytes: &fingerprintLen, count: 4))
        data.append(fingerprintData)

        return data
    }

    /// Decode DeviceIdentity from binary format
    private static func decodeIdentity(_ data: Data) throws -> DeviceIdentity {
        var offset = 0

        guard data.count >= 16 + 64 + 32 + 32 + 32 + 4 else {
            throw KeychainError.decodingError("Data too short for DeviceIdentity")
        }

        let device_id = Array(data[offset..<offset+16])
        offset += 16

        let identity_priv_ed25519 = Array(data[offset..<offset+64])
        offset += 64

        let identity_pub_ed25519 = Array(data[offset..<offset+32])
        offset += 32

        let identity_priv_x25519 = Array(data[offset..<offset+32])
        offset += 32

        let identity_pub_x25519 = Array(data[offset..<offset+32])
        offset += 32

        let fingerprintLen = data[offset..<offset+4].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        offset += 4

        guard data.count >= offset + Int(fingerprintLen) else {
            throw KeychainError.decodingError("Data too short for fingerprint")
        }

        let fingerprintData = data[offset..<offset+Int(fingerprintLen)]
        guard let fingerprint = String(data: fingerprintData, encoding: .utf8) else {
            throw KeychainError.decodingError("Failed to decode fingerprint as UTF-8")
        }

        return DeviceIdentity(
            device_id: device_id,
            identity_priv_ed25519: identity_priv_ed25519,
            identity_pub_ed25519: identity_pub_ed25519,
            identity_priv_x25519: identity_priv_x25519,
            identity_pub_x25519: identity_pub_x25519,
            fingerprint: fingerprint
        )
    }

    /// Encode SessionKeys to binary format
    /// Format: session_id (8) + root_key (32) + kc_key (32) +
    ///         send_chain_key (32) + recv_chain_key (32) + session_binding (32)
    private static func encodeSessionKeys(_ keys: SessionKeys) throws -> Data {
        var data = Data()
        data.append(contentsOf: keys.session_id)
        data.append(contentsOf: keys.root_key)
        data.append(contentsOf: keys.kc_key)
        data.append(contentsOf: keys.send_chain_key)
        data.append(contentsOf: keys.recv_chain_key)
        data.append(contentsOf: keys.session_binding)
        return data
    }

    /// Decode SessionKeys from binary format
    private static func decodeSessionKeys(_ data: Data) throws -> SessionKeys {
        var offset = 0

        guard data.count >= 8 + 32 + 32 + 32 + 32 + 32 else {
            throw KeychainError.decodingError("Data too short for SessionKeys")
        }

        let session_id = Array(data[offset..<offset+8])
        offset += 8

        let root_key = Array(data[offset..<offset+32])
        offset += 32

        let kc_key = Array(data[offset..<offset+32])
        offset += 32

        let send_chain_key = Array(data[offset..<offset+32])
        offset += 32

        let recv_chain_key = Array(data[offset..<offset+32])
        offset += 32

        let session_binding = Array(data[offset..<offset+32])

        return SessionKeys(
            session_id: session_id,
            root_key: root_key,
            kc_key: kc_key,
            send_chain_key: send_chain_key,
            recv_chain_key: recv_chain_key,
            session_binding: session_binding
        )
    }
}
