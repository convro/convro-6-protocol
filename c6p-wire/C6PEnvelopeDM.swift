//
//  C6PEnvelopeDM.swift
//  C6P-Protocol
//
//  Wire-level koperta dla wiadomości DM.
//  To jest dokładnie to, co:
//  - klient wysyła na backend (JSON),
//  - backend przechowuje w DB,
//  - backend zwraca przy pull/pollu,
//  - klient z powrotem deserializuje i odszyfrowuje.
//
//  Zawiera minimalne metadane routingu + zaszyfrowany payload.
//

import Foundation

/// Stan dostarczenia wiadomości z perspektywy klienta.
/// Backend może mieć własne stany, ale te są wystarczające na UI.
enum C6PDeliveryState: String, Codable {
    case pending   = "PENDING"    // wysłane do serwera, czeka w kolejce
    case delivered = "DELIVERED"  // serwer wypchnął do odbiorcy
    case read      = "READ"       // opcjonalnie – odbiorca potwierdził odczyt
    case failed    = "FAILED"     // błąd wysyłki / nieosiągalny odbiorca
}

/// Wire-level koperta dla pojedynczej wiadomości DM.
///
/// ⚠️ Uwaga:
/// - Wszystko poza `sealed` NIE jest używane w kryptografii (nie jest w AAD),
///   więc musi być traktowane jako *niezaufane* z perspektywy modelu zagrożeń.
/// - Cryptography (AEAD + AAD) używa: sessionId, role, direction, messageType, counter –
///   to bierzemy z C6PSessionState i C6PMessageKey, nie z tej koperty.
struct C6PEnvelopeDM: Codable, Hashable, CustomStringConvertible {

    // MARK: - Ogólne

    /// Wersja protokołu C6P (globalne `C6P_VERSION`).
    let c6pVersion: UInt8

    /// Typ wiadomości – dla DM zawsze `.dm`, ale trzymamy tu enum
    /// żeby mieć spójność z innymi typami (group / channel / control).
    let messageType: C6PMessageType

    // MARK: - Routing

    /// Urządzenie nadawcy (lokalne urządzenie, które szyfrowało payload).
    let fromDeviceId: C6PDeviceId

    /// Urządzenie odbiorcy (konkretny device – nie user).
    let toDeviceId: C6PDeviceId

    /// Sesja C6P użyta do zaszyfrowania wiadomości.
    /// Służy do znalezienia właściwego C6PSessionState po stronie klienta.
    let sessionId: C6PSessionId

    // MARK: - Payload

    /// Zaszyfrowany payload (ciphertext + tag).
    let sealed: C6PSealedMessage

    // MARK: - Id / Timestamps / Delivery

    /// Kliencki identyfikator wiadomości (np. UUID string),
    /// używany do deduplikacji / retry itp. po stronie aplikacji.
    let clientMessageId: String

    /// Czas utworzenia wiadomości po stronie nadawcy (lokalny czas).
    let clientTimestamp: Date

    /// Czas przyjęcia wiadomości przez serwer (UTC),
    /// ustawiany przez backend. Może być `nil` po wysłaniu.
    var serverTimestamp: Date?

    /// Opcjonalny identyfikator wiadomości po stronie serwera (np. UUID z DB).
    /// Nie jest wymagany do działania kryptografii – czysto aplikacyjnie.
    var serverMessageId: String?

    /// Lokalny stan dostarczenia (UI). Backend może go nadpisywać
    /// na podstawie swojej logiki.
    var deliveryState: C6PDeliveryState

    // MARK: - Initializer

    /// Główny initializer używany po stronie klienta przy tworzeniu envelope'u
    /// przed wysłaniem na backend.
    init(
        fromDeviceId: C6PDeviceId,
        toDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        sealed: C6PSealedMessage,
        clientMessageId: String = UUID().uuidString,
        clientTimestamp: Date = Date(),
        serverTimestamp: Date? = nil,
        serverMessageId: String? = nil,
        deliveryState: C6PDeliveryState = .pending
    ) {
        self.c6pVersion = C6P_VERSION
        self.messageType = .dm
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.sessionId = sessionId
        self.sealed = sealed
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.serverTimestamp = serverTimestamp
        self.serverMessageId = serverMessageId
        self.deliveryState = deliveryState
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "C6PEnvelopeDM(sessionId=\(sessionId.hexString), from=\(fromDeviceId.hexString), to=\(toDeviceId.hexString), msgType=\(messageType), clientMessageId=\(clientMessageId))"
    }
}
