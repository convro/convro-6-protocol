use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Signed Prekey
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedPrekey {
    pub spk_id: i32,
    pub public_key: Vec<u8>,  // X25519 public key (32 bytes)
    pub signature: Vec<u8>,   // Ed25519 signature (64 bytes)
    pub expires_at: Option<DateTime<Utc>>,
}

/// One-Time Prekey
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OneTimePrekey {
    pub otp_id: i32,
    pub public_key: Vec<u8>,  // X25519 public key (32 bytes)
}

/// Upload prekeys request
#[derive(Debug, Deserialize, Validate)]
pub struct UploadPrekeysRequest {
    pub device_identity_id: Uuid,

    pub signed_prekey: SignedPrekeyDto,

    #[validate(length(min = 1, max = 100))]
    pub one_time_prekeys: Vec<OneTimePrekeyDto>,
}

/// Signed Prekey DTO (hex-encoded)
#[derive(Debug, Deserialize, Validate)]
pub struct SignedPrekeyDto {
    pub spk_id: i32,

    #[validate(length(equal = 64))] // 32 bytes hex
    pub public_key: String,

    #[validate(length(equal = 128))] // 64 bytes hex
    pub signature: String,

    pub expires_at: Option<DateTime<Utc>>,
}

/// One-Time Prekey DTO (hex-encoded)
#[derive(Debug, Deserialize, Validate)]
pub struct OneTimePrekeyDto {
    pub otp_id: i32,

    #[validate(length(equal = 64))]
    pub public_key: String,
}

/// Prekey bundle (for handshake initiation)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct PrekeyBundle {
    pub user_id: Uuid,
    pub convro_number: String,
    pub device_identity_id: Uuid,
    pub device_id: Vec<u8>,
    pub identity_key: Vec<u8>,
    pub signed_prekey: Vec<u8>,
    pub signed_prekey_signature: Vec<u8>,
    pub signed_prekey_id: i32,
    pub one_time_prekey: Option<Vec<u8>>,
    pub otp_id: Option<Uuid>,
}

/// Prekey bundle response (for API)
#[derive(Debug, Serialize)]
pub struct PrekeyBundleResponse {
    pub user_id: Uuid,
    pub convro_number: String,
    pub device_identity_id: Uuid,
    pub device_id: String,          // Hex-encoded
    pub identity_key: String,       // Hex-encoded
    pub signed_prekey: SignedPrekeyResponse,
    pub one_time_prekey: Option<OneTimePrekeyResponse>,
}

#[derive(Debug, Serialize)]
pub struct SignedPrekeyResponse {
    pub spk_id: i32,
    pub public_key: String,   // Hex-encoded
    pub signature: String,    // Hex-encoded
}

#[derive(Debug, Serialize)]
pub struct OneTimePrekeyResponse {
    pub otp_id: Uuid,
    pub public_key: String,   // Hex-encoded
}

impl From<PrekeyBundle> for PrekeyBundleResponse {
    fn from(bundle: PrekeyBundle) -> Self {
        Self {
            user_id: bundle.user_id,
            convro_number: bundle.convro_number,
            device_identity_id: bundle.device_identity_id,
            device_id: hex::encode(bundle.device_id),
            identity_key: hex::encode(bundle.identity_key),
            signed_prekey: SignedPrekeyResponse {
                spk_id: bundle.signed_prekey_id,
                public_key: hex::encode(bundle.signed_prekey),
                signature: hex::encode(bundle.signed_prekey_signature),
            },
            one_time_prekey: bundle.one_time_prekey.zip(bundle.otp_id).map(|(key, id)| {
                OneTimePrekeyResponse {
                    otp_id: id,
                    public_key: hex::encode(key),
                }
            }),
        }
    }
}
