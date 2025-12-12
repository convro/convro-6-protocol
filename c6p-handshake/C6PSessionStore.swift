//
//  C6PSessionStore.swift
//  C6P-Protocol
//
//  Abstrakcja storage'u sesji C6P po stronie klienta.
//
//  - C6PSessionStore: protokół, który możesz zaimplementować na:
//      * Keychain
//      * pliki (JSON / plist)
//      * CoreData / SQLite
//      * in-memory (testy)
//  - C6PMemorySessionStore: prosta, thread-safe implementacja in-memory,
//    idealna jako domyślna / testowa.
//
//  Sesja jest identyfikowana przez parę:
//      (localDeviceId, remoteDeviceId)
//  plus sessionId wewnątrz C6PSessionState.
//

import Foundation

// MARK: - Session Store Protocol

/// Protokół opisujący sposób przechowywania sesji C6P.
///
/// Implementacja może używać:
/// - Keychain,
/// - bazy danych,
/// - plików,
/// - albo zwykłej pamięci operacyjnej.
///
/// Protokół jest synchroniczny (prostota użycia). Jeśli
/// Twoja implementacja używa async IO, może wewnętrznie
/// blokować na swoich kolejkach / taskach.
protocol C6PSessionStore {

    /// Zwraca sesję dla danej pary (localDeviceId, remoteDeviceId),
    /// albo `nil`, jeśli taka sesja nie istnieje.
    func loadSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    ) -> C6PSessionState?

    /// Zapisuje (tworzy lub nadpisuje) sesję.
    ///
    /// Decyzja, jak identyfikować sesję, jest po stronie store'u –
    /// w typowym scenariuszu kluczem jest para (localDeviceId, remoteDeviceId).
    func saveSession(_ session: C6PSessionState)

    /// Usuwa sesję dla danej pary (localDeviceId, remoteDeviceId), jeśli istnieje.
    func deleteSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    )

    /// Zwraca wszystkie sesje dla danego lokalnego urządzenia.
    /// Przydaje się np. do debugowania, migracji, czy UI „aktywnych sesji”.
    func allSessions(for localDeviceId: C6PDeviceId) -> [C6PSessionState]

    /// Czyści wszystkie sesje (np. przy pełnym wylogowaniu / wipe).
    func deleteAllSessions()
}

// MARK: - In-memory Implementation

/// Prosta, thread-safe implementacja C6PSessionStore w pamięci.
///
/// Używa wewnętrznego słownika + kolejki concurrent + barrier do zapisu.
/// Idealna na:
/// - unit testy,
/// - prototypy,
/// - środowisko, gdzie nie potrzebujesz trwałego storage'u.
final class C6PMemorySessionStore: C6PSessionStore {

    // Klucz wewnętrzny – para (localDeviceId, remoteDeviceId).
    private struct Key: Hashable {
        let localDeviceId: C6PDeviceId
        let remoteDeviceId: C6PDeviceId
    }

    /// Właściwy storage.
    private var storage: [Key: C6PSessionState] = [:]

    /// Kolejka do zapewnienia bezpieczeństwa wątków.
    private let queue = DispatchQueue(
        label: "c6p.session.store.memory",
        attributes: .concurrent
    )

    // MARK: - Init

    init() {}

    // MARK: - Helpers

    private func makeKey(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    ) -> Key {
        Key(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
    }

    private func makeKey(for session: C6PSessionState) -> Key {
        Key(localDeviceId: session.localDeviceId, remoteDeviceId: session.remoteDeviceId)
    }

    // MARK: - C6PSessionStore

    func loadSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    ) -> C6PSessionState? {
        let key = makeKey(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        return queue.sync {
            storage[key]
        }
    }

    func saveSession(_ session: C6PSessionState) {
        let key = makeKey(for: session)
        queue.async(flags: .barrier) { [weak self] in
            self?.storage[key] = session
        }
    }

    func deleteSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    ) {
        let key = makeKey(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        queue.async(flags: .barrier) { [weak self] in
            self?.storage.removeValue(forKey: key)
        }
    }

    func allSessions(for localDeviceId: C6PDeviceId) -> [C6PSessionState] {
        queue.sync {
            storage
                .filter { $0.key.localDeviceId == localDeviceId }
                .map { $0.value }
        }
    }

    func deleteAllSessions() {
        queue.async(flags: .barrier) { [weak self] in
            self?.storage.removeAll()
        }
    }
}
