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

    // MARK: - Properties (matching new Conversation struct)
    @NSManaged public var id: String
    @NSManaged public var participantUserId: UUID
    @NSManaged public var participantConvroNumber: String
    @NSManaged public var participantDisplayName: String
    @NSManaged public var lastMessageId: UUID?
    @NSManaged public var lastMessageType: String?
    @NSManaged public var lastMessageText: String?
    @NSManaged public var lastMessageTimestamp: Date?
    @NSManaged public var lastMessageFromMe: Bool
    @NSManaged public var unreadCount: Int32
    @NSManaged public var lastActivity: Date

    // MARK: - Relationships
    @NSManaged public var messages: NSSet?

    // MARK: - Convert to Conversation
    func toConversation() -> Conversation {
        let participant = Participant(
            userId: participantUserId,
            convroNumber: participantConvroNumber,
            displayName: participantDisplayName
        )

        var lastMessage: LastMessage? = nil
        if let msgText = lastMessageText,
           let msgTime = lastMessageTimestamp {
            lastMessage = LastMessage(
                messageId: lastMessageId,
                messageType: lastMessageType,
                text: msgText,
                timestamp: msgTime,
                fromMe: lastMessageFromMe
            )
        }

        return Conversation(
            id: id,
            participant: participant,
            lastMessage: lastMessage,
            unreadCount: Int(unreadCount),
            lastActivity: lastActivity
        )
    }

    // MARK: - Update from Conversation
    func update(from conversation: Conversation) {
        self.id = conversation.id
        self.participantUserId = conversation.participant.userId
        self.participantConvroNumber = conversation.participant.convroNumber
        self.participantDisplayName = conversation.participant.displayName
        self.lastMessageId = conversation.lastMessage?.messageId
        self.lastMessageType = conversation.lastMessage?.messageType
        self.lastMessageText = conversation.lastMessage?.text
        self.lastMessageTimestamp = conversation.lastMessage?.timestamp
        self.lastMessageFromMe = conversation.lastMessage?.fromMe ?? false
        self.unreadCount = Int32(conversation.unreadCount)
        self.lastActivity = conversation.lastActivity
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
