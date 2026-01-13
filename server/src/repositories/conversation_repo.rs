use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::{
    errors::AppResult,
    models::conversation::Conversation,
};

/// Conversation repository for database operations
#[derive(Clone)]
pub struct ConversationRepository {
    pool: PgPool,
}

impl ConversationRepository {
    pub fn new(pool: PgPool) -> Self {
        Self { pool }
    }

    /// List conversations for a user
    pub async fn list_by_user(
        &self,
        user_id: Uuid,
        limit: i64,
        offset: i64,
    ) -> AppResult<Vec<Conversation>> {
        let conversations = sqlx::query_as::<_, Conversation>(
            r#"
            SELECT
                conversation_id,
                owner_user_id,
                participant_user_id,
                session_id,
                conversation_started_at,
                last_activity,
                total_messages,
                last_message_id,
                last_message_type,
                last_message_at,
                unread_count,
                is_active
            FROM user_conversations
            WHERE owner_user_id = $1
            ORDER BY last_activity DESC
            LIMIT $2 OFFSET $3
            "#,
        )
        .bind(user_id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&self.pool)
        .await?;

        Ok(conversations)
    }

    /// Count total conversations for a user
    pub async fn count_by_user(&self, user_id: Uuid) -> AppResult<i64> {
        let row = sqlx::query("SELECT COUNT(*) FROM user_conversations WHERE owner_user_id = $1")
            .bind(user_id)
            .fetch_one(&self.pool)
            .await?;

        let count: i64 = row.try_get(0)?;
        Ok(count)
    }

    /// Refresh conversations materialized view
    pub async fn refresh_view(&self) -> AppResult<()> {
        sqlx::query("REFRESH MATERIALIZED VIEW CONCURRENTLY user_conversations")
            .execute(&self.pool)
            .await?;

        Ok(())
    }

    /// Find conversation by participant
    pub async fn find_by_participant(
        &self,
        owner_user_id: Uuid,
        participant_user_id: Uuid,
    ) -> AppResult<Option<Conversation>> {
        let conversation = sqlx::query_as::<_, Conversation>(
            r#"
            SELECT
                conversation_id,
                owner_user_id,
                participant_user_id,
                session_id,
                conversation_started_at,
                last_activity,
                total_messages,
                last_message_id,
                last_message_type,
                last_message_at,
                unread_count,
                is_active
            FROM user_conversations
            WHERE owner_user_id = $1 AND participant_user_id = $2
            "#,
        )
        .bind(owner_user_id)
        .bind(participant_user_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(conversation)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would go here
    // Requires test database setup
}
