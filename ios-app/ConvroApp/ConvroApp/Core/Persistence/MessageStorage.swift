import Foundation

// MARK: - Message Storage
/// Simple persistent storage for messages using UserDefaults + Codable
/// Replaces Core Data until .xcdatamodeld is created in Xcode
@MainActor
class MessageStorage {
    // MARK: - Singleton
    static let shared = MessageStorage()

    // MARK: - Properties
    private let userDefaults = UserDefaults.standard
    private var currentUserConvroNumber: String?

    // User-specific keys (scoped to current logged-in user)
    private var messagesKey: String {
        guard let user = currentUserConvroNumber else {
            return "convro_messages" // Fallback
        }
        return "convro_messages_\(user)"
    }

    private var conversationsKey: String {
        guard let user = currentUserConvroNumber else {
            return "convro_conversations" // Fallback
        }
        return "convro_conversations_\(user)"
    }

    private init() {}

    // MARK: - User Management

    /// Set current user (call after login)
    func setCurrentUser(convroNumber: String) {
        self.currentUserConvroNumber = convroNumber
        print("💾 MessageStorage scoped to user: \(convroNumber)")
    }

    /// Clear all data for current user (call on logout)
    func clearCurrentUserData() async {
        await deleteAllMessages()
        await deleteAllConversations()
        self.currentUserConvroNumber = nil
        print("🗑️ Cleared all data for current user")
    }

    // MARK: - Messages

    /// Save message to persistent storage
    func saveMessage(_ message: Message) async {
        var messages = await fetchAllMessages()

        // Remove existing message with same ID (update)
        messages.removeAll { $0.id == message.id }

        // Add new message
        messages.append(message)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(messages)
            userDefaults.set(data, forKey: messagesKey)
            print("💾 Message saved to UserDefaults: \(message.id)")
        } catch {
            print("❌ Failed to save message: \(error)")
        }
    }

    /// Fetch messages for specific conversation
    func fetchMessages(forConversation conversationId: String, participantConvroNumber: String) async -> [Message] {
        let allMessages = await fetchAllMessages()

        // Filter messages for this conversation (by participant's Convro number)
        // Match messages where participant is either sender or recipient
        let filtered = allMessages.filter { message in
            message.toConvroNumber == participantConvroNumber ||
            message.fromConvroNumber == participantConvroNumber
        }

        return filtered.sorted { $0.createdAt < $1.createdAt }
    }

    /// Fetch all messages
    func fetchAllMessages() async -> [Message] {
        guard let data = userDefaults.data(forKey: messagesKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            let messages = try decoder.decode([Message].self, from: data)
            return messages
        } catch {
            print("❌ Failed to fetch messages: \(error)")
            return []
        }
    }

    /// Delete message by ID
    func deleteMessage(_ messageId: UUID) async {
        var messages = await fetchAllMessages()
        messages.removeAll { $0.id == messageId }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(messages)
            userDefaults.set(data, forKey: messagesKey)
            print("🗑️ Message deleted: \(messageId)")
        } catch {
            print("❌ Failed to delete message: \(error)")
        }
    }

    /// Delete all messages
    func deleteAllMessages() async {
        userDefaults.removeObject(forKey: messagesKey)
        print("🗑️ All messages deleted")
    }

    // MARK: - Conversations

    /// Save or update conversation
    func saveConversation(_ conversation: StoredConversation) async {
        var conversations = await fetchAllConversations()

        // Remove existing conversation with same ID
        conversations.removeAll { $0.id == conversation.id }

        // Add updated conversation
        conversations.append(conversation)

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(conversations)
            userDefaults.set(data, forKey: conversationsKey)
            print("💾 Conversation saved: \(conversation.id)")
        } catch {
            print("❌ Failed to save conversation: \(error)")
        }
    }

    /// Fetch all conversations
    func fetchAllConversations() async -> [StoredConversation] {
        guard let data = userDefaults.data(forKey: conversationsKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            let conversations = try decoder.decode([StoredConversation].self, from: data)
            return conversations.sorted { $0.lastActivityAt > $1.lastActivityAt }
        } catch {
            print("❌ Failed to fetch conversations: \(error)")
            return []
        }
    }

    /// Delete conversation
    func deleteConversation(_ conversationId: String) async {
        var conversations = await fetchAllConversations()
        conversations.removeAll { $0.id == conversationId }

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(conversations)
            userDefaults.set(data, forKey: conversationsKey)
            print("🗑️ Conversation deleted: \(conversationId)")
        } catch {
            print("❌ Failed to delete conversation: \(error)")
        }
    }

    /// Delete all conversations
    func deleteAllConversations() async {
        userDefaults.removeObject(forKey: conversationsKey)
        print("🗑️ All conversations deleted")
    }
}

// MARK: - Stored Conversation
/// Codable conversation model for persistence
struct StoredConversation: Codable, Identifiable {
    let id: String
    let participantConvroNumber: String
    let participantDisplayName: String?
    let lastMessageText: String?
    let lastActivityAt: Date
    let unreadCount: Int
    let sessionId: String?

    /// Convert to Conversation for UI
    func toConversation() -> Conversation {
        return Conversation(
            id: id,
            participant: Participant(
                userId: UUID(), // Placeholder
                convroNumber: participantConvroNumber,
                displayName: participantDisplayName ?? "Unknown"
            ),
            lastMessage: lastMessageText.map { text in
                LastMessage(
                    messageId: nil,
                    messageType: nil,
                    text: text,
                    timestamp: lastActivityAt,
                    fromMe: false // Simplified for now
                )
            },
            unreadCount: unreadCount,
            lastActivity: lastActivityAt
        )
    }

    /// Create from Conversation
    static func from(conversation: Conversation, sessionId: String? = nil) -> StoredConversation {
        return StoredConversation(
            id: conversation.id,
            participantConvroNumber: conversation.participant.convroNumber,
            participantDisplayName: conversation.participant.displayName,
            lastMessageText: conversation.lastMessage?.text,
            lastActivityAt: conversation.lastActivity,
            unreadCount: conversation.unreadCount,
            sessionId: sessionId
        )
    }
}
