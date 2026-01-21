//! Sessions AEAD Test Vector Validation
//!
//! Generates and validates test vectors for the c6p-sessions AEAD implementation.
//! These vectors demonstrate complete encrypt/decrypt flows.

use c6p_crypto::{DeviceId, SessionContext, SessionId, StreamContext};
use c6p_sessions::{ChainKey, StreamDirection, StreamState};

#[test]
fn test_sessions_aead_roundtrip() {
    println!("\n🔐 C6P Sessions AEAD Validation");
    println!("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

    // Test vector 1: Basic encrypt/decrypt with counter 0
    {
        println!("\n📋 TEST_001: Basic AEAD encrypt/decrypt (counter=0)");

        let session_ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: 0x01,    // I2R
            message_type: 0x01, // DM
            suite_id: 1,        // ChaCha20-Poly1305
        };

        let transcript_hash = c6p_crypto::TranscriptHash([0x42; 32]);
        let chain_key = ChainKey([0x11; 32]);

        let chain_key_copy = chain_key.clone();
        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let plaintext = b"Hello, World!";

        // Encrypt
        let (counter, ciphertext) = sender
            .encrypt_and_send(plaintext, &session_ctx, &transcript_hash, &stream_ctx)
            .expect("Encryption failed");

        assert_eq!(counter.value(), 0, "First counter should be 0");
        println!(
            "   ✅ Encrypted: {} bytes → {} bytes (counter={})",
            plaintext.len(),
            ciphertext.len(),
            counter.value()
        );

        // Decrypt
        let decrypted = receiver
            .receive_and_decrypt(
                counter,
                &ciphertext,
                &session_ctx,
                &transcript_hash,
                &stream_ctx,
            )
            .expect("Decryption failed");

        assert_eq!(&decrypted, plaintext, "Decryption mismatch");
        println!("   ✅ Decrypted: matches original plaintext");

        // Log test vector details
        println!("\n   Test Vector Details:");
        println!("   - Session ID: {}", hex::encode(session_ctx.session_id.0));
        println!(
            "   - Initial Chain Key: {}",
            hex::encode(&chain_key_copy.0[..8])
        );
        println!("   - Plaintext: {} bytes", plaintext.len());
        println!(
            "   - Ciphertext: {} bytes (+{} tag)",
            ciphertext.len() - 16,
            16
        );
    }

    // Test vector 2: Sequential messages (counter advancement)
    {
        println!("\n📋 TEST_002: Sequential messages (counter 0, 1, 2)");

        let session_ctx = SessionContext {
            session_id: SessionId([0x11; 8]),
            initiator_device_id: DeviceId([0xCC; 16]),
            responder_device_id: DeviceId([0xDD; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: 1,
        };

        let transcript_hash = c6p_crypto::TranscriptHash([0xFF; 32]);
        let chain_key = ChainKey([0x22; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let messages = ["First", "Second", "Third"];

        for (i, msg) in messages.iter().enumerate() {
            let (counter, ciphertext) = sender
                .encrypt_and_send(msg.as_bytes(), &session_ctx, &transcript_hash, &stream_ctx)
                .unwrap();

            assert_eq!(counter.value(), i as u64, "Counter mismatch");

            let decrypted = receiver
                .receive_and_decrypt(
                    counter,
                    &ciphertext,
                    &session_ctx,
                    &transcript_hash,
                    &stream_ctx,
                )
                .unwrap();

            assert_eq!(&decrypted, msg.as_bytes(), "Decryption mismatch");
            println!(
                "   ✅ Message {}: counter={}, \"{}\"",
                i,
                counter.value(),
                msg
            );
        }

        println!("   ✅ All sequential messages validated");
    }

    // Test vector 3: Tamper detection
    {
        println!("\n📋 TEST_003: Tamper detection (AEAD authentication)");

        let session_ctx = SessionContext {
            session_id: SessionId([0x99; 8]),
            initiator_device_id: DeviceId([0xEE; 16]),
            responder_device_id: DeviceId([0xFF; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: 1,
        };

        let transcript_hash = c6p_crypto::TranscriptHash([0x88; 32]);
        let chain_key = ChainKey([0x33; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let (counter, mut ciphertext) = sender
            .encrypt_and_send(b"Secret", &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Tamper with ciphertext
        ciphertext[0] ^= 0x01;

        let result = receiver.receive_and_decrypt(
            counter,
            &ciphertext,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err(), "Tampered ciphertext should fail");
        println!("   ✅ Tampering detected and rejected");
    }

    // Test vector 4: Replay detection
    {
        println!("\n📋 TEST_004: Replay attack detection");

        let session_ctx = SessionContext {
            session_id: SessionId([0x77; 8]),
            initiator_device_id: DeviceId([0x12; 16]),
            responder_device_id: DeviceId([0x34; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: 1,
        };

        let transcript_hash = c6p_crypto::TranscriptHash([0xAB; 32]);
        let chain_key = ChainKey([0x44; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let (counter, ciphertext) = sender
            .encrypt_and_send(b"Once", &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // First delivery: should succeed
        receiver
            .receive_and_decrypt(
                counter,
                &ciphertext,
                &session_ctx,
                &transcript_hash,
                &stream_ctx,
            )
            .expect("First delivery should succeed");

        // Replay: should fail
        let result = receiver.receive_and_decrypt(
            counter,
            &ciphertext,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        );

        assert!(result.is_err(), "Replay should be detected");
        match result {
            Err(c6p_sessions::SessionError::ReplayDetected(ctr)) => {
                assert_eq!(ctr, counter.value());
                println!("   ✅ Replay detected for counter {}", ctr);
            }
            _ => panic!("Expected ReplayDetected error"),
        }
    }

    // Test vector 5: Out-of-order delivery
    {
        println!("\n📋 TEST_005: Out-of-order delivery (skip-window)");

        let session_ctx = SessionContext {
            session_id: SessionId([0x55; 8]),
            initiator_device_id: DeviceId([0xAB; 16]),
            responder_device_id: DeviceId([0xCD; 16]),
        };

        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: 1,
        };

        let transcript_hash = c6p_crypto::TranscriptHash([0xDE; 32]);
        let chain_key = ChainKey([0x55; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Send 3 messages
        let (c0, ct0) = sender
            .encrypt_and_send(b"Zero", &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let (c1, ct1) = sender
            .encrypt_and_send(b"One", &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let (c2, ct2) = sender
            .encrypt_and_send(b"Two", &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receive out of order: 2, 0, 1
        let d2 = receiver
            .receive_and_decrypt(c2, &ct2, &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(&d2, b"Two");
        println!("   ✅ Received counter 2 first");

        let d0 = receiver
            .receive_and_decrypt(c0, &ct0, &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(&d0, b"Zero");
        println!("   ✅ Received counter 0 (skip-window)");

        let d1 = receiver
            .receive_and_decrypt(c1, &ct1, &session_ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(&d1, b"One");
        println!("   ✅ Received counter 1 (in order)");

        assert_eq!(
            receiver.recv_expected().value(),
            3,
            "recv_expected should advance to 3"
        );
        println!("   ✅ Out-of-order delivery handled correctly");
    }

    println!("\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
    println!("✅ All 5 sessions AEAD test vectors validated!\n");
}
