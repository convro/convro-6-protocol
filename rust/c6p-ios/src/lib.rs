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

// UniFFI generates #[no_mangle] which triggers unsafe_code lint - allow it
#![allow(unsafe_code)]
// UniFFI generated code has empty lines after doc comments - allow it
#![allow(clippy::empty_line_after_doc_comments)]
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

// ============================================================================
// UNIFFI WRAPPER FUNCTIONS (matching UDL naming convention)
// ============================================================================

// Identity functions with identity_ prefix
pub use identity::generate_identity as identity_generate_identity;
pub use identity::generate_signed_prekey as identity_generate_signed_prekey;
pub use identity::generate_one_time_prekey as identity_generate_one_time_prekey;
pub use identity::compute_device_id as identity_compute_device_id;
pub use identity::compute_fingerprint as identity_compute_fingerprint;
pub use identity::validate_bundle as identity_validate_bundle;

// Handshake functions with handshake_ prefix - need wrappers for return type
/// Initiator: Create handshake offer
pub fn handshake_create_offer(
    initiator_identity: DeviceIdentity,
    responder_bundle: PrekeyBundle,
) -> Result<CreateOfferResult> {
    let (offer, session_keys) = handshake::create_offer(initiator_identity, responder_bundle)?;
    Ok(CreateOfferResult {
        offer,
        session_keys,
    })
}

/// Responder: Accept handshake offer
pub fn handshake_accept_offer(
    responder_identity: DeviceIdentity,
    responder_spk: SignedPrekey,
    responder_otp: Option<OneTimePrekey>,
    offer_bytes: Vec<u8>,
) -> Result<AcceptOfferResult> {
    let (accept, session_keys) =
        handshake::accept_offer(responder_identity, responder_spk, responder_otp, offer_bytes)?;
    Ok(AcceptOfferResult {
        accept,
        session_keys,
    })
}

/// Initiator: Verify accept message
pub use handshake::verify_accept as handshake_verify_accept;

// Utility functions with utils_ prefix
pub use utils::bytes_to_hex as utils_bytes_to_hex;
pub use utils::hex_to_bytes as utils_hex_to_bytes;
pub use utils::random_bytes as utils_random_bytes;

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
