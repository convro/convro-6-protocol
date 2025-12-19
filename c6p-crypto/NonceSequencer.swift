import Foundation
import CryptoKit

// MARK: - Errors

enum C6PNonceError: Error, CustomStringConvertible {
    case invalidLength(expected: Int, actual: Int)
    case counterOverflow48(value: UInt64)
    case unsupportedSuite(C6PEncryptionSuite)

    var description: String {
        switch self {
        case .invalidLength(let expected, let actual):
            return "C6PNonceError.invalidLength(expected=\(expected), actual=\(actual))"
        case .counterOverflow48(let value):
            return "C6PNonceError.counterOverflow48(value=\(value)) – exceeds 48-bit nonce counter range"
        case .unsupportedSuite(let suite):
            return "C6PNonceError.unsupportedSuite(\(suite)) – nonce layout not defined for this suite"
        }
    }
}

// MARK: - Nonce Wrapper (suite-aware)

/// Protocol-level nonce wrapper.
/// Nonce length depends on the AEAD suite:
/// - ChaCha20-Poly1305: 12 bytes
/// - AEGIS-128L:        16 bytes
/// - XChaCha20-Poly1305:24 bytes
struct C6PNonce: Hashable, Codable, CustomStringConvertible {

    let suite: C6PEncryptionSuite
    let data: Data

    init(suite: C6PEncryptionSuite, data: Data) throws {
        let expected = C6PNonceSequencer.expectedNonceLength(for: suite)
        guard data.count == expected else {
            throw C6PNonceError.invalidLength(expected: expected, actual: data.count)
        }
        self.suite = suite
        self.data = data
    }

    var rawBytes: [UInt8] { Array(data) }

    /// CryptoKit adapter for ChaChaPoly only (12B).
    func asChaChaNonce() throws -> ChaChaPoly.Nonce {
        let expected = C6PNonceSequencer.expectedNonceLength(for: .v1_chachaPoly)
        guard suite == .v1_chachaPoly else {
            throw C6PNonceError.unsupportedSuite(suite)
        }
        guard data.count == expected else {
            throw C6PNonceError.invalidLength(expected: expected, actual: data.count)
        }
        return try ChaChaPoly.Nonce(data: data)
    }

    var description: String {
        "C6PNonce(suite=\(suite), \(data.map { String(format: "%02x", $0) }.joined()))"
    }
}

// MARK: - Nonce Sequencer

/// Deterministic nonce construction.
/// IMPORTANT: Uses wire-stable stream id (I→R / R→I), NOT local sending/receiving.
///
/// Layouts (big-endian):
///
/// Suite: ChaCha20-Poly1305 (12B)
///  [0..3]  sessionId (4B)
///  [  4 ]  streamId (1B)   // I→R or R→I
///  [  5 ]  messageType (1B)
///  [6..11] counter48 (6B, BE)  // lower 48 bits
///
/// Suite: AEGIS-128L (16B)
///  [0..3]   sessionId (4B)
///  [  4 ]   streamId (1B)
///  [  5 ]   messageType (1B)
///  [6..7]   reserved (2B = 0x00)
///  [8..15]  counter64 (8B, BE)
///
/// Suite: XChaCha20-Poly1305 (24B)
///  [0..3]   sessionId (4B)
///  [  4 ]   streamId (1B)
///  [  5 ]   messageType (1B)
///  [6..7]   reserved (2B = 0x00)
///  [8..15]  counter64 (8B, BE)
///  [16..23] reserved (8B = 0x00)
enum C6PNonceSequencer {

    // MARK: Public API

    static func expectedNonceLength(for suite: C6PEncryptionSuite) -> Int {
        switch suite {
        case .v1_chachaPoly: return 12
        case .v1_aegis128l:  return 16
        case .v1_xchachaPoly:return 24
        default:
            // keep strict: every new suite must define nonce length explicitly
            return 0
        }
    }

    /// Canonical nonce builder (preferred): accepts wire-stable stream id.
    static func makeNonce(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws -> C6PNonce {

        switch suite {
        case .v1_chachaPoly:
            let c48 = try encodeCounter48(counter.value)
            var bytes = [UInt8]()
            bytes.reserveCapacity(12)
            bytes.append(contentsOf: sessionId.bytes4)
            bytes.append(streamId.rawValue)
            bytes.append(messageType.rawValue)
            bytes.append(contentsOf: c48)
            return try C6PNonce(suite: suite, data: Data(bytes))

        case .v1_aegis128l:
            var bytes = [UInt8]()
            bytes.reserveCapacity(16)
            bytes.append(contentsOf: sessionId.bytes4)
            bytes.append(streamId.rawValue)
            bytes.append(messageType.rawValue)
            bytes.append(0x00) // reserved
            bytes.append(0x00) // reserved
            bytes.append(contentsOf: encodeCounter64(counter.value))
            return try C6PNonce(suite: suite, data: Data(bytes))

        case .v1_xchachaPoly:
            var bytes = [UInt8]()
            bytes.reserveCapacity(24)
            bytes.append(contentsOf: sessionId.bytes4)
            bytes.append(streamId.rawValue)
            bytes.append(messageType.rawValue)
            bytes.append(0x00) // reserved
            bytes.append(0x00) // reserved
            bytes.append(contentsOf: encodeCounter64(counter.value))
            bytes.append(contentsOf: [UInt8](repeating: 0x00, count: 8)) // reserved
            return try C6PNonce(suite: suite, data: Data(bytes))

        default:
            throw C6PNonceError.unsupportedSuite(suite)
        }
    }

    /// Convenience: build CryptoKit ChaChaPoly.Nonce (12B).
    static func makeChaChaNonce(
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws -> ChaChaPoly.Nonce {
        let nonce = try makeNonce(
            suite: .v1_chachaPoly,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter
        )
        return try nonce.asChaChaNonce()
    }

    // MARK: Optional compatibility overload (NOT recommended)

    /// Compatibility overload for legacy call-sites.
    /// Converts local (role, direction) to wire-stable stream id.
    /// Prefer passing streamId directly.
    static func makeNonce(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        role: C6PRole,
        direction: C6PDirection,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws -> C6PNonce {
        let streamId = C6PStreamId.derive(role: role, direction: direction)
        return try makeNonce(
            suite: suite,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter
        )
    }

    // MARK: - Internal encoders

    private static func encodeCounter48(_ value: UInt64) throws -> [UInt8] {
        let max48: UInt64 = 0x0000_FFFF_FFFF_FFFF
        guard value <= max48 else {
            throw C6PNonceError.counterOverflow48(value: value)
        }
        var out = [UInt8](repeating: 0, count: 6)
        for i in 0..<6 {
            let shift = (5 - i) * 8
            out[i] = UInt8((value >> UInt64(shift)) & 0xFF)
        }
        return out
    }

    private static func encodeCounter64(_ value: UInt64) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            let shift = (7 - i) * 8
            out[i] = UInt8((value >> UInt64(shift)) & 0xFF)
        }
        return out
    }
}

// MARK: - SessionId bytes helper (4B)

private extension C6PSessionId {
    var bytes4: [UInt8] { Array(data) } // data is 4 bytes BE in your current model
}

