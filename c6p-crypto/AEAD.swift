import Foundation
import CryptoKit

// routes / wire reminder:
// - Server stores: ciphertext + auth_tag (AEAD tag)
// - ChaCha20-Poly1305 tag length is 16 bytes (CryptoKit).
// - DB can keep VARBINARY(32) for future agility, but DO NOT require tag==32 on wire.

// MARK: - Errors

enum C6PAEADError: Error, LocalizedError, CustomStringConvertible {
    case unsupportedSuite(C6PEncryptionSuite)
    case suiteMismatch(keySuite: C6PEncryptionSuite, nonceSuite: C6PEncryptionSuite)
    case invalidTagLength(expected: Int, actual: Int)
    case decryptFailed

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .unsupportedSuite(let suite):
            return "C6PAEADError.unsupportedSuite(\(suite))"
        case .suiteMismatch(let keySuite, let nonceSuite):
            return "C6PAEADError.suiteMismatch(keySuite=\(keySuite), nonceSuite=\(nonceSuite))"
        case .invalidTagLength(let expected, let actual):
            return "C6PAEADError.invalidTagLength(expected=\(expected), actual=\(actual))"
        case .decryptFailed:
            return "C6PAEADError.decryptFailed (tag mismatch / corrupted data / wrong key or AAD)"
        }
    }
}

// MARK: - Wire-level sealed message (no nonce carried; deterministic reconstruction)

struct C6PSealedMessage: Hashable, Codable {
    let ciphertext: Data
    let tag: Data

    init(ciphertext: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

// MARK: - AEAD (Canonical)

/// Protocol-facing AEAD wrapper with canonical AAD.
/// Nonce is deterministic and must be reconstructed identically on both peers.
///
/// Canonical AAD layout:
///  [ 0 ]    C6P_VERSION (UInt8)
///  [ 1 ]    suite (C6PEncryptionSuite.rawValue)
///  [2..5]   sessionId (4 bytes BE)   // v1
///  [ 6 ]    streamId (C6PStreamId.rawValue)  // wire-stable I→R / R→I
///  [ 7 ]    messageType (C6PMessageType.rawValue)
///  [8..15]  counter (UInt64 BE)
///  [..]     extraAAD (optional, app-defined, must be identical on both sides)
enum C6PAEAD {

    // MARK: - Preferred API (derives nonce from messageKey)

    /// Encrypts using messageKey-bound nonce + canonical AAD.
    static func seal(
        plaintext: Data,
        with messageKey: C6PMessageKey,
        extraAAD: Data? = nil
    ) throws -> C6PSealedMessage {
        let nonce = try C6PNonceSequencer.makeNonce(
            suite: messageKey.suite,
            sessionId: messageKey.sessionId,
            streamId: messageKey.streamId,
            messageType: messageKey.messageType,
            counter: messageKey.counter
        )
        return try seal(plaintext: plaintext, with: messageKey, nonce: nonce, extraAAD: extraAAD)
    }

    /// Decrypts using messageKey-bound nonce + canonical AAD.
    static func open(
        sealed: C6PSealedMessage,
        with messageKey: C6PMessageKey,
        extraAAD: Data? = nil
    ) throws -> Data {
        let nonce = try C6PNonceSequencer.makeNonce(
            suite: messageKey.suite,
            sessionId: messageKey.sessionId,
            streamId: messageKey.streamId,
            messageType: messageKey.messageType,
            counter: messageKey.counter
        )
        return try open(sealed: sealed, with: messageKey, nonce: nonce, extraAAD: extraAAD)
    }

    // MARK: - Lower-level API (accepts precomputed nonce)

    /// Encrypts with explicit nonce (must match suite + deterministic layout).
    static func seal(
        plaintext: Data,
        with messageKey: C6PMessageKey,
        nonce: C6PNonce,
        extraAAD: Data? = nil
    ) throws -> C6PSealedMessage {

        guard messageKey.suite == nonce.suite else {
            throw C6PAEADError.suiteMismatch(keySuite: messageKey.suite, nonceSuite: nonce.suite)
        }

        switch messageKey.suite {
        case .v1_chachaPoly:
            let aad = buildAAD(
                suite: messageKey.suite,
                sessionId: messageKey.sessionId,
                streamId: messageKey.streamId,
                messageType: messageKey.messageType,
                counter: messageKey.counter,
                extraAAD: extraAAD
            )

            let chachaNonce = try nonce.asChaChaNonce()
            let sealed = try ChaChaPoly.seal(
                plaintext,
                using: messageKey.key,
                nonce: chachaNonce,
                authenticating: aad
            )

            // CryptoKit ChaChaPoly.tag is 16 bytes
            return C6PSealedMessage(ciphertext: sealed.ciphertext, tag: sealed.tag)

        default:
            // protocol may support more suites, Swift ref keeps strict
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }
    }

    /// Decrypts with explicit nonce (must match suite + deterministic layout).
    static func open(
        sealed: C6PSealedMessage,
        with messageKey: C6PMessageKey,
        nonce: C6PNonce,
        extraAAD: Data? = nil
    ) throws -> Data {

        guard messageKey.suite == nonce.suite else {
            throw C6PAEADError.suiteMismatch(keySuite: messageKey.suite, nonceSuite: nonce.suite)
        }

        switch messageKey.suite {
        case .v1_chachaPoly:
            let expectedTagLen = 16
            guard sealed.tag.count == expectedTagLen else {
                throw C6PAEADError.invalidTagLength(expected: expectedTagLen, actual: sealed.tag.count)
            }

            let aad = buildAAD(
                suite: messageKey.suite,
                sessionId: messageKey.sessionId,
                streamId: messageKey.streamId,
                messageType: messageKey.messageType,
                counter: messageKey.counter,
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
                // no silent fallbacks
                throw C6PAEADError.decryptFailed
            }

        default:
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }
    }

    // MARK: - Canonical AAD

    private static func buildAAD(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data?
    ) -> Data {
        var data = Data()
        data.reserveCapacity(1 + 1 + 4 + 1 + 1 + 8 + (extraAAD?.count ?? 0))

        data.append(C6P_VERSION)          // 1
        data.append(suite.rawValue)       // 1
        data.append(sessionId.data)       // 4 (v1)
        data.append(streamId.rawValue)    // 1
        data.append(messageType.rawValue) // 1
        data.append(counter.data)         // 8 (UInt64 BE)

        if let extra = extraAAD, !extra.isEmpty {
            data.append(extra)
        }

        return data
    }
}

