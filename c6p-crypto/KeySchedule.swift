import Foundation
import CryptoKit

// MARK: - Role & Direction (local only)

/// Perspective of this device in the session.
enum C6PRole: String, Codable {
    case initiator = "INITIATOR"
    case responder = "RESPONDER"
}

/// Direction from POV of THIS device (local).
/// IMPORTANT: local direction must never be used directly as wire context.
/// For wire-stable context use C6PStreamId.
enum C6PDirection: String, Codable {
    case sending   = "SENDING"
    case receiving = "RECEIVING"
}

// MARK: - Wire-stable stream id (canonical)

/// Wire-stable stream identifier:
/// - i2r: Initiator -> Responder
/// - r2i: Responder -> Initiator
///
/// This is the canonical notion of direction used for:
/// - chain key separation
/// - message key derivation context
/// - nonce/AAD binding (see AEAD.swift)
enum C6PStreamId: UInt8, Codable {
    case i2r = 0x01
    case r2i = 0x02

    /// Derives wire-stable stream id from local (role, direction) in a symmetric way:
    /// - Initiator sending  => i2r ; Responder receiving => i2r
    /// - Responder sending  => r2i ; Initiator receiving => r2i
    static func derive(role: C6PRole, direction: C6PDirection) -> C6PStreamId {
        switch (role, direction) {
        case (.initiator, .sending):   return .i2r
        case (.initiator, .receiving): return .r2i
        case (.responder, .sending):   return .r2i
        case (.responder, .receiving): return .i2r
        }
    }
}

// MARK: - Root Key

/// 32-byte root key for a session.
/// Derived from initial ECDH shared secret + handshake transcript salt + context.
struct C6PRootKey: Hashable, Codable, CustomStringConvertible {

    /// 32-byte key material
    let keyMaterial: Data

    /// Session identifier (currently 4 bytes)
    let sessionId: C6PSessionId

    /// Initiator device id
    let initiatorDeviceId: C6PDeviceId

    /// Responder device id
    let responderDeviceId: C6PDeviceId

    /// Algorithm identifiers (canonical)
    let dhAlgorithmId: String
    let kdfAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        dhAlgorithmId: String = C6PAlgorithmId.dhX25519,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) {
        precondition(keyMaterial.count == 32, "Root key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.dhAlgorithmId = dhAlgorithmId
        self.kdfAlgorithmId = kdfAlgorithmId
    }

    var description: String {
        "C6PRootKey(sessionId=\(sessionId.hexString), dh=\(dhAlgorithmId), kdf=\(kdfAlgorithmId))"
    }
}

// MARK: - Chain Key

/// 32-byte chain key per session stream (I→R or R→I).
/// This is wire-stable: both peers can derive identical CK for a given stream.
struct C6PChainKey: Hashable, Codable, CustomStringConvertible {

    let keyMaterial: Data
    let sessionId: C6PSessionId

    /// Canonical stream id (wire-stable)
    let streamId: C6PStreamId

    /// KDF algorithm id used
    let kdfAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) {
        precondition(keyMaterial.count == 32, "Chain key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.streamId = streamId
        self.kdfAlgorithmId = kdfAlgorithmId
    }

    var description: String {
        "C6PChainKey(sessionId=\(sessionId.hexString), stream=\(streamId))"
    }
}

// MARK: - Message Key

/// Per-message AEAD key.
/// NOTE: This matches AEAD.swift expectations: suite + key.
struct C6PMessageKey: Hashable, Codable, CustomStringConvertible {

    let keyMaterial: Data
    let sessionId: C6PSessionId
    let streamId: C6PStreamId
    let counter: C6PMessageCounter
    let messageType: C6PMessageType

    /// Negotiated/selected encryption suite for this session/message.
    let suite: C6PEncryptionSuite

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) {
        precondition(keyMaterial.count == 32, "Message key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.streamId = streamId
        self.counter = counter
        self.messageType = messageType
        self.suite = suite
    }

    /// CryptoKit key (for suites implemented via CryptoKit)
    var key: SymmetricKey {
        SymmetricKey(data: keyMaterial)
    }

    var description: String {
        "C6PMessageKey(sessionId=\(sessionId.hexString), stream=\(streamId), counter=\(counter.value), suite=\(suite))"
    }
}

// MARK: - Key Schedule

/// Central KDF pipeline for deriving:
/// - Root Key from handshake secret + transcript salt
/// - Two chain keys: I→R and R→I
/// - Per-message keys via ratcheting (chain advancement)
enum C6PKeySchedule {

    // HKDF info labels (domain separation)
    private static let rootLabel       = "C6P_ROOT_KEY_V1"
    private static let chainLabel      = "C6P_CHAIN_KEY_V1"
    private static let stepLabel       = "C6P_CHAIN_STEP_V1"     // produces MK + CK_next
    private static let messageLabel    = "C6P_MESSAGE_KEY_V1"    // (optional) single-output MK only

    // MARK: Root Key

    /// Derives initial root key.
    ///
    /// Inputs:
    /// - sharedSecret: ECDH shared secret (X25519)
    /// - salt: transcript hash / handshake context salt (recommended: 32B)
    /// - sessionId + device ids
    static func deriveInitialRootKey(
        sharedSecret: Data,
        salt: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId
    ) -> C6PRootKey {

        var info = Data()
        info.append(rootLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(C6PAlgorithmId.dhX25519.data(using: .utf8)!)
        info.append(C6PAlgorithmId.kdfHKDFSHA256.data(using: .utf8)!)
        info.append(sessionId.data)
        info.append(initiatorDeviceId.data)
        info.append(responderDeviceId.data)

        let rootBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: sharedSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return C6PRootKey(
            keyMaterial: rootBytes,
            sessionId: sessionId,
            initiatorDeviceId: initiatorDeviceId,
            responderDeviceId: responderDeviceId
        )
    }

    // MARK: Initial Chain Keys

    /// Derives the two initial chain keys for a session:
    /// - CK_i2r: initiator->responder stream
    /// - CK_r2i: responder->initiator stream
    ///
    /// Both peers can derive both keys identically, because they are wire-stable.
    static func deriveInitialChainKeys(rootKey: C6PRootKey) -> (i2r: C6PChainKey, r2i: C6PChainKey) {
        let ckI2R = deriveChainKey(rootKey: rootKey, streamId: .i2r)
        let ckR2I = deriveChainKey(rootKey: rootKey, streamId: .r2i)
        return (i2r: ckI2R, r2i: ckR2I)
    }

    /// Derives a chain key for a given stream id.
    private static func deriveChainKey(rootKey: C6PRootKey, streamId: C6PStreamId) -> C6PChainKey {

        var info = Data()
        info.append(chainLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(rootKey.kdfAlgorithmId.data(using: .utf8)!)
        info.append(rootKey.sessionId.data)

        // bind to both devices and stream for domain separation
        info.append(rootKey.initiatorDeviceId.data)
        info.append(rootKey.responderDeviceId.data)
        info.append(streamId.rawValue)

        let chainBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: rootKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return C6PChainKey(
            keyMaterial: chainBytes,
            sessionId: rootKey.sessionId,
            streamId: streamId,
            kdfAlgorithmId: rootKey.kdfAlgorithmId
        )
    }

    // MARK: Chain Step (recommended)

    /// Advances the chain and derives a fresh message key in one KDF step:
    /// output = HKDF(CK, info, 64) => MK(32) || CK_next(32)
    ///
    /// This is the preferred design:
    /// - ensures per-message uniqueness
    /// - provides forward secrecy across steps
    ///
    /// The `counter` is included to bind message identity (optional but recommended).
    static func deriveMessageKeyAndRatchet(
        from chainKey: C6PChainKey,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) -> (messageKey: C6PMessageKey, nextChainKey: C6PChainKey) {

        var info = Data()
        info.append(stepLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(chainKey.kdfAlgorithmId.data(using: .utf8)!)
        info.append(chainKey.sessionId.data)
        info.append(chainKey.streamId.rawValue)
        info.append(messageType.rawValue)
        info.append(counter.data)

        let out64 = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 64
        )

        let mkBytes = out64.prefix(32)
        let ckNextBytes = out64.suffix(32)

        let mk = C6PMessageKey(
            keyMaterial: Data(mkBytes),
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            counter: counter,
            messageType: messageType,
            suite: suite
        )

        let ckNext = C6PChainKey(
            keyMaterial: Data(ckNextBytes),
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            kdfAlgorithmId: chainKey.kdfAlgorithmId
        )

        return (messageKey: mk, nextChainKey: ckNext)
    }

    // MARK: Legacy single-output MK (optional)

    /// Derives only a message key from the current chain key without advancing it.
    /// Prefer `deriveMessageKeyAndRatchet` unless you have a strict reason.
    static func deriveMessageKeyOnly(
        from chainKey: C6PChainKey,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) -> C6PMessageKey {

        var info = Data()
        info.append(messageLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(chainKey.kdfAlgorithmId.data(using: .utf8)!)
        info.append(chainKey.sessionId.data)
        info.append(chainKey.streamId.rawValue)
        info.append(messageType.rawValue)
        info.append(counter.data)

        let mkBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return C6PMessageKey(
            keyMaterial: mkBytes,
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            counter: counter,
            messageType: messageType,
            suite: suite
        )
    }
}
