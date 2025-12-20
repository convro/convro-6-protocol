import Foundation
import CryptoKit

// MARK: - Role & Direction (local only)

enum C6PRole: String, Codable {
    case initiator = "INITIATOR"
    case responder = "RESPONDER"
}

enum C6PDirection: String, Codable {
    case sending   = "SENDING"
    case receiving = "RECEIVING"
}

// MARK: - Wire-stable stream id (canonical)

enum C6PStreamId: UInt8, Codable {
    case i2r = 0x01
    case r2i = 0x02

    static func derive(role: C6PRole, direction: C6PDirection) -> C6PStreamId {
        switch (role, direction) {
        case (.initiator, .sending):   return .i2r
        case (.initiator, .receiving): return .r2i
        case (.responder, .sending):   return .r2i
        case (.responder, .receiving): return .i2r
        }
    }
}

// MARK: - Errors

enum C6PKeyScheduleError: Error, LocalizedError {
    case invalidLength(field: String, expected: Int, got: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidLength(field, expected, got):
            return "Invalid length for \(field). Expected \(expected) bytes, got \(got)."
        }
    }
}

// MARK: - Root Key

struct C6PRootKey: Hashable, Codable, CustomStringConvertible {
    let keyMaterial: Data
    let sessionId: C6PSessionId
    let initiatorDeviceId: C6PDeviceId
    let responderDeviceId: C6PDeviceId
    let dhAlgorithmId: String
    let kdfAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        dhAlgorithmId: String = C6PAlgorithmId.dhX25519,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) throws {
        guard keyMaterial.count == 32 else {
            throw C6PKeyScheduleError.invalidLength(field: "rootKey", expected: 32, got: keyMaterial.count)
        }
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

struct C6PChainKey: Hashable, Codable, CustomStringConvertible {
    let keyMaterial: Data
    let sessionId: C6PSessionId
    let streamId: C6PStreamId
    let kdfAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) throws {
        guard keyMaterial.count == 32 else {
            throw C6PKeyScheduleError.invalidLength(field: "chainKey", expected: 32, got: keyMaterial.count)
        }
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

struct C6PMessageKey: Hashable, Codable, CustomStringConvertible {
    let keyMaterial: Data
    let sessionId: C6PSessionId
    let streamId: C6PStreamId
    let counter: C6PMessageCounter
    let messageType: C6PMessageType
    let suite: C6PEncryptionSuite

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) throws {
        guard keyMaterial.count == 32 else {
            throw C6PKeyScheduleError.invalidLength(field: "messageKey", expected: 32, got: keyMaterial.count)
        }
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.streamId = streamId
        self.counter = counter
        self.messageType = messageType
        self.suite = suite
    }

    var key: SymmetricKey { SymmetricKey(data: keyMaterial) }

    var description: String {
        "C6PMessageKey(sessionId=\(sessionId.hexString), stream=\(streamId), counter=\(counter.value), suite=\(suite))"
    }
}

// MARK: - Data helpers (stable encoding)

private extension Data {
    mutating func appendUInt8(_ v: UInt8) {
        append(contentsOf: [v])
    }

    mutating func appendString(_ s: String) {
        // UTF-8 bytes, no length prefix (labels are fixed + unique)
        append(s.data(using: .utf8)!)
    }

    mutating func appendFixed(_ d: Data, _ field: String, expected: Int) throws {
        guard d.count == expected else {
            throw C6PKeyScheduleError.invalidLength(field: field, expected: expected, got: d.count)
        }
        append(d)
    }
}

// MARK: - Key Schedule (canonical)

enum C6PKeySchedule {

    private static let rootLabel    = "C6P_ROOT_KEY_V1"
    private static let chainLabel   = "C6P_CHAIN_KEY_V1"
    private static let stepLabel    = "C6P_CHAIN_STEP_V1"
    private static let messageLabel = "C6P_MESSAGE_KEY_V1"

    /// Canonical transcript salt length.
    /// We expect transcriptHash = SHA256(handshakeTranscript) => 32 bytes.
    private static let transcriptSaltLen = 32

    // MARK: Root Key

    static func deriveInitialRootKey(
        sharedSecret: Data,
        salt: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId
    ) throws -> C6PRootKey {

        guard sharedSecret.count == 32 else {
            throw C6PKeyScheduleError.invalidLength(field: "sharedSecret", expected: 32, got: sharedSecret.count)
        }
        guard salt.count == transcriptSaltLen else {
            throw C6PKeyScheduleError.invalidLength(field: "salt", expected: transcriptSaltLen, got: salt.count)
        }

        var info = Data()
        info.appendString(rootLabel)
        info.append(C6P_VERSION)
        info.appendString(C6PAlgorithmId.dhX25519)
        info.appendString(C6PAlgorithmId.kdfHKDFSHA256)

        info.append(sessionId.data)
        info.append(initiatorDeviceId.data)
        info.append(responderDeviceId.data)

        let rootBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: sharedSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return try C6PRootKey(
            keyMaterial: rootBytes,
            sessionId: sessionId,
            initiatorDeviceId: initiatorDeviceId,
            responderDeviceId: responderDeviceId
        )
    }

    // MARK: Initial Chain Keys

    static func deriveInitialChainKeys(rootKey: C6PRootKey) throws -> (i2r: C6PChainKey, r2i: C6PChainKey) {
        let ckI2R = try deriveChainKey(rootKey: rootKey, streamId: .i2r)
        let ckR2I = try deriveChainKey(rootKey: rootKey, streamId: .r2i)
        return (i2r: ckI2R, r2i: ckR2I)
    }

    private static func deriveChainKey(rootKey: C6PRootKey, streamId: C6PStreamId) throws -> C6PChainKey {
        var info = Data()
        info.appendString(chainLabel)
        info.append(C6P_VERSION)
        info.appendString(rootKey.kdfAlgorithmId)

        info.append(rootKey.sessionId.data)
        info.append(rootKey.initiatorDeviceId.data)
        info.append(rootKey.responderDeviceId.data)
        info.appendUInt8(streamId.rawValue)

        let chainBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: rootKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return try C6PChainKey(
            keyMaterial: chainBytes,
            sessionId: rootKey.sessionId,
            streamId: streamId,
            kdfAlgorithmId: rootKey.kdfAlgorithmId
        )
    }

    // MARK: Chain Step (preferred)

    static func deriveMessageKeyAndRatchet(
        from chainKey: C6PChainKey,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) throws -> (messageKey: C6PMessageKey, nextChainKey: C6PChainKey) {

        var info = Data()
        info.appendString(stepLabel)
        info.append(C6P_VERSION)
        info.appendString(chainKey.kdfAlgorithmId)

        info.append(chainKey.sessionId.data)
        info.appendUInt8(chainKey.streamId.rawValue)
        info.appendUInt8(messageType.rawValue)
        info.append(counter.data)

        let out64 = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 64
        )

        let mkBytes = Data(out64.prefix(32))
        let ckNextBytes = Data(out64.suffix(32))

        let mk = try C6PMessageKey(
            keyMaterial: mkBytes,
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            counter: counter,
            messageType: messageType,
            suite: suite
        )

        let ckNext = try C6PChainKey(
            keyMaterial: ckNextBytes,
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            kdfAlgorithmId: chainKey.kdfAlgorithmId
        )

        return (mk, ckNext)
    }

    // MARK: Legacy single-output MK (optional)

    static func deriveMessageKeyOnly(
        from chainKey: C6PChainKey,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite
    ) throws -> C6PMessageKey {

        var info = Data()
        info.appendString(messageLabel)
        info.append(C6P_VERSION)
        info.appendString(chainKey.kdfAlgorithmId)

        info.append(chainKey.sessionId.data)
        info.appendUInt8(chainKey.streamId.rawValue)
        info.appendUInt8(messageType.rawValue)
        info.append(counter.data)

        let mkBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return try C6PMessageKey(
            keyMaterial: mkBytes,
            sessionId: chainKey.sessionId,
            streamId: chainKey.streamId,
            counter: counter,
            messageType: messageType,
            suite: suite
        )
    }
}
