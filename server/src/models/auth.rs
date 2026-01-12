use serde::{Deserialize, Serialize};

/// JWT Claims (re-exported from utils for convenience)
pub use crate::utils::jwt::Claims;

/// Authentication tokens (access + refresh)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthTokens {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_in: u64,
    pub token_type: String,
}

impl AuthTokens {
    pub fn new(access_token: String, refresh_token: String) -> Self {
        Self {
            access_token,
            refresh_token,
            expires_in: 3600, // 1 hour
            token_type: "Bearer".to_string(),
        }
    }
}

/// Refresh token request
#[derive(Debug, Deserialize)]
pub struct RefreshTokenRequest {
    pub refresh_token: String,
}

/// Refresh token response
#[derive(Debug, Serialize)]
pub struct RefreshTokenResponse {
    pub access_token: String,
    pub expires_in: u64,
    pub token_type: String,
}
