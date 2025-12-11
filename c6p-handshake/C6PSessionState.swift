//
//  C6PSessionState.swift
//  C6P-Protocol
//
//  Reprezentuje pełny stan sesji C6P pomiędzy dwoma urządzeniami
//  (localDeviceId, remoteDeviceId).
//
//  Zawiera:
//  - sessionId
//  - role (INITIATOR / RESPONDER)
//  - rootKey
//  - chain keys SEND / RECV
//  - liczniki wiadomości SEND / RECV
//  - podstawowe metadane (status, createdAt, updatedAt)
//

import Foundation

// MARK: - Session Status

/// Status sesji z punktu widzenia lokalnego urządzenia.
/// Pozwala zaznaczyć, czy sesja jest aktywna, zamknięta, albo
/// wymaga ponownego handshaku (np. po wykryciu problemów).
enum C6PSessionStatus: String, Codable {
    case active           = "ACTIVE"
    case closed           = "CLOSED"
    case needsReHandshake = "NEEDS_REHANDSHAKE"
}

// MARK: - Session State

/// Pełny stan sesji C6P między `localDeviceId` a `remoteDeviceId`.
///
/// Ta struktura jest tym, co zapisujesz w storage (Keychain / plik / DB),
/// a następnie odtwarzasz przy starcie aplikacji.
///
/// Wszystkie pola są jawne i możliwe do audytu – żadnej magii.
struct C6PSessionState: Hashable, Codable, CustomStringConvertible {

    // MARK: - Identyfikatory

    /// Identyfikator sesji (4 bajty, wspólny dla obu stron).
    let sessionId: C6PSessionId

    /// Lokalne urządzenie (to, na którym działa ten kod).
    let localDeviceId: C6PDeviceId

    /// Zdalne urządzenie (druga strona sesji).
    let remoteDeviceId: C6PDeviceId

    /// Rola lokalnego urządzenia w tej sesji.
    /// - `.initiator` – jeśli to my zaczęliśmy handshake99;
    /// - `.responder` – jeśli odpowiadaliśmy na ofertę.
    let role: C6PRole

    // MARK: - Klucze

    /// Root key dla tej sesji – wyprowadzony z handshake99.
    var rootKey: C6PRootKey

    /// Łańcuch kluczy używany do wysyłania wiadomości (SEND).
    var sendChainKey: C6PChainKey

    /// Łańcuch kluczy używany do odbierania wiadomości (RECV).
    var recvChainKey: C6PChainKey

    /// Licznik wiadomości wychodzących (per kierunek z punktu widzenia lokalnego urządzenia).
    var sendCounter: C6PMessageCounter

    /// Licznik wiadomości przychodzących.
    var recvCounter: C6PMessageCounter

    // MARK: - Metadane

    /// Kiedy sesja została utworzona (lokalny czas urządzenia).
    var createdAt: Date

    /// Kiedy sesja była ostatnio zmodyfikowana (np. wysłanie / odebranie wiadomości).
    var updatedAt: Date

    /// Status sesji.
    var status: C6PSessionStatus

    // MARK: - Computed

    /// Czy lokalne urządzenie jest inicjatorem tej sesji.
    var isInitiator: Bool {
        role == .initiator
    }

    /// Czy lokalne urządzenie jest respondentem tej sesji.
    var isResponder: Bool {
        role == .responder
    }

    // MARK: - Initializer

    /// Główny initializer. Zakłada, że przekazane rootKey / chainKeys są
    /// już poprawnie wyprowadzone (np. z C6PHandshake99 / C6PKeySchedule).
    ///
    /// Wykonuje kilka spójnościowych `precondition`, żeby złapać
    /// potencjalne błędy już na etapie developmentu.
    init(
        sessionId: C6PSessionId,
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId,
        role: C6PRole,
        rootKey: C6PRootKey,
        sendChainKey: C6PChainKey,
        recvChainKey: C6PChainKey,
        sendCounter: C6PMessageCounter = C6PMessageCounter(),
        recvCounter: C6PMessageCounter = C6PMessageCounter(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: C6PSessionStatus = .active
    ) {
        // Spójność sessionId:
        precondition(rootKey.sessionId == sessionId, "RootKey.sessionId must match C6PSessionState.sessionId")
        precondition(sendChainKey.sessionId == sessionId, "sendChainKey.sessionId must match sessionId")
        precondition(recvChainKey.sessionId == sessionId, "recvChainKey.sessionId must match sessionId")

        // Spójność device IDs w rootKey:
        // rootKey.initiatorDeviceId / responderDeviceId muszą odpowiadać roli.
        switch role {
        case .initiator:
            precondition(rootKey.initiatorDeviceId == localDeviceId, "For role=initiator, rootKey.initiatorDeviceId must be localDeviceId")
            precondition(rootKey.responderDeviceId == remoteDeviceId, "For role=initiator, rootKey.responderDeviceId must be remoteDeviceId")
        case .responder:
            precondition(rootKey.initiatorDeviceId == remoteDeviceId, "For role=responder, rootKey.initiatorDeviceId must be remoteDeviceId")
            precondition(rootKey.responderDeviceId == localDeviceId, "For role=responder, rootKey.responderDeviceId must be localDeviceId")
        }

        // Spójność device IDs w chain keys:
        precondition(sendChainKey.selfDeviceId == localDeviceId, "sendChainKey.selfDeviceId must be localDeviceId")
        precondition(sendChainKey.remoteDeviceId == remoteDeviceId, "sendChainKey.remoteDeviceId must be remoteDeviceId")
        precondition(recvChainKey.selfDeviceId == localDeviceId, "recvChainKey.selfDeviceId must be localDeviceId")
        precondition(recvChainKey.remoteDeviceId == remoteDeviceId, "recvChainKey.remoteDeviceId must be remoteDeviceId")

        // Spójność ról i kierunków w chain keys:
        precondition(sendChainKey.role == role, "sendChainKey.role must match session role")
        precondition(recvChainKey.role == role, "recvChainKey.role must match session role")
        precondition(sendChainKey.direction == .sending, "sendChainKey.direction must be .sending")
        precondition(recvChainKey.direction == .receiving, "recvChainKey.direction must be .receiving")

        self.sessionId = sessionId
        self.localDeviceId = localDeviceId
        self.remoteDeviceId = remoteDeviceId
        self.role = role
        self.rootKey = rootKey
        self.sendChainKey = sendChainKey
        self.recvChainKey = recvChainKey
        self.sendCounter = sendCounter
        self.recvCounter = recvCounter
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }

    // MARK: - Mutating helpers

    /// Aktualizuje znacznik czasu `updatedAt` na teraz.
    mutating func markUpdated() {
        updatedAt = Date()
    }

    /// Oznacza sesję jako zamkniętą. Możesz np. wywołać to po
    /// twardym resecie tożsamości / logout na urządzeniu.
    mutating func markClosed() {
        status = .closed
        updatedAt = Date()
    }

    /// Oznacza, że sesja powinna zostać odtworzona przez nowy handshake
    /// (np. po wykryciu niespójnego stanu / podejrzeniu kompromitacji).
    mutating func markNeedsReHandshake() {
        status = .needsReHandshake
        updatedAt = Date()
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "C6PSessionState(sessionId=\(sessionId.hexString), local=\(localDeviceId.hexString), remote=\(remoteDeviceId.hexString), role=\(role.rawValue), status=\(status.rawValue))"
    }
}
