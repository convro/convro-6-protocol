import Foundation
import CryptoKit

// MARK: - Errors

enum C6PNonceError: Error, CustomStringConvertible {
    case invalidLength(actual: Int)
    case counterOverflow(value: UInt64)

    var description: String {
        switch self {
        case .invalidLength(let actual):
            return "C6PNonceError.invalidLength(actual=\(actual)) – nonce must be exactly 12 bytes"
        case .counterOverflow(let value):
            return "C6PNonceError.counterOverflow(value=\(value)) – exceeds 48-bit nonce counter range"
        }
    }
}

// MARK: - Nonce Wrapper

/// 12-bajtowy nonce do ChaCha20-Poly1305.
/// Opakowanie z typem, żeby nie wozić po kodzie "gołego" Data / [UInt8].
struct C6PNonce: Hashable, Codable, CustomStringConvertible {

    /// Dokładnie 12 bajtów.
    let data: Data

    init(data: Data) throws {
        guard data.count == 12 else {
            throw C6PNonceError.invalidLength(actual: data.count)
        }
        self.data = data
    }

    /// Dostęp do raw bytes (np. logowanie / debug).
    var rawBytes: [UInt8] {
        Array(data)
    }

    /// Konwersja do CryptoKit nonce.
    func asChaChaNonce() throws -> ChaChaPoly.Nonce {
        try ChaChaPoly.Nonce(data: data)
    }

    var description: String {
        "C6PNonce(\(data.map { String(format: "%02x", $0) }.joined()))"
    }
}

// MARK: - Nonce Sequencer

/// Buduje 12-bajtowe nonces w spójny sposób:
///
/// Layout (big-endian):
///
///  [ 0..3 ]  sessionId (4 bytes)
///  [   4  ]  flags: bit0 = direction, bit1 = role
///  [   5  ]  messageType.rawValue
///  [ 6..11]  counter (lower 48 bits, big-endian)
///
enum C6PNonceSequencer {

    // MARK: Public API

    /// Główna funkcja do budowy nonca dla wiadomości.
    ///
    /// - Parameters:
    ///   - sessionId: identyfikator sesji (4 bajty).
    ///   - direction: sending/receiving z perspektywy lokalnego urządzenia.
    ///   - role: initiator/responder (jak w Session.swift).
    ///   - messageType: DM / group / channel / control.
    ///   - counter: monotoniczny licznik wiadomości w tym kierunku.
    ///
    /// - Throws: `C6PNonceError.counterOverflow` jeśli licznik > 2^48-1.
    static func makeNonce(
        sessionId: C6PSessionId,
        direction: C6PDirection,
        role: C6PRole,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws -> C6PNonce {

        let counterData = try encodeCounter48(counter)
        let flagsByte = encodeFlags(direction: direction, role: role)

        var bytes = [UInt8]()
        bytes.reserveCapacity(12)

        // [0..3] sessionId
        bytes.append(contentsOf: sessionId.bytes)

        // [4] flags
        bytes.append(flagsByte)

        // [5] message type
        bytes.append(messageType.rawValue)

        // [6..11] counter (48-bit)
        bytes.append(contentsOf: counterData)

        let nonceData = Data(bytes)
        return try C6PNonce(data: nonceData)
    }

    /// Wygodny helper: buduje nonce *i* od razu ChaChaPoly.Nonce.
    static func makeChaChaNonce(
        sessionId: C6PSessionId,
        direction: C6PDirection,
        role: C6PRole,
        messageType: C6PMessageType,
        counter: C6PMessageCounter
    ) throws -> ChaChaPoly.Nonce {
        let c6pNonce = try makeNonce(
            sessionId: sessionId,
            direction: direction,
            role: role,
            messageType: messageType,
            counter: counter
        )
        return try c6pNonce.asChaChaNonce()
    }

    // MARK: Internal helpers

    /// Koduje direction + role w jednym bajcie:
    ///
    /// bit0 = direction (0 = sending, 1 = receiving)
    /// bit1 = role      (0 = initiator, 1 = responder)
    ///
    /// Pozostałe bity w v1 = 0 (możliwe rozszerzenia w przyszłości).
    private static func encodeFlags(
        direction: C6PDirection,
        role: C6PRole
    ) -> UInt8 {
        var b: UInt8 = 0

        if direction == .receiving {
            b |= 0x01
        }

        if role == .responder {
            b |= 0x02
        }

        // bity 2..7 zarezerwowane na przyszłość (np. typ sesji, feature flags).
        return b
    }

    /// 48-bitowy zapis licznika (6 bajtów big-endian).
    ///
    /// - Throws: `counterOverflow` jeśli `value > 0x0000_FFFF_FFFF_FFFF`.
    private static func encodeCounter48(_ counter: C6PMessageCounter) throws -> [UInt8] {
        let max48: UInt64 = 0x0000_FFFF_FFFF_FFFF
        let value = counter.value

        guard value <= max48 else {
            throw C6PNonceError.counterOverflow(value: value)
        }

        var out = [UInt8](repeating: 0, count: 6)
        // big-endian: bajt 0 = highest, bajt 5 = lowest z 48-bitów
        for i in 0..<6 {
            let shift = (5 - i) * 8
            let byte = UInt8((value >> UInt64(shift)) & 0xFF)
            out[i] = byte
        }
        return out
    }
}

// MARK: - Small extension on C6PSessionId for bytes

private extension C6PSessionId {
    /// 4-bajtowy identyfikator sesji jako [UInt8].
    var bytes: [UInt8] {
        Array(data)
    }
}
