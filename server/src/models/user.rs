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

    // Device identity fields (Ed25519 and X25519 keys)
    #[serde(alias = "identityPubEd25519")]
    #[validate(length(equal = 64))] // Ed25519 public key (32 bytes = 64 hex)
    pub identity_pub_ed25519: String,

    #[serde(alias = "identityPubX25519")]
    #[validate(length(equal = 64))] // X25519 public key (32 bytes = 64 hex)
    pub identity_key: String,

    // Optional: iOS sends deviceId but it's not used (we use Ed25519 as device_id)
    #[serde(alias = "deviceId")]
    pub device_id: Option<String>,

    // Signed prekey
    #[serde(alias = "spkId")]
    pub spk_id: String,

    #[serde(alias = "spkPub")]
    #[validate(length(equal = 64))]
    pub spk_pub: String,

    #[serde(alias = "spkSig")]
    #[validate(length(equal = 128))] // 64 bytes = 128 hex chars
    pub spk_sig: String,

    // One-time prekeys
    #[serde(alias = "oneTimePrekeys")]
    pub one_time_prekeys: Vec<OneTimePrekeyData>,

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

/// One-time prekey data from iOS
#[derive(Debug, Deserialize)]
pub struct OneTimePrekeyData {
    #[serde(alias = "otpId")]
    pub otp_id: String,

    #[serde(alias = "otpPub")]
    pub otp_pub: String,
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
