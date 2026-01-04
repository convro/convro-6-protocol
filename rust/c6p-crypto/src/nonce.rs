//! C6P Deterministic Nonce Derivation (v1) - NORMATIVE
//!
//! Implements docs/crypto/c6p-key-schedule.md §8 and docs/crypto/c6p-nonce-policy.md
//!
//! **CRITICAL:** Nonces are deterministic and MUST bind to all context.
//! No randomness is used (safety proven by per-message keys + counter uniqueness).

use crate::constants::*;
use crate::primitives::*;
use crate::types::*;

/// Derive deterministic nonce for AEAD
///
/// Implements c6p-key-schedule.md §8 (Deterministic Nonce Derivation)
///
/// # Arguments
/// * `mk_material` - Message key material from per-message derivation (32 bytes)
/// * `session_binding` - Session binding (32 bytes)
/// * `suite_id` - AEAD suite ID
/// * `message_type` - Message type
/// * `stream_id` - Stream ID
/// * `session_id` - Session ID
/// * `counter` - Message counter (u64)
///
/// # Returns
/// * Nonce bytes (length depends on suite)
///   - ChaCha20-Poly1305: 12 bytes
///   - XChaCha20-Poly1305: 24 bytes
///   - AEGIS-128L: 16 bytes
///
/// # Specification Reference
/// See docs/crypto/c6p-key-schedule.md §8.2-8.5
///
/// **CRITICAL:** Nonce derivation MUST use session_binding as HKDF salt.
pub fn derive_nonce(
    mk_material: &MkMaterial,
    session_binding: &SessionBinding,
    suite_id: u16,
    message_type: u8,
    stream_id: u8,
    session_id: &SessionId,
    counter: u64,
) -> Vec<u8> {
    // §8.2: Nonce PRK
    // prk_nonce = HKDF-Extract(salt = session_binding, ikm = mk_material)
    let prk_nonce = hkdf_extract(&session_binding.0, &mk_material.0);

    // §8.3: Nonce info block (byte-exact)
    // nonce_info = "C6P_NONCE_V1" || U8(0x01) || U8(suite_id) || U8(message_type) ||
    //              U8(stream_id) || session_id(8) || BE64(counter)
    let mut nonce_info = Vec::with_capacity(LABEL_NONCE.len() + 1 + 1 + 1 + 1 + 8 + 8);
    nonce_info.extend_from_slice(LABEL_NONCE); // "C6P_NONCE_V1"
    nonce_info.push(0x01); // Version
    nonce_info.push((suite_id & 0xFF) as u8); // Suite ID (low byte)
    nonce_info.push(message_type);
    nonce_info.push(stream_id);
    nonce_info.extend_from_slice(&session_id.0); // 8 bytes
    nonce_info.extend_from_slice(&be64(counter)); // 8 bytes

    // §8.4: Nonce length per suite
    let nonce_len = match suite_id {
        SUITE_CHACHA20_POLY1305 => NONCE_LEN_CHACHA20,
        SUITE_XCHACHA20_POLY1305 => NONCE_LEN_XCHACHA20,
        SUITE_AEGIS_128L => NONCE_LEN_AEGIS,
        _ => panic!("Unknown suite_id: 0x{:04x} (MUST fail-closed)", suite_id),
    };

    // §8.5: Nonce output
    // nonce = HKDF-Expand(prk_nonce, info = nonce_info, L = nonce_len)
    hkdf_expand(&prk_nonce, &nonce_info, nonce_len)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_nonce_chacha20() {
        let mk_material = MkMaterial([0x42u8; 32]);
        let session_binding = SessionBinding([0x11u8; 32]);
        let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        assert_eq!(nonce.len(), NONCE_LEN_CHACHA20);

        // Different counter should produce different nonce
        let nonce2 = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            1,
        );
        assert_ne!(nonce, nonce2);

        // Same inputs should produce same nonce (deterministic)
        let nonce3 = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );
        assert_eq!(nonce, nonce3);
    }

    #[test]
    fn test_derive_nonce_xchacha20() {
        let mk_material = MkMaterial([0x42u8; 32]);
        let session_binding = SessionBinding([0x11u8; 32]);
        let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_XCHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        assert_eq!(nonce.len(), NONCE_LEN_XCHACHA20);
    }

    #[test]
    #[should_panic(expected = "Unknown suite_id")]
    fn test_derive_nonce_unknown_suite() {
        let mk_material = MkMaterial([0x42u8; 32]);
        let session_binding = SessionBinding([0x11u8; 32]);
        let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        // Should panic (fail-closed) for unknown suite
        derive_nonce(
            &mk_material,
            &session_binding,
            0x9999, // Invalid suite
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );
    }
}
