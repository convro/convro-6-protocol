//! Error types for session operations

use thiserror::Error;

/// Session operation errors
#[derive(Debug, Error)]
pub enum SessionError {
    /// Replay attack detected
    #[error("Replay attack detected: counter {0} already used")]
    ReplayDetected(u64),

    /// Counter exhaustion
    #[error("Counter exhausted: reached 2^64-1")]
    CounterExhausted,

    /// Message encryption failed
    #[error("Message encryption failed: {0}")]
    EncryptionFailed(String),

    /// Message decryption failed
    #[error("Message decryption failed: {0}")]
    DecryptionFailed(String),

    /// Invalid message format
    #[error("Invalid message format: {0}")]
    InvalidFormat(String),

    /// Session state error
    #[error("Session state error: {0}")]
    StateError(String),

    /// Skip-window overflow
    #[error("Skip-window overflow: gap too large ({0} > max)")]
    SkipWindowOverflow(u64),
}

/// Result type for session operations
pub type Result<T> = std::result::Result<T, SessionError>;
