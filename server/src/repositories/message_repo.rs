use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::{AppError, AppResult},
    models::message::Message,
};

/// Message repository for database operations
#[derive(Clone)]
pub struct MessageRepository {
    pool: PgPool,
}

impl MessageRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// Create new message
    pub async fn create(
        &self,
        from_user_id: Uuid,
        to_user_id: Uuid,
        from_convro_number: String,
        to_convro_number: String,
        session_id: Option<Vec<u8>>,
        message_type: String,
        encrypted_blob: Vec<u8>,
    ) -> AppResult<Message> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            INSERT INTO messages (
                from_user_id,
                to_user_id,
                from_convro_number,
                to_convro_number,
                session_id,
                message_type,
                encrypted_blob,
                delivery_status,
                retry_count,
                expires_at
            )
            VALUES ($1, $2, $3, $4, $5, $6, $7, 'pending', 0, NOW() + INTERVAL '30 days')
            RETURNING
                message_id,
                from_user_id,
                to_user_id,
                from_convro_number,
                to_convro_number,
                session_id,
                message_type,
                encrypted_blob,
                created_at,
                delivered_at,
                read_at,
                delivery_status,
                retry_count,
                next_retry_at,
                expires_at,
                updated_at
            "#,
        )
        .bind(from_user_id)
        .bind(to_user_id)
        .bind(from_convro_number)
        .bind(to_convro_number)
        .bind(session_id)
        .bind(message_type)
        .bind(encrypted_blob)
        .fetch_one(&self.pool)
        .await?;

        tracing::info!(
            "Message created: {} ({} -> {})",
            message.message_id,
            message.from_convro_number,
            message.to_convro_number
        );

        Ok(message)
    }

    /// Fetch inbox (undelivered messages)
    pub async fn fetch_inbox(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<(Vec<Message>, i64)> {
        // Get total count
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) as "count"
            FROM messages
            WHERE to_user_id = $1 AND delivered_at IS NULL
            "#,
        )
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        // Get messages
        let messages = sqlx::query_as::<_, Message>(
            r#"
            SELECT
                message_id,
                from_user_id,
                to_user_id,
                from_convro_number,
                to_convro_number,
                session_id,
                message_type,
                encrypted_blob,
                created_at,
                delivered_at,
                read_at,
                delivery_status,
                retry_count,
                next_retry_at,
                expires_at,
                updated_at
            FROM messages
            WHERE to_user_id = $1 AND delivered_at IS NULL
            ORDER BY created_at ASC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok((messages, total))
    }

    /// Mark message as delivered
    pub async fn mark_as_delivered(&self, message_id: Uuid, user_id: Uuid) -> AppResult<()> {
        let result = sqlx::query(
            r#"
            UPDATE messages
            SET delivered_at = NOW(),
                delivery_status = 'delivered',
                updated_at = NOW()
            WHERE message_id = $1
              AND to_user_id = $2
              AND delivered_at IS NULL
            "#,
        )
        .bind(message_id)
        .bind(user_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Err(AppError::NotFound(
                "Message not found or already delivered".to_string(),
            ));
        }

        tracing::debug!("Message marked as delivered: {}", message_id);

        Ok(())
    }

    /// Get message by ID
    pub async fn find_by_id(&self, message_id: Uuid) -> AppResult<Option<Message>> {
        let message = sqlx::query_as::<_, Message>(
            r#"
            SELECT
                message_id,
                from_user_id,
                to_user_id,
                from_convro_number,
                to_convro_number,
                session_id,
                message_type,
                encrypted_blob,
                created_at,
                delivered_at,
                read_at,
                delivery_status,
                retry_count,
                next_retry_at,
                expires_at,
                updated_at
            FROM messages
            WHERE message_id = $1
            "#,
        )
        .bind(message_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(message)
    }

    /// Get message history for session
    pub async fn get_session_history(
        &self,
        session_id: Vec<u8>,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<(Vec<Message>, i64)> {
        // Get total count
        let total: i64 = sqlx::query_scalar(
            r#"
            SELECT COUNT(*) as "count"
            FROM messages
            WHERE session_id = $1
              AND (from_user_id = $2 OR to_user_id = $2)
            "#,
        )
        .bind(session_id.clone())
        .bind(user_id)
        .fetch_one(&self.pool)
        .await?;

        // Get messages
        let messages = sqlx::query_as::<_, Message>(
            r#"
            SELECT
                message_id,
                from_user_id,
                to_user_id,
                from_convro_number,
                to_convro_number,
                session_id,
                message_type,
                encrypted_blob,
                created_at,
                delivered_at,
                read_at,
                delivery_status,
                retry_count,
                next_retry_at,
                expires_at,
                updated_at
            FROM messages
            WHERE session_id = $1
              AND (from_user_id = $2 OR to_user_id = $2)
            ORDER BY created_at DESC
            LIMIT $3 OFFSET $4
            "#,
        )
        .bind(session_id)
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok((messages, total))
    }

    /// Cleanup expired messages (for background job)
    pub async fn cleanup_expired(&self) -> AppResult<i64> {
        let result: i64 = sqlx::query_scalar(
            r#"
            SELECT cleanup_expired_messages() as "deleted"
            "#
        )
        .fetch_one(&self.pool)
        .await?;

        if result > 0 {
            tracing::info!("Cleaned up {} expired messages", result);
        }

        Ok(result as i64)
    }
}
