//! C6P AEAD Integration (v1) - NORMATIVE
//!
//! Implements AEAD encryption/decryption for session messages.
//!
//! Normative references:
//! - docs/crypto/c6p-aead-and-aad.md (AAD construction, AEAD suites)
//! - docs/crypto/c6p-key-schedule.md §7-8 (suite key mapping, nonce derivation)
//!
//! **CRITICAL:** AAD is exactly 63 bytes in v1. Any deviation MUST fail.

use crate::error::{Result, SessionError};
use crate::types::MessageKeyMaterial;
use c6p_crypto::{
    compute_session_binding, derive_nonce, SessionBinding, SessionContext, SessionId,
    StreamContext, TranscriptHash, SUITE_AEGIS_128L, SUITE_CHACHA20_POLY1305,
    SUITE_XCHACHA20_POLY1305,
};
use chacha20poly1305::{
    aead::{Aead, KeyInit, Payload},
    ChaCha20Poly1305,
};

// ============================================================================
// Constants (Normative)
// ============================================================================

/// C6P protocol version (v1)
const C6P_VERSION: u8 = 0x01;

/// AAD label (10 bytes, ASCII "C6P_AAD_V1")
const AAD_LABEL: &[u8] = b"C6P_AAD_V1";

/// AAD flags (MUST be 0x00 in v1)
const AAD_FLAGS_V1: u8 = 0x00;

/// AAD length (v1)
/// Layout: label(10) + version(1) + message_type(1) + stream_id(1) +
///         suite_id(1) + flags(1) + session_id(8) + session_binding(32) + counter(8) = 63
const AAD_LEN_V1: usize = 63;

/// AEAD tag length (16 bytes for all supported suites)
const TAG_LEN: usize = 16;

// ============================================================================
// §7: Suite Key Mapping (Normative)
// ============================================================================

/// Map mk_material to suite-specific AEAD key
///
/// Implements c6p-key-schedule.md §7 (Per-Suite Key Material Mapping)
///
/// # Arguments
/// * `mk_material` - Message key material (32 bytes)
/// * `suite_id` - AEAD suite ID
///
/// # Returns
/// * Suite-specific key bytes (length depends on suite)
///
/// # Specification
/// - ChaCha20-Poly1305 (0x01): suite_key = mk_material[0..32] (32 bytes)
/// - XChaCha20-Poly1305 (0x02): suite_key = mk_material[0..32] (32 bytes)
/// - AEGIS-128L (0x03): Requires HKDF derivation to 16 bytes
///
/// # Panics
/// Fails closed on unknown suite_id (MUST NOT accept unknown suites)
pub fn map_to_suite_key(mk_material: &MessageKeyMaterial, suite_id: u16) -> Vec<u8> {
    match suite_id {
        SUITE_CHACHA20_POLY1305 => {
            // §7.1: ChaCha20-Poly1305 uses mk_material directly (32 bytes)
            mk_material.as_bytes().to_vec()
        }
        SUITE_XCHACHA20_POLY1305 => {
            // §7.2: XChaCha20-Poly1305 uses mk_material directly (32 bytes)
            mk_material.as_bytes().to_vec()
        }
        SUITE_AEGIS_128L => {
            // §7.3: AEGIS-128L requires HKDF to derive 16-byte key
            // aegis_prk = HKDF-Extract(salt = "C6P_AEAD_AEGIS_128L_V1", ikm = mk_material)
            // aegis_key = HKDF-Expand(aegis_prk, info = "C6P_AEAD_AEGIS_128L_V1" || 0x01, L = 16)
            use c6p_crypto::primitives::{hkdf_expand, hkdf_extract};

            const LABEL_AEGIS: &[u8] = b"C6P_AEAD_AEGIS_128L_V1";

            let aegis_prk = hkdf_extract(LABEL_AEGIS, mk_material.as_bytes());

            let mut aegis_info = Vec::with_capacity(LABEL_AEGIS.len() + 1);
            aegis_info.extend_from_slice(LABEL_AEGIS);
            aegis_info.push(0x01);

            hkdf_expand(&aegis_prk, &aegis_info, 16)
        }
        _ => panic!("Unknown suite_id: 0x{:04x} (MUST fail-closed)", suite_id),
    }
}

// ============================================================================
// §6: Canonical AAD Construction (Normative)
// ============================================================================

/// Construct canonical AAD (Additional Authenticated Data)
///
/// Implements c6p-aead-and-aad.md §6 (Canonical AAD Format)
///
/// # Arguments
/// * `session_id` - Session ID (8 bytes)
/// * `session_binding` - Session binding (32 bytes)
/// * `counter` - Message counter (u64)
/// * `stream_ctx` - Stream context (stream_id, message_type, suite_id)
///
/// # Returns
/// * Exactly 63 bytes of AAD
///
/// # AAD Layout (byte-exact)
/// ```text
/// AAD = "C6P_AAD_V1" (10)
///     || U8(version=0x01) (1)
///     || U8(message_type) (1)
///     || U8(stream_id) (1)
///     || U8(suite_id) (1)
///     || U8(aad_flags=0x00) (1)
///     || session_id (8)
///     || session_binding (32)
///     || BE64(counter) (8)
/// Total: 63 bytes
/// ```
///
/// # Hard Rules
/// - AAD MUST be exactly 63 bytes in v1
/// - aad_flags MUST be 0x00 in v1
/// - session_binding MUST be computed from canonical session state
pub fn construct_aad(
    session_id: &SessionId,
    session_binding: &SessionBinding,
    counter: u64,
    stream_ctx: &StreamContext,
) -> [u8; AAD_LEN_V1] {
    let mut aad = [0u8; AAD_LEN_V1];
    let mut offset = 0;

    // 1. AAD label (10 bytes)
    aad[offset..offset + AAD_LABEL.len()].copy_from_slice(AAD_LABEL);
    offset += AAD_LABEL.len();

    // 2. Version (1 byte)
    aad[offset] = C6P_VERSION;
    offset += 1;

    // 3. Message type (1 byte)
    aad[offset] = stream_ctx.message_type;
    offset += 1;

    // 4. Stream ID (1 byte)
    aad[offset] = stream_ctx.stream_id;
    offset += 1;

    // 5. Suite ID (1 byte) - low byte of u16
    aad[offset] = (stream_ctx.suite_id & 0xFF) as u8;
    offset += 1;

    // 6. AAD flags (1 byte) - MUST be 0x00 in v1
    aad[offset] = AAD_FLAGS_V1;
    offset += 1;

    // 7. Session ID (8 bytes)
    aad[offset..offset + 8].copy_from_slice(&session_id.0);
    offset += 8;

    // 8. Session binding (32 bytes)
    aad[offset..offset + 32].copy_from_slice(&session_binding.0);
    offset += 32;

    // 9. Counter (8 bytes, big-endian)
    aad[offset..offset + 8].copy_from_slice(&counter.to_be_bytes());
    offset += 8;

    // Invariant check: MUST be exactly 63 bytes
    debug_assert_eq!(
        offset, AAD_LEN_V1,
        "AAD construction MUST yield exactly 63 bytes"
    );

    aad
}

// ============================================================================
// §9-10: Encrypt and Decrypt (Normative)
// ============================================================================

/// Encrypt plaintext with AEAD
///
/// Implements c6p-aead-and-aad.md §9 (Encrypt)
///
/// # Arguments
/// * `plaintext` - Message plaintext
/// * `mk_material` - Message key material (32 bytes)
/// * `counter` - Message counter
/// * `ctx` - Session context
/// * `transcript_hash` - Transcript hash from handshake
/// * `stream_ctx` - Stream context
///
/// # Returns
/// * `Ok(sealed)` - Ciphertext || tag (total: plaintext.len + 16)
/// * `Err(SessionError)` - On encryption failure
///
/// # Steps (Normative)
/// 1. Compute session_binding from canonical session state
/// 2. Construct AAD (63 bytes)
/// 3. Map mk_material to suite_key
/// 4. Derive nonce deterministically
/// 5. AEAD seal: (ciphertext, tag) = AEAD_Seal(suite_key, nonce, aad, plaintext)
/// 6. Output sealed = ciphertext || tag
pub fn encrypt_message(
    plaintext: &[u8],
    mk_material: &MessageKeyMaterial,
    counter: u64,
    ctx: &SessionContext,
    _transcript_hash: &TranscriptHash,
    stream_ctx: &StreamContext,
) -> Result<Vec<u8>> {
    // Step 1: Compute session binding
    let session_binding = compute_session_binding(ctx);

    // Step 2: Construct canonical AAD
    let aad = construct_aad(&ctx.session_id, &session_binding, counter, stream_ctx);

    // Step 3: Map mk_material to suite-specific key
    let suite_key = map_to_suite_key(mk_material, stream_ctx.suite_id);

    // Step 4: Derive deterministic nonce
    let nonce = derive_nonce(
        &c6p_crypto::MkMaterial(*mk_material.as_bytes()),
        &session_binding,
        stream_ctx.suite_id,
        stream_ctx.message_type,
        stream_ctx.stream_id,
        &ctx.session_id,
        counter,
    );

    // Step 5: AEAD seal
    let sealed = match stream_ctx.suite_id {
        SUITE_CHACHA20_POLY1305 => {
            let cipher = ChaCha20Poly1305::new_from_slice(&suite_key)
                .map_err(|e| SessionError::EncryptionFailed(format!("Key init failed: {}", e)))?;

            let payload = Payload {
                msg: plaintext,
                aad: &aad,
            };

            cipher
                .encrypt(nonce.as_slice().into(), payload)
                .map_err(|e| SessionError::EncryptionFailed(format!("AEAD seal failed: {}", e)))?
        }
        SUITE_XCHACHA20_POLY1305 => {
            // TODO: Add XChaCha20-Poly1305 support when needed
            return Err(SessionError::InvalidFormat(
                "XChaCha20-Poly1305 not yet implemented".to_string(),
            ));
        }
        SUITE_AEGIS_128L => {
            // TODO: Add AEGIS-128L support when needed
            return Err(SessionError::InvalidFormat(
                "AEGIS-128L not yet implemented".to_string(),
            ));
        }
        _ => {
            return Err(SessionError::InvalidFormat(format!(
                "Unknown suite_id: 0x{:04x}",
                stream_ctx.suite_id
            )));
        }
    };

    Ok(sealed)
}

/// Decrypt ciphertext with AEAD
///
/// Implements c6p-aead-and-aad.md §10 (Decrypt)
///
/// # Arguments
/// * `sealed` - Ciphertext || tag (min length: 16 bytes)
/// * `mk_material` - Message key material (32 bytes)
/// * `counter` - Message counter
/// * `ctx` - Session context
/// * `transcript_hash` - Transcript hash from handshake
/// * `stream_ctx` - Stream context
///
/// # Returns
/// * `Ok(plaintext)` - Decrypted message
/// * `Err(SessionError)` - On decryption failure or validation failure
///
/// # Hard Rules
/// - sealed.len MUST be >= 16 (minimum: empty plaintext + 16-byte tag)
/// - AAD MUST be reconstructed from canonical session state
/// - On AEAD open failure: reject, do NOT advance state
pub fn decrypt_message(
    sealed: &[u8],
    mk_material: &MessageKeyMaterial,
    counter: u64,
    ctx: &SessionContext,
    _transcript_hash: &TranscriptHash,
    stream_ctx: &StreamContext,
) -> Result<Vec<u8>> {
    // Step 1: Structural validation
    if sealed.len() < TAG_LEN {
        return Err(SessionError::DecryptionFailed(format!(
            "Sealed length {} < minimum {}",
            sealed.len(),
            TAG_LEN
        )));
    }

    // Step 2: Compute session binding
    let session_binding = compute_session_binding(ctx);

    // Step 3: Reconstruct AAD
    let aad = construct_aad(&ctx.session_id, &session_binding, counter, stream_ctx);

    // Step 4: Map mk_material to suite-specific key
    let suite_key = map_to_suite_key(mk_material, stream_ctx.suite_id);

    // Step 5: Derive deterministic nonce
    let nonce = derive_nonce(
        &c6p_crypto::MkMaterial(*mk_material.as_bytes()),
        &session_binding,
        stream_ctx.suite_id,
        stream_ctx.message_type,
        stream_ctx.stream_id,
        &ctx.session_id,
        counter,
    );

    // Step 6: AEAD open
    let plaintext = match stream_ctx.suite_id {
        SUITE_CHACHA20_POLY1305 => {
            let cipher = ChaCha20Poly1305::new_from_slice(&suite_key)
                .map_err(|e| SessionError::DecryptionFailed(format!("Key init failed: {}", e)))?;

            let payload = Payload {
                msg: sealed,
                aad: &aad,
            };

            cipher
                .decrypt(nonce.as_slice().into(), payload)
                .map_err(|e| SessionError::DecryptionFailed(format!("AEAD open failed: {}", e)))?
        }
        SUITE_XCHACHA20_POLY1305 => {
            return Err(SessionError::DecryptionFailed(
                "XChaCha20-Poly1305 not yet implemented".to_string(),
            ));
        }
        SUITE_AEGIS_128L => {
            return Err(SessionError::DecryptionFailed(
                "AEGIS-128L not yet implemented".to_string(),
            ));
        }
        _ => {
            return Err(SessionError::DecryptionFailed(format!(
                "Unknown suite_id: 0x{:04x}",
                stream_ctx.suite_id
            )));
        }
    };

    Ok(plaintext)
}

#[cfg(test)]
mod tests {
    use super::*;
    use c6p_crypto::{DeviceId, SessionId};

    fn create_test_context() -> (SessionContext, TranscriptHash, StreamContext) {
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };

        let transcript_hash = TranscriptHash([0x42; 32]);

        let stream_ctx = StreamContext {
            stream_id: 0x01,    // I2R
            message_type: 0x01, // DM
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        (ctx, transcript_hash, stream_ctx)
    }

    #[test]
    fn test_map_to_suite_key_chacha20() {
        let mk_material = MessageKeyMaterial::from_bytes([0x42; 32]);

        let suite_key = map_to_suite_key(&mk_material, SUITE_CHACHA20_POLY1305);

        assert_eq!(suite_key.len(), 32);
        assert_eq!(suite_key, mk_material.as_bytes());
    }

    #[test]
    fn test_map_to_suite_key_aegis() {
        let mk_material = MessageKeyMaterial::from_bytes([0x42; 32]);

        let suite_key = map_to_suite_key(&mk_material, SUITE_AEGIS_128L);

        assert_eq!(suite_key.len(), 16); // AEGIS uses 16-byte key
    }

    #[test]
    #[should_panic(expected = "Unknown suite_id")]
    fn test_map_to_suite_key_unknown() {
        let mk_material = MessageKeyMaterial::from_bytes([0x42; 32]);

        // Should panic (fail-closed) for unknown suite
        map_to_suite_key(&mk_material, 0x9999);
    }

    #[test]
    fn test_construct_aad() {
        let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
        let session_binding = SessionBinding([0x11; 32]);
        let counter = 42u64;

        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let aad = construct_aad(&session_id, &session_binding, counter, &stream_ctx);

        // Verify length
        assert_eq!(aad.len(), AAD_LEN_V1);

        // Verify AAD label
        assert_eq!(&aad[0..10], AAD_LABEL);

        // Verify version
        assert_eq!(aad[10], C6P_VERSION);

        // Verify message_type, stream_id, suite_id
        assert_eq!(aad[11], stream_ctx.message_type);
        assert_eq!(aad[12], stream_ctx.stream_id);
        assert_eq!(aad[13], (stream_ctx.suite_id & 0xFF) as u8);

        // Verify flags
        assert_eq!(aad[14], AAD_FLAGS_V1);

        // Verify session_id
        assert_eq!(&aad[15..23], &session_id.0);

        // Verify session_binding
        assert_eq!(&aad[23..55], &session_binding.0);

        // Verify counter
        assert_eq!(&aad[55..63], &counter.to_be_bytes());
    }

    #[test]
    fn test_encrypt_decrypt_round_trip() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"Hello, C6P!";
        let counter = 0;

        // Encrypt
        let sealed = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Sealed should be plaintext.len + TAG_LEN
        assert_eq!(sealed.len(), plaintext.len() + TAG_LEN);

        // Decrypt
        let decrypted = decrypt_message(
            &sealed,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Should match original plaintext
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_encrypt_decrypt_empty_message() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"";
        let counter = 0;

        // Encrypt empty message
        let sealed = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Should be just the tag (16 bytes)
        assert_eq!(sealed.len(), TAG_LEN);

        // Decrypt
        let decrypted = decrypt_message(
            &sealed,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_decrypt_fails_with_wrong_key() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let wrong_mk_material = MessageKeyMaterial::from_bytes([0xAA; 32]);
        let plaintext = b"Hello, C6P!";
        let counter = 0;

        // Encrypt with correct key
        let sealed = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Try to decrypt with wrong key (should fail)
        let result = decrypt_message(
            &sealed,
            &wrong_mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::DecryptionFailed(_)
        ));
    }

    #[test]
    fn test_decrypt_fails_with_wrong_counter() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"Hello, C6P!";
        let counter = 0;

        // Encrypt with counter=0
        let sealed = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Try to decrypt with counter=1 (should fail - AAD mismatch)
        let result = decrypt_message(
            &sealed,
            &mk_material,
            1, // Wrong counter
            &ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::DecryptionFailed(_)
        ));
    }

    #[test]
    fn test_decrypt_fails_with_tampered_ciphertext() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"Hello, C6P!";
        let counter = 0;

        // Encrypt
        let mut sealed = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Tamper with ciphertext
        sealed[0] ^= 0x01;

        // Decrypt should fail (authentication failure)
        let result = decrypt_message(
            &sealed,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::DecryptionFailed(_)
        ));
    }

    #[test]
    fn test_decrypt_fails_with_short_sealed() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let counter = 0;

        // Try to decrypt with sealed.len < TAG_LEN
        let short_sealed = vec![0u8; 15]; // Less than 16 bytes

        let result = decrypt_message(
            &short_sealed,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::DecryptionFailed(_)
        ));
    }

    #[test]
    fn test_different_counters_produce_different_ciphertext() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"Hello, C6P!";

        // Encrypt with counter=0
        let sealed_0 = encrypt_message(
            plaintext,
            &mk_material,
            0,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Encrypt with counter=1
        let sealed_1 = encrypt_message(
            plaintext,
            &mk_material,
            1,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Different counters should produce different ciphertext (different nonce)
        assert_ne!(sealed_0, sealed_1);
    }

    #[test]
    fn test_deterministic_encryption() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let mk_material = MessageKeyMaterial::from_bytes([0x99; 32]);
        let plaintext = b"Hello, C6P!";
        let counter = 42;

        // Encrypt twice with same inputs
        let sealed_1 = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        let sealed_2 = encrypt_message(
            plaintext,
            &mk_material,
            counter,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Should produce identical output (deterministic nonce)
        assert_eq!(sealed_1, sealed_2);
    }
}
