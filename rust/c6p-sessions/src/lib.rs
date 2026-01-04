//! C6P Session Management
//!
//! Production-grade session ratcheting and replay protection for Convro 6 Protocol.
//! Implements symmetric ratcheting with skip-window for out-of-order messages.
//!
//! **CRITICAL:** This implementation is normative and MUST match docs/sessions/ specification.
//!
//! # Symmetric Ratcheting
//!
//! Each message advances the chain key:
//! ```text
//! (mk_material_N, chain_key_N+1) = DerivePerMessage(chain_key_N, counter_N, ctx, transcript, stream_ctx)
//! ```
//!
//! # Replay Protection
//!
//! Uses sliding skip-window to detect:
//! - Replay attacks (duplicate counter)
//! - Out-of-order delivery (gaps in counter sequence)
//! - Counter exhaustion (2^64-1 limit)
//!
//! # Message Encryption
//!
//! Per-message encryption uses:
//! - Deterministic nonce (derived from mk_material + session_binding + counter)
//! - AAD (session_id || stream_id || message_type || counter || payload_len)
//! - AEAD (ChaCha20-Poly1305 or XChaCha20-Poly1305)
//!
//! # Specification Reference
//!
//! See docs/sessions/ for complete specification:
//! - c6p-sessions-ratchet.md: Ratcheting logic
//! - c6p-sessions-replay.md: Replay protection
//! - c6p-sessions-state.md: State management

#![forbid(unsafe_code)]
#![warn(missing_docs, rust_2018_idioms)]

pub mod ratchet;
pub mod replay;
pub mod state;
pub mod error;

pub use ratchet::*;
pub use replay::*;
pub use state::*;
pub use error::*;
