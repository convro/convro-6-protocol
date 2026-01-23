use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;
use validator::Validate;

/// Contact model (from database)
#[derive(Debug, Clone, Serialize, Deserialize, sqlx::FromRow)]
pub struct Contact {
    pub contact_id: Uuid,
    pub user_id: Uuid,
    pub contact_convro_number: String,
    pub contact_user_id: Option<Uuid>,
    pub display_name: Option<String>,
    pub is_verified: bool,
    pub verified_at: Option<DateTime<Utc>>,
    pub added_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

/// Contact response (for API) - includes contact's device identity
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ContactResponse {
    pub contact_id: Uuid,
    pub convro_number: String,
    pub display_name: Option<String>,
    pub identity_pub_ed25519: String, // Device ID (Ed25519 public key as base64)
    pub fingerprint: String,          // Same as identity_pub_ed25519 for now
    pub verified: bool,
    pub created_at: DateTime<Utc>,
}

/// Add contact request
#[derive(Debug, Deserialize, Validate)]
#[serde(rename_all = "camelCase")]
pub struct AddContactRequest {
    #[validate(length(min = 6, max = 15))]
    pub convro_number: String,

    #[validate(length(max = 100))]
    pub display_name: Option<String>,
}

/// Contacts list response
#[derive(Debug, Serialize)]
pub struct ContactsResponse {
    pub contacts: Vec<ContactResponse>,
}
