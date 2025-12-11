import Foundation
import CryptoKit

// MARK: - Errors

enum C6PAEADError: Error, CustomStringConvertible {
    case unsupportedSuite(C6PEncryptionSuite)
    case decryptFailed
    case invalidCiphertextLength

    var description: String {
        switch self {
        case .unsupportedSuite(let suite):
            return "C6PAEADError.unsupportedSuite(\(suite)) – only ChaCha20-Poly1305 is supported in C6P v1"
        case .decryptFailed:
            return "C6PAEADError.decryptFailed – authentication tag mismatch or corrupted data"
        case .invalidCiphertextLength:
            return "C6PAEADError.invalidCiphertextLength – ciphertext is empty"
        }
    }
}

// MARK: - Sealed Message Wrapper

/// To jest „wire-level” obiekt szyfrowanej wiadomości:
/// - ciphertext: zaszyfrowana treść,
/// - tag: tag uwierzytelniający AEAD.
///
/// Nonce NIE jest tutaj – jest osobno (`C6PNonce`) i w sesji trzymamy go osobno,
/// bo generujemy go deterministycznie (SessionId + direction + role + type + counter).
struct C6PSealedMessage: Hashable, Codable {
    let ciphertext: Data
    let tag: Data

    init(ciphertext: Data, tag: Data) {
        self.ciphertext = ciphertext
        self.tag = tag
    }
}

// MARK: - AEAD Wrapper

/// Thin wrapper nad ChaCha20-Poly1305 z C6P-specyficznym AAD.
///
/// AEAD zawsze autentykuje:
/// - C6P_VERSION (1),
/// - suite,
/// - sessionId,
/// - role,
/// - direction,
/// - messageType,
/// - counter (pełne 64 bity),
/// - opcjonalne `extraAAD` (np. fragment nagłówka wiadomości).
enum C6PAEAD {

    // MARK: Public API – Encrypt

    /// Szyfruje wiadomość przy użyciu danego message key i nonca.
    ///
    /// - Parameters:
    ///   - plaintext: treść do zaszyfrowania.
    ///   - messageKey: klucz wiadomości (z `C6PKeySchedule`).
    ///   - nonce: 12-bajtowy nonce (z `C6PNonceSequencer`).
    ///   - sessionId: identyfikator sesji (4 bajty).
    ///   - role: initiator/responder (lokalne urządzenie).
    ///   - direction: sending/receiving (lokalne urządzenie).
    ///   - messageType: DM / group / channel / control.
    ///   - counter: monotoniczny licznik wiadomości w tym kierunku.
    ///   - extraAAD: opcjonalne dodatkowe AAD (np. meta, które nie jest szyfrowane).
    ///
    /// - Returns: `C6PSealedMessage` (ciphertext + tag).
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

        guard case .v1_chachaPoly = messageKey.suite else {
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }

        // zbuduj AAD
        let aad = buildAAD(
            suite: messageKey.suite,
            sessionId: sessionId,
            role: role,
            direction: direction,
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

        return C6PSealedMessage(
            ciphertext: sealed.ciphertext,
            tag: sealed.tag
        )
    }

    // MARK: Public API – Decrypt

    /// Odszyfrowuje wiadomość – weryfikuje też AAD.
    ///
    /// Musi dostać **dokładnie te same** parametry kontekstowe
    /// (sessionId, role, direction, messageType, counter, extraAAD),
    /// które były użyte przy szyfrowaniu.
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

        guard case .v1_chachaPoly = messageKey.suite else {
            throw C6PAEADError.unsupportedSuite(messageKey.suite)
        }

        guard sealed.ciphertext.isEmpty == false else {
            throw C6PAEADError.invalidCiphertextLength
        }

        let aad = buildAAD(
            suite: messageKey.suite,
            sessionId: sessionId,
            role: role,
            direction: direction,
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
            let plaintext = try ChaChaPoly.open(
                sealedBox,
                using: messageKey.key,
                authenticating: aad
            )
            return plaintext
        } catch {
            // żadnych „cichych” fallbacków – albo się zgadza, albo sesja jest kompromitowana
            throw C6PAEADError.decryptFailed
        }
    }

    // MARK: - AAD Builder

    /// Buduje AAD, które ma być identyczne przy szyfrowaniu i odszyfrowaniu.
    ///
    /// Layout (big-endian, kolejność stała):
    ///
    ///  [ 0 ]    C6P_VERSION (v1 = 0x01)
    ///  [ 1 ]    suite (C6PEncryptionSuite.rawValue)
    ///  [2..5]   sessionId (4 bytes)
    ///  [ 6 ]    role (initiator/responder)
    ///  [ 7 ]    direction (sending/receiving)
    ///  [ 8 ]    messageType.rawValue
    ///  [9..16]  counter (UInt64, big-endian)
    ///  [..]     extraAAD (opcjonalne)
    private static func buildAAD(
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        role: C6PRole,
        direction: C6PDirection,
        messageType: C6PMessageType,
        counter: C6PMessageCounter,
        extraAAD: Data? = nil
    ) -> Data {
        var data = Data()

        // wersja C6P – v1 (można później wyciągnąć do globalnego const, jeśli już jest)
        data.append(0x01) // C6P_VERSION = 1

        // suite
        data.append(suite.rawValue)

        // sessionId (4 bajty)
        data.append(sessionId.data)

        // role
        data.append(encodeRole(role))

        // direction
        data.append(encodeDirection(direction))

        // message type
        data.append(messageType.rawValue)

        // counter (pełne 64 bity, big-endian)
        data.append(encodeCounter64(counter.value))

        // opcjonalne dodatkowe AAD
        if let extra = extraAAD, extra.isEmpty == false {
            data.append(extra)
        }

        return data
    }

    // MARK: - Encoding helpers

    private static func encodeRole(_ role: C6PRole) -> UInt8 {
        switch role {
        case .initiator: return 0x01
        case .responder: return 0x02
        }
    }

    private static func encodeDirection(_ direction: C6PDirection) -> UInt8 {
        switch direction {
        case .sending:   return 0x01
        case .receiving: return 0x02
        }
    }

    private static func encodeCounter64(_ value: UInt64) -> Data {
        var out = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            let shift = (7 - i) * 8
            let byte = UInt8((value >> UInt64(shift)) & 0xFF)
            out[i] = byte
        }
        return Data(out)
    }
}
