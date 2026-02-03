use axum::{
    extract::State,
    routing::get,
    Json, Router,
};

use crate::{
    errors::AppResult,
    models::{user::UserResponse, Claims},
    services::UserService,
};

/// Application state for users endpoints
#[derive(Clone)]
pub struct AppState {
    pub user_service: UserService,
}

/// Create users router
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/users/me", get(get_current_user))
        .with_state(state)
}

/// GET /users/me - Get current user profile
///
/// Returns the authenticated user's profile information.
async fn get_current_user(
    State(state): State<AppState>,
    claims: Claims,
) -> AppResult<Json<UserResponse>> {
    let user = state.user_service.get_user_profile(claims.sub).await?;
    Ok(Json(user))
}
