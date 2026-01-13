use axum::{
    extract::{Query, State},
    routing::get,
    Json, Router,
};
use serde::Deserialize;

use crate::{
    errors::AppResult,
    models::{auth::Claims, conversation::ConversationsListResponse},
    services::conversation_service::ConversationService,
};

/// App state for conversations API
#[derive(Clone)]
pub struct AppState {
    pub conversation_service: ConversationService,
}

/// Create conversations router
pub fn conversations_router(state: AppState) -> Router {
    Router::new()
        .route("/conversations", get(list_conversations))
        .with_state(state)
}

/// Query params for list conversations
#[derive(Debug, Deserialize)]
struct ListConversationsQuery {
    #[serde(default = "default_limit")]
    limit: usize,
    #[serde(default)]
    offset: usize,
}

fn default_limit() -> usize {
    50
}

/// GET /conversations - List all conversations for authenticated user
///
/// Returns user's conversation list sorted by last_activity DESC
async fn list_conversations(
    State(state): State<AppState>,
    claims: Claims, // From JWT middleware
    Query(query): Query<ListConversationsQuery>,
) -> AppResult<Json<ConversationsListResponse>> {
    // Validate limits
    let limit = query.limit.min(100); // Max 100 conversations per request

    // Fetch conversations (use 'sub' field which contains user_id as Uuid)
    let response = state
        .conversation_service
        .list_conversations(claims.sub, limit, query.offset)
        .await?;

    tracing::debug!(
        "Listed {} conversations for user {} (total: {}, limit: {}, offset: {})",
        response.conversations.len(),
        claims.convro_number,
        response.total,
        limit,
        query.offset
    );

    Ok(Json(response))
}

#[cfg(test)]
mod tests {
    use super::*;

    // API tests would go here
}
