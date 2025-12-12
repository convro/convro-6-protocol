//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  Wysokopoziomowy serwis do zarządzania sesjami C6P na kliencie.
//
//  Odpowiada za:
//  - tworzenie / odtwarzanie sesji (C6PHandshake99 + C6PSessionStore),
//  - szyfrowanie DM → C6PEnvelopeDM,
//  - odszyfrowywanie DM z C6PEnvelopeDM,
//  - aktualizację chain keys i counterów (ratchet).
//
//  UI / warstwa aplikacyjna powinna gadać tylko z tym serwisem,
//  a nie bezpośrednio z prymitywami kryptograficznymi.
//

import Foundation

// MARK: - Errors

enum C6PSessionServiceError: Error, CustomStringConvertible {
    case missingSessionForDecryption(remoteDeviceId: C6PDeviceId, sessionId: C6PSessionId)
    case sessionIdMismatch(expected: C6PSessionId, actual: C6PSessionId)
    case invalidEnvelopeMessageType(C6PMessageType)
    case invalidRecipient(expected: C6PDeviceId, actual: C6PDeviceId)
    case prekeyBundleUnavailable(remoteDeviceId: C6PDeviceId)

    var description: String {
        switch self {
        case .missingSessionForDecryption(let remote, let sessionId):
            return "C6PSessionServiceError.missingSessionForDecryption(remote=\(remote.hexString), sessionId=\(sessionId.hexString))"
        case .sessionIdMismatch(let expected, let actual):
            return "C6PSessionServiceError.sessionIdMismatch(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .invalidEnvelopeMessageType(let type):
            return "C6PSessionServiceError.invalidEnvelopeMessageType(\(type)) – expected .dm"
        case .invalidRecipient(let expected, let actual):
            return "C6PSessionServiceError.invalidRecipient(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .prekeyBundleUnavailable(let remote):
            return "C6PSessionServiceError.prekeyBundleUnavailable(remote=\(remote.hexString))"
        }
    }
}

// MARK: - Prekey Bundle Provider

/// Funkcja dostarczająca prekey-bundle dla zdalnego urządzenia.
///
/// Implementacja typowo:
/// - strzela do backendu (HTTP / gRPC),
/// - zwraca `C6PPrekeyBundle` dla danego `remoteDeviceId`.
///
/// Rzuca błędem jeśli backend jest niedostępny / urządzenie nie istnieje itd.
typealias C6PPrekeyBundleProvider = (_ remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundle

// MARK: - Session Service

/// Główny serwis sesji C6P po stronie klienta.
///
/// Typowe użycie:
///
/// ```swift
/// let service = C6PSessionService(
///     localDeviceId: myDeviceId,
///     store: C6PMemorySessionStore(),
///     prekeyBundleProvider: { remoteDeviceId in
///         // fetch z backendu:
///         try apiClient.fetchPrekeyBundle(for: remoteDeviceId)
///     }
/// )
///
/// let envelope = try service.encryptDM(to: remoteDeviceId, plaintext: messageData)
/// // envelope → JSON → POST /v1/dm/send
///
/// let plaintext = try service.decryptDM(from: remoteDeviceId, envelope: envelopeFromServer)
/// ```
///
/// Serwis zakłada prosty model v1:
/// - jedna aktywna sesja per (localDeviceId, remoteDeviceId),
/// - wiadomości DM odszyfrowywane w kolejności (brak wsparcia dla skrajnie
///   out-of-order delivery w v1),
/// - jeśli stan jest niespójny, można oznaczyć sesję jako `.needsReHandshake`
///   i pozwolić serwisowi odbudować ją przy kolejnym wysyłaniu DM.
final class C6PSessionService {

    // MARK: - Properties

    /// Lokalne urządzenie (to, na którym działa ten kod).
    private let localDeviceId: C6PDeviceId

    /// Store sesji – możesz podmienić na Keychain / CoreData itd.
    private let store: C6PSessionStore

    /// Provider prekey-bundle – wywoływany, gdy potrzebujemy założyć nową sesję
    /// jako inicjator (brak istniejącej sesji albo status != .active).
    private let prekeyBundleProvider: C6PPrekeyBundleProvider

    /// Opcjonalny override publicznego klucza tożsamości zdalnego urządzenia,
    /// jeśli znasz go z innego źródła (np. manualna weryfikacja).
    private let remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)?

    // MARK: - Init

    init(
        localDeviceId: C6PDeviceId,
        store: C6PSessionStore,
        prekeyBundleProvider: @escaping C6PPrekeyBundleProvider,
        remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.store = store
        self.prekeyBundleProvider = prekeyBundleProvider
        self.remoteIdentityOverrideProvider = remoteIdentityOverrideProvider
    }

    // MARK: - Public API

    /// Zwraca istniejącą sesję albo tworzy nową (jako inicjator),
    /// jeśli brak aktywnej sesji dla danego zdalnego urządzenia.
    ///
    /// - Parameter remoteDeviceId: zdalne urządzenie, z którym chcemy gadać.
    /// - Returns: aktualny stan sesji (aktywny).
    func getOrCreateSession(with remoteDeviceId: C6PDeviceId) throws -> C6PSessionState {
        // 1. Spróbuj wczytać istniejącą sesję.
        if var session = store.loadSession(
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId
        ) {
            switch session.status {
            case .active:
                return session
            case .closed, .needsReHandshake:
                // Stara / uszkodzona sesja – wyczyść i stwórz nową.
                store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
            }
        }

        // 2. Potrzebujemy nowego handshaku jako inicjator.
        let bundle: C6PPrekeyBundle
        do {
            bundle = try prekeyBundleProvider(remoteDeviceId)
        } catch {
            throw C6PSessionServiceError.prekeyBundleUnavailable(remoteDeviceId: remoteDeviceId)
        }

        let identityOverride = remoteIdentityOverrideProvider?(remoteDeviceId)

        // Handshake99 jako inicjator.
        let result = try C6PHandshake99.startAsInitiator(
            localDeviceId: localDeviceId,
            prekeyBundle: bundle,
            identityPublicKeyOverride: identityOverride
        )

        // Budujemy nowy C6PSessionState.
        var session = C6PSessionState(
            sessionId: result.sessionId,
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId,
            role: .initiator,
            rootKey: result.rootKey,
            sendChainKey: result.sendChainKey,
            recvChainKey: result.recvChainKey,
            sendCounter: result.sendCounter,
            recvCounter: result.recvCounter
        )

        session.markUpdated()
        store.saveSession(session)

        return session
    }

    /// Szyfruje DM do zdalnego urządzenia, zwracając gotowy envelope,
    /// który możesz wysłać na backend.
    ///
    /// - Parameters:
    ///   - remoteDeviceId: docelowe urządzenie peer'a.
    ///   - plaintext: treść do zaszyfrowania (np. JSON-encoded DM payload).
    ///   - extraAAD: opcjonalne dodatkowe AAD (np. fragment nagłówka).
    ///
    /// - Returns: `C6PEnvelopeDM` gotowy do serializacji i wysłania.
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        plaintext: Data,
        extraAAD: Data? = nil
    ) throws -> C6PEnvelopeDM {

        // 1. Upewniamy się, że mamy sesję.
        var session = try getOrCreateSession(with: remoteDeviceId)

        // 2. Przygotowujemy message key i nonce.
        let counter = session.sendCounter

        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.sendChainKey,
            counter: counter,
            messageType: .dm
        )

        // Kierunek z punktu widzenia kryptografii: "wychodząca DM".
        // Dla v1 przyjmujemy prosty model – używamy kierunku .sending
        // z punktu widzenia lokalnego urządzenia.
        let direction: C6PDirection = .sending

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: .dm,
            counter: counter
        )

        // 3. AEAD: szyfrowanie.
        let sealed = try C6PAEAD.seal(
            plaintext: plaintext,
            with: messageKey,
            nonce: nonce,
            sessionId: session.sessionId,
            role: session.role,
            direction: direction,
            messageType: .dm,
            counter: counter,
            extraAAD: extraAAD
        )

        // 4. Budujemy envelope na drut (wire-level).
        let envelope = C6PEnvelopeDM(
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            sealed: sealed
        )

        // 5. Ratchet: aktualizujemy chain key i counter.
        let nextChainKey = C6PKeySchedule.ratchetChainKeyForward(session.sendChainKey)
        session.sendChainKey = nextChainKey
        session.sendCounter.increment()
        session.markUpdated()
        store.saveSession(session)

        return envelope
    }

    /// Odszyfrowuje DM przychodzący z backendu.
    ///
    /// - Parameters:
    ///   - remoteDeviceId: urządzenie nadawcy (fromDeviceId w envelope).
    ///   - envelope: koperta odebrana z backendu.
    ///   - extraAAD: musisz przekazać dokładnie to samo, co użyłeś przy `encryptDM`
    ///               (jeśli w ogóle coś było), inaczej weryfikacja AEAD nie przejdzie.
    ///
    /// - Returns: odszyfrowany plaintext (`Data`), który możesz zdekodować np. z JSON.
    func decryptDM(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelopeDM,
        extraAAD: Data? = nil
    ) throws -> Data {

        // 1. Sprawdzenie typu wiadomości.
        guard envelope.messageType == .dm else {
            throw C6PSessionServiceError.invalidEnvelopeMessageType(envelope.messageType)
        }

        // 2. Sprawdzenie, czy envelope jest skierowany do tego urządzenia.
        guard envelope.toDeviceId == localDeviceId else {
            throw C6PSessionServiceError.invalidRecipient(
                expected: localDeviceId,
                actual: envelope.toDeviceId
            )
        }

        // 3. Wczytujemy sesję.
        guard var session = store.loadSession(
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId
        ) else {
            throw C6PSessionServiceError.missingSessionForDecryption(
                remoteDeviceId: remoteDeviceId,
                sessionId: envelope.sessionId
            )
        }

        // 4. Dodatkowa weryfikacja sessionId (powinien się zgadzać).
        guard session.sessionId == envelope.sessionId else {
            throw C6PSessionServiceError.sessionIdMismatch(
                expected: session.sessionId,
                actual: envelope.sessionId
            )
        }

        // 5. Przygotowujemy message key i nonce dla kierunku przychodzącego.
        let counter = session.recvCounter

        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.recvChainKey,
            counter: counter,
            messageType: envelope.messageType
        )

        let direction: C6PDirection = .receiving

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: envelope.messageType,
            counter: counter
        )

        // 6. AEAD: odszyfrowanie.
        let plaintext = try C6PAEAD.open(
            sealed: envelope.sealed,
            with: messageKey,
            nonce: nonce,
            sessionId: session.sessionId,
            role: session.role,
            direction: direction,
            messageType: envelope.messageType,
            counter: counter,
            extraAAD: extraAAD
        )

        // 7. Ratchet: aktualizacja recv chain key i countera.
        let nextRecvChainKey = C6PKeySchedule.ratchetChainKeyForward(session.recvChainKey)
        session.recvChainKey = nextRecvChainKey
        session.recvCounter.increment()
        session.markUpdated()
        store.saveSession(session)

        return plaintext
    }

    // MARK: - Debug / Maintenance helpers

    /// Zwraca wszystkie sesje dla lokalnego urządzenia – przydatne
    /// w debugowaniu / UI developerskim.
    func allSessions() -> [C6PSessionState] {
        store.allSessions(for: localDeviceId)
    }

    /// Czyści wszystkie sesje lokalnego urządzenia (twardy reset).
    func resetAllSessions() {
        store.deleteAllSessions()
    }

    /// Usuwa sesję z konkretnym zdalnym urządzeniem.
    func deleteSession(with remoteDeviceId: C6PDeviceId) {
        store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
    }
}
