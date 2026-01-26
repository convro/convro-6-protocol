import Foundation

// MARK: - Message
struct Message: Identifiable, Codable {
    let id: UUID
    let sessionId: Data
    let fromConvroNumber: String?
    let toConvroNumber: String
    let messageType: MessageType
    let encryptedBlob: Data?
    let encryptedEnvelope: Data?
    let createdAt: Date
    var deliveredAt: Date?
    var deliveryStatus: DeliveryStatus

    // Local decrypted content (not in API response)
    var decryptedContent: String?
    
    // Local flag indicating if this message was sent by current user
    var isFromMe: Bool = false

    enum CodingKeys: String, CodingKey {
        case id = "message_id"
        case sessionId = "session_id"
        case fromConvroNumber = "from_convro_number"
        case toConvroNumber = "to_convro_number"
        case messageType = "message_type"
        case encryptedBlob = "encrypted_blob"
        case encryptedEnvelope = "encrypted_envelope"
        case createdAt = "created_at"
        case deliveredAt = "delivered_at"
        case deliveryStatus = "delivery_status"
        case decryptedContent = "decrypted_content"
        case isFromMe = "is_from_me"
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
