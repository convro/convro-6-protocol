import Foundation
import CryptoKit

// MARK: - Errors

enum C6PAEADError: Error, LocalizedError, CustomStringConvertible {
    case unsupportedSuite(C6PEncryptionSuite)

    case contextMismatch(field: String)          // mismatched sessionId/streamId/counter/type vs messageKey
    case invalidSessionIdLength(expected: Int, actual: Int)
    case invalidTagLength(expected: Int, actual: Int)

    case decryptFailed

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .unsupportedSuite(let suite):
            return "C6PAEADError.unsupportedSuite(\(suite)) – Swift reference supports only ChaCha20-Poly1305 via CryptoKit."
        case .contextMismatch(let field):
            return "C6PAEADError.contextMismatch(\(field)) – provided context does not match messageKey context"
        case .invalidSessionIdLength(let expected, let actual):
            return "C6PAEADError.invalidSessionIdLength(expected=\(expected), actual=\(actual))"
        case .invalidTagLength(let expected, let actual):
            return "C6PAEADError.invalidTagLength(expected=\(expected), actual=\(actual))"
        case .decryptFailed:
            return "C6PAEADError.decryptFailed – authentication tag mismatch or corrupted data"
        }
    }
}

// MARK: - Wire-level sealed message

/// Wire-level encrypted container.
/// Nonce is not carried here because C6P uses deterministic nonce reconstruction.
struct C6PSealedMessage: Hashable, Codable {
    let ciphertext: Data
    let tag: Data
}

// MARK: - AEAD

/// Protocol-facing AEAD wrapper with C6P-specific canonical AAD.
/// Swift reference currently uses CryptoKit ChaChaPoly.
/// Protocol-level design remains AEAD-agile.
enum C6PAEAD {

    // MARK: Public API – Encrypt

    static func seal(
        plaintext: Data,
        with messageKey: C6PMessageKey,
        nonce: C6PNonce,
        sessionId: C6PSessionId,
        role: C6PRole,
        direction: C6PDirection,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data? = nil
    ) throws -> C6PSealedMessage {

        // Swift reference: only ChaChaPoly via CryptoKit
        guard case .v1_chachaPoly = messageKey.suite else {
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }

        // Canonical stream id (wire-stable)
        let streamId = C6PStreamId.derive(role: role, direction: direction)

        // Defensive: ensure caller does not pass mismatched context
        try validateContext(
            messageKey: messageKey,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter
        )

        // Validate session id size (expected by protocol: currently 4 bytes)
        // NOTE: keep this in sync with C6PSessionId implementation.
        let sidLen = sessionId.data.count
        guard sidLen == 4 else {
            throw C6PAEADError.invalidSessionIdLength(expected: 4, actual: sidLen)
        }

        let aad = buildAAD(
            suite: messageKey.suite,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter,
            extraAAD: extraAAD
        )

        let chachaNonce = try nonce.asChaChaNonce()

        let sealed = try ChaChaPoly.seal(
            plaintext,
            using: messageKey.key,
            nonce: chachaNonce,
            authenticating: aad
        )

        return C6PSealedMessage(ciphertext: sealed.ciphertext, tag: sealed.tag)
    }

    // MARK: Public API – Decrypt

    static func open(
        sealed: C6PSealedMessage,
        with messageKey: C6PMessageKey,
        nonce: C6PNonce,
        sessionId: C6PSessionId,
        role: C6PRole,
        direction: C6PDirection,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data? = nil
    ) throws -> Data {

        // Swift reference: only ChaChaPoly via CryptoKit
        guard case .v1_chachaPoly = messageKey.suite else {
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }

        // ChaChaPoly tag is always 16 bytes
        let expectedTagLen = 16
        guard sealed.tag.count == expectedTagLen else {
            throw C6PAEADError.invalidTagLength(expected: expectedTagLen, actual: sealed.tag.count)
        }

        // Canonical stream id (wire-stable) – MUST match seal()
        let streamId = C6PStreamId.derive(role: role, direction: direction)

        // Defensive: ensure caller does not pass mismatched context
        try validateContext(
            messageKey: messageKey,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter
        )

        // Validate session id size (expected by protocol: currently 4 bytes)
        let sidLen = sessionId.data.count
        guard sidLen == 4 else {
            throw C6PAEADError.invalidSessionIdLength(expected: 4, actual: sidLen)
        }

        let aad = buildAAD(
            suite: messageKey.suite,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter,
            extraAAD: extraAAD
        )

        let chachaNonce = try nonce.asChaChaNonce()

        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: chachaNonce,
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )

        do {
            return try ChaChaPoly.open(sealedBox, using: messageKey.key, authenticating: aad)
        } catch {
            // Never silently fallback.
            throw C6PAEADError.decryptFailed
        }
    }

    // MARK: - Context validation

    private static func validateContext(
        messageKey: C6PMessageKey,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws {
        if messageKey.sessionId != sessionId { throw C6PAEADError.contextMismatch(field: "sessionId") }
        if messageKey.streamId != streamId { throw C6PAEADError.contextMismatch(field: "streamId") }
        if messageKey.messageType != messageType { throw C6PAEADError.contextMismatch(field: "messageType") }
        if messageKey.counter != counter { throw C6PAEADError.contextMismatch(field: "counter") }
    }

    // MARK: - AAD Builder

    /// Canonical AAD layout (fixed order):
    ///
    ///  [ 0 ]    C6P_VERSION (UInt8)
    ///  [ 1 ]    suite (C6PEncryptionSuite.rawValue)
    ///  [..]     sessionId bytes (current: 4 bytes)
    ///  [..]     streamId (C6PStreamId.rawValue)   // wire-stable I→R / R→I
    ///  [..]     messageType.rawValue
    ///  [..]     counter (UInt64, big-endian)
    ///  [..]     extraAAD (optional, raw bytes)
    ///
    /// IMPORTANT:
    /// This AAD is wire-stable. Do not change without bumping protocol version.
    private static func buildAAD(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data? = nil
    ) -> Data {

        let extraLen = extraAAD?.count ?? 0

        var data = Data()
        data.reserveCapacity(1 + 1 + sessionId.data.count + 1 + 1 + 8 + extraLen)

        // version
        data.append(C6P_VERSION)

        // suite
        data.append(suite.rawValue)

        // session id bytes (currently 4 bytes)
        data.append(sessionId.data)

        // stream id (wire-stable)
        data.append(streamId.rawValue)

        // message type
        data.append(messageType.rawValue)

        // counter (UInt64 BE)
        data.append(encodeCounter64(counter.value))

        // optional extra AAD
        if let extra = extraAAD, !extra.isEmpty {
            data.append(extra)
        }

        return data
    }

    // MARK: - Encoding helper

    private static func encodeCounter64(_ value: UInt64) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: MemoryLayout<UInt64>.size)
    }
}
