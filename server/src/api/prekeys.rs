use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use validator::Validate;

use crate::{
    errors::{AppError, AppResult},
    models::{Claims, PrekeyBundleResponse, UploadPrekeysRequest},
    services::PrekeyService,
};

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub prekey_service: PrekeyService,
}

/// Create prekeys router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/prekeys", post(upload_prekeys))
        .route("/prekeys/:convro_number", get(fetch_bundle))
        .route("/prekeys/health", get(get_health))
        .with_state(state)
}

/// POST /prekeys - Upload prekeys
async fn upload_prekeys(
    State(state): State<AppState>,
    claims: Claims, // From JWT middleware
    Json(req): Json<UploadPrekeysRequest>,
) -> AppResult<(StatusCode, Json<UploadPrekeysResponse>)> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Upload prekeys
    let bundle_id = state
        .prekey_service
        .upload_prekeys(req.device_identity_id, req.signed_prekey, req.one_time_prekeys)
        .await?;

    Ok((
        StatusCode::CREATED,
        Json(UploadPrekeysResponse {
            bundle_id,
            device_identity_id: req.device_identity_id,
            otps_uploaded: req.one_time_prekeys.len() as i32,
        }),
    ))
}

/// GET /prekeys/:convro_number - Fetch prekey bundle
async fn fetch_bundle(
    State(state): State<AppState>,
    claims: Claims, // Authenticated user fetching bundle
    Path(convro_number): Path<String>,
) -> AppResult<Json<PrekeyBundleResponse>> {
    // Fetch bundle
    let bundle = state.prekey_service.fetch_bundle(&convro_number).await?;

    Ok(Json(bundle.into()))
}

/// GET /prekeys/health - Get prekey health status
async fn get_health(
    State(state): State<AppState>,
    claims: Claims,
) -> AppResult<Json<PrekeyHealthResponse>> {
    let health_statuses = state.prekey_service.get_prekey_health(claims.sub).await?;

    let devices = health_statuses
        .into_iter()
        .map(|status| DeviceHealthStatus {
            device_identity_id: status.device_identity_id,
            device_name: status.device_name,
            has_signed_prekey: status.has_signed_prekey,
            spk_expires_at: status.spk_expires_at,
            available_otps: status.available_otps,
            consumed_otps: status.consumed_otps,
            status: if status.available_otps >= 10 {
                "healthy"
            } else if status.available_otps > 0 {
                "low"
            } else {
                "critical"
            }
            .to_string(),
        })
        .collect();

    Ok(Json(PrekeyHealthResponse { devices }))
}

#[derive(serde::Serialize)]
struct UploadPrekeysResponse {
    bundle_id: uuid::Uuid,
    device_identity_id: uuid::Uuid,
    otps_uploaded: i32,
}

#[derive(serde::Serialize)]
struct PrekeyHealthResponse {
    devices: Vec<DeviceHealthStatus>,
}

#[derive(serde::Serialize)]
struct DeviceHealthStatus {
    device_identity_id: uuid::Uuid,
    device_name: Option<String>,
    has_signed_prekey: bool,
    spk_expires_at: Option<chrono::DateTime<chrono::Utc>>,
    available_otps: i64,
    consumed_otps: i64,
    status: String, // "healthy", "low", "critical"
}
