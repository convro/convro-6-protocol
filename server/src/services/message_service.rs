use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::message::Message,
    repositories::{MessageRepository, UserRepository},
};

/// Message management service
#[derive(Clone)]
pub struct MessageService {
    pool: PgPool,
}

impl MessageService {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Send message
    pub async fn send_message(
        &self,
        from_user_id: Uuid,
        from_convro_number: String,
        to_convro_number: String,
        session_id: Option<String>,  // Hex-encoded
        message_type: String,
        encrypted_blob: String,  // Base64-encoded
    ) -> AppResult<Message> {
        let message_repo = MessageRepository::new(self.pool.clone());
        let user_repo = UserRepository::new(self.pool.clone());

        // Find recipient by Convro Number
        let recipient = user_repo
            .find_by_convro_number(&to_convro_number)
            .await?
            .ok_or_else(|| AppError::NotFound(format!("User {} not found", to_convro_number)))?;

        // Decode session_id (if present)
        let session_id_bytes = if let Some(sid) = session_id {
            Some(hex::decode(&sid).map_err(|_| {
                AppError::ValidationError("Invalid session_id format (must be hex)".to_string())
            })?)
        } else {
            None
        };

        // Decode encrypted blob (base64)
        let encrypted_blob_bytes =
            base64::Engine::decode(&base64::engine::general_purpose::STANDARD, &encrypted_blob)
                .map_err(|_| {
                    AppError::ValidationError(
                        "Invalid encrypted_blob format (must be base64)".to_string(),
                    )
                })?;

        // Validate message size (max 10MB)
        const MAX_MESSAGE_SIZE: usize = 10 * 1024 * 1024;
        if encrypted_blob_bytes.len() > MAX_MESSAGE_SIZE {
            return Err(AppError::PayloadTooLarge(format!(
                "Message size {} bytes exceeds maximum of {} bytes",
                encrypted_blob_bytes.len(),
                MAX_MESSAGE_SIZE
            )));
        }

        // Validate message type
        const VALID_TYPES: &[&str] = &["handshake_offer", "handshake_accept", "encrypted_message"];
        if !VALID_TYPES.contains(&message_type.as_str()) {
            return Err(AppError::ValidationError(format!(
                "Invalid message_type. Must be one of: {:?}",
                VALID_TYPES
            )));
        }

        // Create message
        let message = message_repo
            .create(
                from_user_id,
                recipient.user_id,
                from_convro_number,
                to_convro_number,
                session_id_bytes,
                message_type,
                encrypted_blob_bytes,
            )
            .await?;

        tracing::info!(
            "Message sent: {} ({} -> {})",
            message.message_id,
            message.from_convro_number,
            message.to_convro_number
        );

        // TODO: Push to WebSocket hub for realtime delivery

        Ok(message)
    }

    /// Fetch inbox (undelivered messages)
    pub async fn fetch_inbox(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<(Vec<Message>, i64)> {
        let message_repo = MessageRepository::new(self.pool.clone());

        // Validate pagination
        if limit > 100 {
            return Err(AppError::ValidationError(
                "Maximum limit is 100 messages per request".to_string(),
            ));
        }

        message_repo.fetch_inbox(user_id, limit, offset).await
    }

    /// Mark message as delivered
    pub async fn mark_as_delivered(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let message_repo = MessageRepository::new(self.pool.clone());
        message_repo.mark_as_delivered(message_id, user_id).await
    }

    /// Get message history for session
    pub async fn get_session_history(
        &self,
        session_id: String,  // Hex-encoded
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<(Vec<Message>, i64)> {
        let message_repo = MessageRepository::new(self.pool.clone());

        // Decode session_id
        let session_id_bytes = hex::decode(&session_id).map_err(|_| {
            AppError::ValidationError("Invalid session_id format (must be hex)".to_string())
        })?;

        // Validate pagination
        if limit > 100 {
            return Err(AppError::ValidationError(
                "Maximum limit is 100 messages per request".to_string(),
            ));
        }

        message_repo
            .get_session_history(session_id_bytes, user_id, limit, offset)
            .await
    }
}
