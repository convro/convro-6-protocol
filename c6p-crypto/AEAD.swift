import Foundation
import CryptoKit

// MARK: - Errors

enum C6PAEADError: Error, CustomStringConvertible {
    case unsupportedSuite(C6PEncryptionSuite)
    case decryptFailed
    case invalidTagLength(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .unsupportedSuite(let suite):
            return "C6PAEADError.unsupportedSuite(\(suite)) – Swift reference supports only ChaCha20-Poly1305 via CryptoKit; protocol may support more suites."
        case .decryptFailed:
            return "C6PAEADError.decryptFailed – authentication tag mismatch or corrupted data"
        case .invalidTagLength(let expected, let actual):
            return "C6PAEADError.invalidTagLength(expected=\(expected), actual=\(actual))"
        }
    }
}

// MARK: - Wire-level sealed message

/// Wire-level encrypted container.
/// Nonce is not carried here because C6P uses deterministic nonce reconstruction.
struct C6PSealedMessage: Hashable, Codable {
    let ciphertext: Data
    let tag: Data

    init(ciphertext: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

// MARK: - Stream id (wire-stable direction)

/// Wire-stable stream identifier:
/// - i2r: Initiator -> Responder
/// - r2i: Responder -> Initiator
///
/// IMPORTANT:
/// This is NOT "local sending/receiving".
/// Both peers MUST derive the same stream id for the same message.
enum C6PStreamId: UInt8 {
    case i2r = 0x01
    case r2i = 0x02
}

// MARK: - AEAD

/// Protocol-facing AEAD wrapper with C6P-specific, canonical AAD.
/// Swift reference currently uses CryptoKit ChaChaPoly.
/// The protocol-level design remains AEAD-agile.
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

        // Wire-stable stream id derived from (role + local direction) in a symmetric way.
        // Sender and receiver will compute the same stream id for the same message.
        let streamId = deriveStreamId(role: role, direction: direction)

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

        // IMPORTANT:
        // Use the SAME stream id derivation rule as seal().
        let streamId = deriveStreamId(role: role, direction: direction)

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
            // No silent fallbacks.
            throw C6PAEADError.decryptFailed
        }
    }

    // MARK: - Canonical stream derivation

    /// Derives a wire-stable stream id from local (role, direction) such that:
    /// - Initiator sending  => i2r ; Responder receiving => i2r
    /// - Responder sending  => r2i ; Initiator receiving => r2i
    ///
    /// This prevents the "local perspective" mismatch that would otherwise break AAD/nonce.
    private static func deriveStreamId(role: C6PRole, direction: C6PDirection) -> C6PStreamId {
        switch (role, direction) {
        case (.initiator, .sending):   return .i2r
        case (.initiator, .receiving): return .r2i
        case (.responder, .sending):   return .r2i
        case (.responder, .receiving): return .i2r
        }
    }

    // MARK: - AAD Builder

    /// Canonical AAD layout (big-endian, fixed order):
    ///
    ///  [ 0 ]    C6P_VERSION (UInt8)
    ///  [ 1 ]    suite (C6PEncryptionSuite.rawValue)
    ///  [2..5]   sessionId (4 bytes, big-endian)   // NOTE: may become 8 bytes in the ideal target
    ///  [ 6 ]    streamId (C6PStreamId.rawValue)   // wire-stable I→R / R→I
    ///  [ 7 ]    messageType.rawValue
    ///  [8..15]  counter (UInt64, big-endian)
    ///  [..]     extraAAD (optional)
    private static func buildAAD(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data? = nil
    ) -> Data {
        var data = Data()
        data.reserveCapacity(1 + 1 + 4 + 1 + 1 + 8 + (extraAAD?.count ?? 0))

        // version
        data.append(C6P_VERSION)

        // suite
        data.append(suite.rawValue)

        // sessionId (current: 4 bytes BE)
        data.append(sessionId.data)

        // stream
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
        var out = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            let shift = (7 - i) * 8
            out[i] = UInt8((value >> UInt64(shift)) & 0xFF)
        }
        return Data(out)
    }
}
