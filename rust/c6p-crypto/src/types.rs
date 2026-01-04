//! C6P Core Types (Normative)
//!
//! Fixed-size types as defined in docs/crypto/c6p-key-schedule.md §1

use crate::constants::*;
use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

// ============================================================================
// Session Identifiers
// ============================================================================

/// Session ID (8 bytes)
#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct SessionId(pub [u8; SESSION_ID_LEN]);

impl std::fmt::Debug for SessionId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "SessionId({})", hex::encode(self.0))
    }
}

/// Device ID (16 bytes)
#[derive(Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub struct DeviceId(pub [u8; DEVICE_ID_LEN]);

impl std::fmt::Debug for DeviceId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "DeviceId({})", hex::encode(self.0))
    }
}

// ============================================================================
// Cryptographic Keys (Zeroized on Drop)
// ============================================================================

/// Root Key (32 bytes) - MUST be zeroized
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct RootKey(pub [u8; ROOT_KEY_LEN]);

impl std::fmt::Debug for RootKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "RootKey([REDACTED])")
    }
}

/// Chain Key (32 bytes) - MUST be zeroized
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct ChainKey(pub [u8; CHAIN_KEY_LEN]);

impl std::fmt::Debug for ChainKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ChainKey([REDACTED])")
    }
}

/// Message Key Material (32 bytes) - MUST be zeroized
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct MkMaterial(pub [u8; MK_MATERIAL_LEN]);

impl std::fmt::Debug for MkMaterial {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "MkMaterial([REDACTED])")
    }
}

/// Key Confirmation Key (32 bytes) - MUST be zeroized
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct KcKey(pub [u8; KC_KEY_LEN]);

impl std::fmt::Debug for KcKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "KcKey([REDACTED])")
    }
}

// ============================================================================
// Context Types
// ============================================================================

/// Canonical session context (CTX = session_id || initiator_device_id || responder_device_id)
/// Total: 40 bytes (8 + 16 + 16)
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionContext {
    /// Session ID (8 bytes)
    pub session_id: SessionId,
    /// Initiator device ID (16 bytes)
    pub initiator_device_id: DeviceId,
    /// Responder device ID (16 bytes)
    pub responder_device_id: DeviceId,
}

impl SessionContext {
    /// Construct canonical CTX bytes (40 bytes)
    pub fn to_bytes(&self) -> [u8; 40] {
        let mut ctx = [0u8; 40];
        ctx[0..8].copy_from_slice(&self.session_id.0);
        ctx[8..24].copy_from_slice(&self.initiator_device_id.0);
        ctx[24..40].copy_from_slice(&self.responder_device_id.0);
        ctx
    }
}

impl std::fmt::Debug for SessionContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("SessionContext")
            .field("session_id", &self.session_id)
            .field("initiator_device_id", &self.initiator_device_id)
            .field("responder_device_id", &self.responder_device_id)
            .finish()
    }
}

/// Per-stream context (STREAM_CTX = stream_id || message_type || suite_id)
/// Total: 3 bytes
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct StreamContext {
    /// Stream ID (0x01 i2r, 0x02 r2i)
    pub stream_id: u8,
    /// Message type (0x01 dm, 0x02 group, 0x03 channel, 0x10 control)
    pub message_type: u8,
    /// Suite ID (0x01 ChaCha20-Poly1305, etc.)
    pub suite_id: u16,
}

impl StreamContext {
    /// Construct canonical STREAM_CTX bytes (3 bytes)
    pub fn to_bytes(&self) -> [u8; 3] {
        [
            self.stream_id,
            self.message_type,
            (self.suite_id >> 8) as u8, // Big-endian high byte (suite_id is u16 but spec uses u8 in STREAM_CTX)
        ]
    }
}

impl std::fmt::Debug for StreamContext {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("StreamContext")
            .field("stream_id", &format_args!("0x{:02x}", self.stream_id))
            .field("message_type", &format_args!("0x{:02x}", self.message_type))
            .field("suite_id", &format_args!("0x{:04x}", self.suite_id))
            .finish()
    }
}

/// Session binding (SHA-256 hash, 32 bytes)
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SessionBinding(pub [u8; SESSION_BINDING_LEN]);

impl std::fmt::Debug for SessionBinding {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "SessionBinding({})", hex::encode(self.0))
    }
}

/// Transcript hash (SHA-256, 32 bytes)
#[derive(Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct TranscriptHash(pub [u8; TRANSCRIPT_HASH_LEN]);

impl std::fmt::Debug for TranscriptHash {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "TranscriptHash({})", hex::encode(self.0))
    }
}

// ============================================================================
// Helper Functions
// ============================================================================

/// Convert u64 counter to big-endian bytes (BE64)
#[inline]
pub fn be64(counter: u64) -> [u8; 8] {
    counter.to_be_bytes()
}

/// Convert u8 to single byte (U8)
#[inline]
pub fn u8_byte(x: u8) -> [u8; 1] {
    [x]
}
