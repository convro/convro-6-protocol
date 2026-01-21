use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

/// Conversation (from materialized view)
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Conversation {
    pub conversation_id: String,
    pub owner_user_id: Uuid,
    pub participant_user_id: Uuid,
    pub session_id: Vec<u8>,
    pub conversation_started_at: DateTime<Utc>,
    pub last_activity: DateTime<Utc>,
    pub total_messages: i32,
    pub last_message_id: Option<Uuid>,
    pub last_message_type: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unread_count: i64,
    pub is_active: bool,
}

/// Conversation response (API)
#[derive(Debug, Serialize)]
pub struct ConversationResponse {
    pub conversation_id: String,
    pub participant: ParticipantInfo,
    pub last_message: Option<LastMessageInfo>,
    pub unread_count: i64,
    pub last_activity: DateTime<Utc>,
    pub conversation_started_at: DateTime<Utc>,
    pub total_messages: i32,
}

/// Participant info
#[derive(Debug, Serialize)]
pub struct ParticipantInfo {
    pub user_id: Uuid,
    pub convro_number: String,
    pub display_name: Option<String>,
}

/// Last message info
#[derive(Debug, Serialize)]
pub struct LastMessageInfo {
    pub message_id: Uuid,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
}

/// Conversations list response
#[derive(Debug, Serialize)]
pub struct ConversationsListResponse {
    pub conversations: Vec<ConversationResponse>,
    pub total: usize,
    pub limit: usize,
    pub offset: usize,
}
