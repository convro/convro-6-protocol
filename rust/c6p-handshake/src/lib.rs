//! IslandAccord v1 - Authenticated Prekey Handshake
//!
//! Production-grade implementation of the IslandAccord v1 protocol for C6P.
//! Provides forward secrecy, future secrecy, and mutual authentication.
//!
//! **CRITICAL:** This implementation is normative and MUST match docs/handshake/ specification.
//!
//! # Protocol Overview
//!
//! IslandAccord v1 is a 3DH or 4DH authenticated handshake protocol:
//!
//! ## 3DH Handshake (without OTP):
//! ```text
//! DH1 = DH(I_eph, R_spk)    // Initiator ephemeral × Responder SPK
//! DH2 = DH(I_id, R_spk)     // Initiator identity × Responder SPK
//! DH3 = DH(I_eph, R_id)     // Initiator ephemeral × Responder identity
//! IKM = DH1 || DH2 || DH3   // 96 bytes
//! ```
//!
//! ## 4DH Handshake (with OTP):
//! ```text
//! DH1 = DH(I_eph, R_spk)    // Initiator ephemeral × Responder SPK
//! DH2 = DH(I_id, R_spk)     // Initiator identity × Responder SPK
//! DH3 = DH(I_eph, R_id)     // Initiator ephemeral × Responder identity
//! DH4 = DH(I_eph, R_otp)    // Initiator ephemeral × Responder OTP
//! IKM = DH1 || DH2 || DH3 || DH4  // 128 bytes
//! ```
//!
//! # Key Confirmation
//!
//! Both parties compute and exchange KC (Key Confirmation) tags:
//! - Initiator sends KC1 in offer
//! - Responder verifies KC1, sends KC2 in accept
//! - Initiator verifies KC2
//!
//! This provides cryptographic proof of agreement on session keys.
//!
//! # Specification Reference
//!
//! See docs/handshake/ for complete protocol specification:
//! - island-accord-crypto.md: Cryptographic construction
//! - island-accord-wire.md: Wire format
//! - island-accord-state-machine.md: Protocol flow

#![forbid(unsafe_code)]
#![warn(missing_docs, rust_2018_idioms)]

pub mod types;
pub mod bundle;
pub mod offer;
pub mod accept;
pub mod error;
pub mod crypto;

pub use types::*;
pub use bundle::*;
pub use offer::*;
pub use accept::*;
pub use error::*;
pub use crypto::*;
