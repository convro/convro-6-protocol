//! Core types for IslandAccord v1 handshake
//!
//! All types are normative and MUST match wire format specification.

use serde::{Deserialize, Serialize};
use std::fmt;
use zeroize::{Zeroize, ZeroizeOnDrop};

// Re-export from c6p-crypto
pub use c6p_crypto::{DeviceId, SessionId, TranscriptHash};

// ============================================================================
// Prekey IDs
// ============================================================================

/// Signed Prekey ID (8 bytes) - normative: island-accord-crypto.md §1.2
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpkId(pub [u8; 8]);

impl SpkId {
    /// Create from hex string (16 hex chars = 8 bytes)
    pub fn from_hex(hex: &str) -> Result<Self, hex::FromHexError> {
        let bytes = hex::decode(hex)?;
        if bytes.len() != 8 {
            return Err(hex::FromHexError::InvalidStringLength);
        }
        let mut arr = [0u8; 8];
        arr.copy_from_slice(&bytes);
        Ok(SpkId(arr))
    }

    /// Convert to hex string (lowercase)
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
}

impl fmt::Debug for SpkId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "SpkId({})", self.to_hex())
    }
}

/// One-Time Prekey ID (8 bytes) - normative: island-accord-crypto.md §1.2
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct OtpId(pub [u8; 8]);

impl OtpId {
    /// Create from hex string (16 hex chars = 8 bytes)
    pub fn from_hex(hex: &str) -> Result<Self, hex::FromHexError> {
        let bytes = hex::decode(hex)?;
        if bytes.len() != 8 {
            return Err(hex::FromHexError::InvalidStringLength);
        }
        let mut arr = [0u8; 8];
        arr.copy_from_slice(&bytes);
        Ok(OtpId(arr))
    }

    /// Convert to hex string (lowercase)
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }
}

impl fmt::Debug for OtpId {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "OtpId({})", self.to_hex())
    }
}

// ============================================================================
// X25519 Keys
// ============================================================================

/// X25519 public key (32 bytes)
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct X25519PublicKey(pub [u8; 32]);

impl X25519PublicKey {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        X25519PublicKey(bytes)
    }

    /// Get as bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for X25519PublicKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "X25519PublicKey({}...)", hex::encode(&self.0[0..4]))
    }
}

/// X25519 private key (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct X25519PrivateKey(pub [u8; 32]);

impl X25519PrivateKey {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        X25519PrivateKey(bytes)
    }

    /// Get as bytes (use with caution - exposes sensitive material)
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for X25519PrivateKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "X25519PrivateKey([REDACTED])")
    }
}

// ============================================================================
// Ed25519 Keys
// ============================================================================

/// Ed25519 public key (32 bytes)
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Ed25519PublicKey(pub [u8; 32]);

impl Ed25519PublicKey {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Ed25519PublicKey(bytes)
    }

    /// Get as bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for Ed25519PublicKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Ed25519PublicKey({}...)", hex::encode(&self.0[0..4]))
    }
}

/// Ed25519 private key (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Ed25519PrivateKey(pub [u8; 32]);

impl Ed25519PrivateKey {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        Ed25519PrivateKey(bytes)
    }

    /// Get as bytes (use with caution - exposes sensitive material)
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for Ed25519PrivateKey {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Ed25519PrivateKey([REDACTED])")
    }
}

/// Ed25519 signature (64 bytes)
#[derive(Clone, Copy, PartialEq, Eq)]
pub struct Ed25519Signature(pub [u8; 64]);

impl Ed25519Signature {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 64]) -> Self {
        Ed25519Signature(bytes)
    }

    /// Get as bytes
    pub fn as_bytes(&self) -> &[u8; 64] {
        &self.0
    }
}

impl fmt::Debug for Ed25519Signature {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "Ed25519Signature({}...)", hex::encode(&self.0[0..8]))
    }
}

// ============================================================================
// DH Secret
// ============================================================================

/// DH shared secret (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct DhSecret(pub [u8; 32]);

impl DhSecret {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        DhSecret(bytes)
    }

    /// Get as bytes (use with caution - exposes sensitive material)
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl fmt::Debug for DhSecret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "DhSecret([REDACTED])")
    }
}
