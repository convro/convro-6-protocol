//! Sessions Test Vector Generation
//!
//! Generates deterministic test vectors for C6P sessions module.
//! Covers ratcheting, out-of-order delivery, replay detection, and negative tests.

use anyhow::Result;
use c6p_crypto::{derive_nonce, MkMaterial, SessionBinding};
use c6p_crypto::{DeviceId, SessionContext, SessionId, StreamContext, TranscriptHash};
use c6p_crypto::{MSG_TYPE_DM, STREAM_I2R, STREAM_R2I, SUITE_CHACHA20_POLY1305};
use c6p_sessions::{
    construct_aad, map_to_suite_key, ratchet_step, ChainKey, Counter, SkipWindow, StreamDirection,
    StreamState,
};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::Path;

// ============================================================================
// Common Types
// ============================================================================

#[derive(Serialize, Deserialize)]
struct TestVectorFile<T> {
    version: String,
    module: String,
    generated_by: String,
    generated_at: String,
    description: String,
    vectors: Vec<T>,
}

// ============================================================================
// Ratchet Send Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct RatchetSendVector {
    case_id: String,
    description: String,
    inputs: RatchetSendInputs,
    crypto_steps: SendCryptoSteps,
    outputs: RatchetSendOutputs,
}

#[derive(Serialize, Deserialize)]
struct RatchetSendInputs {
    initial_chain_key_b64u: String,
    plaintext_b64u: String,
    session_id_hex: String,
    timon_device_id_hex: String,
    peter_device_id_hex: String,
    stream_id: u8,
    message_type: u8,
    suite_id: u16,
    counter: u64,
}

#[derive(Serialize, Deserialize)]
struct SendCryptoSteps {
    mk_material_b64u: String,
    suite_key_b64u: String,
    nonce_material_b64u: String,
    nonce_hex: String,
    aad_hex: String,
}

#[derive(Serialize, Deserialize)]
struct RatchetSendOutputs {
    ciphertext_b64u: String,
    ciphertext_len: usize,
    next_chain_key_b64u: String,
    counter_used: u64,
}

fn generate_ratchet_send_vectors() -> Result<Vec<RatchetSendVector>> {
    let mut vectors = Vec::new();

    // SEND_001: Basic send (counter=0)
    {
        let initial_ck = ChainKey([0x42u8; 32]);
        let plaintext = b"Hello from Timon!";

        let session_ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let transcript_hash = TranscriptHash([0x11u8; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, initial_ck.clone());

        let (counter, ciphertext) =
            sender.encrypt_and_send(plaintext, &session_ctx, &transcript_hash, &stream_ctx)?;

        // Get crypto steps (we'll derive them manually for the vector)
        let output = ratchet_step(
            &initial_ck,
            counter,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        );
        let mk_material = output.mk_material;
        let next_ck = output.next_chain_key;
        let suite_key = map_to_suite_key(&mk_material, stream_ctx.suite_id);
        let session_binding = SessionBinding(transcript_hash.0);
        let nonce = derive_nonce(
            &MkMaterial(*mk_material.as_bytes()),
            &session_binding,
            stream_ctx.suite_id,
            stream_ctx.message_type,
            stream_ctx.stream_id,
            &session_ctx.session_id,
            counter.value(),
        );
        let aad = construct_aad(
            &session_ctx.session_id,
            &session_binding,
            counter.value(),
            &stream_ctx,
        );

        vectors.push(RatchetSendVector {
            case_id: "SEND_001".to_string(),
            description: "Basic send: Timon → Peter (counter=0)".to_string(),
            inputs: RatchetSendInputs {
                initial_chain_key_b64u: base64_url(&initial_ck.0),
                plaintext_b64u: base64_url(plaintext),
                session_id_hex: hex::encode(session_ctx.session_id.0),
                timon_device_id_hex: hex::encode(session_ctx.initiator_device_id.0),
                peter_device_id_hex: hex::encode(session_ctx.responder_device_id.0),
                stream_id: stream_ctx.stream_id,
                message_type: stream_ctx.message_type,
                suite_id: stream_ctx.suite_id,
                counter: 0,
            },
            crypto_steps: SendCryptoSteps {
                mk_material_b64u: base64_url(mk_material.as_bytes()),
                suite_key_b64u: base64_url(&suite_key),
                nonce_material_b64u: base64_url(mk_material.as_bytes()), // Same for this suite
                nonce_hex: hex::encode(nonce),
                aad_hex: hex::encode(aad),
            },
            outputs: RatchetSendOutputs {
                ciphertext_b64u: base64_url(&ciphertext),
                ciphertext_len: ciphertext.len(),
                next_chain_key_b64u: base64_url(&next_ck.0),
                counter_used: counter.value(),
            },
        });
    }

    // SEND_002: Sequential messages (counter 0, 1, 2)
    {
        let initial_ck = ChainKey([0x88u8; 32]);

        let session_ctx = SessionContext {
            session_id: SessionId([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
            initiator_device_id: DeviceId([0xCCu8; 16]),
            responder_device_id: DeviceId([0xDDu8; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let transcript_hash = TranscriptHash([0x22u8; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, initial_ck.clone());

        // Send 3 messages
        let plaintext1 = b"Message 1";
        let plaintext2 = b"Message 2";
        let plaintext3 = b"Message 3";

        let (_counter1, ciphertext1) =
            sender.encrypt_and_send(plaintext1, &session_ctx, &transcript_hash, &stream_ctx)?;
        let (_counter2, ciphertext2) =
            sender.encrypt_and_send(plaintext2, &session_ctx, &transcript_hash, &stream_ctx)?;
        let (counter3, ciphertext3) =
            sender.encrypt_and_send(plaintext3, &session_ctx, &transcript_hash, &stream_ctx)?;

        // Get final chain key state by computing it independently
        let mut current_ck = initial_ck.clone();
        for i in 0..=counter3.value() {
            let output = ratchet_step(
                &current_ck,
                Counter::new(i),
                &session_ctx,
                &transcript_hash,
                &stream_ctx,
            );
            current_ck = output.next_chain_key;
        }
        let final_ck = current_ck;

        vectors.push(RatchetSendVector {
            case_id: "SEND_002".to_string(),
            description: "Sequential sends: Timon sends 3 messages (counters 0,1,2)".to_string(),
            inputs: RatchetSendInputs {
                initial_chain_key_b64u: base64_url(&initial_ck.0),
                plaintext_b64u: format!(
                    "[{},{},{}]",
                    base64_url(plaintext1),
                    base64_url(plaintext2),
                    base64_url(plaintext3)
                ),
                session_id_hex: hex::encode(session_ctx.session_id.0),
                timon_device_id_hex: hex::encode(session_ctx.initiator_device_id.0),
                peter_device_id_hex: hex::encode(session_ctx.responder_device_id.0),
                stream_id: stream_ctx.stream_id,
                message_type: stream_ctx.message_type,
                suite_id: stream_ctx.suite_id,
                counter: 0,
            },
            crypto_steps: SendCryptoSteps {
                mk_material_b64u: "See individual messages".to_string(),
                suite_key_b64u: "See individual messages".to_string(),
                nonce_material_b64u: "See individual messages".to_string(),
                nonce_hex: "See individual messages".to_string(),
                aad_hex: "See individual messages".to_string(),
            },
            outputs: RatchetSendOutputs {
                ciphertext_b64u: format!(
                    "[{},{},{}]",
                    base64_url(&ciphertext1),
                    base64_url(&ciphertext2),
                    base64_url(&ciphertext3)
                ),
                ciphertext_len: ciphertext1.len() + ciphertext2.len() + ciphertext3.len(),
                next_chain_key_b64u: base64_url(&final_ck.0),
                counter_used: counter3.value(),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Ratchet Receive Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct RatchetReceiveVector {
    case_id: String,
    description: String,
    inputs: RatchetReceiveInputs,
    outputs: RatchetReceiveOutputs,
}

#[derive(Serialize, Deserialize)]
struct RatchetReceiveInputs {
    initial_chain_key_b64u: String,
    ciphertext_b64u: String,
    counter: u64,
    session_id_hex: String,
    stream_id: u8,
    message_type: u8,
    suite_id: u16,
}

#[derive(Serialize, Deserialize)]
struct RatchetReceiveOutputs {
    plaintext_b64u: String,
    plaintext_len: usize,
    chain_key_after_receive_b64u: String,
    recv_expected_after: u64,
}

fn generate_ratchet_receive_vectors() -> Result<Vec<RatchetReceiveVector>> {
    let mut vectors = Vec::new();

    // RECV_001: Basic receive (counter=0)
    {
        let initial_ck = ChainKey([0x42u8; 32]);
        let plaintext = b"Hello from Timon!";

        let session_ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let transcript_hash = TranscriptHash([0x11u8; 32]);

        // Sender encrypts
        let mut sender = StreamState::new(StreamDirection::I2R, initial_ck.clone());
        let (counter, ciphertext) =
            sender.encrypt_and_send(plaintext, &session_ctx, &transcript_hash, &stream_ctx)?;

        // Receiver decrypts
        let mut receiver = StreamState::new(StreamDirection::I2R, initial_ck.clone());
        let decrypted = receiver.receive_and_decrypt(
            counter,
            &ciphertext,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )?;

        vectors.push(RatchetReceiveVector {
            case_id: "RECV_001".to_string(),
            description: "Basic receive: Peter receives from Timon (counter=0)".to_string(),
            inputs: RatchetReceiveInputs {
                initial_chain_key_b64u: base64_url(&initial_ck.0),
                ciphertext_b64u: base64_url(&ciphertext),
                counter: counter.value(),
                session_id_hex: hex::encode(session_ctx.session_id.0),
                stream_id: stream_ctx.stream_id,
                message_type: stream_ctx.message_type,
                suite_id: stream_ctx.suite_id,
            },
            outputs: RatchetReceiveOutputs {
                plaintext_b64u: base64_url(&decrypted),
                plaintext_len: decrypted.len(),
                chain_key_after_receive_b64u: base64_url(&{
                    let output = ratchet_step(
                        &initial_ck,
                        counter,
                        &session_ctx,
                        &transcript_hash,
                        &stream_ctx,
                    );
                    output.next_chain_key.0
                }),
                recv_expected_after: counter.value() + 1,
            },
        });
    }

    // RECV_002: Out-of-order receive (skip forward from counter 1 to 5)
    {
        let initial_ck = ChainKey([0x99u8; 32]);
        let plaintext = b"Message number 5";

        let session_ctx = SessionContext {
            session_id: SessionId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]),
            initiator_device_id: DeviceId([0x11u8; 16]),
            responder_device_id: DeviceId([0x22u8; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: STREAM_R2I,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let transcript_hash = TranscriptHash([0x33u8; 32]);

        // Sender encrypts message #5
        let mut sender = StreamState::new(StreamDirection::R2I, initial_ck.clone());
        // Send messages 0-4 (to advance counter)
        for _ in 0..5 {
            sender.encrypt_and_send(b"dummy", &session_ctx, &transcript_hash, &stream_ctx)?;
        }
        // Now send message #5
        let (counter, ciphertext) =
            sender.encrypt_and_send(plaintext, &session_ctx, &transcript_hash, &stream_ctx)?;

        // Receiver starts fresh and receives out-of-order message #5
        let mut receiver = StreamState::new(StreamDirection::R2I, initial_ck.clone());
        let decrypted = receiver.receive_and_decrypt(
            counter,
            &ciphertext,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )?;

        vectors.push(RatchetReceiveVector {
            case_id: "RECV_002".to_string(),
            description: "Out-of-order: Peter receives counter=5 (skipping 0-4)".to_string(),
            inputs: RatchetReceiveInputs {
                initial_chain_key_b64u: base64_url(&initial_ck.0),
                ciphertext_b64u: base64_url(&ciphertext),
                counter: counter.value(),
                session_id_hex: hex::encode(session_ctx.session_id.0),
                stream_id: stream_ctx.stream_id,
                message_type: stream_ctx.message_type,
                suite_id: stream_ctx.suite_id,
            },
            outputs: RatchetReceiveOutputs {
                plaintext_b64u: base64_url(&decrypted),
                plaintext_len: decrypted.len(),
                chain_key_after_receive_b64u: base64_url(&{
                    let mut current_ck = initial_ck;
                    for i in 0..=counter.value() {
                        let output = ratchet_step(
                            &current_ck,
                            Counter::new(i),
                            &session_ctx,
                            &transcript_hash,
                            &stream_ctx,
                        );
                        current_ck = output.next_chain_key;
                    }
                    current_ck.0
                }),
                recv_expected_after: counter.value() + 1,
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Skip Window Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct SkipWindowVector {
    case_id: String,
    description: String,
    inputs: SkipWindowInputs,
    outputs: SkipWindowOutputs,
}

#[derive(Serialize, Deserialize)]
struct SkipWindowInputs {
    initial_recv_expected: u64,
    message_sequence: Vec<u64>,
    description_sequence: String,
}

#[derive(Serialize, Deserialize)]
struct SkipWindowOutputs {
    final_recv_expected: u64,
    bitmap_stats: String,
    accepted_counters: Vec<u64>,
    rejected_counters: Vec<u64>,
}

fn generate_skip_window_vectors() -> Result<Vec<SkipWindowVector>> {
    let mut vectors = Vec::new();

    // SKIP_001: Sequential in-order delivery
    {
        let mut window = SkipWindow::new();
        let sequence = vec![0, 1, 2, 3, 4];
        let mut accepted = Vec::new();
        let mut rejected = Vec::new();

        for &counter in &sequence {
            if window.can_accept(Counter::new(counter)).unwrap_or(false) {
                accepted.push(counter);
                let _ = window.mark_consumed(Counter::new(counter));
            } else {
                rejected.push(counter);
            }
        }

        vectors.push(SkipWindowVector {
            case_id: "SKIP_001".to_string(),
            description: "Sequential in-order delivery (counters 0-4)".to_string(),
            inputs: SkipWindowInputs {
                initial_recv_expected: 0,
                message_sequence: sequence.clone(),
                description_sequence: "Sequential: 0,1,2,3,4".to_string(),
            },
            outputs: SkipWindowOutputs {
                final_recv_expected: window.recv_expected().value(),
                bitmap_stats: format!("{}/{} bits set", window.stats().consumed_count, 2048),
                accepted_counters: accepted,
                rejected_counters: rejected,
            },
        });
    }

    // SKIP_002: Out-of-order delivery with gaps
    {
        let mut window = SkipWindow::new();
        let sequence = vec![0, 2, 1, 5, 3, 4, 6]; // Mixed order
        let mut accepted = Vec::new();
        let mut rejected = Vec::new();

        for &counter in &sequence {
            if window.can_accept(Counter::new(counter)).unwrap_or(false) {
                accepted.push(counter);
                let _ = window.mark_consumed(Counter::new(counter));
            } else {
                rejected.push(counter);
            }
        }

        vectors.push(SkipWindowVector {
            case_id: "SKIP_002".to_string(),
            description: "Out-of-order delivery with gaps (0,2,1,5,3,4,6)".to_string(),
            inputs: SkipWindowInputs {
                initial_recv_expected: 0,
                message_sequence: sequence.clone(),
                description_sequence: "Out-of-order: 0,2,1,5,3,4,6".to_string(),
            },
            outputs: SkipWindowOutputs {
                final_recv_expected: window.recv_expected().value(),
                bitmap_stats: format!("{}/{} bits set", window.stats().consumed_count, 2048),
                accepted_counters: accepted,
                rejected_counters: rejected,
            },
        });
    }

    // SKIP_003: Replay attack detection
    {
        let mut window = SkipWindow::new();
        let sequence = vec![0, 1, 2, 1, 2, 3]; // Duplicates of 1 and 2
        let mut accepted = Vec::new();
        let mut rejected = Vec::new();

        for &counter in &sequence {
            if window.can_accept(Counter::new(counter)).unwrap_or(false) {
                accepted.push(counter);
                let _ = window.mark_consumed(Counter::new(counter));
            } else {
                rejected.push(counter);
            }
        }

        vectors.push(SkipWindowVector {
            case_id: "SKIP_003".to_string(),
            description: "Replay detection (counters 0,1,2,1,2,3 - duplicates rejected)"
                .to_string(),
            inputs: SkipWindowInputs {
                initial_recv_expected: 0,
                message_sequence: sequence.clone(),
                description_sequence: "With replays: 0,1,2,1,2,3".to_string(),
            },
            outputs: SkipWindowOutputs {
                final_recv_expected: window.recv_expected().value(),
                bitmap_stats: format!("{}/{} bits set", window.stats().consumed_count, 2048),
                accepted_counters: accepted,
                rejected_counters: rejected,
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Negative Test Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct NegativeVector {
    case_id: String,
    description: String,
    test_type: String,
    inputs: serde_json::Value,
    expected_error: String,
}

fn generate_negative_vectors() -> Result<Vec<NegativeVector>> {
    let mut vectors = Vec::new();

    // NEG_001: Tampered ciphertext (AEAD auth failure)
    {
        let initial_ck = ChainKey([0x42u8; 32]);
        let initial_ck_copy = ChainKey([0x42u8; 32]); // Clone for later use
        let plaintext = b"Original message";

        let session_ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let transcript_hash = TranscriptHash([0x11u8; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, initial_ck);
        let (counter, mut ciphertext) =
            sender.encrypt_and_send(plaintext, &session_ctx, &transcript_hash, &stream_ctx)?;

        // Tamper with ciphertext
        ciphertext[0] ^= 0xFF;

        vectors.push(NegativeVector {
            case_id: "NEG_001".to_string(),
            description: "Tampered ciphertext (AEAD auth failure)".to_string(),
            test_type: "tampered_ciphertext".to_string(),
            inputs: serde_json::json!({
                "initial_chain_key_b64u": base64_url(&initial_ck_copy.0),
                "ciphertext_b64u": base64_url(&ciphertext),
                "counter": counter.value(),
            }),
            expected_error: "DecryptionFailed".to_string(),
        });
    }

    // NEG_002: Replay attack (counter reuse)
    {
        vectors.push(NegativeVector {
            case_id: "NEG_002".to_string(),
            description: "Replay attack (reused counter)".to_string(),
            test_type: "replay_attack".to_string(),
            inputs: serde_json::json!({
                "scenario": "Send message with counter=5, then try to send counter=5 again",
                "expected_behavior": "Second message with counter=5 should be rejected by SkipWindow",
            }),
            expected_error: "ReplayDetected".to_string(),
        });
    }

    // NEG_003: Counter too far in future (exceeds skip window)
    {
        vectors.push(NegativeVector {
            case_id: "NEG_003".to_string(),
            description: "Counter too far ahead (exceeds SKIP_WINDOW_SIZE)".to_string(),
            test_type: "excessive_skip".to_string(),
            inputs: serde_json::json!({
                "recv_expected": 0,
                "received_counter": 2048_u64 + 1,
                "skip_window_size": 2048,
            }),
            expected_error: "CounterTooFarAhead".to_string(),
        });
    }

    Ok(vectors)
}

// ============================================================================
// Helper Functions
// ============================================================================

fn base64_url(data: &[u8]) -> String {
    use base64::Engine;
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(data)
}

fn write_json_file<T: Serialize>(path: &Path, data: &T, force: bool) -> Result<()> {
    if path.exists() && !force {
        anyhow::bail!(
            "File already exists: {} (use --force to overwrite)",
            path.display()
        );
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

    // Generate ratchet_send_vectors.json
    {
        let vectors = generate_ratchet_send_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "ratchet_send".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Message encryption with symmetric ratcheting (Timon sends)".to_string(),
            vectors,
        };

        let path = output_dir.join("ratchet_send_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate ratchet_receive_vectors.json
    {
        let vectors = generate_ratchet_receive_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "ratchet_receive".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Message decryption with symmetric ratcheting (Peter receives)"
                .to_string(),
            vectors,
        };

        let path = output_dir.join("ratchet_receive_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate skip_window_vectors.json
    {
        let vectors = generate_skip_window_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "skip_window".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Out-of-order message handling and replay detection".to_string(),
            vectors,
        };

        let path = output_dir.join("skip_window_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate negative_vectors.json
    {
        let vectors = generate_negative_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "negative_tests".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Negative test cases (tampered data, replay attacks)".to_string(),
            vectors,
        };

        let path = output_dir.join("negative_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    Ok(())
}
