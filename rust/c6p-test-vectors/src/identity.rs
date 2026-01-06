//! Identity Test Vector Generation
//!
//! Generates deterministic test vectors for C6P identity module.
//! Uses deterministic keys derived from fixed seeds for reproducibility.

use anyhow::Result;
use c6p_identity::{DeviceId, Fingerprint};
use c6p_handshake::{X25519PublicKey, X25519PrivateKey};
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
// Device ID Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct DeviceIdVector {
    case_id: String,
    description: String,
    inputs: DeviceIdInputs,
    outputs: DeviceIdOutputs,
}

#[derive(Serialize, Deserialize)]
struct DeviceIdInputs {
    ed25519_public_key_b64u: String,
    ed25519_public_key_hex: String,
}

#[derive(Serialize, Deserialize)]
struct DeviceIdOutputs {
    device_id_hex: String,
    device_id_len: usize,
}

fn generate_device_id_vectors() -> Result<Vec<DeviceIdVector>> {
    let mut vectors = Vec::new();

    // DEVICE_ID_001: Timon's device (deterministic seed 0x01)
    {
        let seed = [0x01u8; 32];
        let signing_key = SigningKey::from_bytes(&seed);
        let public_key = signing_key.verifying_key();
        let public_key_bytes = public_key.to_bytes();

        let device_id = DeviceId::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(DeviceIdVector {
            case_id: "DEVICE_ID_001".to_string(),
            description: "Device ID for Timon (deterministic seed 0x01)".to_string(),
            inputs: DeviceIdInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: DeviceIdOutputs {
                device_id_hex: device_id.to_hex(),
                device_id_len: 16,
            },
        });
    }

    // DEVICE_ID_002: Peter's device (deterministic seed 0x02)
    {
        let seed = [0x02u8; 32];
        let signing_key = SigningKey::from_bytes(&seed);
        let public_key = signing_key.verifying_key();
        let public_key_bytes = public_key.to_bytes();

        let device_id = DeviceId::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(DeviceIdVector {
            case_id: "DEVICE_ID_002".to_string(),
            description: "Device ID for Peter (deterministic seed 0x02)".to_string(),
            inputs: DeviceIdInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: DeviceIdOutputs {
                device_id_hex: device_id.to_hex(),
                device_id_len: 16,
            },
        });
    }

    // DEVICE_ID_003: All-zeros key (edge case)
    {
        // Note: All-zeros is not a valid Ed25519 key, but we can still derive a device ID
        let public_key_bytes = [0x00u8; 32];
        let device_id = DeviceId::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(DeviceIdVector {
            case_id: "DEVICE_ID_003".to_string(),
            description: "Device ID for all-zeros public key (edge case)".to_string(),
            inputs: DeviceIdInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: DeviceIdOutputs {
                device_id_hex: device_id.to_hex(),
                device_id_len: 16,
            },
        });
    }

    // DEVICE_ID_004: All-ones key (edge case)
    {
        let public_key_bytes = [0xFFu8; 32];
        let device_id = DeviceId::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(DeviceIdVector {
            case_id: "DEVICE_ID_004".to_string(),
            description: "Device ID for all-ones public key (edge case)".to_string(),
            inputs: DeviceIdInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: DeviceIdOutputs {
                device_id_hex: device_id.to_hex(),
                device_id_len: 16,
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Fingerprint Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct FingerprintVector {
    case_id: String,
    description: String,
    inputs: FingerprintInputs,
    outputs: FingerprintOutputs,
}

#[derive(Serialize, Deserialize)]
struct FingerprintInputs {
    ed25519_public_key_b64u: String,
    ed25519_public_key_hex: String,
}

#[derive(Serialize, Deserialize)]
struct FingerprintOutputs {
    fingerprint_b64u: String,
    fingerprint_hex: String,
    fingerprint_short_hex: String,
    fingerprint_formatted: String,
    fingerprint_len: usize,
}

fn generate_fingerprint_vectors() -> Result<Vec<FingerprintVector>> {
    let mut vectors = Vec::new();

    // FINGERPRINT_001: Timon's fingerprint
    {
        let seed = [0x01u8; 32];
        let signing_key = SigningKey::from_bytes(&seed);
        let public_key = signing_key.verifying_key();
        let public_key_bytes = public_key.to_bytes();

        let fingerprint = Fingerprint::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(FingerprintVector {
            case_id: "FINGERPRINT_001".to_string(),
            description: "Fingerprint for Timon (all formats)".to_string(),
            inputs: FingerprintInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: FingerprintOutputs {
                fingerprint_b64u: fingerprint.to_base64url(),
                fingerprint_hex: fingerprint.to_hex(),
                fingerprint_short_hex: fingerprint.short_hex(),
                fingerprint_formatted: fingerprint.formatted(),
                fingerprint_len: 32,
            },
        });
    }

    // FINGERPRINT_002: Peter's fingerprint
    {
        let seed = [0x02u8; 32];
        let signing_key = SigningKey::from_bytes(&seed);
        let public_key = signing_key.verifying_key();
        let public_key_bytes = public_key.to_bytes();

        let fingerprint = Fingerprint::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(FingerprintVector {
            case_id: "FINGERPRINT_002".to_string(),
            description: "Fingerprint for Peter (all formats)".to_string(),
            inputs: FingerprintInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: FingerprintOutputs {
                fingerprint_b64u: fingerprint.to_base64url(),
                fingerprint_hex: fingerprint.to_hex(),
                fingerprint_short_hex: fingerprint.short_hex(),
                fingerprint_formatted: fingerprint.formatted(),
                fingerprint_len: 32,
            },
        });
    }

    // FINGERPRINT_003: Edge case (all zeros)
    {
        let public_key_bytes = [0x00u8; 32];
        let fingerprint = Fingerprint::from_ed25519_public_key(&public_key_bytes)?;

        vectors.push(FingerprintVector {
            case_id: "FINGERPRINT_003".to_string(),
            description: "Fingerprint for all-zeros key (edge case)".to_string(),
            inputs: FingerprintInputs {
                ed25519_public_key_b64u: base64_url(&public_key_bytes),
                ed25519_public_key_hex: hex::encode(&public_key_bytes),
            },
            outputs: FingerprintOutputs {
                fingerprint_b64u: fingerprint.to_base64url(),
                fingerprint_hex: fingerprint.to_hex(),
                fingerprint_short_hex: fingerprint.short_hex(),
                fingerprint_formatted: fingerprint.formatted(),
                fingerprint_len: 32,
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Signed Prekey Signature Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct SpkSigVector {
    case_id: String,
    description: String,
    inputs: SpkSigInputs,
    outputs: SpkSigOutputs,
}

#[derive(Serialize, Deserialize)]
struct SpkSigInputs {
    ik_sig_priv_b64u: String,
    ik_sig_pub_b64u: String,
    spk_id_hex: String,
    spk_pub_b64u: String,
}

#[derive(Serialize, Deserialize)]
struct SpkSigOutputs {
    message_to_sign_hex: String,
    message_to_sign_len: usize,
    spk_sig_b64u: String,
    verification_result: bool,
}

fn generate_spk_signature_vectors() -> Result<Vec<SpkSigVector>> {
    let mut vectors = Vec::new();

    // SPK_SIG_001: Timon's signed prekey
    {
        let ik_seed = [0x01u8; 32];
        let ik_signing_key = SigningKey::from_bytes(&ik_seed);
        let ik_verifying_key = ik_signing_key.verifying_key();

        let spk_seed = [0x11u8; 32];
        let spk_priv = X25519PrivateKey::from_bytes(spk_seed);
        let spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let spk_id = [0x01u8, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08];

        // Construct message to sign: "C6P_PREKEY_V1" || spk_id || spk_pub
        let mut message = Vec::new();
        message.extend_from_slice(b"C6P_PREKEY_V1");
        message.extend_from_slice(&spk_id);
        message.extend_from_slice(spk_pub.as_bytes());

        // Sign the message
        let signature = ik_signing_key.sign(&message);

        // Verify
        let verification_ok = ik_verifying_key.verify_strict(&message, &signature).is_ok();

        vectors.push(SpkSigVector {
            case_id: "SPK_SIG_001".to_string(),
            description: "Timon signs SPK (valid signature)".to_string(),
            inputs: SpkSigInputs {
                ik_sig_priv_b64u: base64_url(&ik_signing_key.to_bytes()),
                ik_sig_pub_b64u: base64_url(&ik_verifying_key.to_bytes()),
                spk_id_hex: hex::encode(&spk_id),
                spk_pub_b64u: base64_url(spk_pub.as_bytes()),
            },
            outputs: SpkSigOutputs {
                message_to_sign_hex: hex::encode(&message),
                message_to_sign_len: message.len(),
                spk_sig_b64u: base64_url(&signature.to_bytes()),
                verification_result: verification_ok,
            },
        });
    }

    // SPK_SIG_002: Peter's signed prekey
    {
        let ik_seed = [0x02u8; 32];
        let ik_signing_key = SigningKey::from_bytes(&ik_seed);
        let ik_verifying_key = ik_signing_key.verifying_key();

        let spk_seed = [0x22u8; 32];
        let spk_priv = X25519PrivateKey::from_bytes(spk_seed);
        let spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let spk_id = [0x11u8, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];

        let mut message = Vec::new();
        message.extend_from_slice(b"C6P_PREKEY_V1");
        message.extend_from_slice(&spk_id);
        message.extend_from_slice(spk_pub.as_bytes());

        let signature = ik_signing_key.sign(&message);
        let verification_ok = ik_verifying_key.verify_strict(&message, &signature).is_ok();

        vectors.push(SpkSigVector {
            case_id: "SPK_SIG_002".to_string(),
            description: "Peter signs SPK (valid signature)".to_string(),
            inputs: SpkSigInputs {
                ik_sig_priv_b64u: base64_url(&ik_signing_key.to_bytes()),
                ik_sig_pub_b64u: base64_url(&ik_verifying_key.to_bytes()),
                spk_id_hex: hex::encode(&spk_id),
                spk_pub_b64u: base64_url(spk_pub.as_bytes()),
            },
            outputs: SpkSigOutputs {
                message_to_sign_hex: hex::encode(&message),
                message_to_sign_len: message.len(),
                spk_sig_b64u: base64_url(&signature.to_bytes()),
                verification_result: verification_ok,
            },
        });
    }

    // SPK_SIG_003: Invalid signature (tampered)
    {
        let ik_seed = [0x03u8; 32];
        let ik_signing_key = SigningKey::from_bytes(&ik_seed);
        let ik_verifying_key = ik_signing_key.verifying_key();

        let spk_seed = [0x33u8; 32];
        let spk_priv = X25519PrivateKey::from_bytes(spk_seed);
        let spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let spk_id = [0xAAu8; 8];

        let mut message = Vec::new();
        message.extend_from_slice(b"C6P_PREKEY_V1");
        message.extend_from_slice(&spk_id);
        message.extend_from_slice(spk_pub.as_bytes());

        let signature = ik_signing_key.sign(&message);

        // Tamper with signature
        let mut tampered_sig_bytes = signature.to_bytes();
        tampered_sig_bytes[0] ^= 0xFF;

        // Try to verify tampered signature
        let tampered_sig = ed25519_dalek::Signature::from_bytes(&tampered_sig_bytes);
        let verification_ok = ik_verifying_key.verify_strict(&message, &tampered_sig).is_ok();

        vectors.push(SpkSigVector {
            case_id: "SPK_SIG_003".to_string(),
            description: "Tampered SPK signature (verification should fail)".to_string(),
            inputs: SpkSigInputs {
                ik_sig_priv_b64u: base64_url(&ik_signing_key.to_bytes()),
                ik_sig_pub_b64u: base64_url(&ik_verifying_key.to_bytes()),
                spk_id_hex: hex::encode(&spk_id),
                spk_pub_b64u: base64_url(spk_pub.as_bytes()),
            },
            outputs: SpkSigOutputs {
                message_to_sign_hex: hex::encode(&message),
                message_to_sign_len: message.len(),
                spk_sig_b64u: base64_url(&tampered_sig_bytes),
                verification_result: verification_ok,
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Identity Key Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct IdentityKeyVector {
    case_id: String,
    description: String,
    outputs: IdentityKeyOutputs,
}

#[derive(Serialize, Deserialize)]
struct IdentityKeyOutputs {
    ed25519_priv_b64u: String,
    ed25519_pub_b64u: String,
    ed25519_pub_hex: String,
    x25519_priv_b64u: String,
    x25519_pub_b64u: String,
    x25519_pub_hex: String,
    device_id_hex: String,
    fingerprint_b64u: String,
}

fn generate_identity_key_vectors() -> Result<Vec<IdentityKeyVector>> {
    let mut vectors = Vec::new();

    // IDENTITY_001: Timon's complete identity
    {
        let ed_seed = [0x01u8; 32];
        let ed_signing_key = SigningKey::from_bytes(&ed_seed);
        let ed_verifying_key = ed_signing_key.verifying_key();

        let x_seed = [0x11u8; 32];
        let x_priv = X25519PrivateKey::from_bytes(x_seed);
        let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let device_id = DeviceId::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;
        let fingerprint = Fingerprint::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;

        vectors.push(IdentityKeyVector {
            case_id: "IDENTITY_001".to_string(),
            description: "Timon's complete identity keys".to_string(),
            outputs: IdentityKeyOutputs {
                ed25519_priv_b64u: base64_url(&ed_signing_key.to_bytes()),
                ed25519_pub_b64u: base64_url(&ed_verifying_key.to_bytes()),
                ed25519_pub_hex: hex::encode(&ed_verifying_key.to_bytes()),
                x25519_priv_b64u: base64_url(x_priv.as_bytes()),
                x25519_pub_b64u: base64_url(x_pub.as_bytes()),
                x25519_pub_hex: hex::encode(x_pub.as_bytes()),
                device_id_hex: device_id.to_hex(),
                fingerprint_b64u: fingerprint.to_base64url(),
            },
        });
    }

    // IDENTITY_002: Peter's complete identity
    {
        let ed_seed = [0x02u8; 32];
        let ed_signing_key = SigningKey::from_bytes(&ed_seed);
        let ed_verifying_key = ed_signing_key.verifying_key();

        let x_seed = [0x22u8; 32];
        let x_priv = X25519PrivateKey::from_bytes(x_seed);
        let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let device_id = DeviceId::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;
        let fingerprint = Fingerprint::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;

        vectors.push(IdentityKeyVector {
            case_id: "IDENTITY_002".to_string(),
            description: "Peter's complete identity keys".to_string(),
            outputs: IdentityKeyOutputs {
                ed25519_priv_b64u: base64_url(&ed_signing_key.to_bytes()),
                ed25519_pub_b64u: base64_url(&ed_verifying_key.to_bytes()),
                ed25519_pub_hex: hex::encode(&ed_verifying_key.to_bytes()),
                x25519_priv_b64u: base64_url(x_priv.as_bytes()),
                x25519_pub_b64u: base64_url(x_pub.as_bytes()),
                x25519_pub_hex: hex::encode(x_pub.as_bytes()),
                device_id_hex: device_id.to_hex(),
                fingerprint_b64u: fingerprint.to_base64url(),
            },
        });
    }

    Ok(vectors)
}

// ============================================================================
// Prekey Bundle Payload Vectors
// ============================================================================

#[derive(Serialize, Deserialize)]
struct PrekeyPayloadVector {
    case_id: String,
    description: String,
    inputs: PrekeyPayloadInputs,
    outputs: PrekeyPayloadOutputs,
}

#[derive(Serialize, Deserialize)]
struct PrekeyPayloadInputs {
    device_id_hex: String,
    ed25519_pub_b64u: String,
    x25519_pub_b64u: String,
    spk_id_hex: String,
    spk_pub_b64u: String,
    spk_sig_b64u: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    otp_id_hex: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    otp_pub_b64u: Option<String>,
}

#[derive(Serialize, Deserialize)]
struct PrekeyPayloadOutputs {
    prekey_bundle_json: String,
    bundle_type: String,
}

fn generate_prekey_payload_vectors() -> Result<Vec<PrekeyPayloadVector>> {
    let mut vectors = Vec::new();

    // PREKEY_001: Timon's 3DH bundle (no OTP)
    {
        let ed_seed = [0x01u8; 32];
        let ed_signing_key = SigningKey::from_bytes(&ed_seed);
        let ed_verifying_key = ed_signing_key.verifying_key();

        let x_seed = [0x11u8; 32];
        let x_priv = X25519PrivateKey::from_bytes(x_seed);
        let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let spk_seed = [0x11u8; 32];
        let spk_priv = X25519PrivateKey::from_bytes(spk_seed);
        let spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let spk_id = [0x01u8, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08];

        let mut spk_message = Vec::new();
        spk_message.extend_from_slice(b"C6P_PREKEY_V1");
        spk_message.extend_from_slice(&spk_id);
        spk_message.extend_from_slice(spk_pub.as_bytes());
        let spk_sig = ed_signing_key.sign(&spk_message);

        let device_id = DeviceId::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;

        vectors.push(PrekeyPayloadVector {
            case_id: "PREKEY_001".to_string(),
            description: "Timon's 3DH prekey bundle (no OTP)".to_string(),
            inputs: PrekeyPayloadInputs {
                device_id_hex: device_id.to_hex(),
                ed25519_pub_b64u: base64_url(&ed_verifying_key.to_bytes()),
                x25519_pub_b64u: base64_url(x_pub.as_bytes()),
                spk_id_hex: hex::encode(&spk_id),
                spk_pub_b64u: base64_url(spk_pub.as_bytes()),
                spk_sig_b64u: base64_url(&spk_sig.to_bytes()),
                otp_id_hex: None,
                otp_pub_b64u: None,
            },
            outputs: PrekeyPayloadOutputs {
                prekey_bundle_json: format!(
                    r#"{{"deviceId":"{}","identityPubEd25519":"{}","identityPubX25519":"{}","spkId":"{}","spkPub":"{}","spkSig":"{}"}}"#,
                    device_id.to_hex(),
                    base64_url(&ed_verifying_key.to_bytes()),
                    base64_url(x_pub.as_bytes()),
                    hex::encode(&spk_id),
                    base64_url(spk_pub.as_bytes()),
                    base64_url(&spk_sig.to_bytes())
                ),
                bundle_type: "3DH".to_string(),
            },
        });
    }

    // PREKEY_002: Peter's 4DH bundle (with OTP)
    {
        let ed_seed = [0x02u8; 32];
        let ed_signing_key = SigningKey::from_bytes(&ed_seed);
        let ed_verifying_key = ed_signing_key.verifying_key();

        let x_seed = [0x22u8; 32];
        let x_priv = X25519PrivateKey::from_bytes(x_seed);
        let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(x_seed, x25519_dalek::X25519_BASEPOINT_BYTES));

        let spk_seed = [0x22u8; 32];
        let spk_priv = X25519PrivateKey::from_bytes(spk_seed);
        let spk_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(spk_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let spk_id = [0x11u8, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88];

        let mut spk_message = Vec::new();
        spk_message.extend_from_slice(b"C6P_PREKEY_V1");
        spk_message.extend_from_slice(&spk_id);
        spk_message.extend_from_slice(spk_pub.as_bytes());
        let spk_sig = ed_signing_key.sign(&spk_message);

        let otp_seed = [0x33u8; 32];
        let otp_priv = X25519PrivateKey::from_bytes(otp_seed);
        let otp_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(otp_seed, x25519_dalek::X25519_BASEPOINT_BYTES));
        let otp_id = [0xAAu8, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11];

        let device_id = DeviceId::from_ed25519_public_key(&ed_verifying_key.to_bytes())?;

        vectors.push(PrekeyPayloadVector {
            case_id: "PREKEY_002".to_string(),
            description: "Peter's 4DH prekey bundle (with OTP)".to_string(),
            inputs: PrekeyPayloadInputs {
                device_id_hex: device_id.to_hex(),
                ed25519_pub_b64u: base64_url(&ed_verifying_key.to_bytes()),
                x25519_pub_b64u: base64_url(x_pub.as_bytes()),
                spk_id_hex: hex::encode(&spk_id),
                spk_pub_b64u: base64_url(spk_pub.as_bytes()),
                spk_sig_b64u: base64_url(&spk_sig.to_bytes()),
                otp_id_hex: Some(hex::encode(&otp_id)),
                otp_pub_b64u: Some(base64_url(otp_pub.as_bytes())),
            },
            outputs: PrekeyPayloadOutputs {
                prekey_bundle_json: format!(
                    r#"{{"deviceId":"{}","identityPubEd25519":"{}","identityPubX25519":"{}","spkId":"{}","spkPub":"{}","spkSig":"{}","otpId":"{}","otpPub":"{}"}}"#,
                    device_id.to_hex(),
                    base64_url(&ed_verifying_key.to_bytes()),
                    base64_url(x_pub.as_bytes()),
                    hex::encode(&spk_id),
                    base64_url(spk_pub.as_bytes()),
                    base64_url(&spk_sig.to_bytes()),
                    hex::encode(&otp_id),
                    base64_url(otp_pub.as_bytes())
                ),
                bundle_type: "4DH".to_string(),
            },
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

    // Generate device_id_vectors.json
    {
        let vectors = generate_device_id_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "device_id".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Device ID derivation from Ed25519 public keys".to_string(),
            vectors,
        };

        let path = output_dir.join("device_id_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate fingerprint_vectors.json
    {
        let vectors = generate_fingerprint_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "fingerprint".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Human-readable fingerprint generation (multiple formats)".to_string(),
            vectors,
        };

        let path = output_dir.join("fingerprint_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate signed_prekey_sig_vectors.json
    {
        let vectors = generate_spk_signature_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "signed_prekey_sig".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Signed prekey signature creation and validation".to_string(),
            vectors,
        };

        let path = output_dir.join("signed_prekey_sig_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate identity_key_vectors.json
    {
        let vectors = generate_identity_key_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "identity_keys".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Complete identity key generation (Ed25519 + X25519 + Device ID + Fingerprint)".to_string(),
            vectors,
        };

        let path = output_dir.join("identity_key_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    // Generate prekeys_payload_vectors.json
    {
        let vectors = generate_prekey_payload_vectors()?;
        let file = TestVectorFile {
            version: "1.0".to_string(),
            module: "prekey_bundle".to_string(),
            generated_by: "rust-c6p-test-vectors v0.1.0".to_string(),
            generated_at: chrono::Utc::now().to_rfc3339(),
            description: "Prekey bundle JSON payloads (3DH and 4DH)".to_string(),
            vectors,
        };

        let path = output_dir.join("prekeys_payload_vectors.json");
        write_json_file(&path, &file, force)?;
        if verbose {
            println!("      Generated: {}", path.display());
        }
    }

    Ok(())
}
