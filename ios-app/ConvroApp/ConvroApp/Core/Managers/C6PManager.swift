import Foundation

// MARK: - C6P Manager
/// Core manager for C6P operations (handshake, encryption, sessions)
@MainActor
class C6PManager: ObservableObject {
    // MARK: - Singleton
    static let shared = C6PManager()

    // MARK: - Properties
    @Published var isInitialized: Bool = false
    private var deviceIdentity: DeviceIdentity?
    private var activeSessions: [String: C6PSessionWrapper] = [:]

    // MARK: - Initialization
    private init() {
        // Load device identity from Keychain on init
        Task {
            await loadDeviceIdentityFromKeychain()
        }
    }

    // MARK: - Identity Management

    /// Generate new device identity using C6P FFI
    func generateDeviceIdentity() throws -> DeviceIdentity {
        let identity = try identityGenerateIdentity()
        self.deviceIdentity = identity

        // Save to Keychain immediately
        Task {
            try await KeychainManager.shared.saveDeviceIdentity(identity)
        }

        return identity
    }

    /// Load device identity from Keychain
    func loadDeviceIdentity() -> DeviceIdentity? {
        return deviceIdentity
    }

    private func loadDeviceIdentityFromKeychain() async {
        do {
            self.deviceIdentity = try await KeychainManager.shared.loadDeviceIdentity()
            self.isInitialized = (deviceIdentity != nil)
        } catch {
            print("⚠️ No device identity found in Keychain")
            self.isInitialized = false
        }
    }

    /// Generate signed prekey for device
    func generateSignedPrekey() throws -> SignedPrekey {
        guard let identity = deviceIdentity else {
            throw C6PManagerError.noDeviceIdentity
        }
        return try identityGenerateSignedPrekey(identity: identity)
    }

    /// Generate one-time prekey
    func generateOneTimePrekey() throws -> OneTimePrekey {
        return try identityGenerateOneTimePrekey()
    }

    /// Validate prekey bundle (verify SPK signature)
    func validateBundle(_ bundle: PrekeyBundle) throws {
        try identityValidateBundle(bundle: bundle)
    }

    /// Compute fingerprint from Ed25519 public key
    func computeFingerprint(ed25519Pub: [UInt8]) throws -> String {
        return try identityComputeFingerprint(ed25519Pub: ed25519Pub)
    }

    // MARK: - Handshake Operations

    /// Initiator: Create handshake offer
    /// Returns CreateOfferResult containing offer + session keys
    func createHandshakeOffer(responderBundle: PrekeyBundle) throws -> CreateOfferResult {
        guard let initiatorIdentity = deviceIdentity else {
            throw C6PManagerError.noDeviceIdentity
        }

        // Call C6P FFI to create offer
        let result = try handshakeCreateOffer(
            initiatorIdentity: initiatorIdentity,
            responderBundle: responderBundle
        )

        // Store session keys in Keychain immediately (CRITICAL)
        let sessionId = result.offer.sessionId.toHexString()
        Task {
            try await KeychainManager.shared.saveSessionKeys(result.sessionKeys, sessionId: sessionId)
        }

        // Create session state
        let sessionState = try SessionState(keys: result.sessionKeys, isInitiator: true)
        let wrapper = C6PSessionWrapper(
            sessionId: sessionId,
            participantId: responderBundle.responderDeviceId.toHexString(),
            sessionState: sessionState
        )
        activeSessions[sessionId] = wrapper

        return result
    }

    /// Responder: Accept handshake offer
    /// Returns AcceptOfferResult containing accept + session keys
    func acceptHandshakeOffer(
        offerBytes: [UInt8],
        responderSPK: SignedPrekey,
        responderOTP: OneTimePrekey?
    ) throws -> AcceptOfferResult {
        guard let responderIdentity = deviceIdentity else {
            throw C6PManagerError.noDeviceIdentity
        }

        // Call C6P FFI to accept offer
        let result = try handshakeAcceptOffer(
            responderIdentity: responderIdentity,
            responderSpk: responderSPK,
            responderOtp: responderOTP,
            offerBytes: offerBytes
        )

        // Store session keys in Keychain immediately (CRITICAL)
        let sessionId = result.accept.sessionId.toHexString()
        Task {
            try await KeychainManager.shared.saveSessionKeys(result.sessionKeys, sessionId: sessionId)
        }

        // Create session state
        let sessionState = try SessionState(keys: result.sessionKeys, isInitiator: false)
        let wrapper = C6PSessionWrapper(
            sessionId: sessionId,
            participantId: result.accept.responderDeviceId.toHexString(),
            sessionState: sessionState
        )
        activeSessions[sessionId] = wrapper

        return result
    }

    /// Initiator: Verify accept message
    func verifyHandshakeAccept(
        offer: HandshakeOffer,
        acceptBytes: [UInt8],
        sessionKeys: SessionKeys
    ) throws {
        try handshakeVerifyAccept(
            offer: offer,
            acceptBytes: acceptBytes,
            sessionKeys: sessionKeys
        )
    }

    // MARK: - Session Management

    func getSession(sessionId: String) -> C6PSessionWrapper? {
        return activeSessions[sessionId]
    }

    func saveSession(_ wrapper: C6PSessionWrapper) {
        activeSessions[wrapper.sessionId] = wrapper

        // Persist session state to database
        Task {
            await SessionDatabase.shared.saveSession(wrapper)
        }
    }

    func removeSession(sessionId: String) {
        activeSessions.removeValue(forKey: sessionId)

        // Remove from database
        Task {
            await SessionDatabase.shared.deleteSession(sessionId: sessionId)
        }
    }

    // MARK: - Encryption/Decryption

    /// Encrypt message using active session
    func encrypt(message: String, sessionId: String) throws -> Data {
        guard let wrapper = activeSessions[sessionId] else {
            throw C6PManagerError.sessionNotFound
        }

        let plaintext = Data(message.utf8)
        let encrypted = try wrapper.sessionState.encrypt(plaintext: Array(plaintext))

        // Serialize EncryptedMessage to Data
        let data = try encryptedMessageToData(encrypted)

        // Save updated session state
        saveSession(wrapper)

        return data
    }

    /// Decrypt message using active session
    func decrypt(ciphertext: Data, sessionId: String) throws -> String {
        guard let wrapper = activeSessions[sessionId] else {
            throw C6PManagerError.sessionNotFound
        }

        // Deserialize Data to EncryptedMessage
        let encrypted = try dataToEncryptedMessage(ciphertext)

        let plaintext = try wrapper.sessionState.decrypt(message: encrypted)

        // Save updated session state
        saveSession(wrapper)

        guard let message = String(data: Data(plaintext), encoding: .utf8) else {
            throw C6PManagerError.invalidUTF8
        }

        return message
    }

    // MARK: - Utilities

    /// Convert bytes to hex string
    func bytesToHex(_ data: [UInt8]) -> String {
        return utilsBytesToHex(data: data)
    }

    /// Convert hex string to bytes
    func hexToBytes(_ hex: String) throws -> [UInt8] {
        return try utilsHexToBytes(hex: hex)
    }

    /// Generate cryptographically secure random bytes
    func randomBytes(length: UInt32) throws -> [UInt8] {
        return try utilsRandomBytes(length: length)
    }

    // MARK: - Private Helpers

    private func encryptedMessageToData(_ message: EncryptedMessage) throws -> Data {
        // Simple binary serialization: counter (8 bytes) + ciphertext length (4 bytes) + ciphertext + tag (16 bytes)
        var data = Data()

        // Counter (8 bytes, big-endian)
        withUnsafeBytes(of: message.counter.bigEndian) { bytes in
            data.append(contentsOf: bytes)
        }

        // Ciphertext length (4 bytes, big-endian)
        let length = UInt32(message.ciphertext.count).bigEndian
        withUnsafeBytes(of: length) { bytes in
            data.append(contentsOf: bytes)
        }

        // Ciphertext
        data.append(contentsOf: message.ciphertext)

        // Tag (16 bytes)
        data.append(contentsOf: message.tag)

        return data
    }

    private func dataToEncryptedMessage(_ data: Data) throws -> EncryptedMessage {
        guard data.count >= 28 else { // 8 + 4 + 16
            throw C6PManagerError.invalidEncryptedMessage
        }

        // Counter (8 bytes)
        let counter = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 0, as: UInt64.self).bigEndian
        }

        // Ciphertext length (4 bytes)
        let length = data.withUnsafeBytes { bytes in
            bytes.load(fromByteOffset: 8, as: UInt32.self).bigEndian
        }

        guard data.count >= 28 + Int(length) else {
            throw C6PManagerError.invalidEncryptedMessage
        }

        // Ciphertext
        let ciphertext = Array(data[12..<(12 + Int(length))])

        // Tag (16 bytes)
        let tag = Array(data[(12 + Int(length))...])

        return EncryptedMessage(
            counter: counter,
            ciphertext: ciphertext,
            tag: tag
        )
    }
}

// MARK: - Session Wrapper
/// Wrapper for C6P SessionState with metadata
class C6PSessionWrapper {
    let sessionId: String
    let participantId: String
    let sessionState: SessionState

    init(sessionId: String, participantId: String, sessionState: SessionState) {
        self.sessionId = sessionId
        self.participantId = participantId
        self.sessionState = sessionState
    }
}

// MARK: - Errors
enum C6PManagerError: LocalizedError {
    case noDeviceIdentity
    case sessionNotFound
    case invalidEncryptedMessage
    case invalidUTF8

    var errorDescription: String? {
        switch self {
        case .noDeviceIdentity:
            return "No device identity found. Generate one first."
        case .sessionNotFound:
            return "Session not found. Complete handshake first."
        case .invalidEncryptedMessage:
            return "Invalid encrypted message format"
        case .invalidUTF8:
            return "Decrypted data is not valid UTF-8"
        }
    }
}

// MARK: - Extensions
extension Array where Element == UInt8 {
    func toHexString() -> String {
        return utilsBytesToHex(data: self)
    }
}
