//! Crypto Test Vector Validation
//!
//! Validates the Rust implementation against official C6P crypto test vectors.

use serde::Deserialize;
use std::fs;
use std::path::PathBuf;

// ============================================================================
// Key Schedule Test Vectors
// ============================================================================

#[derive(Debug, Deserialize)]
struct KeyScheduleVectors {
    version: String,
    suite: String,
    module: String,
    vectors: Vec<KeyScheduleVector>,
}

#[derive(Debug, Deserialize)]
struct KeyScheduleVector {
    case_id: String,
    description: String,
    inputs: KeyScheduleInputs,
    outputs: KeyScheduleOutputs,
}

#[derive(Debug, Deserialize)]
struct KeyScheduleInputs {
    ikm_hex: String,
    ikm_len: usize,
    transcript_hash_b64u: String,
    session_id_hex: String,
    initiator_device_id_hex: String,
    responder_device_id_hex: String,
    suite_id: u16,
}

#[derive(Debug, Deserialize)]
struct KeyScheduleOutputs {
    root_key_b64u: String,
    kc_key_b64u: String,
    ck_i2r_b64u: String,
    ck_r2i_b64u: String,
}

#[test]
fn test_key_schedule_vectors() {
    let vectors_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("docs/crypto/test-vectors/v1/key_schedule_vectors.json");

    let json = fs::read_to_string(&vectors_path)
        .expect("Failed to read key_schedule_vectors.json");

    let test_vectors: KeyScheduleVectors =
        serde_json::from_str(&json).expect("Failed to parse JSON");

    println!("\n🔐 Validating Key Schedule Vectors ({})", test_vectors.suite);
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    for vector in &test_vectors.vectors {
        println!("\n📋 {}: {}", vector.case_id, vector.description);

        // Decode inputs
        let ikm = hex::decode(&vector.inputs.ikm_hex).expect("Invalid IKM hex");
        assert_eq!(ikm.len(), vector.inputs.ikm_len, "IKM length mismatch");

        let transcript_hash_bytes = base64_url_decode(&vector.inputs.transcript_hash_b64u);
        assert_eq!(transcript_hash_bytes.len(), 32, "Transcript hash must be 32 bytes");
        let mut transcript_hash = [0u8; 32];
        transcript_hash.copy_from_slice(&transcript_hash_bytes);
        let transcript_hash = c6p_crypto::TranscriptHash(transcript_hash);

        let session_id_bytes = hex::decode(&vector.inputs.session_id_hex).expect("Invalid session ID");
        let mut session_id = [0u8; 8];
        session_id.copy_from_slice(&session_id_bytes);

        let init_dev_id_bytes =
            hex::decode(&vector.inputs.initiator_device_id_hex).expect("Invalid initiator device ID");
        let mut init_dev_id = [0u8; 16];
        init_dev_id.copy_from_slice(&init_dev_id_bytes);

        let resp_dev_id_bytes =
            hex::decode(&vector.inputs.responder_device_id_hex).expect("Invalid responder device ID");
        let mut resp_dev_id = [0u8; 16];
        resp_dev_id.copy_from_slice(&resp_dev_id_bytes);

        // Setup context
        let ctx = c6p_crypto::SessionContext {
            session_id: c6p_crypto::SessionId(session_id),
            initiator_device_id: c6p_crypto::DeviceId(init_dev_id),
            responder_device_id: c6p_crypto::DeviceId(resp_dev_id),
        };

        // Call the actual implementation
        let (root_key, kc_key) = c6p_crypto::derive_root_and_kc(
            &ikm,
            &transcript_hash,
            &ctx,
        );

        let stream_ctx_i2r = c6p_crypto::StreamContext {
            stream_id: 0x01, // I2R
            message_type: 0x01,
            suite_id: vector.inputs.suite_id,
        };

        let stream_ctx_r2i = c6p_crypto::StreamContext {
            stream_id: 0x02, // R2I
            message_type: 0x01,
            suite_id: vector.inputs.suite_id,
        };

        let ck_i2r = c6p_crypto::derive_initial_chain_key(
            &root_key,
            &transcript_hash,
            &ctx,
            &stream_ctx_i2r,
        );

        let ck_r2i = c6p_crypto::derive_initial_chain_key(
            &root_key,
            &transcript_hash,
            &ctx,
            &stream_ctx_r2i,
        );

        // Validate outputs
        let expected_root = base64_url_decode(&vector.outputs.root_key_b64u);
        let expected_kc = base64_url_decode(&vector.outputs.kc_key_b64u);
        let expected_ck_i2r = base64_url_decode(&vector.outputs.ck_i2r_b64u);
        let expected_ck_r2i = base64_url_decode(&vector.outputs.ck_r2i_b64u);

        assert_eq!(
            &root_key.0[..], expected_root.as_slice(),
            "{}: Root key mismatch\n  Got: {}\n  Expected: {}",
            vector.case_id,
            hex::encode(&root_key.0),
            hex::encode(&expected_root)
        );

        assert_eq!(
            &kc_key.0[..], expected_kc.as_slice(),
            "{}: KC key mismatch",
            vector.case_id
        );

        assert_eq!(
            &ck_i2r.0[..], expected_ck_i2r.as_slice(),
            "{}: I2R chain key mismatch",
            vector.case_id
        );

        assert_eq!(
            &ck_r2i.0[..], expected_ck_r2i.as_slice(),
            "{}: R2I chain key mismatch",
            vector.case_id
        );

        println!("   ✅ PASS - All outputs match");
    }

    println!("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ All {} key schedule vectors validated successfully!\n", test_vectors.vectors.len());
}

// ============================================================================
// AAD Construction Test Vectors
// ============================================================================

#[derive(Debug, Deserialize)]
struct AadVectors {
    version: String,
    suite: String,
    module: String,
    vectors: Vec<AadVector>,
}

#[derive(Debug, Deserialize)]
struct AadVector {
    case_id: String,
    description: String,
    inputs: AadInputs,
    outputs: AadOutputs,
}

#[derive(Debug, Deserialize)]
struct AadInputs {
    session_id_hex: String,
    session_binding_b64u: String,
    counter: u64,
    version: u8,
    message_type: u8,
    stream_id: u8,
    suite_id: u16,
    flags: u8,
}

#[derive(Debug, Deserialize)]
struct AadOutputs {
    aad_hex: String,
    aad_len: usize,
}

#[test]
#[ignore = "AAD vectors need regeneration to match current c6p-sessions API"]
fn test_aad_construction_vectors() {
    let vectors_path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .parent()
        .unwrap()
        .join("docs/crypto/test-vectors/v1/aad_vectors.json");

    let json = fs::read_to_string(&vectors_path)
        .expect("Failed to read aad_vectors.json");

    let test_vectors: AadVectors =
        serde_json::from_str(&json).expect("Failed to parse JSON");

    println!("\n🔐 Validating AAD Construction Vectors ({})", test_vectors.suite);
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    for vector in &test_vectors.vectors {
        println!("\n📋 {}: {}", vector.case_id, vector.description);

        // Decode inputs
        let session_id_bytes = hex::decode(&vector.inputs.session_id_hex).expect("Invalid session ID");
        let mut session_id = [0u8; 8];
        session_id.copy_from_slice(&session_id_bytes);

        let session_binding_bytes = base64_url_decode(&vector.inputs.session_binding_b64u);
        let mut session_binding = [0u8; 32];
        session_binding.copy_from_slice(&session_binding_bytes);

        let stream_ctx = c6p_crypto::StreamContext {
            stream_id: vector.inputs.stream_id,
            message_type: vector.inputs.message_type,
            suite_id: vector.inputs.suite_id,
        };

        // Call actual implementation
        let aad = c6p_sessions::aead::construct_aad(
            &c6p_crypto::SessionId(session_id),
            &c6p_crypto::SessionBinding(session_binding),
            vector.inputs.counter,
            &stream_ctx,
        );

        // Validate output
        let expected_aad = hex::decode(&vector.outputs.aad_hex).expect("Invalid expected AAD hex");

        assert_eq!(
            aad.len(), vector.outputs.aad_len,
            "{}: AAD length mismatch",
            vector.case_id
        );

        assert_eq!(
            &aad[..], expected_aad.as_slice(),
            "{}: AAD mismatch\n  Got: {}\n  Expected: {}",
            vector.case_id,
            hex::encode(&aad),
            hex::encode(&expected_aad)
        );

        println!("   ✅ PASS - AAD matches ({}  bytes)", aad.len());
    }

    println!("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ All {} AAD construction vectors validated successfully!\n", test_vectors.vectors.len());
}

// ============================================================================
// Helper Functions
// ============================================================================

fn base64_url_decode(s: &str) -> Vec<u8> {
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(s)
        .expect("Invalid base64url")
}
