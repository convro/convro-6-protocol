import Foundation

// MARK: - Conversation
// This model matches ConversationEntity (Core Data) structure for local persistence
struct Conversation: Identifiable, Codable {
    let id: UUID
    let participantConvroNumber: String
    let participantDisplayName: String?
    let lastMessageAt: Date?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case id = "conversation_id"
        case participantConvroNumber = "participant_convro_number"
        case participantDisplayName = "participant_display_name"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }
}
