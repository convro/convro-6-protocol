import CoreData

// MARK: - Message Database
/// Local message cache for conversations using Core Data persistence
@MainActor
class MessageDatabase {
    // MARK: - Singleton
    static let shared = MessageDatabase()

    // MARK: - Properties
    private let context: NSManagedObjectContext

    private init() {
        self.context = CoreDataStack.shared.viewContext
    }

    // MARK: - Save

    /// Save message to Core Data
    func saveMessage(_ message: Message) async {
        // Check if message already exists
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", message.id as CVarArg)

        do {
            let existingMessages = try context.fetch(fetchRequest)

            if let existingMessage = existingMessages.first {
                // Update existing message
                existingMessage.update(from: message)
            } else {
                // Create new message entity
                let entity = MessageEntity(context: context)
                entity.update(from: message)
            }

            // Save context
            if context.hasChanges {
                try context.save()
                print("💾 Message saved to Core Data: \(message.id)")
            }
        } catch {
            print("❌ Failed to save message to Core Data: \(error)")
        }
    }

    // MARK: - Fetch

    /// Fetch messages for conversation from Core Data
    /// Note: Since Message no longer has conversationId, this fetches all messages
    /// and filters locally. Consider adding a conversationId field to Message/MessageEntity
    /// or using a different approach for production.
    func fetchMessages(forConversation conversationId: String) async -> [Message] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let entities = try context.fetch(fetchRequest)
            // For now, return all messages - filtering logic TBD based on business requirements
            return entities.map { $0.toMessage() }
        } catch {
            print("❌ Failed to fetch messages from Core Data: \(error)")
            return []
        }
    }

    /// Fetch all messages from Core Data
    func fetchAllMessages() async -> [Message] {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        do {
            let entities = try context.fetch(fetchRequest)
            return entities.map { $0.toMessage() }
        } catch {
            print("❌ Failed to fetch all messages from Core Data: \(error)")
            return []
        }
    }

    // MARK: - Delete

    /// Delete message by ID from Core Data
    func deleteMessage(_ messageId: UUID) async {
        let fetchRequest: NSFetchRequest<MessageEntity> = MessageEntity.fetchRequest()
        fetchRequest.predicate = NSPredicate(format: "id == %@", messageId as CVarArg)

        do {
            let entities = try context.fetch(fetchRequest)
            for entity in entities {
                context.delete(entity)
            }

            if context.hasChanges {
                try context.save()
                print("🗑️  Message deleted from Core Data: \(messageId)")
            }
        } catch {
            print("❌ Failed to delete message from Core Data: \(error)")
        }
    }

    /// Delete all messages for conversation from Core Data
    /// Note: Since Message no longer has conversationId, this is a no-op placeholder
    func deleteMessages(forConversation conversationId: String) async {
        print("⚠️  deleteMessages(forConversation:) not implemented - Message no longer has conversationId")
        // TODO: Implement filtering logic based on fromConvroNumber/toConvroNumber or re-add conversationId
    }

    /// Delete all messages from Core Data (logout)
    func deleteAllMessages() async {
        let fetchRequest: NSFetchRequest<NSFetchRequestResult> = MessageEntity.fetchRequest()
        let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetchRequest)

        do {
            try context.execute(deleteRequest)
            try context.save()
            print("🗑️  All messages deleted from Core Data")
        } catch {
            print("❌ Failed to delete all messages from Core Data: \(error)")
        }
    }
}
