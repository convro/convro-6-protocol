//! C6P iOS Bridge (UniFFI)
//!
//! This crate provides Swift/iOS bindings for the Convro 6 Protocol
//! using Mozilla's UniFFI framework. It exposes a clean, idiomatic
//! Swift API for:
//!
//! - Identity management (device IDs, fingerprints, keys)
//! - IslandAccord v1 handshake (offers, accepts, bundles)
//! - Session management (encrypt/decrypt, ratcheting)
//!
//! # Architecture
//!
//! This bridge wraps the core C6P Rust crates (c6p-crypto, c6p-identity,
//! c6p-handshake, c6p-sessions) with UniFFI-compatible types and functions.
//!
//! ## Design Principles
//!
//! 1. **Zero-copy where possible**: Use byte arrays for keys/IDs
//! 2. **Type safety**: Leverage Rust's type system, expose clean Swift API
//! 3. **Error handling**: Map Rust errors to Swift-friendly enums
//! 4. **Stateless functions**: Most operations are pure functions
//! 5. **Opaque state**: SessionState is opaque, managed by Swift
//!
//! # Building for iOS
//!
//! ```bash
//! # Build XCFramework
//! ./scripts/build-xcframework.sh
//! ```
//!
//! # Usage from Swift
//!
//! ```swift
//! import c6p_ios
//!
//! // Generate identity
//! let identity = try identity.generate_identity()
//!
//! // Create offer
//! let offer = try handshake.create_offer(
//!     initiator_identity: identity,
//!     responder_bundle: bundle
//! )
//!
//! // Encrypt message
//! let session = try SessionState(keys: keys, is_initiator: true)
//! let encrypted = try session.encrypt(plaintext: data)
//! ```

#![forbid(unsafe_code)]
#![warn(missing_docs, rust_2018_idioms)]

mod error;
mod handshake;
mod identity;
mod session;
mod types;
mod utils;

// Re-export public API
pub use error::*;
pub use handshake::*;
pub use identity::*;
pub use session::*;
pub use types::*;
pub use utils::*;

// UniFFI setup
uniffi::include_scaffolding!("c6p_ios");

/// Get C6P iOS bridge version
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_version() {
        let ver = version();
        assert!(!ver.is_empty());
        assert!(ver.starts_with("0."));
    }
}
