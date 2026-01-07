//! C6P Comprehensive Performance Benchmarks
//!
//! Measures performance of all critical C6P operations for grant documentation
//! and performance validation.

use c6p_crypto::{
    derive_initial_chain_key, derive_root_and_kc, DeviceId, SessionContext, SessionId,
    StreamContext, TranscriptHash, SUITE_CHACHA20_POLY1305,
};
use c6p_handshake::{Accept, Offer, PrekeyBundle};
use c6p_identity::{DeviceId as IdentityDeviceId, Fingerprint};
use c6p_sessions::{ChainKey, StreamDirection, StreamState};
use criterion::{black_box, criterion_group, criterion_main, BenchmarkId, Criterion, Throughput};
use ed25519_dalek::SigningKey;
use rand::RngCore;

// ============================================================================
// Helper Functions
// ============================================================================

fn create_test_keys() -> (
    c6p_handshake::Ed25519PrivateKey,
    c6p_handshake::Ed25519PublicKey,
    c6p_handshake::X25519PrivateKey,
    c6p_handshake::X25519PublicKey,
) {
    let mut rng = rand::thread_rng();
    let mut seed = [0u8; 32];
    rng.fill_bytes(&mut seed);

    let signing_key = SigningKey::from_bytes(&seed);
    let ed_pub =
        c6p_handshake::Ed25519PublicKey::from_bytes(signing_key.verifying_key().to_bytes());
    let ed_priv = c6p_handshake::Ed25519PrivateKey::from_bytes(seed);

    let mut x_priv_bytes = [0u8; 32];
    rng.fill_bytes(&mut x_priv_bytes);
    let x_priv = c6p_handshake::X25519PrivateKey::from_bytes(x_priv_bytes);
    let x_pub = c6p_handshake::X25519PublicKey::from_bytes(x25519_dalek::x25519(
        x_priv_bytes,
        x25519_dalek::X25519_BASEPOINT_BYTES,
    ));

    (ed_priv, ed_pub, x_priv, x_pub)
}

fn create_prekey_bundle() -> (
    PrekeyBundle,
    c6p_handshake::Ed25519PrivateKey,
    c6p_handshake::Ed25519PublicKey,
    c6p_handshake::X25519PrivateKey,
    c6p_handshake::X25519PublicKey,
    c6p_handshake::X25519PrivateKey,
    c6p_handshake::X25519PublicKey,
) {
    let (peter_ed_priv, peter_ed_pub, peter_x_priv, peter_x_pub) = create_test_keys();
    let (_, _, peter_spk_priv, peter_spk_pub) = create_test_keys();

    let spk_id = c6p_handshake::SpkId([0x01; 8]);
    let mut spk_msg = Vec::new();
    spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
    spk_msg.extend_from_slice(&spk_id.0);
    spk_msg.extend_from_slice(&peter_spk_pub.0);
    let spk_sig = c6p_handshake::ed25519_sign(&peter_ed_priv, &spk_msg).unwrap();

    let bundle = PrekeyBundle::new(
        c6p_handshake::DeviceId([0xBB; 16]),
        peter_ed_pub,
        peter_x_pub,
        spk_id,
        peter_spk_pub,
        spk_sig,
        None,
    );

    (
        bundle,
        peter_ed_priv,
        peter_ed_pub,
        peter_x_priv,
        peter_x_pub,
        peter_spk_priv,
        peter_spk_pub,
    )
}

// ============================================================================
// Identity Benchmarks
// ============================================================================

fn bench_identity(c: &mut Criterion) {
    let mut group = c.benchmark_group("identity");

    // Device ID derivation
    group.bench_function("device_id_derivation", |b| {
        let public_key = [0x42; 32];
        b.iter(|| IdentityDeviceId::from_ed25519_public_key(black_box(&public_key)))
    });

    // Fingerprint generation
    group.bench_function("fingerprint_generation", |b| {
        let public_key = [0x42; 32];
        b.iter(|| Fingerprint::from_ed25519_public_key(black_box(&public_key)))
    });

    // Fingerprint formatting
    group.bench_function("fingerprint_formatting", |b| {
        let public_key = [0x42; 32];
        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
        b.iter(|| black_box(&fp).formatted())
    });

    group.finish();
}

// ============================================================================
// Crypto Benchmarks
// ============================================================================

fn bench_crypto(c: &mut Criterion) {
    let mut group = c.benchmark_group("crypto");

    // Root key derivation (3DH - 96 bytes IKM)
    group.bench_function("root_key_derivation_3dh", |b| {
        let ikm = vec![0x42; 96];
        let transcript_hash = TranscriptHash([0x11; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01; 8]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };

        b.iter(|| {
            derive_root_and_kc(
                black_box(&ikm),
                black_box(&transcript_hash),
                black_box(&ctx),
            )
        })
    });

    // Root key derivation (4DH - 128 bytes IKM)
    group.bench_function("root_key_derivation_4dh", |b| {
        let ikm = vec![0x42; 128];
        let transcript_hash = TranscriptHash([0x11; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01; 8]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };

        b.iter(|| {
            derive_root_and_kc(
                black_box(&ikm),
                black_box(&transcript_hash),
                black_box(&ctx),
            )
        })
    });

    // Chain key derivation
    group.bench_function("chain_key_derivation", |b| {
        let root_key = c6p_crypto::RootKey([0x42; 32]);
        let transcript_hash = TranscriptHash([0x11; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01; 8]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };
        let stream_ctx = StreamContext {
            stream_id: 0x01,
            message_type: 0x01,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        b.iter(|| {
            derive_initial_chain_key(
                black_box(&root_key),
                black_box(&transcript_hash),
                black_box(&ctx),
                black_box(&stream_ctx),
            )
        })
    });

    group.finish();
}

// ============================================================================
// Handshake Benchmarks
// ============================================================================

fn bench_handshake(c: &mut Criterion) {
    let mut group = c.benchmark_group("handshake");

    // Offer construction
    group.bench_function("offer_construction", |b| {
        let (
            bundle,
            _peter_ed_priv,
            _peter_ed_pub,
            _peter_x_priv,
            _peter_x_pub,
            _peter_spk_priv,
            _peter_spk_pub,
        ) = create_prekey_bundle();
        let (timon_ed_priv, timon_ed_pub, timon_x_priv, timon_x_pub) = create_test_keys();
        let (_, _, timon_eph_priv, timon_eph_pub) = create_test_keys();

        b.iter(|| {
            Offer::construct(
                black_box(&bundle),
                c6p_handshake::SessionId([0x11; 8]),
                c6p_handshake::DeviceId([0xAA; 16]),
                &timon_x_priv,
                &timon_x_pub,
                &timon_ed_priv,
                &timon_ed_pub,
                &timon_eph_priv,
                &timon_eph_pub,
                SUITE_CHACHA20_POLY1305,
            )
        })
    });

    // Accept construction (includes offer validation)
    group.bench_function("accept_construction", |b| {
        let (
            bundle,
            _peter_ed_priv,
            peter_ed_pub,
            peter_x_priv,
            peter_x_pub,
            peter_spk_priv,
            _peter_spk_pub,
        ) = create_prekey_bundle();
        let (timon_ed_priv, timon_ed_pub, timon_x_priv, timon_x_pub) = create_test_keys();
        let (_, _, timon_eph_priv, timon_eph_pub) = create_test_keys();

        let (offer, _) = Offer::construct(
            &bundle,
            c6p_handshake::SessionId([0x11; 8]),
            c6p_handshake::DeviceId([0xAA; 16]),
            &timon_x_priv,
            &timon_x_pub,
            &timon_ed_priv,
            &timon_ed_pub,
            &timon_eph_priv,
            &timon_eph_pub,
            SUITE_CHACHA20_POLY1305,
        )
        .unwrap();

        b.iter(|| {
            Accept::construct(
                black_box(&offer),
                c6p_handshake::DeviceId([0xBB; 16]),
                &peter_x_priv,
                &peter_x_pub,
                &peter_ed_pub,
                c6p_handshake::SpkId([0x01; 8]),
                &peter_spk_priv,
                &bundle.spk_pub,
                None,
            )
        })
    });

    group.finish();
}

// ============================================================================
// Sessions AEAD Benchmarks
// ============================================================================

fn bench_sessions(c: &mut Criterion) {
    let mut group = c.benchmark_group("sessions_aead");

    let session_ctx = SessionContext {
        session_id: SessionId([0x01; 8]),
        initiator_device_id: DeviceId([0xAA; 16]),
        responder_device_id: DeviceId([0xBB; 16]),
    };

    let stream_ctx = StreamContext {
        stream_id: 0x01,
        message_type: 0x01,
        suite_id: SUITE_CHACHA20_POLY1305,
    };

    let transcript_hash = TranscriptHash([0x42; 32]);

    // Encryption throughput for different message sizes
    for size in [64, 256, 1024, 4096, 16384].iter() {
        group.throughput(Throughput::Bytes(*size as u64));
        group.bench_with_input(BenchmarkId::new("encrypt", size), size, |b, &size| {
            let mut sender = StreamState::new(StreamDirection::I2R, ChainKey([0x11; 32]));
            let plaintext = vec![0x42u8; size];

            b.iter(|| {
                sender.encrypt_and_send(
                    black_box(&plaintext),
                    black_box(&session_ctx),
                    black_box(&transcript_hash),
                    black_box(&stream_ctx),
                )
            })
        });
    }

    // Decryption throughput for different message sizes
    for size in [64, 256, 1024, 4096, 16384].iter() {
        group.throughput(Throughput::Bytes(*size as u64));
        group.bench_with_input(BenchmarkId::new("decrypt", size), size, |b, &size| {
            let mut sender = StreamState::new(StreamDirection::I2R, ChainKey([0x11; 32]));
            let mut receiver = StreamState::new(StreamDirection::I2R, ChainKey([0x11; 32]));
            let plaintext = vec![0x42u8; size];

            let (counter, ciphertext) = sender
                .encrypt_and_send(&plaintext, &session_ctx, &transcript_hash, &stream_ctx)
                .unwrap();

            b.iter(|| {
                receiver.receive_and_decrypt(
                    black_box(counter),
                    black_box(&ciphertext),
                    black_box(&session_ctx),
                    black_box(&transcript_hash),
                    black_box(&stream_ctx),
                )
            })
        });
    }

    group.finish();
}

// ============================================================================
// End-to-End Benchmarks
// ============================================================================

fn bench_end_to_end(c: &mut Criterion) {
    let mut group = c.benchmark_group("end_to_end");

    // Full handshake + first message (cold start)
    group.bench_function("full_handshake_plus_message", |b| {
        b.iter(|| {
            // Setup
            let (
                bundle,
                _peter_ed_priv,
                peter_ed_pub,
                peter_x_priv,
                peter_x_pub,
                peter_spk_priv,
                _peter_spk_pub,
            ) = create_prekey_bundle();
            let (timon_ed_priv, timon_ed_pub, timon_x_priv, timon_x_pub) = create_test_keys();
            let (_, _, timon_eph_priv, timon_eph_pub) = create_test_keys();

            // Handshake
            let (offer, timon_output) = Offer::construct(
                &bundle,
                c6p_handshake::SessionId([0x11; 8]),
                c6p_handshake::DeviceId([0xAA; 16]),
                &timon_x_priv,
                &timon_x_pub,
                &timon_ed_priv,
                &timon_ed_pub,
                &timon_eph_priv,
                &timon_eph_pub,
                SUITE_CHACHA20_POLY1305,
            )
            .unwrap();

            let (_accept, _peter_output) = Accept::construct(
                &offer,
                c6p_handshake::DeviceId([0xBB; 16]),
                &peter_x_priv,
                &peter_x_pub,
                &peter_ed_pub,
                c6p_handshake::SpkId([0x01; 8]),
                &peter_spk_priv,
                &bundle.spk_pub,
                None,
            )
            .unwrap();

            // First message
            let mut sender = StreamState::new(
                StreamDirection::I2R,
                ChainKey::from_bytes(timon_output.send_chain_key),
            );

            let session_ctx = SessionContext {
                session_id: SessionId([0x01; 8]),
                initiator_device_id: DeviceId([0xAA; 16]),
                responder_device_id: DeviceId([0xBB; 16]),
            };

            let stream_ctx = StreamContext {
                stream_id: 0x01,
                message_type: 0x01,
                suite_id: SUITE_CHACHA20_POLY1305,
            };

            let transcript_hash = TranscriptHash([0x42; 32]);

            sender
                .encrypt_and_send(b"Hello", &session_ctx, &transcript_hash, &stream_ctx)
                .unwrap();
        })
    });

    group.finish();
}

// ============================================================================
// Criterion Configuration
// ============================================================================

criterion_group!(
    benches,
    bench_identity,
    bench_crypto,
    bench_handshake,
    bench_sessions,
    bench_end_to_end
);
criterion_main!(benches);
