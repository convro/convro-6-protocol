//! Error types for identity operations

use thiserror::Error;

/// Identity operation errors
#[derive(Debug, Error)]
pub enum IdentityError {
    /// Invalid public key
    #[error("Invalid public key: {0}")]
    InvalidPublicKey(String),

    /// Invalid device ID
    #[error("Invalid device ID: {0}")]
    InvalidDeviceId(String),

    /// Invalid fingerprint
    #[error("Invalid fingerprint: {0}")]
    InvalidFingerprint(String),

    /// Encoding error
    #[error("Encoding error: {0}")]
    EncodingError(String),
}

/// Result type for identity operations
pub type Result<T> = std::result::Result<T, IdentityError>;
