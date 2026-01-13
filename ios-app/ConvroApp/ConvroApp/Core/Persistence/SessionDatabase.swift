import Foundation

// MARK: - Session Database
/// Local session cache
class SessionDatabase {
    // MARK: - Singleton
    static let shared = SessionDatabase()

    private init() {}

    // MARK: - Save
    func save(_ session: Session) throws {
        // TODO: Serialize and save to file/CoreData
        fatalError("Not implemented")
    }

    // MARK: - Load
    func loadSession(sessionId: Data) throws -> Session? {
        // TODO: Load from storage
        fatalError("Not implemented")
    }

    func loadAllSessions() throws -> [Session] {
        // TODO: Load all sessions
        fatalError("Not implemented")
    }

    // MARK: - Delete
    func deleteSession(sessionId: Data) throws {
        // TODO: Delete from storage
        fatalError("Not implemented")
    }
}
