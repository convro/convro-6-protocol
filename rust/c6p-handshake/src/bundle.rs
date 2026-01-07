//! Prekey bundle types and validation
//!
//! CRITICAL: SPK signature MUST be verified BEFORE any DH operations (fail-closed)
//! Normative reference: island-accord-crypto.md §3

use crate::crypto::verify_spk_signature;
use crate::error::{HandshakeError, Result};
use crate::types::*;

/// Prekey bundle (responder's published prekeys)
///
/// Normative reference: island-accord-crypto.md §3.1
///
/// This structure contains all the public keys needed by an initiator
/// to start an IslandAccord v1 handshake with a responder.
#[derive(Debug, Clone)]
pub struct PrekeyBundle {
    /// Responder device ID (16 bytes)
    pub responder_device_id: DeviceId,

    /// Responder identity public key (Ed25519) for signature verification
    pub identity_pub_ed25519: Ed25519PublicKey,

    /// Responder identity public key (X25519) for DH
    pub identity_pub_x25519: X25519PublicKey,

    /// Signed prekey ID (8 bytes)
    pub spk_id: SpkId,

    /// Signed prekey public key (X25519)
    pub spk_pub: X25519PublicKey,

    /// SPK signature (Ed25519 signature over SPK)
    ///
    /// Signature covers: LABEL_PREKEY || spkId(8) || spkPub(32)
    /// Signed by: identity_pub_ed25519
    pub spk_sig: Ed25519Signature,

    /// Optional one-time prekey ID (8 bytes)
    ///
    /// If None, handshake will use 3DH (without OTP)
    /// If Some, handshake will use 4DH (with OTP)
    pub otp_id: Option<OtpId>,

    /// Optional one-time prekey public key (X25519)
    pub otp_pub: Option<X25519PublicKey>,
}

impl PrekeyBundle {
    /// Create a new prekey bundle
    ///
    /// # Arguments
    /// * `responder_device_id` - Responder's device ID
    /// * `identity_pub_ed25519` - Responder's Ed25519 identity public key
    /// * `identity_pub_x25519` - Responder's X25519 identity public key
    /// * `spk_id` - Signed prekey ID
    /// * `spk_pub` - Signed prekey public key
    /// * `spk_sig` - SPK signature
    /// * `otp` - Optional (otp_id, otp_pub) tuple
    ///
    /// # Returns
    /// * Prekey bundle (NOT YET VALIDATED - call validate() before use!)
    pub fn new(
        responder_device_id: DeviceId,
        identity_pub_ed25519: Ed25519PublicKey,
        identity_pub_x25519: X25519PublicKey,
        spk_id: SpkId,
        spk_pub: X25519PublicKey,
        spk_sig: Ed25519Signature,
        otp: Option<(OtpId, X25519PublicKey)>,
    ) -> Self {
        let (otp_id, otp_pub) = match otp {
            Some((id, pub_key)) => (Some(id), Some(pub_key)),
            None => (None, None),
        };

        PrekeyBundle {
            responder_device_id,
            identity_pub_ed25519,
            identity_pub_x25519,
            spk_id,
            spk_pub,
            spk_sig,
            otp_id,
            otp_pub,
        }
    }

    /// Validate prekey bundle (verify SPK signature)
    ///
    /// Normative reference: island-accord-crypto.md §3.2
    ///
    /// CRITICAL: This MUST be called BEFORE any DH operations!
    ///
    /// Verification:
    /// - MSG = "C6P_PREKEY_V1" || spkId(8) || spkPub(32)
    /// - Verify: Ed25519.Verify(identity_pub_ed25519, spkSig, MSG) == true
    ///
    /// # Returns
    /// * `Ok(())` if SPK signature is valid
    /// * `Err(HandshakeError::InvalidSpkSignature)` if invalid
    ///
    /// # Security
    /// - Fail-closed: Any verification failure aborts handshake
    /// - Prevents server from injecting malicious SPKs
    /// - Ensures SPK belongs to claimed responder
    pub fn validate(&self) -> Result<()> {
        // Verify SPK signature
        verify_spk_signature(
            &self.identity_pub_ed25519,
            &self.spk_id,
            &self.spk_pub,
            &self.spk_sig,
        )?;

        // Additional consistency checks
        if self.otp_id.is_some() != self.otp_pub.is_some() {
            return Err(HandshakeError::InvalidBundle(
                "OTP ID and OTP public key must both be present or both absent".to_string(),
            ));
        }

        Ok(())
    }

    /// Check if bundle includes OTP (4DH handshake)
    ///
    /// # Returns
    /// * `true` if OTP is present (4DH handshake)
    /// * `false` if OTP is absent (3DH handshake)
    pub fn has_otp(&self) -> bool {
        self.otp_id.is_some() && self.otp_pub.is_some()
    }

    /// Get OTP tuple if present
    ///
    /// # Returns
    /// * `Some((otp_id, otp_pub))` if OTP is present
    /// * `None` if OTP is absent
    pub fn otp(&self) -> Option<(OtpId, X25519PublicKey)> {
        match (self.otp_id, self.otp_pub) {
            (Some(id), Some(pub_key)) => Some((id, pub_key)),
            _ => None,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::crypto::ed25519_sign;

    /// Helper: Generate a valid test bundle with proper SPK signature
    fn create_test_bundle(include_otp: bool) -> (PrekeyBundle, Ed25519PrivateKey) {
        // Generate identity keypair
        let identity_priv_ed25519 = Ed25519PrivateKey::from_bytes([0x42; 32]);

        // Derive public key from private key
        use ed25519_dalek::SigningKey;
        let signing_key = SigningKey::from_bytes(&identity_priv_ed25519.0);
        let identity_pub_ed25519 =
            Ed25519PublicKey::from_bytes(signing_key.verifying_key().to_bytes());

        let identity_pub_x25519 = X25519PublicKey::from_bytes([0x11; 32]);
        let responder_device_id = DeviceId([0xAA; 16]);

        // SPK
        let spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
        let spk_pub = X25519PublicKey::from_bytes([0x22; 32]);

        // Generate valid SPK signature
        let mut spk_msg = Vec::new();
        spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        spk_msg.extend_from_slice(&spk_id.0);
        spk_msg.extend_from_slice(&spk_pub.0);
        let spk_sig = ed25519_sign(&identity_priv_ed25519, &spk_msg).unwrap();

        // OTP (optional)
        let otp = if include_otp {
            Some((
                OtpId([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18]),
                X25519PublicKey::from_bytes([0x33; 32]),
            ))
        } else {
            None
        };

        let bundle = PrekeyBundle::new(
            responder_device_id,
            identity_pub_ed25519,
            identity_pub_x25519,
            spk_id,
            spk_pub,
            spk_sig,
            otp,
        );

        (bundle, identity_priv_ed25519)
    }

    #[test]
    fn test_bundle_validation_3dh() {
        let (bundle, _) = create_test_bundle(false);

        // Should validate successfully
        assert!(bundle.validate().is_ok());

        // Should not have OTP
        assert!(!bundle.has_otp());
        assert!(bundle.otp().is_none());
    }

    #[test]
    fn test_bundle_validation_4dh() {
        let (bundle, _) = create_test_bundle(true);

        // Should validate successfully
        assert!(bundle.validate().is_ok());

        // Should have OTP
        assert!(bundle.has_otp());
        assert!(bundle.otp().is_some());
    }

    #[test]
    fn test_bundle_invalid_spk_signature() {
        let (mut bundle, _) = create_test_bundle(false);

        // Corrupt the SPK signature
        bundle.spk_sig.0[0] ^= 0xFF;

        // Should fail validation
        assert!(bundle.validate().is_err());
    }

    #[test]
    fn test_bundle_otp_inconsistency() {
        let (mut bundle, _) = create_test_bundle(false);

        // Add OTP ID but not OTP public key (inconsistent)
        bundle.otp_id = Some(OtpId([0x11; 8]));
        bundle.otp_pub = None;

        // Should fail validation
        let result = bundle.validate();
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            HandshakeError::InvalidBundle(_)
        ));
    }
}
