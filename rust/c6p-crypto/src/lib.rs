//! C6P Crypto Core (v1)
//!
//! Production-grade cryptographic implementation for Convro 6 Protocol.
//! All derivations follow the normative specification in docs/crypto/c6p-key-schedule.md
//!
//! **CRITICAL:** KDF labels are normative and MUST NOT be changed.
//! Any deviation from c6p-key-schedule.md is a protocol violation.

#![forbid(unsafe_code)]
#![warn(missing_docs, rust_2018_idioms)]

pub mod constants;
pub mod key_schedule;
pub mod nonce;
pub mod primitives;
pub mod types;

pub use constants::*;
pub use key_schedule::*;
pub use nonce::*;
pub use primitives::*;
pub use types::*;
