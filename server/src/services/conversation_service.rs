use sqlx::PgPool;
use uuid::Uuid;

use crate::{
    errors::AppResult,
    models::{
        conversation::{
            Conversation, ConversationResponse, ConversationsListResponse, LastMessageInfo,
            ParticipantInfo,
        },
        user::User,
    },
    repositories::{conversation_repo::ConversationRepository, user_repo::UserRepository},
};

/// Conversation service for business logic
#[derive(Clone)]
pub struct ConversationService {
    conversation_repo: ConversationRepository,
    user_repo: UserRepository,
}

impl ConversationService {
    pub fn new(pool: PgPool) -> Self {
        Self {
            conversation_repo: ConversationRepository::new(pool.clone()),
            user_repo: UserRepository::new(pool),
        }
    }

    /// List conversations for authenticated user
    pub async fn list_conversations(
        &self,
        user_id: Uuid,
        limit: usize,
        offset: usize,
    ) -> AppResult<ConversationsListResponse> {
        // Fetch conversations
        let conversations = self
            .conversation_repo
            .list_by_user(user_id, limit as i64, offset as i64)
            .await?;

        // Get total count
        let total = self.conversation_repo.count_by_user(user_id).await? as usize;

        // Fetch participant details for each conversation
        let mut conversation_responses = Vec::new();
        for conv in conversations {
            // Get participant user info
            let participant = self
                .user_repo
                .find_by_id(conv.participant_user_id)
                .await?
                .ok_or_else(|| {
                    crate::errors::AppError::NotFound("Participant not found".to_string())
                })?;

            conversation_responses.push(self.to_response(conv, participant));
        }

        Ok(ConversationsListResponse {
            conversations: conversation_responses,
            total,
            limit,
            offset,
        })
    }

    /// Convert conversation to API response
    fn to_response(&self, conv: Conversation, participant: User) -> ConversationResponse {
        ConversationResponse {
            conversation_id: conv.conversation_id,
            participant: ParticipantInfo {
                user_id: participant.user_id,
                convro_number: participant.convro_number,
                display_name: participant.display_name,
            },
            last_message: conv.last_message_id.map(|id| LastMessageInfo {
                message_id: id,
                message_type: conv.last_message_type.unwrap_or_default(),
                created_at: conv.last_message_at.unwrap_or(conv.last_activity),
            }),
            unread_count: conv.unread_count,
            last_activity: conv.last_activity,
            conversation_started_at: conv.conversation_started_at,
            total_messages: conv.total_messages,
        }
    }

    /// Refresh conversations view
    pub async fn refresh_view(&self) -> AppResult<()> {
        self.conversation_repo.refresh_view().await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Unit tests would go here
}
