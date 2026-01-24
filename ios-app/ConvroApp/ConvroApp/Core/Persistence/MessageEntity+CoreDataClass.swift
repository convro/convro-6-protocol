import Foundation
import CoreData

// MARK: - Message Entity
/// Core Data entity for persisting messages locally
@objc(MessageEntity)
public class MessageEntity: NSManagedObject {
    // MARK: - Fetch Request
    @nonobjc public class func fetchRequest() -> NSFetchRequest<MessageEntity> {
        return NSFetchRequest<MessageEntity>(entityName: "MessageEntity")
    }

    // MARK: - Properties (matching new Message struct)
    @NSManaged public var id: UUID
    @NSManaged public var sessionId: Data
    @NSManaged public var fromConvroNumber: String?
    @NSManaged public var toConvroNumber: String
    @NSManaged public var messageType: String
    @NSManaged public var encryptedBlob: Data?
    @NSManaged public var encryptedEnvelope: Data?
    @NSManaged public var createdAt: Date
    @NSManaged public var deliveredAt: Date?
    @NSManaged public var deliveryStatus: String
    @NSManaged public var decryptedContent: String?

    // MARK: - Relationships
    @NSManaged public var conversation: ConversationEntity?

    // MARK: - Convert to Message
    func toMessage() -> Message {
        return Message(
            id: id,
            sessionId: sessionId,
            fromConvroNumber: fromConvroNumber,
            toConvroNumber: toConvroNumber,
            messageType: MessageType(rawValue: messageType) ?? .sealedSender,
            encryptedBlob: encryptedBlob,
            encryptedEnvelope: encryptedEnvelope,
            createdAt: createdAt,
            deliveredAt: deliveredAt,
            deliveryStatus: DeliveryStatus(rawValue: deliveryStatus) ?? .pending
        )
    }

    // MARK: - Update from Message
    func update(from message: Message) {
        self.id = message.id
        self.sessionId = message.sessionId
        self.fromConvroNumber = message.fromConvroNumber
        self.toConvroNumber = message.toConvroNumber
        self.messageType = message.messageType.rawValue
        self.encryptedBlob = message.encryptedBlob
        self.encryptedEnvelope = message.encryptedEnvelope
        self.createdAt = message.createdAt
        self.deliveredAt = message.deliveredAt
        self.deliveryStatus = message.deliveryStatus.rawValue
        self.decryptedContent = message.decryptedContent
    }
}
