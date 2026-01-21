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

    // MARK: - Properties
    @NSManaged public var id: UUID
    @NSManaged public var conversationId: UUID?
    @NSManaged public var senderConvroNumber: String
    @NSManaged public var content: String
    @NSManaged public var timestamp: Date
    @NSManaged public var isFromCurrentUser: Bool
    @NSManaged public var deliveryStatus: String
    @NSManaged public var sessionId: String?

    // MARK: - Relationships
    @NSManaged public var conversation: ConversationEntity?

    // MARK: - Convert to Message
    func toMessage() -> Message {
        return Message(
            id: id,
            conversationId: conversationId,
            senderConvroNumber: senderConvroNumber,
            content: content,
            timestamp: timestamp,
            isFromCurrentUser: isFromCurrentUser,
            deliveryStatus: DeliveryStatus(rawValue: deliveryStatus) ?? .pending,
            sessionId: sessionId
        )
    }

    // MARK: - Update from Message
    func update(from message: Message) {
        self.id = message.id
        self.conversationId = message.conversationId
        self.senderConvroNumber = message.senderConvroNumber
        self.content = message.content
        self.timestamp = message.timestamp
        self.isFromCurrentUser = message.isFromCurrentUser
        self.deliveryStatus = message.deliveryStatus.rawValue
        self.sessionId = message.sessionId
    }
}
