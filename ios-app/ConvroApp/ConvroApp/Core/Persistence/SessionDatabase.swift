import Foundation

// MARK: - Session Database
/// Local session cache for C6P sessions
/// Note: Session keys are stored in Keychain via KeychainManager
/// This manager handles session metadata and C6PSessionWrapper persistence
@MainActor
class SessionDatabase {
    // MARK: - Singleton
    static let shared = SessionDatabase()

    // MARK: - Properties
    private var sessions: [String: C6PSessionWrapper] = [:]

    private init() {}

    // MARK: - Save

    /// Save session wrapper (called by C6PManager)
    func saveSession(_ wrapper: C6PSessionWrapper) async {
        sessions[wrapper.sessionId] = wrapper
        // Note: Actual SessionKeys are persisted in Keychain by C6PManager
        // This just keeps session metadata in memory
        print("💾 Session saved: \(wrapper.sessionId)")
    }

    // MARK: - Load

    /// Load session by ID
    func loadSession(sessionId: String) async -> C6PSessionWrapper? {
        return sessions[sessionId]
    }

    /// Load all active sessions
    func loadAllSessions() async -> [C6PSessionWrapper] {
        return Array(sessions.values)
    }

    // MARK: - Delete

    /// Delete session
    func deleteSession(sessionId: String) async {
        sessions.removeValue(forKey: sessionId)
        print("🗑️  Session deleted: \(sessionId)")
    }

    /// Clear all sessions (logout)
    func clearAllSessions() async {
        sessions.removeAll()
        print("🗑️  All sessions cleared")
    }
}
