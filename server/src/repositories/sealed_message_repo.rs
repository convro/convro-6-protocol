use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::sealed_message::SealedMessage,
};

/// Sealed message repository for database operations
#[derive(Clone)]
pub struct SealedMessageRepository {
    pool: PgPool,
}

impl SealedMessageRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create new sealed message
    pub async fn create(
        &self,
        to_user_id: Uuid,
        encrypted_envelope: Vec<u8>, // Must be exactly 64KB
        message_type: Option<String>,
    ) -> AppResult<SealedMessage> {
        // Verify size (database constraint will also check this)
        if encrypted_envelope.len() != 65536 {
            return Err(AppError::ValidationError(format!(
                "Encrypted envelope must be exactly 64KB, got {} bytes",
                encrypted_envelope.len()
            )));
        }

        // Default message type to 'sealed' if not provided
        let msg_type = message_type.unwrap_or_else(|| "sealed".to_string());

        let message = sqlx::query_as::<_, SealedMessage>(
            r#"
            INSERT INTO messages_sealed (to_user_id, encrypted_envelope, message_type)
            VALUES ($1, $2, $3)
            RETURNING
                message_id,
                to_user_id,
                message_type,
                encrypted_envelope,
                created_at,
                delivered_at,
                delivery_status,
                expires_at,
                updated_at
            "#,
        )
        .bind(to_user_id)
        .bind(&encrypted_envelope)
        .bind(&msg_type)
        .fetch_one(&self.pool)
        .await
        .map_err(|e| {
            if let sqlx::Error::Database(db_err) = &e {
                if db_err.message().contains("check constraint") {
                    return AppError::ValidationError(
                        "Encrypted envelope must be exactly 64KB".to_string(),
                    );
                }
            }
            AppError::DatabaseError(e)
        })?;

        tracing::info!(
            "Sealed message created: {} for user {}",
            message.message_id,
            to_user_id
        );

        Ok(message)
    }

    /// Fetch inbox for user (undelivered sealed messages)
    pub async fn fetch_inbox(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<Vec<SealedMessage>> {
        let messages = sqlx::query_as::<_, SealedMessage>(
            r#"
            SELECT
                message_id,
                to_user_id,
                message_type,
                encrypted_envelope,
                created_at,
                delivered_at,
                delivery_status,
                expires_at,
                updated_at
            FROM messages_sealed
            WHERE to_user_id = $1 AND delivery_status = 'pending'
            ORDER BY created_at ASC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(messages)
    }

    /// Count pending messages for user
    pub async fn count_pending(&self, user_id: Uuid) -> AppResult<i64> {
        let row = sqlx::query(
            "SELECT COUNT(*) FROM messages_sealed WHERE to_user_id = $1 AND delivery_status = 'pending'",
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        let count: i64 = row.try_get(0)?;
        Ok(count)
    }

    /// Mark message as delivered
    pub async fn mark_as_delivered(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            r#"
            UPDATE messages_sealed
            SET delivery_status = 'delivered', delivered_at = NOW()
            WHERE message_id = $1 AND to_user_id = $2
            "#,
        )
        .bind(message_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound("Sealed message not found".to_string()));
        }

        tracing::debug!("Sealed message {} marked as delivered", message_id);

        Ok(())
    }

    /// Find message by ID
    pub async fn find_by_id(&self, message_id: Uuid) -> AppResult<Option<SealedMessage>> {
        let message = sqlx::query_as::<_, SealedMessage>(
            r#"
            SELECT
                message_id,
                to_user_id,
                message_type,
                encrypted_envelope,
                created_at,
                delivered_at,
                delivery_status,
                expires_at,
                updated_at
            FROM messages_sealed
            WHERE message_id = $1
            "#,
        )
        .bind(message_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(message)
    }

    /// Cleanup expired sealed messages
    pub async fn cleanup_expired(&self) -> AppResult<i64> {
        let result = sqlx::query_scalar::<_, i64>("SELECT cleanup_expired_sealed_messages()")
            .fetch_one(&self.pool)
            .await?;

        if result > 0 {
            tracing::info!("Cleaned up {} expired sealed messages", result);
        }

        Ok(result)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would go here
    // Requires test database setup
}
