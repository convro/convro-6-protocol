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
    pub otp_id: String,       // Client's hex-encoded OTP ID (16 chars = 8 bytes)
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
#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct SignedPrekeyDto {
    pub spk_id: i32,

    #[validate(length(equal = 64))] // 32 bytes hex
    pub public_key: String,

    #[validate(length(equal = 128))] // 64 bytes hex
    pub signature: String,

    pub expires_at: Option<DateTime<Utc>>,
}

/// One-Time Prekey DTO (hex-encoded)
#[derive(Debug, Serialize, Deserialize, Validate)]
pub struct OneTimePrekeyDto {
    #[serde(alias = "otpId")]  // Accept both otp_id and otpId from clients
    #[validate(length(equal = 16))]  // 8 bytes = 16 hex chars
    pub otp_id: String,

    #[serde(alias = "otpPub")]  // Accept both public_key and otpPub from clients
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
    pub client_otp_id: Option<String>,  // Client's original hex-encoded OTP ID
}

/// Prekey bundle response (for API) - flat structure matching iOS client expectations
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct PrekeyBundleResponse {
    pub user_id: Uuid,
    pub convro_number: String,
    pub device_identity_id: Uuid,

    // Device identity (flat)
    pub responder_device_id: String,      // Hex-encoded Ed25519 pub key (device_id)
    pub identity_pub_ed25519: String,     // Hex-encoded Ed25519 pub key (identity_key)
    pub identity_pub_x25519: String,      // Hex-encoded X25519 pub key (same as identity_key for now)

    // Signed prekey (flat)
    pub spk_id: String,                   // Hex-encoded SPK ID
    pub spk_pub: String,                  // Hex-encoded X25519 pub key
    pub spk_sig: String,                  // Hex-encoded Ed25519 signature

    // One-time prekey (flat, optional)
    #[serde(skip_serializing_if = "Option::is_none")]
    pub otp_id: Option<String>,           // Client's original hex OTP ID
    #[serde(skip_serializing_if = "Option::is_none")]
    pub otp_pub: Option<String>,          // Hex-encoded X25519 pub key
}

impl From<PrekeyBundle> for PrekeyBundleResponse {
    fn from(bundle: PrekeyBundle) -> Self {
        // Extract OTP fields if present
        let (otp_id, otp_pub) = match (bundle.client_otp_id, bundle.one_time_prekey) {
            (Some(id), Some(key)) => (Some(id), Some(hex::encode(key))),
            _ => (None, None),
        };

        Self {
            user_id: bundle.user_id,
            convro_number: bundle.convro_number,
            device_identity_id: bundle.device_identity_id,

            // Device identity
            responder_device_id: hex::encode(&bundle.device_id),
            identity_pub_ed25519: hex::encode(&bundle.device_id),  // Ed25519 pub is device_id
            identity_pub_x25519: hex::encode(&bundle.identity_key), // X25519 DH key

            // Signed prekey
            spk_id: hex::encode(bundle.signed_prekey_id.to_be_bytes()),
            spk_pub: hex::encode(&bundle.signed_prekey),
            spk_sig: hex::encode(&bundle.signed_prekey_signature),

            // One-time prekey
            otp_id,
            otp_pub,
        }
    }
}
