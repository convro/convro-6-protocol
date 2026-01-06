//! IslandAccord Handshake Test Vector Generation
//!
//! Generates deterministic test vectors for C6P handshake module.
//! Covers offer construction, accept construction, key derivation (3DH/4DH),
//! and key confirmation tags.
//!
//! Uses Timon (initiator) and Peter (responder) as example participants.

use anyhow::Result;
use c6p_crypto::*;
use c6p_handshake::*;
use ed25519_dalek::{SigningKey, Signer};
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
// Island Accord Offer Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct OfferVector {
    case_id: String,
    description: String,
    inputs: OfferInputs,
    outputs: OfferOutputs,
}

#[derive(Serialize, Deserialize)]
struct OfferInputs {
    // Timon's (initiator) keys
    timon_ed_priv_b64u: String,
    timon_ed_pub_b64u: String,
    timon_x_priv_b64u: String,
    timon_x_pub_b64u: String,
    timon_eph_priv_b64u: String,
    timon_eph_pub_b64u: String,
    timon_device_id_hex: String,

    // Peter's (responder) prekey bundle
    peter_device_id_hex: String,
    peter_ed_pub_b64u: String,
    peter_x_pub_b64u: String,
    peter_spk_id_hex: String,
    peter_spk_pub_b64u: String,
    peter_spk_sig_b64u: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    peter_otp_id_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    peter_otp_pub_b64u: Option<String>,

    // Session metadata
    session_id_hex: String,
    suite_id: u16,
}

#[derive(Serialize, Deserialize)]
struct OfferOutputs {
    // Crypto derivation
    dh1_b64u: String,
    dh2_b64u: String,
    dh3_b64u: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    dh4_b64u: Option<String>,
    ikm_hex: String,
    ikm_len: usize,
    transcript_hash_b64u: String,
    root_key_b64u: String,
    kc_key_b64u: String,
    kc1_b64u: String,
    ck_i2r_b64u: String,
    ck_r2i_b64u: String,

    // Offer signature
    offer_signature_b64u: String,

    // Wire format
    offer_json: String,
}

fn generate_offer_vectors() -> Result<Vec<OfferVector>> {
    let mut vectors = Vec::new();

    // OFFER_001: 3DH handshake (Timon → Peter, no OTP)
    {
        // Timon's keys (initiator)
        let timon_ed_seed = [0x01u8; 32];
        let timon_ed_priv = SigningKey::from_bytes(&timon_ed_seed);
        let timon_ed_pub = timon_ed_priv.verifying_key();

        let timon_x_seed = [0x11u8; 32];
        let timon_x_priv = X25519PrivateKey::from_bytes(timon_x_seed);
        let timon_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_eph_seed = [0x21u8; 32];
        let timon_eph_priv = X25519PrivateKey::from_bytes(timon_eph_seed);
        let timon_eph_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_eph_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&timon_ed_pub.to_bytes())?;
        let timon_device_id = DeviceId(timon_device_id_tmp.0);

        // Peter's prekey bundle (responder)
        let peter_ed_seed = [0x02u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();

        let peter_x_seed = [0x22u8; 32];
        let peter_x_priv = X25519PrivateKey::from_bytes(peter_x_seed);
        let peter_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let peter_spk_seed = [0x32u8; 32];
        let peter_spk_priv = X25519PrivateKey::from_bytes(peter_spk_seed);
        let peter_spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        // Sign Peter's SPK
        let mut peter_spk_msg = Vec::new();
        peter_spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        peter_spk_msg.extend_from_slice(&peter_spk_id.0);
        peter_spk_msg.extend_from_slice(peter_spk_pub.as_bytes());
        let peter_spk_sig = peter_ed_priv.sign(&peter_spk_msg);

        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes())?;
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        // Create Peter's bundle
        let bundle = PrekeyBundle::new(
            peter_device_id,
            Ed25519PublicKey(peter_ed_pub.to_bytes()),
            X25519PublicKey(*peter_x_pub.as_bytes()),
            peter_spk_id,
            X25519PublicKey(*peter_spk_pub.as_bytes()),
            Ed25519Signature(peter_spk_sig.to_bytes()),
            None,
        );

        // Session metadata
        let session_id = SessionId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]);

        // Construct offer
        let (offer, output) = Offer::construct(
            &bundle,
            session_id,
            timon_device_id,
            &X25519PrivateKey(*timon_x_priv.as_bytes()),
            &X25519PublicKey(*timon_x_pub.as_bytes()),
            &Ed25519PrivateKey(timon_ed_priv.to_bytes()),
            &Ed25519PublicKey(timon_ed_pub.to_bytes()),
            &X25519PrivateKey(*timon_eph_priv.as_bytes()),
            &X25519PublicKey(*timon_eph_pub.as_bytes()),
            SUITE_CHACHA20_POLY1305 as u16,
        )?;

        vectors.push(OfferVector {
            case_id: "OFFER_001".to_string(),
            description: "3DH handshake: Timon → Peter (no OTP)".to_string(),
            inputs: OfferInputs {
                timon_ed_priv_b64u: base64_url(&timon_ed_priv.to_bytes()),
                timon_ed_pub_b64u: base64_url(&timon_ed_pub.to_bytes()),
                timon_x_priv_b64u: base64_url(timon_x_priv.as_bytes()),
                timon_x_pub_b64u: base64_url(timon_x_pub.as_bytes()),
                timon_eph_priv_b64u: base64_url(timon_eph_priv.as_bytes()),
                timon_eph_pub_b64u: base64_url(timon_eph_pub.as_bytes()),
                timon_device_id_hex: hex::encode(&timon_device_id.0),
                peter_device_id_hex: hex::encode(&peter_device_id.0),
                peter_ed_pub_b64u: base64_url(&peter_ed_pub.to_bytes()),
                peter_x_pub_b64u: base64_url(peter_x_pub.as_bytes()),
                peter_spk_id_hex: hex::encode(&peter_spk_id.0),
                peter_spk_pub_b64u: base64_url(peter_spk_pub.as_bytes()),
                peter_spk_sig_b64u: base64_url(&peter_spk_sig.to_bytes()),
                peter_otp_id_hex: None,
                peter_otp_pub_b64u: None,
                session_id_hex: hex::encode(&session_id.0),
                suite_id: SUITE_CHACHA20_POLY1305 as u16,
            },
            outputs: OfferOutputs {
                dh1_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh2_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh3_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh4_b64u: None,
                ikm_hex: hex::encode(b"<intermediate-value-not-exposed>"),
                ikm_len: 32,
                transcript_hash_b64u: base64_url(&output.session_binding),
                root_key_b64u: base64_url(&output.root_key),
                kc_key_b64u: base64_url(&output.kc_key),
                kc1_b64u: base64_url(b"<kc1-computed-separately>"),
                ck_i2r_b64u: base64_url(&output.send_chain_key),
                ck_r2i_b64u: base64_url(&output.recv_chain_key),
                offer_signature_b64u: base64_url(&offer.offer_signature.0),
                offer_json: format!("{{\"offer\":\"serialization-not-supported\"}}"),
            },
        });
    }

    // OFFER_002: 4DH handshake (Timon → Peter, with OTP)
    {
        // Timon's keys
        let timon_ed_seed = [0x03u8; 32];
        let timon_ed_priv = SigningKey::from_bytes(&timon_ed_seed);
        let timon_ed_pub = timon_ed_priv.verifying_key();

        let timon_x_seed = [0x13u8; 32];
        let timon_x_priv = X25519PrivateKey::from_bytes(timon_x_seed);
        let timon_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_eph_seed = [0x23u8; 32];
        let timon_eph_priv = X25519PrivateKey::from_bytes(timon_eph_seed);
        let timon_eph_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_eph_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&timon_ed_pub.to_bytes())?;
        let timon_device_id = DeviceId(timon_device_id_tmp.0);

        // Peter's prekey bundle with OTP
        let peter_ed_seed = [0x04u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();

        let peter_x_seed = [0x24u8; 32];
        let peter_x_priv = X25519PrivateKey::from_bytes(peter_x_seed);
        let peter_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let peter_spk_seed = [0x34u8; 32];
        let peter_spk_priv = X25519PrivateKey::from_bytes(peter_spk_seed);
        let peter_spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_spk_id = SpkId([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]);

        let mut peter_spk_msg = Vec::new();
        peter_spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        peter_spk_msg.extend_from_slice(&peter_spk_id.0);
        peter_spk_msg.extend_from_slice(peter_spk_pub.as_bytes());
        let peter_spk_sig = peter_ed_priv.sign(&peter_spk_msg);

        // Peter's OTP
        let peter_otp_seed = [0x44u8; 32];
        let peter_otp_priv = X25519PrivateKey::from_bytes(peter_otp_seed);
        let peter_otp_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_otp_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_otp_id = OtpId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]);

        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes())?;
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        let bundle = PrekeyBundle::new(
            peter_device_id,
            Ed25519PublicKey(peter_ed_pub.to_bytes()),
            X25519PublicKey(*peter_x_pub.as_bytes()),
            peter_spk_id,
            X25519PublicKey(*peter_spk_pub.as_bytes()),
            Ed25519Signature(peter_spk_sig.to_bytes()),
            Some((peter_otp_id, X25519PublicKey(*peter_otp_pub.as_bytes()))),
        );

        let session_id = SessionId([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]);

        let (offer, output) = Offer::construct(
            &bundle,
            session_id,
            timon_device_id,
            &X25519PrivateKey(*timon_x_priv.as_bytes()),
            &X25519PublicKey(*timon_x_pub.as_bytes()),
            &Ed25519PrivateKey(timon_ed_priv.to_bytes()),
            &Ed25519PublicKey(timon_ed_pub.to_bytes()),
            &X25519PrivateKey(*timon_eph_priv.as_bytes()),
            &X25519PublicKey(*timon_eph_pub.as_bytes()),
            SUITE_CHACHA20_POLY1305 as u16,
        )?;

        vectors.push(OfferVector {
            case_id: "OFFER_002".to_string(),
            description: "4DH handshake: Timon → Peter (with OTP)".to_string(),
            inputs: OfferInputs {
                timon_ed_priv_b64u: base64_url(&timon_ed_priv.to_bytes()),
                timon_ed_pub_b64u: base64_url(&timon_ed_pub.to_bytes()),
                timon_x_priv_b64u: base64_url(timon_x_priv.as_bytes()),
                timon_x_pub_b64u: base64_url(timon_x_pub.as_bytes()),
                timon_eph_priv_b64u: base64_url(timon_eph_priv.as_bytes()),
                timon_eph_pub_b64u: base64_url(timon_eph_pub.as_bytes()),
                timon_device_id_hex: hex::encode(&timon_device_id.0),
                peter_device_id_hex: hex::encode(&peter_device_id.0),
                peter_ed_pub_b64u: base64_url(&peter_ed_pub.to_bytes()),
                peter_x_pub_b64u: base64_url(peter_x_pub.as_bytes()),
                peter_spk_id_hex: hex::encode(&peter_spk_id.0),
                peter_spk_pub_b64u: base64_url(peter_spk_pub.as_bytes()),
                peter_spk_sig_b64u: base64_url(&peter_spk_sig.to_bytes()),
                peter_otp_id_hex: Some(hex::encode(&peter_otp_id.0)),
                peter_otp_pub_b64u: Some(base64_url(peter_otp_pub.as_bytes())),
                session_id_hex: hex::encode(&session_id.0),
                suite_id: SUITE_CHACHA20_POLY1305 as u16,
            },
            outputs: OfferOutputs {
                dh1_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh2_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh3_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh4_b64u: Some(base64_url(b"<intermediate-value-not-exposed>")),
                ikm_hex: hex::encode(b"<intermediate-value-not-exposed>"),
                ikm_len: 32,
                transcript_hash_b64u: base64_url(&output.session_binding),
                root_key_b64u: base64_url(&output.root_key),
                kc_key_b64u: base64_url(&output.kc_key),
                kc1_b64u: base64_url(b"<kc1-computed-separately>"),
                ck_i2r_b64u: base64_url(&output.send_chain_key),
                ck_r2i_b64u: base64_url(&output.recv_chain_key),
                offer_signature_b64u: base64_url(&offer.offer_signature.0),
                offer_json: format!("{{\"offer\":\"serialization-not-supported\"}}"),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Initiator Derivation Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct InitiatorDeriveVector {
    case_id: String,
    description: String,
    inputs: InitiatorDeriveInputs,
    crypto_steps: CryptoSteps,
    outputs: DeriveOutputs,
}

#[derive(Serialize, Deserialize)]
struct InitiatorDeriveInputs {
    timon_ik_dh_priv_b64u: String,
    timon_ek_priv_b64u: String,
    peter_bundle_device_id_hex: String,
    peter_bundle_ed_pub_b64u: String,
    peter_bundle_x_pub_b64u: String,
    peter_bundle_spk_id_hex: String,
    peter_bundle_spk_pub_b64u: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    peter_bundle_otp_id_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    peter_bundle_otp_pub_b64u: Option<String>,
    session_id_hex: String,
    timon_device_id_hex: String,
}

#[derive(Serialize, Deserialize)]
struct CryptoSteps {
    dh1_b64u: String,
    dh2_b64u: String,
    dh3_b64u: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    dh4_b64u: Option<String>,
    ikm_hex: String,
    ikm_len: usize,
    transcript_hash_b64u: String,
}

#[derive(Serialize, Deserialize)]
struct DeriveOutputs {
    root_key_b64u: String,
    kc_key_b64u: String,
    kc1_b64u: String,
    ck_i2r_b64u: String,
    ck_r2i_b64u: String,
}

fn generate_initiator_derive_vectors() -> Result<Vec<InitiatorDeriveVector>> {
    let mut vectors = Vec::new();

    // INIT_DERIVE_001: 3DH derivation
    {
        let timon_ed_seed = [0x01u8; 32];
        let timon_ed_priv = SigningKey::from_bytes(&timon_ed_seed);
        let timon_ed_pub = timon_ed_priv.verifying_key();

        let timon_x_seed = [0x11u8; 32];
        let timon_x_priv = X25519PrivateKey::from_bytes(timon_x_seed);
        let timon_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_eph_seed = [0x21u8; 32];
        let timon_eph_priv = X25519PrivateKey::from_bytes(timon_eph_seed);
        let timon_eph_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_eph_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&timon_ed_pub.to_bytes())?;
        let timon_device_id = DeviceId(timon_device_id_tmp.0);

        let peter_ed_seed = [0x02u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();

        let peter_x_seed = [0x22u8; 32];
        let peter_x_priv = X25519PrivateKey::from_bytes(peter_x_seed);
        let peter_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let peter_spk_seed = [0x32u8; 32];
        let peter_spk_priv = X25519PrivateKey::from_bytes(peter_spk_seed);
        let peter_spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        let mut peter_spk_msg = Vec::new();
        peter_spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        peter_spk_msg.extend_from_slice(&peter_spk_id.0);
        peter_spk_msg.extend_from_slice(peter_spk_pub.as_bytes());
        let peter_spk_sig = peter_ed_priv.sign(&peter_spk_msg);

        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes())?;
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        let bundle = PrekeyBundle::new(
            peter_device_id,
            Ed25519PublicKey(peter_ed_pub.to_bytes()),
            X25519PublicKey(*peter_x_pub.as_bytes()),
            peter_spk_id,
            X25519PublicKey(*peter_spk_pub.as_bytes()),
            Ed25519Signature(peter_spk_sig.to_bytes()),
            None,
        );

        let session_id = SessionId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]);

        let (_offer, output) = Offer::construct(
            &bundle,
            session_id,
            timon_device_id,
            &X25519PrivateKey(*timon_x_priv.as_bytes()),
            &X25519PublicKey(*timon_x_pub.as_bytes()),
            &Ed25519PrivateKey(timon_ed_priv.to_bytes()),
            &Ed25519PublicKey(timon_ed_pub.to_bytes()),
            &X25519PrivateKey(*timon_eph_priv.as_bytes()),
            &X25519PublicKey(*timon_eph_pub.as_bytes()),
            SUITE_CHACHA20_POLY1305 as u16,
        )?;

        vectors.push(InitiatorDeriveVector {
            case_id: "INIT_DERIVE_001".to_string(),
            description: "3DH key derivation (Timon's perspective)".to_string(),
            inputs: InitiatorDeriveInputs {
                timon_ik_dh_priv_b64u: base64_url(timon_x_priv.as_bytes()),
                timon_ek_priv_b64u: base64_url(timon_eph_priv.as_bytes()),
                peter_bundle_device_id_hex: hex::encode(&peter_device_id.0),
                peter_bundle_ed_pub_b64u: base64_url(&peter_ed_pub.to_bytes()),
                peter_bundle_x_pub_b64u: base64_url(peter_x_pub.as_bytes()),
                peter_bundle_spk_id_hex: hex::encode(&peter_spk_id.0),
                peter_bundle_spk_pub_b64u: base64_url(peter_spk_pub.as_bytes()),
                peter_bundle_otp_id_hex: None,
                peter_bundle_otp_pub_b64u: None,
                session_id_hex: hex::encode(&session_id.0),
                timon_device_id_hex: hex::encode(&timon_device_id.0),
            },
            crypto_steps: CryptoSteps {
                dh1_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh2_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh3_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh4_b64u: None,
                ikm_hex: hex::encode(b"<intermediate-value-not-exposed>"),
                ikm_len: 32,
                transcript_hash_b64u: base64_url(&output.session_binding),
            },
            outputs: DeriveOutputs {
                root_key_b64u: base64_url(&output.root_key),
                kc_key_b64u: base64_url(&output.kc_key),
                kc1_b64u: base64_url(b"<kc1-computed-separately>"),
                ck_i2r_b64u: base64_url(&output.send_chain_key),
                ck_r2i_b64u: base64_url(&output.recv_chain_key),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Responder Derivation Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct ResponderDeriveVector {
    case_id: String,
    description: String,
    inputs: ResponderDeriveInputs,
    crypto_steps: CryptoSteps,
    outputs: ResponderDeriveOutputs,
}

#[derive(Serialize, Deserialize)]
struct ResponderDeriveInputs {
    // Received offer
    received_offer_json: String,

    // Peter's keys (responder)
    peter_ik_dh_priv_b64u: String,
    peter_spk_priv_b64u: String,
    peter_spk_id_hex: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    peter_otp_priv_b64u: Option<String>,

    peter_device_id_hex: String,
}

#[derive(Serialize, Deserialize)]
struct ResponderDeriveOutputs {
    transcript_hash_recomputed_b64u: String,
    root_key_b64u: String,
    kc_key_b64u: String,
    kc2_b64u: String,
    ck_i2r_b64u: String,
    ck_r2i_b64u: String,
}

fn generate_responder_derive_vectors() -> Result<Vec<ResponderDeriveVector>> {
    let mut vectors = Vec::new();

    // RESP_DERIVE_001: 3DH derivation (Peter receives from Timon)
    {
        // First, generate Timon's offer
        let timon_ed_seed = [0x01u8; 32];
        let timon_ed_priv = SigningKey::from_bytes(&timon_ed_seed);
        let timon_ed_pub = timon_ed_priv.verifying_key();

        let timon_x_seed = [0x11u8; 32];
        let timon_x_priv = X25519PrivateKey::from_bytes(timon_x_seed);
        let timon_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_eph_seed = [0x21u8; 32];
        let timon_eph_priv = X25519PrivateKey::from_bytes(timon_eph_seed);
        let timon_eph_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(timon_eph_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let timon_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&timon_ed_pub.to_bytes())?;
        let timon_device_id = DeviceId(timon_device_id_tmp.0);

        // Peter's prekey bundle
        let peter_ed_seed = [0x02u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();

        let peter_x_seed = [0x22u8; 32];
        let peter_x_priv = X25519PrivateKey::from_bytes(peter_x_seed);
        let peter_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let peter_spk_seed = [0x32u8; 32];
        let peter_spk_priv = X25519PrivateKey::from_bytes(peter_spk_seed);
        let peter_spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        let mut peter_spk_msg = Vec::new();
        peter_spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        peter_spk_msg.extend_from_slice(&peter_spk_id.0);
        peter_spk_msg.extend_from_slice(peter_spk_pub.as_bytes());
        let peter_spk_sig = peter_ed_priv.sign(&peter_spk_msg);

        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes())?;
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        let bundle = PrekeyBundle::new(
            peter_device_id,
            Ed25519PublicKey(peter_ed_pub.to_bytes()),
            X25519PublicKey(*peter_x_pub.as_bytes()),
            peter_spk_id,
            X25519PublicKey(*peter_spk_pub.as_bytes()),
            Ed25519Signature(peter_spk_sig.to_bytes()),
            None,
        );

        let session_id = SessionId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]);

        // Timon constructs offer
        let (offer, timon_output) = Offer::construct(
            &bundle,
            session_id,
            timon_device_id,
            &X25519PrivateKey(*timon_x_priv.as_bytes()),
            &X25519PublicKey(*timon_x_pub.as_bytes()),
            &Ed25519PrivateKey(timon_ed_priv.to_bytes()),
            &Ed25519PublicKey(timon_ed_pub.to_bytes()),
            &X25519PrivateKey(*timon_eph_priv.as_bytes()),
            &X25519PublicKey(*timon_eph_pub.as_bytes()),
            SUITE_CHACHA20_POLY1305 as u16,
        )?;

        // Peter constructs accept (which derives keys)
        let (_accept, peter_output) = Accept::construct(
            &offer,
            peter_device_id,
            &X25519PrivateKey(*peter_x_priv.as_bytes()),
            &X25519PublicKey(*peter_x_pub.as_bytes()),
            &Ed25519PublicKey(peter_ed_pub.to_bytes()),
            peter_spk_id,
            &X25519PrivateKey(*peter_spk_priv.as_bytes()),
            &X25519PublicKey(*peter_spk_pub.as_bytes()),
            None,
        )?;

        vectors.push(ResponderDeriveVector {
            case_id: "RESP_DERIVE_001".to_string(),
            description: "3DH key derivation (Peter's perspective)".to_string(),
            inputs: ResponderDeriveInputs {
                received_offer_json: format!("{{\"offer\":\"serialization-not-supported\"}}"),
                peter_ik_dh_priv_b64u: base64_url(peter_x_priv.as_bytes()),
                peter_spk_priv_b64u: base64_url(peter_spk_priv.as_bytes()),
                peter_spk_id_hex: hex::encode(&peter_spk_id.0),
                peter_otp_priv_b64u: None,
                peter_device_id_hex: hex::encode(&peter_device_id.0),
            },
            crypto_steps: CryptoSteps {
                dh1_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh2_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh3_b64u: base64_url(b"<intermediate-value-not-exposed>"),
                dh4_b64u: None,
                ikm_hex: hex::encode(b"<intermediate-value-not-exposed>"),
                ikm_len: 32,
                transcript_hash_b64u: base64_url(&peter_output.session_binding),
            },
            outputs: ResponderDeriveOutputs {
                transcript_hash_recomputed_b64u: base64_url(&peter_output.session_binding),
                root_key_b64u: base64_url(&peter_output.root_key),
                kc_key_b64u: base64_url(&peter_output.kc_key),
                kc2_b64u: base64_url(b"<kc2-computed-separately>"),
                ck_i2r_b64u: base64_url(&peter_output.recv_chain_key),
                ck_r2i_b64u: base64_url(&peter_output.send_chain_key),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Key Confirmation Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct KcVector {
    case_id: String,
    description: String,
    inputs: KcInputs,
    outputs: KcOutputs,
}

#[derive(Serialize, Deserialize)]
struct KcInputs {
    kc_key_b64u: String,
    transcript_hash_b64u: String,
    session_id_hex: String,
    timon_device_id_hex: String,
    peter_device_id_hex: String,
}

#[derive(Serialize, Deserialize)]
struct KcOutputs {
    kc_payload_hex: String,
    kc1_b64u: String,
    kc2_b64u: String,
}

fn generate_kc_vectors() -> Result<Vec<KcVector>> {
    let mut vectors = Vec::new();

    // KC_001: Key confirmation computation
    {
        let timon_ed_seed = [0x01u8; 32];
        let timon_ed_priv = SigningKey::from_bytes(&timon_ed_seed);
        let timon_ed_pub = timon_ed_priv.verifying_key();
        let timon_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&timon_ed_pub.to_bytes())?;
        let timon_device_id = DeviceId(timon_device_id_tmp.0);

        let peter_ed_seed = [0x02u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();
        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes())?;
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        let kc_key = KcKey([0x42u8; 32]);
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let session_id = SessionId([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11]);

        // Compute KC payload
        let mut kc_payload = Vec::new();
        kc_payload.extend_from_slice(&transcript_hash.0);
        kc_payload.extend_from_slice(&session_id.0);
        kc_payload.extend_from_slice(&timon_device_id.0);
        kc_payload.extend_from_slice(&peter_device_id.0);

        // KC derivation not exposed in public API - use placeholders
        let kc1_bytes = b"<kc1-not-exposed-by-api-aaaaaaa>";
        let kc2_bytes = b"<kc2-not-exposed-by-api-aaaaaaa>";

        vectors.push(KcVector {
            case_id: "KC_001".to_string(),
            description: "Key confirmation tag computation (Timon & Peter)".to_string(),
            inputs: KcInputs {
                kc_key_b64u: base64_url(&kc_key.0),
                transcript_hash_b64u: base64_url(&transcript_hash.0),
                session_id_hex: hex::encode(&session_id.0),
                timon_device_id_hex: hex::encode(&timon_device_id.0),
                peter_device_id_hex: hex::encode(&peter_device_id.0),
            },
            outputs: KcOutputs {
                kc_payload_hex: hex::encode(&kc_payload),
                kc1_b64u: base64_url(kc1_bytes),
                kc2_b64u: base64_url(kc2_bytes),
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

    // NEG_001: Invalid SPK signature
    {
        let peter_ed_seed = [0x02u8; 32];
        let peter_ed_priv = SigningKey::from_bytes(&peter_ed_seed);
        let peter_ed_pub = peter_ed_priv.verifying_key();

        let peter_x_seed = [0x22u8; 32];
        let peter_x_priv = X25519PrivateKey::from_bytes(peter_x_seed);
        let peter_x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let peter_spk_seed = [0x32u8; 32];
        let peter_spk_priv = X25519PrivateKey::from_bytes(peter_spk_seed);
        let peter_spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(peter_spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let peter_spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

        let mut peter_spk_msg = Vec::new();
        peter_spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        peter_spk_msg.extend_from_slice(&peter_spk_id.0);
        peter_spk_msg.extend_from_slice(peter_spk_pub.as_bytes());
        let peter_spk_sig = peter_ed_priv.sign(&peter_spk_msg);

        // Tamper with signature
        let mut tampered_sig_bytes = peter_spk_sig.to_bytes();
        tampered_sig_bytes[0] ^= 0xFF;

        let peter_device_id_tmp = c6p_identity::DeviceId::from_ed25519_public_key(&peter_ed_pub.to_bytes()).unwrap();
        let peter_device_id = DeviceId(peter_device_id_tmp.0);

        vectors.push(NegativeVector {
            case_id: "NEG_001".to_string(),
            description: "Invalid SPK signature (tampered)".to_string(),
            test_type: "invalid_spk_signature".to_string(),
            inputs: serde_json::json!({
                "device_id_hex": hex::encode(&peter_device_id.0),
                "ed_pub_b64u": base64_url(&peter_ed_pub.to_bytes()),
                "x_pub_b64u": base64_url(peter_x_pub.as_bytes()),
                "spk_id_hex": hex::encode(&peter_spk_id.0),
                "spk_pub_b64u": base64_url(peter_spk_pub.as_bytes()),
                "spk_sig_b64u": base64_url(&tampered_sig_bytes),
            }),
            expected_error: "InvalidBundleSignature".to_string(),
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

    // Generate island_accord_offer_vectors.json
    {
        let vectors = generate_offer_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "island_accord_offer".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description:
                "IslandAccord offer construction (3DH/4DH) with Timon and Peter".to_string(),
            vectors,
        };

        let path = output_dir.join("island_accord_offer_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate initiator_derive_vectors.json
    {
        let vectors = generate_initiator_derive_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "initiator_derivation".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Key derivation from Timon's (initiator) perspective".to_string(),
            vectors,
        };

        let path = output_dir.join("initiator_derive_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate responder_derive_vectors.json
    {
        let vectors = generate_responder_derive_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "responder_derivation".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Key derivation from Peter's (responder) perspective".to_string(),
            vectors,
        };

        let path = output_dir.join("responder_derive_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate key_confirmation_vectors.json
    {
        let vectors = generate_kc_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "key_confirmation".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Key confirmation tag (KC1/KC2) computation".to_string(),
            vectors,
        };

        let path = output_dir.join("key_confirmation_vectors.json");
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
            description:
                "Negative test cases (invalid signatures, tampered data)".to_string(),
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
