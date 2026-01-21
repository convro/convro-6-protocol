use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde::Deserialize;
use uuid::Uuid;
use validator::Validate;

use crate::{
    errors::{AppError, AppResult},
    models::{message::InboxResponse, Claims, MessageResponse, SendMessageRequest},
    services::MessageService,
};

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub message_service: MessageService,
}

/// Create messages router (LEGACY mode - backward compatibility ONLY)
///
/// ⚠️ WARNING: This is LEGACY mode where server sees sender identity
/// USE /messages instead (sealed sender = privacy-first standard)
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/messages/legacy", post(send_message))
        .route("/messages/legacy/inbox", get(fetch_inbox))
        .route("/messages/legacy/:message_id/delivered", post(mark_delivered))
        .route("/messages/legacy/history", get(get_history))
        .with_state(state)
}

/// POST /messages/legacy - Send message (LEGACY MODE)
///
/// ⚠️ PRIVACY WARNING: Server sees sender identity in legacy mode
/// Migrate to sealed sender at /messages for privacy-first standard
async fn send_message(
    State(state): State<AppState>,
    claims: Claims, // From JWT middleware
    Json(req): Json<SendMessageRequest>,
) -> AppResult<(StatusCode, Json<MessageResponse>)> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Send message
    let message = state
        .message_service
        .send_message(
            claims.sub,
            claims.convro_number.clone(),
            req.to_convro_number,
            req.session_id,
            req.message_type,
            req.encrypted_blob,
        )
        .await?;

    Ok((StatusCode::CREATED, Json(message.into())))
}

/// GET /messages/legacy/inbox - Fetch inbox (LEGACY)
async fn fetch_inbox(
    State(state): State<AppState>,
    claims: Claims,
    Query(params): Query<PaginationParams>,
) -> AppResult<Json<InboxResponse>> {
    let limit = params.limit.unwrap_or(50).min(100);
    let offset = params.offset.unwrap_or(0);

    let (messages, total) = state.message_service.fetch_inbox(claims.sub, limit, offset).await?;

    let messages_response: Vec<MessageResponse> = messages.into_iter().map(|m| m.into()).collect();

    Ok(Json(InboxResponse {
        messages: messages_response,
        total,
        limit,
        offset,
    }))
}

/// POST /messages/legacy/:message_id/delivered - Mark message as delivered (LEGACY)
async fn mark_delivered(
    State(state): State<AppState>,
    claims: Claims,
    Path(message_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    state
        .message_service
        .mark_as_delivered(message_id, claims.sub)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

/// GET /messages/legacy/history - Get message history for session (LEGACY)
async fn get_history(
    State(state): State<AppState>,
    claims: Claims,
    Query(params): Query<HistoryParams>,
) -> AppResult<Json<InboxResponse>> {
    let session_id = params
        .session_id
        .ok_or_else(|| AppError::ValidationError("session_id is required".to_string()))?;

    let limit = params.pagination.limit.unwrap_or(50).min(100);
    let offset = params.pagination.offset.unwrap_or(0);

    let (messages, total) = state
        .message_service
        .get_session_history(session_id, claims.sub, limit, offset)
        .await?;

    let messages_response: Vec<MessageResponse> = messages.into_iter().map(|m| m.into()).collect();

    Ok(Json(InboxResponse {
        messages: messages_response,
        total,
        limit,
        offset,
    }))
}

#[derive(Deserialize)]
struct PaginationParams {
    limit: Option<i64>,
    offset: Option<i64>,
}

#[derive(Deserialize)]
struct HistoryParams {
    session_id: Option<String>,
    #[serde(flatten)]
    pagination: PaginationParams,
}
