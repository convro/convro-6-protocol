use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Message model (from database)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Message {
    pub message_id: Uuid,
    pub from_user_id: Uuid,
    pub to_user_id: Uuid,
    pub from_convro_number: String,
    pub to_convro_number: String,
    pub session_id: Option<Vec<u8>>,
    pub message_type: String,
    pub encrypted_blob: Vec<u8>,
    pub created_at: DateTime<Utc>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub read_at: Option<DateTime<Utc>>,
    pub delivery_status: String,
    pub retry_count: i32,
    pub next_retry_at: Option<DateTime<Utc>>,
    pub expires_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Send message request
#[derive(Debug, Deserialize, Validate)]
pub struct SendMessageRequest {
    #[validate(length(min = 1, max = 15))]
    pub to_convro_number: String,

    #[validate(length(min = 1, max = 30))]
    pub message_type: String, // "handshake_offer", "handshake_accept", "encrypted_message"

    pub session_id: Option<String>, // Hex-encoded

    #[validate(length(min = 1))]
    pub encrypted_blob: String, // Base64-encoded

    pub metadata: Option<MessageMetadata>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MessageMetadata {
    pub content_type: Option<String>,
    pub size_bytes: Option<usize>,
}

/// Message response (for API)
#[derive(Debug, Serialize)]
pub struct MessageResponse {
    pub message_id: Uuid,
    pub from_convro_number: String,
    pub to_convro_number: String,
    pub message_type: String,
    pub session_id: Option<String>, // Hex-encoded
    pub encrypted_blob: String,     // Base64-encoded
    pub created_at: DateTime<Utc>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub delivery_status: String,
}

impl From<Message> for MessageResponse {
    fn from(msg: Message) -> Self {
        Self {
            message_id: msg.message_id,
            from_convro_number: msg.from_convro_number,
            to_convro_number: msg.to_convro_number,
            message_type: msg.message_type,
            session_id: msg.session_id.map(hex::encode),
            encrypted_blob: base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &msg.encrypted_blob,
            ),
            created_at: msg.created_at,
            delivered_at: msg.delivered_at,
            delivery_status: msg.delivery_status,
        }
    }
}

/// Inbox response
#[derive(Debug, Serialize)]
pub struct InboxResponse {
    pub messages: Vec<MessageResponse>,
    pub total: i64,
    pub limit: i64,
    pub offset: i64,
}
