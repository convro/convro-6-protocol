use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{delete, get, post},
    Json, Router,
};
use uuid::Uuid;
use validator::Validate;

use crate::{
    errors::{AppError, AppResult},
    models::{device::DeviceResponse, Claims, RegisterDeviceRequest},
    services::DeviceService,
};

/// Application state
#[derive(Clone)]
pub struct AppState {
    pub device_service: DeviceService,
}

/// Create devices router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/devices", post(register_device))
        .route("/devices", get(list_devices))
        .route("/devices/:device_id", delete(deactivate_device))
        .with_state(state)
}

/// POST /devices - Register new device
async fn register_device(
    State(state): State<AppState>,
    claims: Claims, // From JWT middleware
    Json(req): Json<RegisterDeviceRequest>,
) -> AppResult<(StatusCode, Json<DeviceResponse>)> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Register device
    let device = state
        .device_service
        .register_device(
            claims.sub,
            req.device_id,
            req.identity_key,
            req.device_name,
            req.device_platform,
            req.device_os_version,
            req.app_version,
        )
        .await?;

    Ok((StatusCode::CREATED, Json(device.into())))
}

/// GET /devices - List user's devices
async fn list_devices(
    State(state): State<AppState>,
    claims: Claims,
) -> AppResult<Json<DevicesListResponse>> {
    let devices = state.device_service.list_user_devices(claims.sub).await?;

    let devices_response: Vec<DeviceResponse> = devices.into_iter().map(|d| d.into()).collect();

    Ok(Json(DevicesListResponse {
        devices: devices_response,
    }))
}

/// DELETE /devices/:device_id - Deactivate device
async fn deactivate_device(
    State(state): State<AppState>,
    claims: Claims,
    Path(device_id): Path<Uuid>,
) -> AppResult<StatusCode> {
    state
        .device_service
        .deactivate_device(device_id, claims.sub)
        .await?;

    Ok(StatusCode::NO_CONTENT)
}

#[derive(serde::Serialize)]
struct DevicesListResponse {
    devices: Vec<DeviceResponse>,
}
