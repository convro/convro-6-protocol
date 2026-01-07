//! C6P Identity Management
//!
//! Production-grade identity operations for Convro 6 Protocol.
//! Handles device IDs, fingerprints, and identity proofs.
//!
//! **CRITICAL:** This implementation is normative and MUST match docs/identity/ specification.
//!
//! # Device IDs
//!
//! Device IDs are derived from Ed25519 identity public keys:
//! ```text
//! device_id = SHA-256("C6P_DEVICE_ID_V1" || ed25519_public_key)[0..16]
//! ```
//!
//! # Fingerprints
//!
//! Human-readable fingerprints for identity verification:
//! ```text
//! fingerprint_hash = SHA-256("C6P_FINGERPRINT_V1" || ed25519_public_key)
//! fingerprint = Base32(fingerprint_hash[0..20])
//! ```
//!
//! # Specification Reference
//!
//! See docs/identity/ for complete specification

#![forbid(unsafe_code)]
#![warn(missing_docs, rust_2018_idioms)]

pub mod device_id;
pub mod error;
pub mod fingerprint;

pub use device_id::*;
pub use error::*;
pub use fingerprint::*;
