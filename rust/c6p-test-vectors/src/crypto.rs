//! Crypto Test Vector Generation
//!
//! Generates deterministic test vectors for C6P crypto module.

use anyhow::Result;
use c6p_crypto::*;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

// ============================================================================
// Common Types
// ============================================================================

#[derive(Serialize, Deserialize)]
struct TestVectorFile<T> {
    version: String,
    suite: String,
    module: String,
    generated_by: String,
    generated_at: String,
    description: String,
    vectors: Vec<T>,
}

// ============================================================================
// Key Schedule Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct KeyScheduleVector {
    case_id: String,
    description: String,
    inputs: KeyScheduleInputs,
    #[serde(skip_serializing_if = "Option::is_none")]
    intermediate: Option<KeyScheduleIntermediate>,
    outputs: KeyScheduleOutputs,
}

#[derive(Serialize, Deserialize)]
struct KeyScheduleInputs {
    ikm_hex: String,
    ikm_len: usize,
    transcript_hash_b64u: String,
    session_id_hex: String,
    initiator_device_id_hex: String,
    responder_device_id_hex: String,
    suite_id: u16,
}

#[derive(Serialize, Deserialize)]
struct KeyScheduleIntermediate {
    ctx_hex: String,
    salt_root_hex: String,
    prk_root_hex: String,
    salt_chain_hex: String,
    prk_chain_hex: String,
}

#[derive(Serialize, Deserialize)]
struct KeyScheduleOutputs {
    root_key_b64u: String,
    kc_key_b64u: String,
    ck_i2r_b64u: String,
    ck_r2i_b64u: String,
}

fn generate_key_schedule_vectors() -> Result<Vec<KeyScheduleVector>> {
    let mut vectors = Vec::new();

    // Vector ROOT_001: 3DH (no OTP) - 96 bytes IKM
    {
        let ikm = [0x42u8; 96];
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let (root_key, kc_key) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);

        let stream_ctx_i2r = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };
        let stream_ctx_r2i = StreamContext {
            stream_id: STREAM_R2I,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let ck_i2r = derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_i2r);
        let ck_r2i = derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_r2i);

        vectors.push(KeyScheduleVector {
            case_id: "ROOT_001".to_string(),
            description: "3DH root derivation (no OTP, 96-byte IKM)".to_string(),
            inputs: KeyScheduleInputs {
                ikm_hex: hex::encode(&ikm),
                ikm_len: ikm.len(),
                transcript_hash_b64u: base64_url(&transcript_hash.0),
                session_id_hex: hex::encode(&ctx.session_id.0),
                initiator_device_id_hex: hex::encode(&ctx.initiator_device_id.0),
                responder_device_id_hex: hex::encode(&ctx.responder_device_id.0),
                suite_id: SUITE_CHACHA20_POLY1305,
            },
            intermediate: None, // Can add if needed for debugging
            outputs: KeyScheduleOutputs {
                root_key_b64u: base64_url(&root_key.0),
                kc_key_b64u: base64_url(&kc_key.0),
                ck_i2r_b64u: base64_url(&ck_i2r.0),
                ck_r2i_b64u: base64_url(&ck_r2i.0),
            },
        });
    }

    // Vector ROOT_002: 4DH (with OTP) - 128 bytes IKM
    {
        let ikm = [0x88u8; 128];
        let transcript_hash = TranscriptHash([0x22u8; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
            initiator_device_id: DeviceId([0xCCu8; 16]),
            responder_device_id: DeviceId([0xDDu8; 16]),
        };

        let (root_key, kc_key) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);

        let stream_ctx_i2r = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };
        let stream_ctx_r2i = StreamContext {
            stream_id: STREAM_R2I,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let ck_i2r = derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_i2r);
        let ck_r2i = derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_r2i);

        vectors.push(KeyScheduleVector {
            case_id: "ROOT_002".to_string(),
            description: "4DH root derivation (with OTP, 128-byte IKM)".to_string(),
            inputs: KeyScheduleInputs {
                ikm_hex: hex::encode(&ikm),
                ikm_len: ikm.len(),
                transcript_hash_b64u: base64_url(&transcript_hash.0),
                session_id_hex: hex::encode(&ctx.session_id.0),
                initiator_device_id_hex: hex::encode(&ctx.initiator_device_id.0),
                responder_device_id_hex: hex::encode(&ctx.responder_device_id.0),
                suite_id: SUITE_CHACHA20_POLY1305,
            },
            intermediate: None,
            outputs: KeyScheduleOutputs {
                root_key_b64u: base64_url(&root_key.0),
                kc_key_b64u: base64_url(&kc_key.0),
                ck_i2r_b64u: base64_url(&ck_i2r.0),
                ck_r2i_b64u: base64_url(&ck_r2i.0),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Nonce Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct NonceVector {
    case_id: String,
    description: String,
    inputs: NonceInputs,
    outputs: NonceOutputs,
}

#[derive(Serialize, Deserialize)]
struct NonceInputs {
    mk_material_b64u: String,
    session_binding_b64u: String,
    suite_id: u16,
    suite_name: String,
    message_type: u8,
    stream_id: u8,
    session_id_hex: String,
    counter: u64,
}

#[derive(Serialize, Deserialize)]
struct NonceOutputs {
    nonce_hex: String,
    nonce_len: usize,
}

fn generate_nonce_vectors() -> Result<Vec<NonceVector>> {
    let mut vectors = Vec::new();

    let mk_material = MkMaterial([0x42u8; 32]);
    let session_binding = SessionBinding([0x11u8; 32]);
    let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

    // NONCE_001: ChaCha20-Poly1305 (12 bytes)
    {
        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        vectors.push(NonceVector {
            case_id: "NONCE_001".to_string(),
            description: "ChaCha20-Poly1305 nonce (12 bytes, counter=0)".to_string(),
            inputs: NonceInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                suite_id: SUITE_CHACHA20_POLY1305,
                suite_name: "ChaCha20-Poly1305".to_string(),
                message_type: MSG_TYPE_DM,
                stream_id: STREAM_I2R,
                session_id_hex: hex::encode(&session_id.0),
                counter: 0,
            },
            outputs: NonceOutputs {
                nonce_hex: hex::encode(&nonce),
                nonce_len: nonce.len(),
            },
        });
    }

    // NONCE_002: XChaCha20-Poly1305 (24 bytes)
    {
        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_XCHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        vectors.push(NonceVector {
            case_id: "NONCE_002".to_string(),
            description: "XChaCha20-Poly1305 nonce (24 bytes, counter=0)".to_string(),
            inputs: NonceInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                suite_id: SUITE_XCHACHA20_POLY1305,
                suite_name: "XChaCha20-Poly1305".to_string(),
                message_type: MSG_TYPE_DM,
                stream_id: STREAM_I2R,
                session_id_hex: hex::encode(&session_id.0),
                counter: 0,
            },
            outputs: NonceOutputs {
                nonce_hex: hex::encode(&nonce),
                nonce_len: nonce.len(),
            },
        });
    }

    // NONCE_003: Counter boundary (2^32 - 1)
    {
        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0xFFFFFFFF,
        );

        vectors.push(NonceVector {
            case_id: "NONCE_003".to_string(),
            description: "Counter boundary test (counter=2^32-1)".to_string(),
            inputs: NonceInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                suite_id: SUITE_CHACHA20_POLY1305,
                suite_name: "ChaCha20-Poly1305".to_string(),
                message_type: MSG_TYPE_DM,
                stream_id: STREAM_I2R,
                session_id_hex: hex::encode(&session_id.0),
                counter: 0xFFFFFFFF,
            },
            outputs: NonceOutputs {
                nonce_hex: hex::encode(&nonce),
                nonce_len: nonce.len(),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// AAD Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct AadVector {
    case_id: String,
    description: String,
    inputs: AadInputs,
    outputs: AadOutputs,
}

#[derive(Serialize, Deserialize)]
struct AadInputs {
    session_id_hex: String,
    stream_id: u8,
    message_type: u8,
    counter: u64,
    payload_len: usize,
}

#[derive(Serialize, Deserialize)]
struct AadOutputs {
    aad_hex: String,
    aad_len: usize,
}

fn generate_aad_vectors() -> Result<Vec<AadVector>> {
    let mut vectors = Vec::new();

    let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

    // AAD_001: Basic DM message I2R
    {
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 0, 1024);

        vectors.push(AadVector {
            case_id: "AAD_001".to_string(),
            description: "AAD for DM message (I2R, counter=0, 1024 bytes)".to_string(),
            inputs: AadInputs {
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 0,
                payload_len: 1024,
            },
            outputs: AadOutputs {
                aad_hex: hex::encode(&aad),
                aad_len: aad.len(),
            },
        });
    }

    // AAD_002: R2I stream
    {
        let aad = construct_aad(&session_id, STREAM_R2I, MSG_TYPE_DM, 0, 512);

        vectors.push(AadVector {
            case_id: "AAD_002".to_string(),
            description: "AAD for DM message (R2I, counter=0, 512 bytes)".to_string(),
            inputs: AadInputs {
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_R2I,
                message_type: MSG_TYPE_DM,
                counter: 0,
                payload_len: 512,
            },
            outputs: AadOutputs {
                aad_hex: hex::encode(&aad),
                aad_len: aad.len(),
            },
        });
    }

    // AAD_003: High counter value
    {
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 0xFFFFFFFF, 2048);

        vectors.push(AadVector {
            case_id: "AAD_003".to_string(),
            description: "AAD with high counter (counter=2^32-1)".to_string(),
            inputs: AadInputs {
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 0xFFFFFFFF,
                payload_len: 2048,
            },
            outputs: AadOutputs {
                aad_hex: hex::encode(&aad),
                aad_len: aad.len(),
            },
        });
    }

    // AAD_004: Zero-length payload
    {
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 1, 0);

        vectors.push(AadVector {
            case_id: "AAD_004".to_string(),
            description: "AAD with zero-length payload".to_string(),
            inputs: AadInputs {
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 1,
                payload_len: 0,
            },
            outputs: AadOutputs {
                aad_hex: hex::encode(&aad),
                aad_len: aad.len(),
            },
        });
    }

    Ok(vectors)
}

/// Construct AAD for AEAD encryption
///
/// AAD format (24 bytes):
/// session_id(8) || stream_id(1) || message_type(1) || counter(8) || payload_len(6)
fn construct_aad(
    session_id: &SessionId,
    stream_id: u8,
    message_type: u8,
    counter: u64,
    payload_len: usize,
) -> Vec<u8> {
    let mut aad = Vec::with_capacity(24);
    aad.extend_from_slice(&session_id.0); // 8 bytes
    aad.push(stream_id); // 1 byte
    aad.push(message_type); // 1 byte
    aad.extend_from_slice(&be64(counter)); // 8 bytes
    aad.extend_from_slice(&be48(payload_len as u64)); // 6 bytes
    aad
}

/// Convert u64 to 6-byte big-endian (for payload length)
fn be48(value: u64) -> [u8; 6] {
    let bytes = value.to_be_bytes();
    [bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7]]
}

/// Convert u64 to 8-byte big-endian
fn be64(value: u64) -> [u8; 8] {
    value.to_be_bytes()
}

// ============================================================================
// AEAD Vectors (ChaCha20-Poly1305)
// ============================================================================

#[derive(Serialize, Deserialize)]
struct AeadVector {
    case_id: String,
    description: String,
    inputs: AeadInputs,
    outputs: AeadOutputs,
}

#[derive(Serialize, Deserialize)]
struct AeadInputs {
    mk_material_b64u: String,
    session_binding_b64u: String,
    session_id_hex: String,
    stream_id: u8,
    message_type: u8,
    counter: u64,
    plaintext_hex: String,
    plaintext_len: usize,
    aad_hex: String,
    suite_id: u16,
    suite_name: String,
}

#[derive(Serialize, Deserialize)]
struct AeadOutputs {
    nonce_hex: String,
    ciphertext_hex: String,
    ciphertext_len: usize,
}

fn generate_aead_chacha20_vectors() -> Result<Vec<AeadVector>> {
    let mut vectors = Vec::new();

    let mk_material = MkMaterial([0x42u8; 32]);
    let session_binding = SessionBinding([0x11u8; 32]);
    let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

    // AEAD_CHACHA20_001: Simple plaintext
    {
        let plaintext = b"Hello, C6P!";
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 0, plaintext.len());

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        // For test vectors, we use a deterministic key derivation
        // In production, mk_material would be used to derive the actual message key
        let message_key = derive_message_key(&mk_material);
        let ciphertext = encrypt_chacha20poly1305(&message_key, &nonce, &aad, plaintext)?;

        vectors.push(AeadVector {
            case_id: "AEAD_CHACHA20_001".to_string(),
            description: "ChaCha20-Poly1305 encryption of simple plaintext".to_string(),
            inputs: AeadInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 0,
                plaintext_hex: hex::encode(plaintext),
                plaintext_len: plaintext.len(),
                aad_hex: hex::encode(&aad),
                suite_id: SUITE_CHACHA20_POLY1305,
                suite_name: "ChaCha20-Poly1305".to_string(),
            },
            outputs: AeadOutputs {
                nonce_hex: hex::encode(&nonce),
                ciphertext_hex: hex::encode(&ciphertext),
                ciphertext_len: ciphertext.len(),
            },
        });
    }

    // AEAD_CHACHA20_002: Empty plaintext
    {
        let plaintext = b"";
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 1, plaintext.len());

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            1,
        );

        let message_key = derive_message_key(&mk_material);
        let ciphertext = encrypt_chacha20poly1305(&message_key, &nonce, &aad, plaintext)?;

        vectors.push(AeadVector {
            case_id: "AEAD_CHACHA20_002".to_string(),
            description: "ChaCha20-Poly1305 encryption of empty plaintext".to_string(),
            inputs: AeadInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 1,
                plaintext_hex: hex::encode(plaintext),
                plaintext_len: plaintext.len(),
                aad_hex: hex::encode(&aad),
                suite_id: SUITE_CHACHA20_POLY1305,
                suite_name: "ChaCha20-Poly1305".to_string(),
            },
            outputs: AeadOutputs {
                nonce_hex: hex::encode(&nonce),
                ciphertext_hex: hex::encode(&ciphertext),
                ciphertext_len: ciphertext.len(),
            },
        });
    }

    // AEAD_CHACHA20_003: Larger payload (1024 bytes)
    {
        let plaintext = vec![0x55u8; 1024];
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 2, plaintext.len());

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_CHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            2,
        );

        let message_key = derive_message_key(&mk_material);
        let ciphertext = encrypt_chacha20poly1305(&message_key, &nonce, &aad, &plaintext)?;

        vectors.push(AeadVector {
            case_id: "AEAD_CHACHA20_003".to_string(),
            description: "ChaCha20-Poly1305 encryption of 1024-byte payload".to_string(),
            inputs: AeadInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 2,
                plaintext_hex: hex::encode(&plaintext),
                plaintext_len: plaintext.len(),
                aad_hex: hex::encode(&aad),
                suite_id: SUITE_CHACHA20_POLY1305,
                suite_name: "ChaCha20-Poly1305".to_string(),
            },
            outputs: AeadOutputs {
                nonce_hex: hex::encode(&nonce),
                ciphertext_hex: hex::encode(&ciphertext),
                ciphertext_len: ciphertext.len(),
            },
        });
    }

    Ok(vectors)
}

fn generate_aead_xchacha20_vectors() -> Result<Vec<AeadVector>> {
    let mut vectors = Vec::new();

    let mk_material = MkMaterial([0x42u8; 32]);
    let session_binding = SessionBinding([0x11u8; 32]);
    let session_id = SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

    // AEAD_XCHACHA20_001: Simple plaintext
    {
        let plaintext = b"Hello, XChaCha20!";
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 0, plaintext.len());

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_XCHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            0,
        );

        let message_key = derive_message_key(&mk_material);
        let ciphertext = encrypt_xchacha20poly1305(&message_key, &nonce, &aad, plaintext)?;

        vectors.push(AeadVector {
            case_id: "AEAD_XCHACHA20_001".to_string(),
            description: "XChaCha20-Poly1305 encryption of simple plaintext".to_string(),
            inputs: AeadInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 0,
                plaintext_hex: hex::encode(plaintext),
                plaintext_len: plaintext.len(),
                aad_hex: hex::encode(&aad),
                suite_id: SUITE_XCHACHA20_POLY1305,
                suite_name: "XChaCha20-Poly1305".to_string(),
            },
            outputs: AeadOutputs {
                nonce_hex: hex::encode(&nonce),
                ciphertext_hex: hex::encode(&ciphertext),
                ciphertext_len: ciphertext.len(),
            },
        });
    }

    // AEAD_XCHACHA20_002: Empty plaintext
    {
        let plaintext = b"";
        let aad = construct_aad(&session_id, STREAM_I2R, MSG_TYPE_DM, 1, plaintext.len());

        let nonce = derive_nonce(
            &mk_material,
            &session_binding,
            SUITE_XCHACHA20_POLY1305,
            MSG_TYPE_DM,
            STREAM_I2R,
            &session_id,
            1,
        );

        let message_key = derive_message_key(&mk_material);
        let ciphertext = encrypt_xchacha20poly1305(&message_key, &nonce, &aad, plaintext)?;

        vectors.push(AeadVector {
            case_id: "AEAD_XCHACHA20_002".to_string(),
            description: "XChaCha20-Poly1305 encryption of empty plaintext".to_string(),
            inputs: AeadInputs {
                mk_material_b64u: base64_url(&mk_material.0),
                session_binding_b64u: base64_url(&session_binding.0),
                session_id_hex: hex::encode(&session_id.0),
                stream_id: STREAM_I2R,
                message_type: MSG_TYPE_DM,
                counter: 1,
                plaintext_hex: hex::encode(plaintext),
                plaintext_len: plaintext.len(),
                aad_hex: hex::encode(&aad),
                suite_id: SUITE_XCHACHA20_POLY1305,
                suite_name: "XChaCha20-Poly1305".to_string(),
            },
            outputs: AeadOutputs {
                nonce_hex: hex::encode(&nonce),
                ciphertext_hex: hex::encode(&ciphertext),
                ciphertext_len: ciphertext.len(),
            },
        });
    }

    Ok(vectors)
}

/// Derive message key from mk_material (for AEAD encryption)
///
/// In the spec, mk_material is used to derive the actual AEAD key.
/// For simplicity in test vectors, we use HKDF-Expand directly.
fn derive_message_key(mk_material: &MkMaterial) -> [u8; 32] {
    use c6p_crypto::primitives::hkdf_expand;
    let key_bytes = hkdf_expand(&mk_material.0, b"C6P_MSG_KEY_V1", 32);
    let mut key = [0u8; 32];
    key.copy_from_slice(&key_bytes);
    key
}

/// Encrypt with ChaCha20-Poly1305
fn encrypt_chacha20poly1305(
    key: &[u8; 32],
    nonce: &[u8],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    use chacha20poly1305::{
        aead::{Aead, KeyInit, Payload},
        ChaCha20Poly1305,
    };

    let cipher = ChaCha20Poly1305::new(key.into());
    let nonce_array: [u8; 12] = nonce.try_into()
        .map_err(|_| anyhow::anyhow!("Invalid nonce length for ChaCha20"))?;

    let payload = Payload {
        msg: plaintext,
        aad,
    };

    cipher.encrypt(&nonce_array.into(), payload)
        .map_err(|e| anyhow::anyhow!("ChaCha20-Poly1305 encryption failed: {}", e))
}

/// Encrypt with XChaCha20-Poly1305
fn encrypt_xchacha20poly1305(
    key: &[u8; 32],
    nonce: &[u8],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>> {
    use chacha20poly1305::{
        aead::{Aead, KeyInit, Payload},
        XChaCha20Poly1305,
    };

    let cipher = XChaCha20Poly1305::new(key.into());
    let nonce_array: [u8; 24] = nonce.try_into()
        .map_err(|_| anyhow::anyhow!("Invalid nonce length for XChaCha20"))?;

    let payload = Payload {
        msg: plaintext,
        aad,
    };

    cipher.encrypt(&nonce_array.into(), payload)
        .map_err(|e| anyhow::anyhow!("XChaCha20-Poly1305 encryption failed: {}", e))
}

// ============================================================================
// Helper Functions
// ============================================================================

fn base64_url(data: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(data)
}

fn write_json_file<T: Serialize>(
    path: &Path,
    data: &T,
    force: bool,
) -> Result<()> {
    if path.exists() && !force {
        anyhow::bail!("File already exists: {} (use --force to overwrite)", path.display());
    }

    let json = serde_json::to_string_pretty(data)?;
    fs::write(path, json)?;
    Ok(())
}

// ============================================================================
// Public API
// ============================================================================

pub fn generate_all(output_dir: &Path, verbose: bool, force: bool) -> Result<()> {
    fs::create_dir_all(output_dir)?;

    // Generate key_schedule_vectors.json
    {
        let vectors = generate_key_schedule_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            suite: "C6P_CRYPTO_V1".to_string(),
            module: "key_schedule".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Root key and chain key derivation test vectors".to_string(),
            vectors,
        };

        let path = output_dir.join("key_schedule_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate nonce_vectors.json
    {
        let vectors = generate_nonce_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            suite: "C6P_CRYPTO_V1".to_string(),
            module: "nonce".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Deterministic nonce derivation test vectors".to_string(),
            vectors,
        };

        let path = output_dir.join("nonce_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate aad_vectors.json
    {
        let vectors = generate_aad_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            suite: "C6P_CRYPTO_V1".to_string(),
            module: "aad".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Additional Authenticated Data (AAD) construction test vectors".to_string(),
            vectors,
        };

        let path = output_dir.join("aad_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate aead_vectors_chacha20poly1305.json
    {
        let vectors = generate_aead_chacha20_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            suite: "C6P_CRYPTO_V1".to_string(),
            module: "aead_chacha20poly1305".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "ChaCha20-Poly1305 AEAD encryption/decryption test vectors".to_string(),
            vectors,
        };

        let path = output_dir.join("aead_vectors_chacha20poly1305.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate aead_vectors_xchacha20poly1305.json
    {
        let vectors = generate_aead_xchacha20_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            suite: "C6P_CRYPTO_V1".to_string(),
            module: "aead_xchacha20poly1305".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "XChaCha20-Poly1305 AEAD encryption/decryption test vectors".to_string(),
            vectors,
        };

        let path = output_dir.join("aead_vectors_xchacha20poly1305.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    Ok(())
}
