use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Device identity model (from database)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Device {
    pub device_identity_id: Uuid,
    pub user_id: Uuid,
    pub device_id: Vec<u8>,        // Ed25519 public key (32 bytes)
    pub identity_key: Vec<u8>,     // X25519 public key (32 bytes)
    pub device_name: Option<String>,
    pub device_platform: Option<String>,
    pub device_os_version: Option<String>,
    pub app_version: Option<String>,
    pub registered_at: DateTime<Utc>,
    pub last_seen: Option<DateTime<Utc>>,
    pub is_active: bool,
}

/// Register device request
#[derive(Debug, Deserialize, Validate)]
pub struct RegisterDeviceRequest {
    #[validate(length(equal = 64))] // 32 bytes = 64 hex chars
    pub device_id: String,

    #[validate(length(equal = 64))]
    pub identity_key: String,

    #[validate(length(max = 100))]
    pub device_name: Option<String>,

    #[validate(length(max = 20))]
    pub device_platform: Option<String>,

    #[validate(length(max = 50))]
    pub device_os_version: Option<String>,

    #[validate(length(max = 20))]
    pub app_version: Option<String>,
}

/// Device response (for API)
#[derive(Debug, Serialize)]
pub struct DeviceResponse {
    pub device_identity_id: Uuid,
    pub device_id: String, // Hex-encoded
    pub identity_key: String, // Hex-encoded
    pub device_name: Option<String>,
    pub device_platform: Option<String>,
    pub registered_at: DateTime<Utc>,
    pub last_seen: Option<DateTime<Utc>>,
    pub is_active: bool,
}

impl From<Device> for DeviceResponse {
    fn from(device: Device) -> Self {
        Self {
            device_identity_id: device.device_identity_id,
            device_id: hex::encode(device.device_id),
            identity_key: hex::encode(device.identity_key),
            device_name: device.device_name,
            device_platform: device.device_platform,
            registered_at: device.registered_at,
            last_seen: device.last_seen,
            is_active: device.is_active,
        }
    }
}
