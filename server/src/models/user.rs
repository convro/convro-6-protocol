use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

use super::auth::AuthTokens;

/// User model (from database)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct User {
    pub user_id: Uuid,
    pub username: String,
    pub convro_number: String,
    pub password_hash: String,
    pub display_name: Option<String>,
    pub account_status: String,
    pub created_at: DateTime<Utc>,
    pub last_login: Option<DateTime<Utc>>,
    pub updated_at: DateTime<Utc>,
}

/// Create user request (registration)
#[derive(Debug, Deserialize, Validate)]
pub struct CreateUserRequest {
    #[validate(length(min = 3, max = 50))]
    pub username: String,

    #[validate(length(min = 8))]
    pub password: String,

    #[validate(length(max = 100))]
    pub display_name: Option<String>,

    // Device identity fields
    #[serde(alias = "deviceId")]
    #[validate(length(equal = 64))] // 32 bytes = 64 hex chars
    pub device_id: String,

    #[serde(alias = "identityPubX25519")]
    #[validate(length(equal = 64))]
    pub identity_key: String,

    // Optional device info
    #[serde(alias = "deviceName")]
    pub device_name: Option<String>,

    #[serde(alias = "devicePlatform")]
    pub device_platform: Option<String>,

    #[serde(alias = "deviceOsVersion")]
    pub device_os_version: Option<String>,

    #[serde(alias = "appVersion")]
    pub app_version: Option<String>,
}

/// Login request
#[derive(Debug, Deserialize, Validate)]
pub struct LoginRequest {
    #[validate(length(min = 3))]
    pub username: String,

    #[validate(length(min = 1))]
    pub password: String,
}

/// User response (for API)
#[derive(Debug, Serialize)]
pub struct UserResponse {
    pub user_id: Uuid,
    pub username: String,
    pub convro_number: String,
    pub display_name: Option<String>,
    pub created_at: DateTime<Utc>,
    pub last_login: Option<DateTime<Utc>>,
    pub account_status: String,
}

impl From<User> for UserResponse {
    fn from(user: User) -> Self {
        Self {
            user_id: user.user_id,
            username: user.username,
            convro_number: user.convro_number,
            display_name: user.display_name,
            created_at: user.created_at,
            last_login: user.last_login,
            account_status: user.account_status,
        }
    }
}

/// Register response (includes tokens)
#[derive(Debug, Serialize)]
pub struct RegisterResponse {
    #[serde(flatten)]
    pub user: UserResponse,
    pub tokens: AuthTokens,
}

/// Login response (includes tokens)
#[derive(Debug, Serialize)]
pub struct LoginResponse {
    #[serde(flatten)]
    pub user: UserResponse,
    pub tokens: AuthTokens,
}
