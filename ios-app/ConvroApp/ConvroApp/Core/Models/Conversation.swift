import Foundation

// MARK: - Conversation
struct Conversation: Identifiable, Codable {
    let id: String
    let participant: Participant
    let lastMessage: LastMessage?
    let unreadCount: Int
    let lastActivity: Date

    enum CodingKeys: String, CodingKey {
        case id = "conversation_id"
        case participant
        case lastMessage = "last_message"
        case unreadCount = "unread_count"
        case lastActivity = "last_activity"
    }
}

// MARK: - Participant
struct Participant: Codable {
    let userId: UUID
    let convroNumber: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case convroNumber = "convro_number"
        case displayName = "display_name"
    }
}

// MARK: - Last Message
struct LastMessage: Codable {
    let messageId: UUID
    let messageType: String
    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case messageType = "message_type"
        case timestamp
    }
}

// MARK: - Conversations List Response
struct ConversationsListResponse: Codable {
    let conversations: [Conversation]
    let total: Int
    let limit: Int
    let offset: Int
}
