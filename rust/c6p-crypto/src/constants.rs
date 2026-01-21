//! C6P Protocol Constants (Normative)
//!
//! All constants defined in docs/crypto/c6p-crypto-registry.md

/// C6P Protocol Version (v1)
pub const C6P_VERSION: u8 = 0x01;

/// IslandAccord Handshake Version (v1)
pub const IA_VERSION: u8 = 0x01;

// ============================================================================
// KDF Domain Separation Labels (NORMATIVE - from c6p-key-schedule.md §3)
// ============================================================================

/// Root key derivation label
pub const LABEL_ROOT: &[u8] = b"C6P_ROOT_V1";

/// Chain key derivation label
pub const LABEL_CHAIN: &[u8] = b"C6P_CHAIN_V1";

/// Message key derivation label
pub const LABEL_MSG: &[u8] = b"C6P_MSG_V1";

/// Nonce derivation label
pub const LABEL_NONCE: &[u8] = b"C6P_NONCE_V1";

/// Key confirmation derivation label
pub const LABEL_KC: &[u8] = b"C6P_KC_V1";

/// Rekey derivation label (reserved)
pub const LABEL_REKEY: &[u8] = b"C6P_REKEY_V1";

/// Export key derivation label (reserved)
pub const LABEL_EXPORT: &[u8] = b"C6P_EXPORT_V1";

/// Session binding label
pub const LABEL_BIND: &[u8] = b"C6P_BIND_V1";

/// Prekey signature label
pub const LABEL_PREKEY: &[u8] = b"C6P_PREKEY_V1";

/// IslandAccord handshake transcript label
pub const LABEL_HANDSHAKE: &[u8] = b"ISLAND_ACCORD_V1";

/// Offer signature label
pub const LABEL_OFFER_SIG: &[u8] = b"IA_OFFER_SIG_V1";

// ============================================================================
// Stream IDs (Normative - from c6p-crypto-registry.md)
// ============================================================================

/// Initiator to Responder stream
pub const STREAM_I2R: u8 = 0x01;

/// Responder to Initiator stream
pub const STREAM_R2I: u8 = 0x02;

// ============================================================================
// Message Types (Normative - from c6p-crypto-registry.md)
// ============================================================================

/// Direct Message type
pub const MSG_TYPE_DM: u8 = 0x01;

/// Group Message type (future)
pub const MSG_TYPE_GROUP: u8 = 0x02;

/// Channel Message type (future)
pub const MSG_TYPE_CHANNEL: u8 = 0x03;

/// Control Message type
pub const MSG_TYPE_CONTROL: u8 = 0x10;

// ============================================================================
// Suite IDs (Normative - from c6p-crypto-registry.md)
// ============================================================================

/// ChaCha20-Poly1305 (default)
pub const SUITE_CHACHA20_POLY1305: u16 = 0x01;

/// XChaCha20-Poly1305
pub const SUITE_XCHACHA20_POLY1305: u16 = 0x02;

/// AEGIS-128L
pub const SUITE_AEGIS_128L: u16 = 0x03;

// ============================================================================
// Fixed Sizes (Normative - from c6p-key-schedule.md §1)
// ============================================================================

/// Session ID length (bytes)
pub const SESSION_ID_LEN: usize = 8;

/// Device ID length (bytes)
pub const DEVICE_ID_LEN: usize = 16;

/// Root key length (bytes)
pub const ROOT_KEY_LEN: usize = 32;

/// Chain key length (bytes)
pub const CHAIN_KEY_LEN: usize = 32;

/// Message key material length (bytes)
pub const MK_MATERIAL_LEN: usize = 32;

/// Key confirmation key length (bytes)
pub const KC_KEY_LEN: usize = 32;

/// Session binding length (bytes)
pub const SESSION_BINDING_LEN: usize = 32;

/// Transcript hash length (bytes)
pub const TRANSCRIPT_HASH_LEN: usize = 32;

/// X25519 public key length (bytes)
pub const X25519_PUBLIC_KEY_LEN: usize = 32;

/// Ed25519 public key length (bytes)
pub const ED25519_PUBLIC_KEY_LEN: usize = 32;

/// Ed25519 signature length (bytes)
pub const ED25519_SIGNATURE_LEN: usize = 64;

/// SHA-256 hash length (bytes)
pub const SHA256_HASH_LEN: usize = 32;

/// HMAC-SHA256 tag length (bytes)
pub const HMAC_SHA256_TAG_LEN: usize = 32;

// ============================================================================
// Nonce Lengths per Suite (Normative - from c6p-key-schedule.md §8.4)
// ============================================================================

/// ChaCha20-Poly1305 nonce length
pub const NONCE_LEN_CHACHA20: usize = 12;

/// XChaCha20-Poly1305 nonce length
pub const NONCE_LEN_XCHACHA20: usize = 24;

/// AEGIS-128L nonce length
pub const NONCE_LEN_AEGIS: usize = 16;

// ============================================================================
// AAD Length (Normative - from c6p-aead-and-aad.md)
// ============================================================================

/// Canonical AAD length (63 bytes)
pub const AAD_LEN: usize = 63;

// ============================================================================
// Skip Window (Normative - from c6p-replay-and-skip-window.md)
// ============================================================================

/// DM ratchet skip-window size (messages)
pub const SKIP_WINDOW_DM: u64 = 2048;
