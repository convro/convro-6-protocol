use axum::{
    body::Bytes,
    extract::{Path, State},
    routing::{delete, get, post},
    Json, Router,
};
use uuid::Uuid;

use crate::{
    errors::AppResult,
    models::{contact::{AddContactRequest, ContactResponse, ContactsResponse}, Claims},
    services::ContactService,
};

/// Application state for contacts endpoints
#[derive(Clone)]
pub struct AppState {
    pub contact_service: ContactService,
}

/// Create contacts router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/contacts", get(list_contacts).post(add_contact))
        .route("/contacts/:id", delete(delete_contact))
        .route("/contacts/:id/verify", post(verify_contact))
        .with_state(state)
}

/// GET /contacts - List all contacts for authenticated user
async fn list_contacts(
    State(state): State<AppState>,
    claims: Claims,
) -> AppResult<Json<ContactsResponse>> {
    let contacts = state.contact_service.list_contacts(claims.sub).await?;
    Ok(Json(contacts))
}

/// POST /contacts - Add new contact
async fn add_contact(
    State(state): State<AppState>,
    claims: Claims,
    body: Bytes,
) -> AppResult<Json<ContactResponse>> {
    // Log raw body for debugging
    let body_str = String::from_utf8_lossy(&body);
    tracing::info!(
        "POST /contacts - user_id={}, raw_body: {}",
        claims.sub,
        body_str
    );

    // Try to deserialize
    let request: AddContactRequest = serde_json::from_slice(&body)
        .map_err(|e| {
            tracing::error!("JSON deserialization failed: {}", e);
            crate::errors::AppError::ValidationError(format!("Invalid JSON: {}", e))
        })?;

    tracing::info!(
        "Deserialized: convro_number='{}' (len={}), display_name={:?}",
        request.convro_number,
        request.convro_number.len(),
        request.display_name
    );

    let contact = state.contact_service.add_contact(claims.sub, request).await?;
    Ok(Json(contact))
}

/// DELETE /contacts/:id - Delete contact
async fn delete_contact(
    State(state): State<AppState>,
    claims: Claims,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<serde_json::Value>> {
    state
        .contact_service
        .delete_contact(contact_id, claims.sub)
        .await?;
    Ok(Json(serde_json::json!({"success": true})))
}

/// POST /contacts/:id/verify - Mark contact as verified
async fn verify_contact(
    State(state): State<AppState>,
    claims: Claims,
    Path(contact_id): Path<Uuid>,
) -> AppResult<Json<ContactResponse>> {
    let contact = state
        .contact_service
        .verify_contact(contact_id, claims.sub, true)
        .await?;
    Ok(Json(contact))
}
