//! Error types for IslandAccord v1 handshake

use thiserror::Error;

/// IslandAccord handshake errors
#[derive(Debug, Error)]
pub enum HandshakeError {
    /// Invalid prekey bundle
    #[error("Invalid prekey bundle: {0}")]
    InvalidBundle(String),

    /// SPK signature verification failed
    #[error("SPK signature verification failed")]
    InvalidSpkSignature,

    /// Offer signature verification failed
    #[error("Offer signature verification failed")]
    InvalidOfferSignature,

    /// Transcript hash mismatch
    #[error("Transcript hash mismatch")]
    TranscriptMismatch,

    /// Key confirmation verification failed
    #[error("Key confirmation verification failed: {0}")]
    KcVerificationFailed(String),

    /// Invalid wire format
    #[error("Invalid wire format: {0}")]
    InvalidWireFormat(String),

    /// Cryptographic operation failed
    #[error("Cryptographic operation failed: {0}")]
    CryptoError(String),

    /// Protocol state error
    #[error("Protocol state error: {0}")]
    StateError(String),
}

/// Result type for handshake operations
pub type Result<T> = std::result::Result<T, HandshakeError>;
