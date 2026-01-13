import CoreData

// MARK: - Message Database
/// Local message cache using Core Data
class MessageDatabase {
    // MARK: - Singleton
    static let shared = MessageDatabase()

    private let context: NSManagedObjectContext

    private init() {
        self.context = CoreDataStack.shared.viewContext
    }

    // MARK: - Save
    func save(_ message: Message) throws {
        // TODO: Convert Message to NSManagedObject
        // TODO: Save to Core Data
        fatalError("Not implemented")
    }

    // MARK: - Fetch
    func fetchMessages(forConversation conversationId: String) throws -> [Message] {
        // TODO: Fetch from Core Data
        // TODO: Convert to Message models
        fatalError("Not implemented")
    }

    // MARK: - Delete
    func deleteMessage(_ messageId: UUID) throws {
        // TODO: Delete from Core Data
        fatalError("Not implemented")
    }

    func deleteAllMessages() throws {
        // TODO: Batch delete all messages
        fatalError("Not implemented")
    }
}
