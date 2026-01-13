import CoreData

// MARK: - Message Database
/// Local message cache for conversations
/// TODO: Implement Core Data entities when data model is finalized
@MainActor
class MessageDatabase {
    // MARK: - Singleton
    static let shared = MessageDatabase()

    // MARK: - Properties
    private let context: NSManagedObjectContext
    private var messageCache: [String: [Message]] = [:] // conversationId -> messages

    private init() {
        self.context = CoreDataStack.shared.viewContext
    }

    // MARK: - Save

    /// Save message to local cache
    func saveMessage(_ message: Message) async {
        let conversationId = message.conversationId?.uuidString ?? "unknown"

        if messageCache[conversationId] == nil {
            messageCache[conversationId] = []
        }

        messageCache[conversationId]?.append(message)
        print("💾 Message saved to conversation: \(conversationId)")

        // TODO: Persist to Core Data when entity model is defined
    }

    // MARK: - Fetch

    /// Fetch messages for conversation
    func fetchMessages(forConversation conversationId: String) async -> [Message] {
        return messageCache[conversationId] ?? []
    }

    /// Fetch all messages
    func fetchAllMessages() async -> [Message] {
        return messageCache.values.flatMap { $0 }
    }

    // MARK: - Delete

    /// Delete message by ID
    func deleteMessage(_ messageId: UUID) async {
        for (conversationId, messages) in messageCache {
            messageCache[conversationId] = messages.filter { $0.id != messageId }
        }
        print("🗑️  Message deleted: \(messageId)")
    }

    /// Delete all messages for conversation
    func deleteMessages(forConversation conversationId: String) async {
        messageCache.removeValue(forKey: conversationId)
        print("🗑️  All messages deleted for conversation: \(conversationId)")
    }

    /// Delete all messages (logout)
    func deleteAllMessages() async {
        messageCache.removeAll()
        print("🗑️  All messages deleted")
    }
}
