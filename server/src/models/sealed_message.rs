use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;
use validator::Validate;

/// Sealed sender message (database model)
#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SealedMessage {
    pub message_id: Uuid,
    pub to_user_id: Uuid,
    pub message_type: String,
    pub encrypted_envelope: Vec<u8>, // 64KB padded
    pub created_at: DateTime<Utc>,   // Obfuscated (rounded to 5min)
    pub delivered_at: Option<DateTime<Utc>>,
    pub delivery_status: String,
    pub expires_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Send sealed message request
#[derive(Debug, Deserialize, Validate)]
pub struct SendSealedMessageRequest {
    #[validate(length(min = 8, max = 15))]
    pub to_convro_number: String,

    /// Encrypted envelope (base64-encoded, will be 64KB after padding)
    #[validate(length(min = 1))]
    pub encrypted_envelope: String,
}

/// Send sealed message response
#[derive(Debug, Serialize)]
pub struct SendSealedMessageResponse {
    pub message_id: Uuid,
    pub delivery_status: String,
    pub created_at: DateTime<Utc>, // Obfuscated timestamp
}

/// Sealed message response (for inbox)
#[derive(Debug, Serialize)]
pub struct SealedMessageResponse {
    pub message_id: Uuid,
    pub encrypted_envelope: String, // Base64-encoded
    pub created_at: DateTime<Utc>,
    pub delivered_at: Option<DateTime<Utc>>,
}

/// Sealed inbox response
#[derive(Debug, Serialize)]
pub struct SealedInboxResponse {
    pub messages: Vec<SealedMessageResponse>,
    pub total: usize,
    pub limit: usize,
    pub offset: usize,
}

impl SealedMessage {
    /// Convert to API response
    pub fn to_response(&self) -> SealedMessageResponse {
        SealedMessageResponse {
            message_id: self.message_id,
            encrypted_envelope: base64::Engine::encode(
                &base64::engine::general_purpose::STANDARD,
                &self.encrypted_envelope,
            ),
            created_at: self.created_at,
            delivered_at: self.delivered_at,
        }
    }
}
