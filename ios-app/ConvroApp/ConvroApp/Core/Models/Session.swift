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
// Note: Actual SessionState is managed by C6PProtocol.SessionState (FFI class)
// This Swift struct is NOT used - session state is stored in C6PSessionWrapper
// which wraps the FFI SessionState class directly.
//
// Session keys are stored securely in Keychain via KeychainManager.
// See C6PManager.swift for SessionState usage.
