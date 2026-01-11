//! Error types for iOS bridge

use thiserror::Error;

/// C6P error types exposed to Swift
///
/// These errors map from the various C6P crate error types
/// into a unified, Swift-friendly error enum.
#[derive(Debug, Error)]
pub enum C6pError {
    /// Invalid key format or length
    #[error("Invalid key: {0}")]
    InvalidKey(String),

    /// Invalid signature
    #[error("Invalid signature: {0}")]
    InvalidSignature(String),

    /// Invalid device ID
    #[error("Invalid device ID: {0}")]
    InvalidDeviceId(String),

    /// Invalid fingerprint
    #[error("Invalid fingerprint: {0}")]
    InvalidFingerprint(String),

    /// Handshake failed
    #[error("Handshake failed: {0}")]
    HandshakeFailed(String),

    /// Cryptographic error
    #[error("Crypto error: {0}")]
    CryptoError(String),

    /// Session error
    #[error("Session error: {0}")]
    SessionError(String),

    /// Replay attack detected
    #[error("Replay detected: {0}")]
    ReplayDetected(String),

    /// Counter exhausted (2^64-1 limit)
    #[error("Counter exhausted")]
    CounterExhausted,

    /// Decryption failed
    #[error("Decryption failed: {0}")]
    DecryptionFailed(String),

    /// Serialization/deserialization error
    #[error("Serialization error: {0}")]
    SerializationError(String),

    /// Invalid input
    #[error("Invalid input: {0}")]
    InvalidInput(String),
}

impl From<c6p_identity::IdentityError> for C6pError {
    fn from(e: c6p_identity::IdentityError) -> Self {
        match e {
            c6p_identity::IdentityError::InvalidPublicKey(_) => C6pError::InvalidKey(e.to_string()),
            c6p_identity::IdentityError::InvalidDeviceId(_) => {
                C6pError::InvalidDeviceId(e.to_string())
            }
            c6p_identity::IdentityError::InvalidFingerprint(_) => {
                C6pError::InvalidFingerprint(e.to_string())
            }
            c6p_identity::IdentityError::EncodingError(_) => {
                C6pError::SerializationError(e.to_string())
            }
        }
    }
}

impl From<c6p_handshake::HandshakeError> for C6pError {
    fn from(e: c6p_handshake::HandshakeError) -> Self {
        match e {
            c6p_handshake::HandshakeError::InvalidBundle(_) => {
                C6pError::HandshakeFailed(e.to_string())
            }
            c6p_handshake::HandshakeError::InvalidSpkSignature => {
                C6pError::InvalidSignature(e.to_string())
            }
            c6p_handshake::HandshakeError::InvalidOfferSignature => {
                C6pError::InvalidSignature(e.to_string())
            }
            c6p_handshake::HandshakeError::TranscriptMismatch => {
                C6pError::HandshakeFailed(e.to_string())
            }
            c6p_handshake::HandshakeError::KcVerificationFailed(_) => {
                C6pError::HandshakeFailed(e.to_string())
            }
            c6p_handshake::HandshakeError::InvalidWireFormat(_) => {
                C6pError::HandshakeFailed(e.to_string())
            }
            c6p_handshake::HandshakeError::CryptoError(_) => C6pError::CryptoError(e.to_string()),
            c6p_handshake::HandshakeError::StateError(_) => {
                C6pError::HandshakeFailed(e.to_string())
            }
        }
    }
}

impl From<c6p_sessions::SessionError> for C6pError {
    fn from(e: c6p_sessions::SessionError) -> Self {
        match e {
            c6p_sessions::SessionError::ReplayDetected(_) => {
                C6pError::ReplayDetected(e.to_string())
            }
            c6p_sessions::SessionError::CounterExhausted => C6pError::CounterExhausted,
            c6p_sessions::SessionError::DecryptionFailed(_) => {
                C6pError::DecryptionFailed(e.to_string())
            }
            _ => C6pError::SessionError(e.to_string()),
        }
    }
}

impl From<hex::FromHexError> for C6pError {
    fn from(e: hex::FromHexError) -> Self {
        C6pError::SerializationError(format!("Hex error: {}", e))
    }
}

/// Result type for iOS bridge operations
pub type Result<T> = std::result::Result<T, C6pError>;
