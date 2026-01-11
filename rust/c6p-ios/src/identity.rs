//! Identity management functions for iOS bridge

use crate::error::{C6pError, Result};
use crate::types::{DeviceIdentity, OneTimePrekey, PrekeyBundle, SignedPrekey};
use c6p_identity::{DeviceId, Fingerprint};
use ed25519_dalek::{Signer, SigningKey, VerifyingKey};
use rand::rngs::OsRng;

/// Generate a new device identity
///
/// Creates a fresh Ed25519 + X25519 key pair and derives device ID and fingerprint.
///
/// # Returns
///
/// DeviceIdentity with:
/// - device_id (16 bytes)
/// - Ed25519 key pair (signing)
/// - X25519 key pair (DH)
/// - fingerprint (Base64URL string)
///
/// # Errors
///
/// Returns error if random number generation fails
pub fn generate_identity() -> Result<DeviceIdentity> {
    // Generate Ed25519 identity key pair
    let signing_key = SigningKey::generate(&mut OsRng);
    let verifying_key = signing_key.verifying_key();

    // Generate X25519 key pair for DH operations
    let mut x25519_priv_bytes = [0u8; 32];
    rand::RngCore::fill_bytes(&mut OsRng, &mut x25519_priv_bytes);
    let x25519_pub_bytes =
        x25519_dalek::x25519(x25519_priv_bytes, x25519_dalek::X25519_BASEPOINT_BYTES);

    // Derive device ID from Ed25519 public key
    let device_id = DeviceId::from_ed25519_public_key(verifying_key.as_bytes())?;

    // Derive human-readable fingerprint
    let fingerprint = Fingerprint::from_ed25519_public_key(verifying_key.as_bytes())?;

    Ok(DeviceIdentity {
        device_id: device_id.0.to_vec(),
        identity_priv_ed25519: signing_key.to_keypair_bytes().to_vec(),
        identity_pub_ed25519: verifying_key.as_bytes().to_vec(),
        identity_priv_x25519: x25519_priv_bytes.to_vec(),
        identity_pub_x25519: x25519_pub_bytes.to_vec(),
        fingerprint: fingerprint.to_base64url(),
    })
}

/// Generate a signed prekey
///
/// Creates a fresh X25519 key pair and signs it with the identity Ed25519 key.
///
/// # Arguments
///
/// * `identity` - Device identity containing Ed25519 signing key
///
/// # Returns
///
/// SignedPrekey with:
/// - spk_id (8 random bytes)
/// - X25519 key pair
/// - Ed25519 signature over SPK
///
/// # Errors
///
/// Returns error if signing fails or key parsing fails
pub fn generate_signed_prekey(identity: DeviceIdentity) -> Result<SignedPrekey> {
    // Generate fresh X25519 key pair for SPK
    let mut spk_priv_bytes = [0u8; 32];
    rand::RngCore::fill_bytes(&mut OsRng, &mut spk_priv_bytes);
    let spk_pub_bytes = x25519_dalek::x25519(spk_priv_bytes, x25519_dalek::X25519_BASEPOINT_BYTES);

    // Generate random SPK ID (8 bytes)
    let mut spk_id = [0u8; 8];
    rand::RngCore::fill_bytes(&mut OsRng, &mut spk_id);

    // Parse Ed25519 signing key
    let keypair_bytes: [u8; 64] = identity
        .identity_priv_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Invalid Ed25519 keypair length".to_string()))?;
    let signing_key = SigningKey::from_keypair_bytes(&keypair_bytes)
        .map_err(|e| C6pError::InvalidKey(format!("Invalid Ed25519 key: {}", e)))?;

    // Sign: "C6P_PREKEY_V1" || spkId(8) || spkPub(32)
    let label = b"C6P_PREKEY_V1";
    let mut msg = Vec::with_capacity(label.len() + 8 + 32);
    msg.extend_from_slice(label);
    msg.extend_from_slice(&spk_id);
    msg.extend_from_slice(&spk_pub_bytes);

    let signature = signing_key.sign(&msg);

    Ok(SignedPrekey {
        spk_id: spk_id.to_vec(),
        spk_priv: spk_priv_bytes.to_vec(),
        spk_pub: spk_pub_bytes.to_vec(),
        spk_sig: signature.to_bytes().to_vec(),
    })
}

/// Generate a one-time prekey
///
/// Creates a fresh X25519 key pair for one-time use in 4DH handshakes.
///
/// # Returns
///
/// OneTimePrekey with:
/// - otp_id (8 random bytes)
/// - X25519 key pair
///
/// # Errors
///
/// Returns error if random number generation fails
pub fn generate_one_time_prekey() -> Result<OneTimePrekey> {
    // Generate fresh X25519 key pair
    let mut otp_priv_bytes = [0u8; 32];
    rand::RngCore::fill_bytes(&mut OsRng, &mut otp_priv_bytes);
    let otp_pub_bytes = x25519_dalek::x25519(otp_priv_bytes, x25519_dalek::X25519_BASEPOINT_BYTES);

    // Generate random OTP ID (8 bytes)
    let mut otp_id = [0u8; 8];
    rand::RngCore::fill_bytes(&mut OsRng, &mut otp_id);

    Ok(OneTimePrekey {
        otp_id: otp_id.to_vec(),
        otp_priv: otp_priv_bytes.to_vec(),
        otp_pub: otp_pub_bytes.to_vec(),
    })
}

/// Compute device ID from Ed25519 public key
///
/// # Arguments
///
/// * `ed25519_pub` - Ed25519 public key (32 bytes)
///
/// # Returns
///
/// Device ID (16 bytes)
///
/// # Errors
///
/// Returns error if key is invalid
pub fn compute_device_id(ed25519_pub: Vec<u8>) -> Result<Vec<u8>> {
    let pub_bytes: [u8; 32] = ed25519_pub
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;

    let device_id = DeviceId::from_ed25519_public_key(&pub_bytes)?;
    Ok(device_id.0.to_vec())
}

/// Compute fingerprint from Ed25519 public key
///
/// # Arguments
///
/// * `ed25519_pub` - Ed25519 public key (32 bytes)
///
/// # Returns
///
/// Fingerprint (Base64URL string)
///
/// # Errors
///
/// Returns error if key is invalid
pub fn compute_fingerprint(ed25519_pub: Vec<u8>) -> Result<String> {
    let pub_bytes: [u8; 32] = ed25519_pub
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;

    let fingerprint = Fingerprint::from_ed25519_public_key(&pub_bytes)?;
    Ok(fingerprint.to_base64url())
}

/// Validate prekey bundle (verify SPK signature)
///
/// CRITICAL: This MUST be called before using a bundle in a handshake!
///
/// # Arguments
///
/// * `bundle` - Prekey bundle to validate
///
/// # Errors
///
/// Returns error if:
/// - SPK signature is invalid
/// - Key lengths are incorrect
/// - Ed25519 verification fails
pub fn validate_bundle(bundle: PrekeyBundle) -> Result<()> {
    // Parse Ed25519 public key
    let verifying_key_bytes: [u8; 32] = bundle
        .identity_pub_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;

    let verifying_key = VerifyingKey::from_bytes(&verifying_key_bytes)
        .map_err(|e| C6pError::InvalidKey(format!("Invalid Ed25519 public key: {}", e)))?;

    // Parse signature
    let signature_bytes: [u8; 64] = bundle
        .spk_sig
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidSignature("Signature must be 64 bytes".to_string()))?;

    let signature = ed25519_dalek::Signature::from_bytes(&signature_bytes);

    // Verify signature over: "C6P_PREKEY_V1" || spkId(8) || spkPub(32)
    let label = b"C6P_PREKEY_V1";
    let mut msg = Vec::with_capacity(label.len() + 8 + 32);
    msg.extend_from_slice(label);
    msg.extend_from_slice(&bundle.spk_id);
    msg.extend_from_slice(&bundle.spk_pub);

    verifying_key.verify_strict(&msg, &signature).map_err(|e| {
        C6pError::InvalidSignature(format!("SPK signature verification failed: {}", e))
    })?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_generate_identity() {
        let identity = generate_identity().unwrap();
        assert_eq!(identity.device_id.len(), 16);
        assert_eq!(identity.identity_pub_ed25519.len(), 32);
        assert_eq!(identity.identity_pub_x25519.len(), 32);
        // Base64URL fingerprint length varies
        assert!(!identity.fingerprint.is_empty());
    }

    #[test]
    fn test_generate_signed_prekey() {
        let identity = generate_identity().unwrap();
        let spk = generate_signed_prekey(identity.clone()).unwrap();

        assert_eq!(spk.spk_id.len(), 8);
        assert_eq!(spk.spk_pub.len(), 32);
        assert_eq!(spk.spk_sig.len(), 64);

        // Verify signature
        let bundle = PrekeyBundle {
            responder_device_id: identity.device_id,
            identity_pub_ed25519: identity.identity_pub_ed25519,
            identity_pub_x25519: identity.identity_pub_x25519,
            spk_id: spk.spk_id,
            spk_pub: spk.spk_pub,
            spk_sig: spk.spk_sig,
            otp_id: None,
            otp_pub: None,
        };

        validate_bundle(bundle).unwrap();
    }

    #[test]
    fn test_generate_one_time_prekey() {
        let otp = generate_one_time_prekey().unwrap();
        assert_eq!(otp.otp_id.len(), 8);
        assert_eq!(otp.otp_pub.len(), 32);
    }

    #[test]
    fn test_compute_device_id() {
        let identity = generate_identity().unwrap();
        let device_id = compute_device_id(identity.identity_pub_ed25519).unwrap();
        assert_eq!(device_id, identity.device_id);
    }

    #[test]
    fn test_compute_fingerprint() {
        let identity = generate_identity().unwrap();
        let fingerprint = compute_fingerprint(identity.identity_pub_ed25519).unwrap();
        assert_eq!(fingerprint, identity.fingerprint);
    }
}
