use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::sealed_message::{SealedInboxResponse, SealedMessage, SealedMessageResponse},
    repositories::{sealed_message_repo::SealedMessageRepository, user_repo::UserRepository},
    utils::{padding, timing},
};

/// Sealed message service for business logic
#[derive(Clone)]
pub struct SealedMessageService {
    sealed_message_repo: SealedMessageRepository,
    user_repo: UserRepository,
}

impl SealedMessageService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            sealed_message_repo: SealedMessageRepository::new(pool.clone()),
            user_repo: UserRepository::new(pool),
        }
    }

    /// Send sealed message
    ///
    /// - Validates recipient exists
    /// - Pads encrypted envelope to 64KB
    /// - Obfuscates timestamp (rounds to 5min)
    /// - Applies timing jitter (0-5s delay)
    pub async fn send_sealed_message(
        &self,
        to_convro_number: String,
        encrypted_envelope: Vec<u8>,
        message_type: Option<String>,
    ) -> AppResult<SealedMessage> {
        tracing::info!("send_sealed_message called: to={}, envelope_size={}, message_type={:?}",
            to_convro_number, encrypted_envelope.len(), message_type);

        // Find recipient by Convro Number
        let recipient = self
            .user_repo
            .find_by_convro_number(&to_convro_number)
            .await?
            .ok_or_else(|| {
                tracing::error!("Recipient not found: {}", to_convro_number);
                AppError::NotFound("Recipient not found".to_string())
            })?;

        tracing::info!("Recipient found: user_id={}", recipient.user_id);

        // Check if this is a handshake message (don't pad handshake messages)
        let is_handshake = message_type.as_ref().map_or(false, |t| {
            t == "handshake_offer" || t == "handshake_accept"
        });

        tracing::info!("is_handshake={}", is_handshake);

        // Pad envelope to 64KB (only for regular sealed messages, not handshakes)
        let final_envelope = if is_handshake {
            encrypted_envelope // Keep handshake messages as-is (small wire format)
        } else if encrypted_envelope.len() == padding::SEALED_ENVELOPE_SIZE {
            encrypted_envelope
        } else {
            padding::pad_sealed_envelope(encrypted_envelope)?
        };

        // Apply timing jitter (0-5s delay for timing obfuscation)
        timing::apply_timing_jitter().await;

        // Create sealed message
        let message = self
            .sealed_message_repo
            .create(recipient.user_id, final_envelope, message_type, is_handshake)
            .await?;

        tracing::info!(
            "Sealed message sent: {} to user {} (identity hidden)",
            message.message_id,
            recipient.convro_number
        );

        Ok(message)
    }

    /// Fetch sealed inbox for user
    pub async fn fetch_inbox(
        &self,
        user_id: Uuid,
        limit: usize,
        offset: usize,
    ) -> AppResult<SealedInboxResponse> {
        // Fetch pending messages
        let messages = self
            .sealed_message_repo
            .fetch_inbox(user_id, limit as i64, offset as i64)
            .await?;

        // Get total count
        let total = self.sealed_message_repo.count_pending(user_id).await? as usize;

        // Convert to responses
        let message_responses: Vec<SealedMessageResponse> =
            messages.iter().map(|m| m.to_response()).collect();

        Ok(SealedInboxResponse {
            messages: message_responses,
            total,
            limit,
            offset,
        })
    }

    /// Mark sealed message as delivered
    pub async fn mark_as_delivered(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        self.sealed_message_repo
            .mark_as_delivered(message_id, user_id)
            .await?;

        tracing::debug!("Sealed message {} marked as delivered", message_id);

        Ok(())
    }

    /// Cleanup expired sealed messages
    pub async fn cleanup_expired(&self) -> AppResult<i64> {
        self.sealed_message_repo.cleanup_expired().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Unit tests would go here
}
