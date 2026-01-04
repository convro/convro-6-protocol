//! Core types for IslandAccord v1 handshake
//!
//! All types are normative and MUST match wire format specification.

use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

// Re-export from c6p-crypto
pub use c6p_crypto::{DeviceId, SessionId, TranscriptHash};

/// Signed Prekey ID (4 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct SpkId(pub [u8; 4]);

/// One-Time Prekey ID (4 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct OtpId(pub [u8; 4]);

/// X25519 public key (32 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct X25519PublicKey(pub [u8; 32]);

/// X25519 private key (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct X25519PrivateKey(pub [u8; 32]);

/// Ed25519 public key (32 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ed25519PublicKey(pub [u8; 32]);

/// Ed25519 private key (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct Ed25519PrivateKey(pub [u8; 32]);

/// Ed25519 signature (64 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Ed25519Signature(pub [u8; 64]);

/// DH shared secret (32 bytes) - zeroized on drop
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct DhSecret(pub [u8; 32]);
