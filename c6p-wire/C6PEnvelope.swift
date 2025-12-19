//
//  C6PEnvelope.swift
//  C6P-Protocol
//
//  Jeden, wspólny wire-level envelope dla v1.
//  - Minimalny routing
//  - sealed ciphertext
//
//  UWAGA: messageType NIE jest w envelope (ukrywamy “shape” rozmowy).
//  Kontekst DM/group/channel siedzi w E2EE payload (C6PInnerPayload).
//

import Foundation

// MARK: - Delivery state (UI-level)

enum C6PDeliveryState: String, Codable {
    case pending   = "PENDING"
    case delivered = "DELIVERED"
    case read      = "READ"
    case failed    = "FAILED"
}

// MARK: - Envelope

struct C6PEnvelope: Codable, Hashable, CustomStringConvertible {

    // MARK: Protocol

    /// Globalna wersja protokołu (C6P_VERSION).
    let c6pVersion: UInt8

    // MARK: Routing (plaintext, ale wiązane do AEAD przez C6PWireAAD)

    /// Urządzenie nadawcy (router potrzebuje do autoryzacji / diagnostyki).
    let fromDeviceId: C6PDeviceId

    /// Urządzenie odbiorcy (fan-out na konkretne device).
    let toDeviceId: C6PDeviceId

    /// Sesja użyta do szyfrowania (lookup local session state).
    let sessionId: C6PSessionId

    // MARK: Payload (ciphertext)

    /// Zaszyfrowany payload (ciphertext + tag).
    let sealed: C6PSealedMessage

    // MARK: Client IDs / timestamps (app-level)

    /// Id klienta do deduplikacji i retry (UUID string recommended).
    let clientMessageId: String

    /// Lokalny czas utworzenia (nadawca).
    let clientTimestamp: Date

    /// Czas przyjęcia przez serwer (UTC) – ustawiane przez backend.
    var serverTimestamp: Date?

    /// Opcjonalny id po stronie serwera (np. UUID w DB).
    var serverMessageId: String?

    /// Status dla UI.
    var deliveryState: C6PDeliveryState

    // MARK: Init

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

    // MARK: CustomStringConvertible

    var description: String {
        "C6PEnvelope(v=\(c6pVersion), sessionId=\(sessionId.hexString), from=\(fromDeviceId.hexString), to=\(toDeviceId.hexString), clientMessageId=\(clientMessageId))"
    }
}

