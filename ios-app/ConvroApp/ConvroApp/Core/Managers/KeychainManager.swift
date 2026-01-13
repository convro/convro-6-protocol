import Foundation
import Security
import C6PProtocol

// MARK: - Keychain Manager
/// Secure storage manager for keys, identities, and sensitive data
@MainActor
class KeychainManager {
    // MARK: - Singleton
    static let shared = KeychainManager()

    // MARK: - Configuration
    private let serviceName = "app.convro.ios"
    private let accessGroup = "$(AppIdentifierPrefix)app.convro.ios"

    // Keychain keys
    private enum Keys {
        static let deviceIdentity = "device_identity"
        static let sessionKeyPrefix = "session_key_"
        static let signedPrekey = "signed_prekey"
        static let oneTimePrekeys = "one_time_prekeys"
    }

    private init() {}

    // MARK: - Save Operations
    func save(_ data: Data, forKey key: String) throws {
        do {
            try KeychainWrapper.save(data: data, service: serviceName, account: key)
        } catch {
            throw KeychainError.saveFailed
        }
    }

    func saveString(_ string: String, forKey key: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        try save(data, forKey: key)
    }

    // MARK: - Retrieve Operations
    func retrieve(forKey key: String) throws -> Data {
        do {
            return try KeychainWrapper.load(service: serviceName, account: key)
        } catch {
            throw KeychainError.itemNotFound
        }
    }

    func retrieveString(forKey key: String) throws -> String {
        let data = try retrieve(forKey: key)
        guard let string = String(data: data, encoding: .utf8) else {
            throw KeychainError.decodingFailed
        }
        return string
    }

    // MARK: - Delete Operations
    func delete(forKey key: String) throws {
        do {
            try KeychainWrapper.delete(service: serviceName, account: key)
        } catch {
            throw KeychainError.deleteFailed
        }
    }

    func deleteAll() throws {
        // Delete common keys
        try? delete(forKey: Keys.deviceIdentity)
        try? delete(forKey: Keys.signedPrekey)
        try? delete(forKey: Keys.oneTimePrekeys)

        // Note: Session keys are deleted individually via deleteSessionKeys()
    }

    // MARK: - Device Identity Operations

    /// Save device identity to Keychain
    func saveDeviceIdentity(_ identity: DeviceIdentity) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(DeviceIdentityWrapper(identity: identity))
        try save(data, forKey: Keys.deviceIdentity)
    }

    /// Load device identity from Keychain
    func loadDeviceIdentity() async throws -> DeviceIdentity {
        let data = try retrieve(forKey: Keys.deviceIdentity)
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(DeviceIdentityWrapper.self, from: data)
        return wrapper.toDeviceIdentity()
    }

    /// Delete device identity from Keychain
    func deleteDeviceIdentity() async throws {
        try delete(forKey: Keys.deviceIdentity)
    }

    // MARK: - Session Keys Operations

    /// Save session keys to Keychain (CRITICAL - called after handshake)
    func saveSessionKeys(_ keys: SessionKeys, sessionId: String) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(SessionKeysWrapper(keys: keys))
        try save(data, forKey: Keys.sessionKeyPrefix + sessionId)
    }

    /// Load session keys from Keychain
    func loadSessionKeys(sessionId: String) async throws -> SessionKeys {
        let data = try retrieve(forKey: Keys.sessionKeyPrefix + sessionId)
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(SessionKeysWrapper.self, from: data)
        return wrapper.toSessionKeys()
    }

    /// Delete session keys from Keychain
    func deleteSessionKeys(sessionId: String) async throws {
        try delete(forKey: Keys.sessionKeyPrefix + sessionId)
    }

    // MARK: - Prekey Operations

    /// Save signed prekey to Keychain
    func saveSignedPrekey(_ spk: SignedPrekey) async throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(SignedPrekeyWrapper(spk: spk))
        try save(data, forKey: Keys.signedPrekey)
    }

    /// Load signed prekey from Keychain
    func loadSignedPrekey() async throws -> SignedPrekey {
        let data = try retrieve(forKey: Keys.signedPrekey)
        let decoder = JSONDecoder()
        let wrapper = try decoder.decode(SignedPrekeyWrapper.self, from: data)
        return wrapper.toSignedPrekey()
    }
}

// MARK: - Keychain Error
enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case itemNotFound
    case saveFailed
    case deleteFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Failed to encode data"
        case .decodingFailed:
            return "Failed to decode data"
        case .itemNotFound:
            return "Item not found in Keychain"
        case .saveFailed:
            return "Failed to save to Keychain"
        case .deleteFailed:
            return "Failed to delete from Keychain"
        }
    }
}

// MARK: - Codable Wrappers (C6P types → JSON)

/// Wrapper for DeviceIdentity (C6P FFI type → Codable)
private struct DeviceIdentityWrapper: Codable {
    let deviceId: Data
    let identityPrivEd25519: Data
    let identityPubEd25519: Data
    let identityPrivX25519: Data
    let identityPubX25519: Data
    let fingerprint: String

    init(identity: DeviceIdentity) {
        self.deviceId = Data(identity.deviceId)
        self.identityPrivEd25519 = Data(identity.identityPrivEd25519)
        self.identityPubEd25519 = Data(identity.identityPubEd25519)
        self.identityPrivX25519 = Data(identity.identityPrivX25519)
        self.identityPubX25519 = Data(identity.identityPubX25519)
        self.fingerprint = identity.fingerprint
    }

    func toDeviceIdentity() -> DeviceIdentity {
        return DeviceIdentity(
            deviceId: Array(deviceId),
            identityPrivEd25519: Array(identityPrivEd25519),
            identityPubEd25519: Array(identityPubEd25519),
            identityPrivX25519: Array(identityPrivX25519),
            identityPubX25519: Array(identityPubX25519),
            fingerprint: fingerprint
        )
    }
}

/// Wrapper for SessionKeys (C6P FFI type → Codable)
private struct SessionKeysWrapper: Codable {
    let sessionId: Data
    let rootKey: Data
    let kcKey: Data
    let sendChainKey: Data
    let recvChainKey: Data
    let sessionBinding: Data

    init(keys: SessionKeys) {
        self.sessionId = Data(keys.sessionId)
        self.rootKey = Data(keys.rootKey)
        self.kcKey = Data(keys.kcKey)
        self.sendChainKey = Data(keys.sendChainKey)
        self.recvChainKey = Data(keys.recvChainKey)
        self.sessionBinding = Data(keys.sessionBinding)
    }

    func toSessionKeys() -> SessionKeys {
        return SessionKeys(
            sessionId: Array(sessionId),
            rootKey: Array(rootKey),
            kcKey: Array(kcKey),
            sendChainKey: Array(sendChainKey),
            recvChainKey: Array(recvChainKey),
            sessionBinding: Array(sessionBinding)
        )
    }
}

/// Wrapper for SignedPrekey (C6P FFI type → Codable)
private struct SignedPrekeyWrapper: Codable {
    let spkId: Data
    let spkPriv: Data
    let spkPub: Data
    let spkSig: Data

    init(spk: SignedPrekey) {
        self.spkId = Data(spk.spkId)
        self.spkPriv = Data(spk.spkPriv)
        self.spkPub = Data(spk.spkPub)
        self.spkSig = Data(spk.spkSig)
    }

    func toSignedPrekey() -> SignedPrekey {
        return SignedPrekey(
            spkId: Array(spkId),
            spkPriv: Array(spkPriv),
            spkPub: Array(spkPub),
            spkSig: Array(spkSig)
        )
    }
}
