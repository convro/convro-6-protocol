//
//  C6PSessionStore.swift
//  Convro-6-Protocol (C6P)
//
//  Client-side session storage abstraction.
//
//  Requirements (v1 ideal):
//  - Synchronous semantics (save/delete visible immediately)
//  - Thread-safe
//  - Efficient lookup by (localDeviceId, sessionId) because envelopes carry sessionId
//  - Atomic updates for counters/keys (store is responsible for not losing state)
//

import Foundation

// MARK: - Session Store Protocol

/// Storage abstraction for C6P sessions.
///
/// Implementations may use:
/// - Keychain (+ file metadata),
/// - SQLite/CoreData,
/// - files (JSON/plist),
/// - in-memory (tests).
///
/// This protocol is synchronous by design.
/// If your backend is async/IO-based, you must internally block until the operation is committed.
protocol C6PSessionStore {

    /// Load session for a device-pair (local, remote).
    /// Typical usage: UI lists or "active session with this device".
    func loadSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    ) -> C6PSessionState?

    /// Save (create or overwrite) a session.
    /// Must be committed before returning.
    func saveSession(_ session: C6PSessionState)

    /// Delete session for a device-pair (local, remote).
    /// Must be committed before returning.
    func deleteSession(
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId
    )

    /// Return all sessions for a local device.
    func allSessions(for localDeviceId: C6PDeviceId) -> [C6PSessionState]

    /// Delete all sessions.
    func deleteAllSessions()
}

// MARK: - Convenience API (required for wire envelopes)

extension C6PSessionStore {

    /// Load session by (localDeviceId, sessionId).
    ///
    /// This is the primary lookup used by wire envelopes:
    /// envelope carries `sessionId`, client uses it to locate the correct session state.
    ///
    /// Default implementation scans `allSessions(for:)`.
    /// Concrete stores SHOULD override for O(1) lookup.
    func loadSession(
        localDeviceId: C6PDeviceId,
        sessionId: C6PSessionId
    ) -> C6PSessionState? {
        allSessions(for: localDeviceId).first { $0.sessionId == sessionId }
    }

    /// Delete session by (localDeviceId, sessionId).
    /// Default implementation resolves by scan and then deletes by pair.
    func deleteSession(
        localDeviceId: C6PDeviceId,
        sessionId: C6PSessionId
    ) {
        guard let s = loadSession(localDeviceId: localDeviceId, sessionId: sessionId) else { return }
        deleteSession(localDeviceId: s.localDeviceId, remoteDeviceId: s.remoteDeviceId)
    }
}

// MARK: - In-memory Implementation (thread-safe, sync, indexed)

/// Thread-safe in-memory store with:
/// - pair lookup: (localDeviceId, remoteDeviceId)
/// - session lookup: (localDeviceId, sessionId)
///
/// All writes are synchronous barriers => immediately visible.
final class C6PMemorySessionStore: C6PSessionStore {

    // Key: device pair
    private struct PairKey: Hashable {
        let localDeviceId: C6PDeviceId
        let remoteDeviceId: C6PDeviceId
    }

    // Key: session lookup (envelope-driven)
    private struct SessionKey: Hashable {
        let localDeviceId: C6PDeviceId
        let sessionId: C6PSessionId
    }

    // Main storage
    private var byPair: [PairKey: C6PSessionState] = [:]

    // Secondary index: (local, sessionId) -> (local, remote)
    private var indexBySession: [SessionKey: PairKey] = [:]

    // Thread-safety
    private let queue = DispatchQueue(label: "c6p.session.store.memory", attributes: .concurrent)

    init() {}

    // MARK: - Helpers

    private func pairKey(local: C6PDeviceId, remote: C6PDeviceId) -> PairKey {
        PairKey(localDeviceId: local, remoteDeviceId: remote)
    }

    private func pairKey(for session: C6PSessionState) -> PairKey {
        PairKey(localDeviceId: session.localDeviceId, remoteDeviceId: session.remoteDeviceId)
    }

    private func sessionKey(local: C6PDeviceId, sessionId: C6PSessionId) -> SessionKey {
        SessionKey(localDeviceId: local, sessionId: sessionId)
    }

    // MARK: - C6PSessionStore

    func loadSession(localDeviceId: C6PDeviceId, remoteDeviceId: C6PDeviceId) -> C6PSessionState? {
        let k = pairKey(local: localDeviceId, remote: remoteDeviceId)
        return queue.sync { byPair[k] }
    }

    func saveSession(_ session: C6PSessionState) {
        let pk = pairKey(for: session)
        let sk = sessionKey(local: session.localDeviceId, sessionId: session.sessionId)

        queue.sync(flags: .barrier) {
            // If overwriting an existing session for this pair, remove old sessionId index.
            if let old = byPair[pk] {
                let oldSk = sessionKey(local: old.localDeviceId, sessionId: old.sessionId)
                indexBySession.removeValue(forKey: oldSk)
            }

            byPair[pk] = session
            indexBySession[sk] = pk
        }
    }

    func deleteSession(localDeviceId: C6PDeviceId, remoteDeviceId: C6PDeviceId) {
        let pk = pairKey(local: localDeviceId, remote: remoteDeviceId)

        queue.sync(flags: .barrier) {
            if let removed = byPair.removeValue(forKey: pk) {
                let sk = sessionKey(local: removed.localDeviceId, sessionId: removed.sessionId)
                indexBySession.removeValue(forKey: sk)
            }
        }
    }

    func allSessions(for localDeviceId: C6PDeviceId) -> [C6PSessionState] {
        queue.sync {
            byPair.values.filter { $0.localDeviceId == localDeviceId }
        }
    }

    func deleteAllSessions() {
        queue.sync(flags: .barrier) {
            byPair.removeAll()
            indexBySession.removeAll()
        }
    }

    // MARK: - Override convenience for O(1) envelope lookup

    func loadSession(localDeviceId: C6PDeviceId, sessionId: C6PSessionId) -> C6PSessionState? {
        let sk = sessionKey(local: localDeviceId, sessionId: sessionId)
        return queue.sync {
            guard let pk = indexBySession[sk] else { return nil }
            return byPair[pk]
        }
    }

    func deleteSession(localDeviceId: C6PDeviceId, sessionId: C6PSessionId) {
        let sk = sessionKey(local: localDeviceId, sessionId: sessionId)
        queue.sync(flags: .barrier) {
            guard let pk = indexBySession.removeValue(forKey: sk) else { return }
            byPair.removeValue(forKey: pk)
        }
    }
}

