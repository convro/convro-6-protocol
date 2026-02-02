use axum::{
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
/// Creates a new user account and assigns a Convro Number.
async fn register(
    State(state): State<AppState>,
    Json(req): Json<CreateUserRequest>,
) -> AppResult<(StatusCode, Json<RegisterResponse>)> {
    // Validate request
    req.validate()
        .map_err(|e| AppError::ValidationError(e.to_string()))?;

    // Register user via service (includes device identity and prekeys)
    let (user, tokens) = state
        .auth_service
        .register_user(req)
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
