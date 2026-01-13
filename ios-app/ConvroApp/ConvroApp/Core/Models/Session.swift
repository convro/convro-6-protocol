import Foundation

// MARK: - Session
struct Session: Identifiable, Codable {
    let id: Data
    let initiatorUserId: UUID
    let responderUserId: UUID
    let conversationStartedAt: Date
    var lastActivity: Date
    var isActive: Bool

    // C6P session state (stored separately in Keychain)
    var sessionState: SessionState?

    enum CodingKeys: String, CodingKey {
        case id = "session_id"
        case initiatorUserId = "initiator_user_id"
        case responderUserId = "responder_user_id"
        case conversationStartedAt = "conversation_started_at"
        case lastActivity = "last_activity"
        case isActive = "is_active"
    }
}

// MARK: - Session State
struct SessionState {
    // TODO: Add C6P session state fields
    // - Root key
    // - Send/receive chain keys
    // - Consumed counters set
}
