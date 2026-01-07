//! IslandAccord accept construction and validation
//!
//! Normative reference: island-accord-crypto.md §10.2, §A.2
//!
//! Responder flow:
//! - Parse offer
//! - Validate responder device ID matches
//! - Recompute mirrored DHs
//! - Rebuild transcript and verify
//! - Verify offer signature
//! - Verify KC1
//! - Compute KC2
//! - Return accept + session keys

use crate::crypto::*;
use crate::error::{HandshakeError, Result};
use crate::offer::Offer;
use crate::types::*;
use c6p_crypto::{derive_initial_chain_key, derive_root_and_kc, SessionContext, StreamContext};

/// IslandAccord accept (from responder to initiator)
///
/// Normative reference: island-accord-crypto.md §10.2
///
/// Wire format fields:
/// - `sessionId` (hex16)
/// - `responderDeviceId` (hex32)
/// - `kc2` (b64url32) // MUST equal directional RESP tag (§9.2)
#[derive(Debug, Clone)]
pub struct Accept {
    /// Session ID (8 bytes)
    pub session_id: SessionId,

    /// Responder device ID (16 bytes)
    pub responder_device_id: DeviceId,

    /// Key confirmation tag KC2 (32 bytes)
    pub kc2: [u8; 32],
}

/// Responder handshake output (derived session keys)
///
/// This contains all the cryptographic material derived by the responder
/// after processing the offer and creating the accept.
#[derive(Debug)]
pub struct ResponderHandshakeOutput {
    /// Root key (32 bytes) - for future ratcheting
    pub root_key: [u8; 32],

    /// Key confirmation key (32 bytes) - used for KC1/KC2
    pub kc_key: [u8; 32],

    /// Send chain key (R2I direction) (32 bytes)
    pub send_chain_key: [u8; 32],

    /// Receive chain key (I2R direction) (32 bytes)
    pub recv_chain_key: [u8; 32],

    /// Session binding (32 bytes) - deterministic nonce derivation
    pub session_binding: [u8; 32],
}

impl Accept {
    /// Construct accept from responder perspective
    ///
    /// Normative reference: island-accord-crypto.md §A.2
    ///
    /// # Arguments
    /// * `offer` - Received offer from initiator
    /// * `responder_device_id` - This responder's device ID (MUST match offer.responder_device_id)
    /// * `responder_ik_dh_priv` - Responder's identity private key (X25519) for DH
    /// * `responder_ik_dh_pub` - Responder's identity public key (X25519) for transcript
    /// * `responder_ik_sig_pub` - Responder's identity public key (Ed25519) for transcript
    /// * `spk_id` - SPK ID referenced in offer (for verification)
    /// * `spk_priv` - SPK private key (X25519)
    /// * `spk_pub` - SPK public key (X25519)
    /// * `otp` - Optional (otp_id, otp_priv, otp_pub) if offer used OTP
    ///
    /// # Returns
    /// * `Ok((Accept, ResponderHandshakeOutput))` if validation succeeds
    /// * `Err(HandshakeError)` if any validation fails (fail-closed)
    ///
    /// # Process (13 steps):
    /// 1. Validate responder_device_id matches offer
    /// 2. Validate SPK ID matches
    /// 3. Validate OTP consistency (if offer used OTP, we must have OTP keys)
    /// 4. Recompute mirrored DHs (DH1, DH2, DH3, optional DH4)
    /// 5. Construct IKM (96 or 128 bytes)
    /// 6. Rebuild transcript (same 17 fields as initiator)
    /// 7. Compute transcript hash
    /// 8. Derive root_key + kc_key
    /// 9. Derive initial chain keys (SWAPPED: send=R2I, recv=I2R)
    /// 10. Verify offer signature
    /// 11. Verify KC1
    /// 12. Compute KC2
    /// 13. Return accept + handshake output
    #[allow(clippy::too_many_arguments)]
    pub fn construct(
        offer: &Offer,
        responder_device_id: DeviceId,
        responder_ik_dh_priv: &X25519PrivateKey,
        responder_ik_dh_pub: &X25519PublicKey,
        responder_ik_sig_pub: &Ed25519PublicKey,
        spk_id: SpkId,
        spk_priv: &X25519PrivateKey,
        spk_pub: &X25519PublicKey,
        otp: Option<(OtpId, X25519PrivateKey, X25519PublicKey)>,
    ) -> Result<(Self, ResponderHandshakeOutput)> {
        // Step 1: Validate responder device ID matches
        if offer.responder_device_id != responder_device_id {
            return Err(HandshakeError::InvalidWireFormat(format!(
                "Offer responder_device_id mismatch: expected {:?}, got {:?}",
                responder_device_id, offer.responder_device_id
            )));
        }

        // Step 2: Validate SPK ID matches
        if offer.used_spk_id != spk_id {
            return Err(HandshakeError::InvalidWireFormat(format!(
                "SPK ID mismatch: expected {:?}, got {:?}",
                spk_id, offer.used_spk_id
            )));
        }

        // Step 3: Validate OTP consistency
        let offer_has_otp = offer.has_otp();
        let responder_has_otp = otp.is_some();
        if offer_has_otp != responder_has_otp {
            return Err(HandshakeError::InvalidWireFormat(format!(
                "OTP mismatch: offer has_otp={}, responder has_otp={}",
                offer_has_otp, responder_has_otp
            )));
        }

        // If OTP is present, validate IDs match
        if let (Some(offer_otp_id), Some((otp_id, _, _))) = (offer.used_otp_id, otp.as_ref()) {
            if offer_otp_id != *otp_id {
                return Err(HandshakeError::InvalidWireFormat(format!(
                    "OTP ID mismatch: expected {:?}, got {:?}",
                    otp_id, offer_otp_id
                )));
            }
        }

        // Step 4: Recompute mirrored DHs
        // DH1 = DH(SPK_priv, initiator_ik_dh_pub)
        let dh1 = x25519_dh(spk_priv, &offer.initiator_identity_dh_pub);

        // DH2 = DH(responder_ik_dh_priv, initiator_ek_pub)
        let dh2 = x25519_dh(responder_ik_dh_priv, &offer.initiator_ephemeral_dh_pub);

        // DH3 = DH(SPK_priv, initiator_ek_pub)
        let dh3 = x25519_dh(spk_priv, &offer.initiator_ephemeral_dh_pub);

        // DH4 (optional) = DH(OTP_priv, initiator_ek_pub)
        let dh4 = if let (Some(_offer_otp_pub), Some((_, otp_priv, _))) =
            (offer.used_otp_pub, otp.as_ref())
        {
            Some(x25519_dh(otp_priv, &offer.initiator_ephemeral_dh_pub))
        } else {
            None
        };

        // Step 5: Construct IKM (96 or 128 bytes)
        let ikm = construct_ikm(&dh1, &dh2, &dh3, dh4.as_ref());

        // Step 6: Rebuild transcript (same 17 fields as initiator)
        let transcript_bytes = build_transcript(
            offer.suite_id,
            &offer.session_id,
            &offer.initiator_device_id,
            &offer.responder_device_id,
            &offer.initiator_identity_dh_pub,
            &offer.initiator_identity_sig_pub,
            &offer.initiator_ephemeral_dh_pub,
            responder_ik_dh_pub,
            responder_ik_sig_pub,
            &offer.used_spk_id,
            spk_pub,
            &offer.used_spk_sig,
            offer.used_otp_id.as_ref().zip(offer.used_otp_pub.as_ref()),
        );

        // Step 7: Compute transcript hash
        let transcript_hash = compute_transcript_hash(&transcript_bytes);

        // Step 8: Derive root_key + kc_key via c6p-crypto
        let ctx = SessionContext {
            session_id: offer.session_id,
            initiator_device_id: offer.initiator_device_id,
            responder_device_id: offer.responder_device_id,
        };

        let (root_key, kc_key) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);

        // Step 9: Derive initial chain keys (SWAPPED from initiator perspective!)
        // Responder sends on R2I stream (0x02), receives on I2R stream (0x01)
        let message_type = 0x01; // Default message type for initial chain keys
        let stream_ctx_r2i = StreamContext {
            stream_id: c6p_crypto::STREAM_R2I,
            message_type,
            suite_id: offer.suite_id,
        };
        let stream_ctx_i2r = StreamContext {
            stream_id: c6p_crypto::STREAM_I2R,
            message_type,
            suite_id: offer.suite_id,
        };

        let send_chain_key =
            derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_r2i);
        let recv_chain_key =
            derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_i2r);

        // Compute session binding
        let session_binding = c6p_crypto::compute_session_binding(&ctx);

        // Step 10: Verify offer signature
        verify_offer_signature(
            &offer.initiator_identity_sig_pub,
            &offer.offer_signature,
            &transcript_hash,
            offer.suite_id,
            &offer.session_id,
            &offer.initiator_device_id,
            &offer.responder_device_id,
        )?;

        // Step 11: Verify KC1
        let expected_kc1 = compute_kc1(
            &kc_key.0,
            &offer.session_id,
            &offer.initiator_device_id,
            &offer.responder_device_id,
            &transcript_hash,
            offer.suite_id,
        );

        if offer.kc1 != expected_kc1 {
            return Err(HandshakeError::KcVerificationFailed(
                "KC1 verification failed".to_string(),
            ));
        }

        // Step 12: Compute KC2
        let kc2 = compute_kc2(
            &kc_key.0,
            &offer.session_id,
            &offer.initiator_device_id,
            &offer.responder_device_id,
            &transcript_hash,
            offer.suite_id,
        );

        // Step 13: Construct accept
        let accept = Accept {
            session_id: offer.session_id,
            responder_device_id: offer.responder_device_id,
            kc2,
        };

        // Construct handshake output
        let output = ResponderHandshakeOutput {
            root_key: root_key.0,
            kc_key: kc_key.0,
            send_chain_key: send_chain_key.0,
            recv_chain_key: recv_chain_key.0,
            session_binding: session_binding.0,
        };

        Ok((accept, output))
    }

    /// Validate accept from initiator perspective
    ///
    /// Normative reference: island-accord-crypto.md §10.2
    ///
    /// # Arguments
    /// * `expected_session_id` - Expected session ID
    /// * `expected_responder_device_id` - Expected responder device ID
    /// * `kc_key` - KC key derived during offer construction
    /// * `transcript_hash` - Transcript hash computed during offer construction
    /// * `suite_id` - Suite ID from offer
    /// * `initiator_device_id` - Initiator device ID
    ///
    /// # Returns
    /// * `Ok(())` if KC2 verification succeeds
    /// * `Err(HandshakeError::KcVerificationFailed)` if KC2 fails
    ///
    /// # Security
    /// Initiator MUST NOT mark session active until KC2 verifies exactly.
    pub fn validate(
        &self,
        expected_session_id: &SessionId,
        expected_responder_device_id: &DeviceId,
        kc_key: &[u8; 32],
        transcript_hash: &TranscriptHash,
        suite_id: u16,
        initiator_device_id: &DeviceId,
    ) -> Result<()> {
        // Validate session ID matches
        if &self.session_id != expected_session_id {
            return Err(HandshakeError::InvalidWireFormat(format!(
                "Accept session_id mismatch: expected {:?}, got {:?}",
                expected_session_id, self.session_id
            )));
        }

        // Validate responder device ID matches
        if &self.responder_device_id != expected_responder_device_id {
            return Err(HandshakeError::InvalidWireFormat(format!(
                "Accept responder_device_id mismatch: expected {:?}, got {:?}",
                expected_responder_device_id, self.responder_device_id
            )));
        }

        // Verify KC2
        let expected_kc2 = compute_kc2(
            kc_key,
            &self.session_id,
            initiator_device_id,
            &self.responder_device_id,
            transcript_hash,
            suite_id,
        );

        if self.kc2 != expected_kc2 {
            return Err(HandshakeError::KcVerificationFailed(
                "KC2 verification failed".to_string(),
            ));
        }

        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bundle::PrekeyBundle;
    use crate::crypto::ed25519_sign;
    use crate::offer::Offer;

    /// Helper: Create test keys
    fn create_test_keys() -> (
        Ed25519PrivateKey,
        Ed25519PublicKey,
        X25519PrivateKey,
        X25519PublicKey,
    ) {
        use ed25519_dalek::SigningKey;
        use rand::RngCore;

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

    #[test]
    fn test_accept_construction_and_validation_3dh() {
        // Create initiator keys
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();

        // Create responder keys
        let (resp_ed_priv, resp_ed_pub, resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, spk_priv, spk_pub) = create_test_keys();

        // Generate SPK signature
        let spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
        let mut spk_msg = Vec::new();
        spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        spk_msg.extend_from_slice(&spk_id.0);
        spk_msg.extend_from_slice(&spk_pub.0);
        let spk_sig = ed25519_sign(&resp_ed_priv, &spk_msg).unwrap();

        // Create bundle (no OTP = 3DH)
        let bundle = PrekeyBundle::new(
            DeviceId([0xBB; 16]),
            resp_ed_pub,
            resp_x_pub,
            spk_id,
            spk_pub,
            spk_sig,
            None, // No OTP
        );

        // Initiator constructs offer
        let (offer, init_output) = Offer::construct(
            &bundle,
            SessionId([0x11; 8]),
            DeviceId([0xAA; 16]),
            &init_x_priv,
            &init_x_pub,
            &init_ed_priv,
            &init_ed_pub,
            &init_eph_priv,
            &init_eph_pub,
            0x01, // ChaCha20-Poly1305
        )
        .unwrap();

        // Responder constructs accept
        let result = Accept::construct(
            &offer,
            DeviceId([0xBB; 16]),
            &resp_x_priv,
            &resp_x_pub,
            &resp_ed_pub,
            spk_id,
            &spk_priv,
            &spk_pub,
            None, // No OTP
        );

        assert!(result.is_ok());
        let (accept, resp_output) = result.unwrap();

        // Verify accept structure
        assert_eq!(accept.session_id, offer.session_id);
        assert_eq!(accept.responder_device_id, offer.responder_device_id);

        // Verify responder derived same keys as initiator (symmetric)
        assert_eq!(resp_output.root_key, init_output.root_key);
        assert_eq!(resp_output.kc_key, init_output.kc_key);
        assert_eq!(resp_output.session_binding, init_output.session_binding);

        // Verify chain keys are swapped (responder send = initiator recv, etc.)
        assert_eq!(resp_output.send_chain_key, init_output.recv_chain_key);
        assert_eq!(resp_output.recv_chain_key, init_output.send_chain_key);

        // Initiator validates accept (use offer's stored transcript hash)
        let transcript_hash = offer.transcript_hash;

        let validation_result = accept.validate(
            &offer.session_id,
            &offer.responder_device_id,
            &init_output.kc_key,
            &transcript_hash,
            offer.suite_id,
            &offer.initiator_device_id,
        );

        assert!(validation_result.is_ok());
    }

    #[test]
    fn test_accept_construction_and_validation_4dh() {
        // Create initiator keys
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();

        // Create responder keys
        let (resp_ed_priv, resp_ed_pub, resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, spk_priv, spk_pub) = create_test_keys();
        let (_, _, otp_priv, otp_pub) = create_test_keys();

        // Generate SPK signature
        let spk_id = SpkId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
        let mut spk_msg = Vec::new();
        spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        spk_msg.extend_from_slice(&spk_id.0);
        spk_msg.extend_from_slice(&spk_pub.0);
        let spk_sig = ed25519_sign(&resp_ed_priv, &spk_msg).unwrap();

        // Create bundle (with OTP = 4DH)
        let otp_id = OtpId([0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18]);
        let bundle = PrekeyBundle::new(
            DeviceId([0xBB; 16]),
            resp_ed_pub,
            resp_x_pub,
            spk_id,
            spk_pub,
            spk_sig,
            Some((otp_id, otp_pub)),
        );

        // Initiator constructs offer
        let (offer, init_output) = Offer::construct(
            &bundle,
            SessionId([0x11; 8]),
            DeviceId([0xAA; 16]),
            &init_x_priv,
            &init_x_pub,
            &init_ed_priv,
            &init_ed_pub,
            &init_eph_priv,
            &init_eph_pub,
            0x01,
        )
        .unwrap();

        // Responder constructs accept (with OTP)
        let result = Accept::construct(
            &offer,
            DeviceId([0xBB; 16]),
            &resp_x_priv,
            &resp_x_pub,
            &resp_ed_pub,
            spk_id,
            &spk_priv,
            &spk_pub,
            Some((otp_id, otp_priv, otp_pub)),
        );

        assert!(result.is_ok());
        let (_accept, resp_output) = result.unwrap();

        // Verify keys match (symmetric)
        assert_eq!(resp_output.root_key, init_output.root_key);
        assert_eq!(resp_output.kc_key, init_output.kc_key);

        // Verify chain keys are swapped
        assert_eq!(resp_output.send_chain_key, init_output.recv_chain_key);
        assert_eq!(resp_output.recv_chain_key, init_output.send_chain_key);
    }

    #[test]
    fn test_accept_fails_on_wrong_device_id() {
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();
        let (resp_ed_priv, resp_ed_pub, resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, spk_priv, spk_pub) = create_test_keys();

        let spk_id = SpkId([0x01; 8]);
        let mut spk_msg = Vec::new();
        spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        spk_msg.extend_from_slice(&spk_id.0);
        spk_msg.extend_from_slice(&spk_pub.0);
        let spk_sig = ed25519_sign(&resp_ed_priv, &spk_msg).unwrap();

        let bundle = PrekeyBundle::new(
            DeviceId([0xBB; 16]),
            resp_ed_pub,
            resp_x_pub,
            spk_id,
            spk_pub,
            spk_sig,
            None,
        );

        let (offer, _) = Offer::construct(
            &bundle,
            SessionId([0x11; 8]),
            DeviceId([0xAA; 16]),
            &init_x_priv,
            &init_x_pub,
            &init_ed_priv,
            &init_ed_pub,
            &init_eph_priv,
            &init_eph_pub,
            0x01,
        )
        .unwrap();

        // Try to construct accept with WRONG device ID
        let result = Accept::construct(
            &offer,
            DeviceId([0xCC; 16]), // WRONG! Should be [0xBB; 16]
            &resp_x_priv,
            &resp_x_pub,
            &resp_ed_pub,
            spk_id,
            &spk_priv,
            &spk_pub,
            None,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            HandshakeError::InvalidWireFormat(_)
        ));
    }

    #[test]
    fn test_accept_fails_on_kc2_mismatch() {
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();
        let (resp_ed_priv, resp_ed_pub, resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, spk_priv, spk_pub) = create_test_keys();

        let spk_id = SpkId([0x01; 8]);
        let mut spk_msg = Vec::new();
        spk_msg.extend_from_slice(b"C6P_PREKEY_V1");
        spk_msg.extend_from_slice(&spk_id.0);
        spk_msg.extend_from_slice(&spk_pub.0);
        let spk_sig = ed25519_sign(&resp_ed_priv, &spk_msg).unwrap();

        let bundle = PrekeyBundle::new(
            DeviceId([0xBB; 16]),
            resp_ed_pub,
            resp_x_pub,
            spk_id,
            spk_pub,
            spk_sig,
            None,
        );

        let (offer, init_output) = Offer::construct(
            &bundle,
            SessionId([0x11; 8]),
            DeviceId([0xAA; 16]),
            &init_x_priv,
            &init_x_pub,
            &init_ed_priv,
            &init_ed_pub,
            &init_eph_priv,
            &init_eph_pub,
            0x01,
        )
        .unwrap();

        let (mut accept, _) = Accept::construct(
            &offer,
            DeviceId([0xBB; 16]),
            &resp_x_priv,
            &resp_x_pub,
            &resp_ed_pub,
            spk_id,
            &spk_priv,
            &spk_pub,
            None,
        )
        .unwrap();

        // Corrupt KC2
        accept.kc2[0] ^= 0xFF;

        let transcript_hash = offer.transcript_hash;

        let result = accept.validate(
            &offer.session_id,
            &offer.responder_device_id,
            &init_output.kc_key,
            &transcript_hash,
            offer.suite_id,
            &offer.initiator_device_id,
        );

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            HandshakeError::KcVerificationFailed(_)
        ));
    }
}
