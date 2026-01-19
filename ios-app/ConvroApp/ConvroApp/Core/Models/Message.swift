import Foundation

// MARK: - Message
// This model matches MessageEntity (Core Data) structure for local persistence
struct Message: Identifiable, Codable {
    let id: UUID
    let conversationId: UUID?
    let senderConvroNumber: String
    let content: String
    let timestamp: Date
    let isFromCurrentUser: Bool
    var deliveryStatus: DeliveryStatus
    let sessionId: String?

    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case conversationId = "conversation_id"
        case senderConvroNumber = "sender_convro_number"
        case content
        case timestamp
        case isFromCurrentUser = "is_from_current_user"
        case deliveryStatus = "delivery_status"
        case sessionId = "session_id"
    }
}

// MARK: - Message Type
enum MessageType: String, Codable {
    case handshakeOffer = "handshake_offer"
    case handshakeAccept = "handshake_accept"
    case encryptedMessage = "encrypted_message"
    case sealedSender = "sealed_sender"
}

// MARK: - Delivery Status
enum DeliveryStatus: String, Codable {
    case pending
    case delivered
    case read
}
