use axum::{
    body::Bytes,
    extract::State,
    http::StatusCode,
    routing::post,
    Json, Router,
};
use validator::Validate;

use crate::{
    errors::{AppError, AppResult},
    models::{
        auth::{RefreshTokenRequest, RefreshTokenResponse},
        user::{CreateUserRequest, LoginRequest, LoginResponse, RegisterResponse},
        Claims,
    },
    services::AuthService,
};

/// Application state (passed to all handlers)
#[derive(Clone)]
pub struct AppState {
    pub auth_service: AuthService,
}

/// Create auth router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh_token))
        .route("/auth/logout", post(logout))
        .with_state(state)
}

/// POST /auth/register - Register new user
///
/// Creates a new user account, device identity, and assigns a Convro Number.
async fn register(
    State(state): State<AppState>,
    body: Bytes,
) -> AppResult<(StatusCode, Json<RegisterResponse>)> {
    // Log raw body for debugging
    let body_str = String::from_utf8_lossy(&body);
    tracing::info!("POST /auth/register - raw_body: {}", body_str);

    // Deserialize request
    let req: CreateUserRequest = serde_json::from_slice(&body)
        .map_err(|e| {
            tracing::error!("Registration JSON deserialization failed: {}", e);
            AppError::ValidationError(format!("Invalid JSON: {}", e))
        })?;

    tracing::info!(
        "Registration attempt - username: {}, has_identity_pub_ed25519: {}, has_identity_key: {}, has_spk_id: {}, has_spk_pub: {}, has_spk_sig: {}, otp_count: {}",
        req.username,
        !req.identity_pub_ed25519.is_empty(),
        !req.identity_key.is_empty(),
        !req.spk_id.is_empty(),
        !req.spk_pub.is_empty(),
        !req.spk_sig.is_empty(),
        req.one_time_prekeys.len()
    );

    // Validate request
    req.validate()
        .map_err(|e| {
            tracing::error!("Registration validation failed: {}", e);
            AppError::ValidationError(e.to_string())
        })?;

    // Register user, device, and prekeys via service
    let (user, tokens) = state
        .auth_service
        .register_user(
            req.username,
            req.password,
            req.display_name,
            req.identity_pub_ed25519,  // Ed25519 -> device_id in DB
            req.identity_key,           // X25519 -> identity_key in DB
            req.spk_id,
            req.spk_pub,
            req.spk_sig,
            req.one_time_prekeys,
            req.device_name,
            req.device_platform,
            req.device_os_version,
            req.app_version,
        )
        .await?;

    let response = RegisterResponse {
        user: user.into(),
        tokens,
    };

    Ok((StatusCode::CREATED, Json(response)))
}

/// POST /auth/login - Login existing user
///
/// Authenticates user and returns JWT tokens.
async fn login(
    State(state): State<AppState>,
    Json(req): Json<LoginRequest>,
) -> AppResult<Json<LoginResponse>> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Authenticate user
    let (user, tokens) = state
        .auth_service
        .login(req.username, req.password)
        .await?;

    let response = LoginResponse {
        user: user.into(),
        tokens,
    };

    Ok(Json(response))
}

/// POST /auth/refresh - Refresh access token
///
/// Obtains new access token using refresh token.
async fn refresh_token(
    State(state): State<AppState>,
    Json(req): Json<RefreshTokenRequest>,
) -> AppResult<Json<RefreshTokenResponse>> {
    // Refresh access token
    let access_token = state
        .auth_service
        .refresh_access_token(req.refresh_token)
        .await?;

    let response = RefreshTokenResponse {
        access_token,
        expires_in: 3600,
        token_type: "Bearer".to_string(),
    };

    Ok(Json(response))
}

/// POST /auth/logout - Logout user
///
/// Invalidates current tokens (for stateless JWT, this is a no-op).
async fn logout(
    State(state): State<AppState>,
    claims: Claims, // Extracted by JWT middleware
) -> AppResult<StatusCode> {
    state.auth_service.logout(claims.sub).await?;

    Ok(StatusCode::NO_CONTENT)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Integration tests would go here
    // Requires test database and HTTP client
}
