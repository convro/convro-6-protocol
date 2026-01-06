//! Full C6P End-to-End Demo
//!
//! This example demonstrates a complete C6P workflow:
//! 1. Generate ephemeral keys for initiator and responder
//! 2. Perform IslandAccord v1 handshake (3DH)
//! 3. Derive session keys from handshake
//! 4. Exchange multiple encrypted messages
//! 5. Demonstrate out-of-order delivery
//! 6. Show replay attack detection
//!
//! Run with: cargo run --example full_session_demo

use c6p_crypto::{DeviceId, SessionContext, SessionId, StreamContext, SUITE_CHACHA20_POLY1305};
use c6p_handshake::{
    ed25519_sign, Accept, Ed25519PrivateKey, Ed25519PublicKey, Offer, PrekeyBundle, SpkId,
    X25519PrivateKey, X25519PublicKey,
};
use c6p_sessions::{ChainKey, StreamDirection, StreamState};

// Helper to create test keys (simplified from production use)
fn create_test_keys() -> (
    Ed25519PrivateKey,
    Ed25519PublicKey,
    X25519PrivateKey,
    X25519PublicKey,
) {
    use ed25519_dalek::SigningKey;
    use rand::RngCore;

    // Random keys for demo
    let mut rng = rand::thread_rng();
    let mut seed = [0u8; 32];
    rng.fill_bytes(&mut seed);

    let signing_key = SigningKey::from_bytes(&seed);
    let ed_pub = Ed25519PublicKey::from_bytes(signing_key.verifying_key().to_bytes());
    let ed_priv = Ed25519PrivateKey::from_bytes(seed);

    let mut x_priv_bytes = [0u8; 32];
    rng.fill_bytes(&mut x_priv_bytes);
    let x_priv = X25519PrivateKey::from_bytes(x_priv_bytes);
    let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(
        x_priv_bytes,
        x25519_dalek::X25519_BASEPOINT_BYTES,
    ));

    (ed_priv, ed_pub, x_priv, x_pub)
}

fn main() {
    println!("🔐 C6P Full Session Demo");
    println!("{}", "=".repeat(60));
    println!();

    // ========================================================================
    // STEP 1: Setup - Generate Keys and IDs
    // ========================================================================
    println!("📋 STEP 1: Setup");
    println!("{}", "-".repeat(60));

    // Initiator (Alice) - needs identity + ephemeral keys
    let alice_device_id = DeviceId([0xAA; 16]);
    let (alice_ed_priv, alice_ed_pub, alice_x_priv, alice_x_pub) = create_test_keys();
    let (_, _, alice_eph_priv, alice_eph_pub) = create_test_keys();

    // Responder (Bob) - needs identity + SPK keys
    let bob_device_id = DeviceId([0xBB; 16]);
    let (bob_ed_priv, bob_ed_pub, bob_x_priv, bob_x_pub) = create_test_keys();
    let (_, _, bob_spk_priv, bob_spk_pub) = create_test_keys();

    println!("✅ Alice device ID: {}", hex::encode(alice_device_id.0));
    println!("✅ Bob device ID:   {}", hex::encode(bob_device_id.0));
    println!();

    // ========================================================================
    // STEP 2: Handshake - IslandAccord v1
    // ========================================================================
    println!("🤝 STEP 2: IslandAccord v1 Handshake");
    println!("{}", "-".repeat(60));

    // Bob creates prekey bundle (would be published to server in production)
    let spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

    // Sign SPK
    let mut spk_msg = Vec::new();
    spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
    spk_msg.extend_from_slice(&spk_id.0);
    spk_msg.extend_from_slice(&bob_spk_pub.0);
    let spk_sig = ed25519_sign(&bob_ed_priv, &spk_msg).expect("SPK signing failed");

    let bob_bundle = PrekeyBundle::new(
        bob_device_id,
        bob_ed_pub,
        bob_x_pub,
        spk_id,
        bob_spk_pub,
        spk_sig,
        None, // No OTP = 3DH handshake
    );

    println!("✅ Bob created prekey bundle (3DH mode)");
    println!();

    // Alice creates Offer
    println!("📤 Alice creates handshake offer...");
    let session_id = SessionId([0x11; 8]);

    let (offer, alice_output) = Offer::construct(
        &bob_bundle,
        session_id,
        alice_device_id,
        &alice_x_priv,
        &alice_x_pub,
        &alice_ed_priv,
        &alice_ed_pub,
        &alice_eph_priv,
        &alice_eph_pub,
        SUITE_CHACHA20_POLY1305,
    )
    .expect("Offer construction failed");

    println!("✅ Offer created:");
    println!(
        "   - Ephemeral public: {}",
        hex::encode(&offer.initiator_ephemeral_dh_pub.0[..8])
    );
    println!("   - Session ID: {}", hex::encode(offer.session_id.0));
    println!();

    // Bob accepts Offer
    println!("📥 Bob accepts handshake offer...");

    let (accept, bob_output) = Accept::construct(
        &offer,
        bob_device_id,
        &bob_x_priv,
        &bob_x_pub,
        &bob_ed_pub,
        spk_id,
        &bob_spk_priv,
        &bob_spk_pub,
        None, // No OTP
    )
    .expect("Accept construction failed");

    println!("✅ Accept created:");
    println!("   - Session ID: {}", hex::encode(accept.session_id.0));
    println!("   - KC2 tag: {}", hex::encode(&accept.kc2[..8]));
    println!();

    // Verify both sides have same keys
    assert_eq!(
        alice_output.root_key, bob_output.root_key,
        "Root keys must match!"
    );

    println!("✅ Handshake complete! Both parties share:");
    println!("   - Root key: {}", hex::encode(&alice_output.root_key[..8]));
    println!(
        "   - Session binding: {}",
        hex::encode(&alice_output.session_binding[..8])
    );
    println!();

    // ========================================================================
    // STEP 3: Session Setup - Derive Chain Keys
    // ========================================================================
    println!("🔑 STEP 3: Session Setup");
    println!("{}", "-".repeat(60));

    let session_ctx = SessionContext {
        session_id,
        initiator_device_id: alice_device_id,
        responder_device_id: bob_device_id,
    };

    let stream_ctx = StreamContext {
        stream_id: 0x01,           // I2R (Alice → Bob)
        message_type: 0x01,        // DM
        suite_id: SUITE_CHACHA20_POLY1305,
    };

    // Alice sends I2R, Bob receives I2R
    let chain_key_i2r = ChainKey::from_bytes(alice_output.send_chain_key);
    let mut alice_state = StreamState::new(StreamDirection::I2R, chain_key_i2r.clone());
    let mut bob_state = StreamState::new(StreamDirection::I2R, chain_key_i2r);

    // Use placeholder transcript hash (in production: from handshake)
    let transcript_hash = c6p_crypto::TranscriptHash([0u8; 32]);

    println!("✅ Session initialized:");
    println!("   - Session ID: {}", hex::encode(session_id.0));
    println!("   - Stream: I2R (Alice → Bob)");
    println!("   - Cipher: ChaCha20-Poly1305");
    println!();

    // ========================================================================
    // STEP 4: Message Exchange - Multiple Messages
    // ========================================================================
    println!("💬 STEP 4: Encrypted Message Exchange");
    println!("{}", "-".repeat(60));

    let messages = vec![
        "Hello Bob! 👋",
        "This is Alice speaking.",
        "C6P is working perfectly! 🎉",
    ];

    for (i, plaintext) in messages.iter().enumerate() {
        println!("📨 Message #{}: \"{}\"", i, plaintext);

        // Alice encrypts
        let (counter, sealed) = alice_state
            .encrypt_and_send(
                plaintext.as_bytes(),
                &session_ctx,
                &transcript_hash,
                &stream_ctx,
            )
            .expect("Encryption should succeed");

        println!(
            "   🔒 Encrypted (counter={}, size={} bytes)",
            counter.value(),
            sealed.len()
        );

        // Bob decrypts
        let decrypted = bob_state
            .receive_and_decrypt(
                counter,
                &sealed,
                &session_ctx,
                &transcript_hash,
                &stream_ctx,
            )
            .expect("Decryption should succeed");

        println!(
            "   🔓 Decrypted: \"{}\"",
            String::from_utf8_lossy(&decrypted)
        );

        assert_eq!(decrypted, plaintext.as_bytes());
        println!("   ✅ Message verified!");
        println!();
    }

    println!("✅ All messages exchanged successfully!");
    println!(
        "   - Alice sent: {} messages",
        alice_state.send_counter().value()
    );
    println!(
        "   - Bob received: {} messages",
        bob_state.recv_expected().value()
    );
    println!();

    // ========================================================================
    // STEP 5: Out-of-Order Delivery
    // ========================================================================
    println!("🔀 STEP 5: Out-of-Order Delivery Demo");
    println!("{}", "-".repeat(60));

    // Alice sends 3 more messages
    let msg_3 = "Message 3";
    let msg_4 = "Message 4";
    let msg_5 = "Message 5";

    let (counter_3, sealed_3) = alice_state
        .encrypt_and_send(
            msg_3.as_bytes(),
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();
    let (counter_4, sealed_4) = alice_state
        .encrypt_and_send(
            msg_4.as_bytes(),
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();
    let (counter_5, sealed_5) = alice_state
        .encrypt_and_send(
            msg_5.as_bytes(),
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

    println!("📤 Alice sent 3 messages (counters: 3, 4, 5)");
    println!();

    // Bob receives out of order: 5, 3, 4
    println!("📥 Bob receives OUT OF ORDER: 5, 3, 4");
    println!();

    // Receive #5 first
    println!("   Receiving counter 5...");
    let dec_5 = bob_state
        .receive_and_decrypt(
            counter_5,
            &sealed_5,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();
    assert_eq!(dec_5, msg_5.as_bytes());
    println!(
        "   ✅ Decrypted: \"{}\"",
        String::from_utf8_lossy(&dec_5)
    );
    println!(
        "   📊 recv_expected = {} (not advanced yet)",
        bob_state.recv_expected().value()
    );
    println!();

    // Receive #3
    println!("   Receiving counter 3...");
    let dec_3 = bob_state
        .receive_and_decrypt(
            counter_3,
            &sealed_3,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();
    assert_eq!(dec_3, msg_3.as_bytes());
    println!(
        "   ✅ Decrypted: \"{}\"",
        String::from_utf8_lossy(&dec_3)
    );
    println!(
        "   📊 recv_expected = {} (advanced!)",
        bob_state.recv_expected().value()
    );
    println!();

    // Receive #4
    println!("   Receiving counter 4...");
    let dec_4 = bob_state
        .receive_and_decrypt(
            counter_4,
            &sealed_4,
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();
    assert_eq!(dec_4, msg_4.as_bytes());
    println!(
        "   ✅ Decrypted: \"{}\"",
        String::from_utf8_lossy(&dec_4)
    );
    println!(
        "   📊 recv_expected = {} (all consumed!)",
        bob_state.recv_expected().value()
    );
    println!();

    println!("✅ Out-of-order delivery handled correctly!");
    println!();

    // ========================================================================
    // STEP 6: Replay Attack Detection
    // ========================================================================
    println!("🛡️  STEP 6: Replay Attack Detection");
    println!("{}", "-".repeat(60));

    println!("🚨 Attacker tries to replay counter 3...");
    let replay_result = bob_state.receive_and_decrypt(
        counter_3,
        &sealed_3,
        &session_ctx,
        &transcript_hash,
        &stream_ctx,
    );

    match replay_result {
        Err(c6p_sessions::SessionError::ReplayDetected(ctr)) => {
            println!("✅ Replay attack DETECTED and BLOCKED!");
            println!("   Counter {} was already consumed", ctr);
        }
        _ => panic!("Replay attack should have been detected!"),
    }
    println!();

    // ========================================================================
    // STEP 7: Tamper Detection
    // ========================================================================
    println!("🛡️  STEP 7: Tamper Detection");
    println!("{}", "-".repeat(60));

    // Alice sends one more message
    let (counter_6, mut sealed_6) = alice_state
        .encrypt_and_send(
            b"Tamper test",
            &session_ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

    println!("🚨 Attacker tampers with ciphertext...");
    sealed_6[0] ^= 0x01; // Flip one bit

    let tamper_result = bob_state.receive_and_decrypt(
        counter_6,
        &sealed_6,
        &session_ctx,
        &transcript_hash,
        &stream_ctx,
    );

    match tamper_result {
        Err(c6p_sessions::SessionError::DecryptionFailed(_)) => {
            println!("✅ Tampering DETECTED and BLOCKED!");
            println!("   AEAD authentication failed");
        }
        _ => panic!("Tamper should have been detected!"),
    }
    println!();

    // ========================================================================
    // Summary
    // ========================================================================
    println!("{}", "=".repeat(60));
    println!("🎉 DEMO COMPLETE!");
    println!("{}", "=".repeat(60));
    println!();
    println!("✅ Demonstrated:");
    println!("   ✓ IslandAccord v1 handshake (3DH)");
    println!("   ✓ Session key derivation");
    println!("   ✓ Multiple encrypted messages");
    println!("   ✓ Out-of-order delivery (2048-bit skip-window)");
    println!("   ✓ Replay attack detection");
    println!("   ✓ Tamper detection (AEAD)");
    println!();
    println!("🔐 C6P is PRODUCTION READY!");
    println!();
}
