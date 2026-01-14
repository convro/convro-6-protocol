import Foundation
import CoreData

// MARK: - Conversation Entity
/// Core Data entity for persisting conversations locally
@objc(ConversationEntity)
public class ConversationEntity: NSManagedObject {
    // MARK: - Fetch Request
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ConversationEntity> {
        return NSFetchRequest<ConversationEntity>(entityName: "ConversationEntity")
    }

    // MARK: - Properties
    @NSManaged public var id: UUID
    @NSManaged public var participantConvroNumber: String
    @NSManaged public var participantDisplayName: String?
    @NSManaged public var lastMessageAt: Date?
    @NSManaged public var unreadCount: Int32

    // MARK: - Relationships
    @NSManaged public var messages: NSSet?

    // MARK: - Convert to Conversation
    func toConversation() -> Conversation {
        return Conversation(
            id: id,
            participantConvroNumber: participantConvroNumber,
            participantDisplayName: participantDisplayName,
            lastMessageAt: lastMessageAt,
            unreadCount: Int(unreadCount)
        )
    }

    // MARK: - Update from Conversation
    func update(from conversation: Conversation) {
        self.id = conversation.id
        self.participantConvroNumber = conversation.participantConvroNumber
        self.participantDisplayName = conversation.participantDisplayName
        self.lastMessageAt = conversation.lastMessageAt
        self.unreadCount = Int32(conversation.unreadCount)
    }
}

// MARK: - Generated accessors for messages
extension ConversationEntity {
    @objc(addMessagesObject:)
    @NSManaged public func addToMessages(_ value: MessageEntity)

    @objc(removeMessagesObject:)
    @NSManaged public func removeFromMessages(_ value: MessageEntity)

    @objc(addMessages:)
    @NSManaged public func addToMessages(_ values: NSSet)

    @objc(removeMessages:)
    @NSManaged public func removeFromMessages(_ values: NSSet)
}
