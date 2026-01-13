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
    models::{
        auth::Claims,
        sealed_message::{
            SealedInboxResponse, SendSealedMessageRequest, SendSealedMessageResponse,
        },
    },
    services::sealed_message_service::SealedMessageService,
};

/// App state for sealed messages API
#[derive(Clone)]
pub struct AppState {
    pub sealed_message_service: SealedMessageService,
}

/// Create sealed messages router
pub fn sealed_messages_router(state: AppState) -> Router {
    Router::new()
        .route("/messages/sealed", post(send_sealed_message))
        .route("/messages/sealed/inbox", get(fetch_sealed_inbox))
        .route(
            "/messages/sealed/:message_id/delivered",
            post(mark_sealed_delivered),
        )
        .with_state(state)
}

/// Query params for inbox
#[derive(Debug, Deserialize)]
struct InboxQuery {
    #[serde(default = "default_limit")]
    limit: usize,
    #[serde(default)]
    offset: usize,
}

fn default_limit() -> usize {
    50
}

/// POST /messages/sealed - Send sealed sender message
///
/// Privacy features:
/// - Sender identity hidden from server
/// - Envelope padded to 64KB (hides content length)
/// - Timestamp obfuscated (rounded to 5min)
/// - Timing jitter applied (0-5s delay)
async fn send_sealed_message(
    State(state): State<AppState>,
    _claims: Claims, // Sender authenticated but identity NOT stored
    Json(req): Json<SendSealedMessageRequest>,
) -> AppResult<(StatusCode, Json<SendSealedMessageResponse>)> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Decode base64 encrypted envelope
    let encrypted_envelope = base64::Engine::decode(
        &base64::engine::general_purpose::STANDARD,
        &req.encrypted_envelope,
    )
    .map_err(|_| {
        AppError::ValidationError("Invalid base64 encrypted_envelope".to_string())
    })?;

    // Send sealed message (service handles padding, timing obfuscation)
    let message = state
        .sealed_message_service
        .send_sealed_message(req.to_convro_number.clone(), encrypted_envelope)
        .await?;

    tracing::info!(
        "Sealed message sent: {} to {} (sender identity hidden)",
        message.message_id,
        req.to_convro_number
    );

    Ok((
        StatusCode::CREATED,
        Json(SendSealedMessageResponse {
            message_id: message.message_id,
            delivery_status: message.delivery_status,
            created_at: message.created_at, // Obfuscated timestamp
        }),
    ))
}

/// GET /messages/sealed/inbox - Fetch sealed inbox
///
/// Returns pending sealed messages for authenticated user
async fn fetch_sealed_inbox(
    State(state): State<AppState>,
    claims: Claims, // Recipient authenticated
    Query(query): Query<InboxQuery>,
) -> AppResult<Json<SealedInboxResponse>> {
    // Validate limits
    let limit = query.limit.min(100); // Max 100 messages per request

    // Fetch inbox (use 'sub' field which contains user_id)
    let user_id = claims.sub;

    let response = state
        .sealed_message_service
        .fetch_inbox(user_id, limit, query.offset)
        .await?;

    tracing::debug!(
        "Fetched {} sealed messages for user {} (total: {}, limit: {}, offset: {})",
        response.messages.len(),
        claims.convro_number,
        response.total,
        limit,
        query.offset
    );

    Ok(Json(response))
}

/// POST /messages/sealed/:message_id/delivered - Mark sealed message as delivered
///
/// Acknowledges receipt of sealed message
async fn mark_sealed_delivered(
    State(state): State<AppState>,
    claims: Claims, // Recipient
    Path(message_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    // Mark as delivered (use 'sub' field which contains user_id)
    let user_id = claims.sub;

    state
        .sealed_message_service
        .mark_as_delivered(message_id, user_id)
        .await?;

    tracing::debug!(
        "Sealed message {} marked as delivered by user {}",
        message_id,
        claims.convro_number
    );

    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    // API tests would go here
}
