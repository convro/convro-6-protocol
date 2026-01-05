//! IslandAccord offer construction and parsing
//!
//! Normative reference: island-accord-crypto.md §10.1
//!
//! Initiator constructs offer with:
//! - DH computations (3DH or 4DH)
//! - Transcript hash
//! - Root/KC key derivation
//! - KC1 computation
//! - Offer signature

use crate::types::*;
use crate::error::Result;
use crate::bundle::PrekeyBundle;
use crate::crypto::*;
use c6p_crypto::{derive_root_and_kc, derive_initial_chain_key, SessionContext, StreamContext};

/// IslandAccord offer (from initiator to responder)
///
/// Normative reference: island-accord-crypto.md §10.1
#[derive(Debug, Clone)]
pub struct Offer {
    /// Protocol version (v1 = 0x01)
    pub version: u8,

    /// Suite ID
    pub suite_id: u16,

    /// Session ID (8 bytes)
    pub session_id: SessionId,

    /// Initiator device ID (16 bytes)
    pub initiator_device_id: DeviceId,

    /// Responder device ID (16 bytes)
    pub responder_device_id: DeviceId,

    /// Initiator identity DH public key (X25519)
    pub initiator_identity_dh_pub: X25519PublicKey,

    /// Initiator identity signature public key (Ed25519)
    pub initiator_identity_sig_pub: Ed25519PublicKey,

    /// Initiator ephemeral DH public key (X25519)
    pub initiator_ephemeral_dh_pub: X25519PublicKey,

    /// Used SPK ID (8 bytes)
    pub used_spk_id: SpkId,

    /// Used SPK public key (X25519)
    pub used_spk_pub: X25519PublicKey,

    /// Used SPK signature (Ed25519)
    pub used_spk_sig: Ed25519Signature,

    /// Used OTP ID (8 bytes, optional)
    pub used_otp_id: Option<OtpId>,

    /// Used OTP public key (X25519, optional)
    pub used_otp_pub: Option<X25519PublicKey>,

    /// Transcript hash (32 bytes)
    pub transcript_hash: TranscriptHash,

    /// Key confirmation tag KC1 (32 bytes)
    pub kc1: [u8; 32],

    /// Offer signature (Ed25519, 64 bytes)
    pub offer_signature: Ed25519Signature,
}

/// Handshake output (initiator side)
///
/// Contains derived session keys after successful offer construction
#[derive(Debug)]
pub struct InitiatorHandshakeOutput {
    /// Root key (32 bytes) - used for future ratcheting
    pub root_key: [u8; 32],

    /// KC key (32 bytes) - used for key confirmation
    pub kc_key: [u8; 32],

    /// Send chain key (initiator → responder)
    pub send_chain_key: [u8; 32],

    /// Receive chain key (responder → initiator)
    pub recv_chain_key: [u8; 32],

    /// Session binding (32 bytes) - for nonce derivation
    pub session_binding: [u8; 32],
}

impl Offer {
    /// Construct offer from initiator perspective
    ///
    /// Normative reference: island-accord-crypto.md §5, §6, §7, §8, §9
    ///
    /// # Arguments
    /// * `bundle` - Validated prekey bundle from responder
    /// * `session_id` - Fresh session ID (8 bytes)
    /// * `initiator_device_id` - Initiator's device ID (16 bytes)
    /// * `initiator_ik_dh_priv` - Initiator's X25519 identity private key
    /// * `initiator_ik_dh_pub` - Initiator's X25519 identity public key
    /// * `initiator_ik_sig_priv` - Initiator's Ed25519 identity private key
    /// * `initiator_ik_sig_pub` - Initiator's Ed25519 identity public key
    /// * `initiator_ek_priv` - Initiator's ephemeral X25519 private key (FRESH!)
    /// * `initiator_ek_pub` - Initiator's ephemeral X25519 public key
    /// * `suite_id` - AEAD suite ID (0x01 = ChaCha20-Poly1305)
    ///
    /// # Returns
    /// * `(Offer, InitiatorHandshakeOutput)` - Offer to send + derived session keys
    ///
    /// # Security
    /// - Bundle MUST be validated before calling this function
    /// - Ephemeral key MUST be freshly generated (NEVER reused)
    /// - All DH operations use constant-time x25519
    /// - Fails closed on any error
    #[allow(clippy::too_many_arguments)]
    pub fn construct(
        bundle: &PrekeyBundle,
        session_id: SessionId,
        initiator_device_id: DeviceId,
        initiator_ik_dh_priv: &X25519PrivateKey,
        initiator_ik_dh_pub: &X25519PublicKey,
        initiator_ik_sig_priv: &Ed25519PrivateKey,
        initiator_ik_sig_pub: &Ed25519PublicKey,
        initiator_ek_priv: &X25519PrivateKey,
        initiator_ek_pub: &X25519PublicKey,
        suite_id: u16,
    ) -> Result<(Self, InitiatorHandshakeOutput)> {
        // Step 1: Validate bundle (CRITICAL - must happen before any DH!)
        bundle.validate()?;

        // Step 2: Perform DH computations (island-accord-crypto.md §5)
        // DH1 = DH(A_IK_dh_priv, B_SPK_pub)
        let dh1 = x25519_dh(initiator_ik_dh_priv, &bundle.spk_pub);

        // DH2 = DH(A_EK_priv, B_IK_dh_pub)
        let dh2 = x25519_dh(initiator_ek_priv, &bundle.identity_pub_x25519);

        // DH3 = DH(A_EK_priv, B_SPK_pub)
        let dh3 = x25519_dh(initiator_ek_priv, &bundle.spk_pub);

        // DH4 (optional, only if OTP present)
        let dh4 = if let Some(otp_pub) = bundle.otp_pub {
            Some(x25519_dh(initiator_ek_priv, &otp_pub))
        } else {
            None
        };

        // Step 3: Construct IKM (island-accord-crypto.md §5.3)
        let ikm = construct_ikm(&dh1, &dh2, &dh3, dh4.as_ref());

        // Step 4: Build transcript (island-accord-crypto.md §6)
        let transcript_bytes = build_transcript(
            suite_id,
            &session_id,
            &initiator_device_id,
            &bundle.responder_device_id,
            initiator_ik_dh_pub,
            initiator_ik_sig_pub,
            initiator_ek_pub,
            &bundle.identity_pub_x25519,
            &bundle.identity_pub_ed25519,
            &bundle.spk_id,
            &bundle.spk_pub,
            &bundle.spk_sig,
            bundle.otp().as_ref().map(|(id, pub_key)| (id, pub_key)),
        );

        let transcript_hash = compute_transcript_hash(&transcript_bytes);

        // Step 5: Derive root_key + kc_key (island-accord-crypto.md §7)
        let ctx = SessionContext {
            session_id,
            initiator_device_id,
            responder_device_id: bundle.responder_device_id,
        };

        let (root_key, kc_key) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);

        // Step 6: Derive initial chain keys (island-accord-crypto.md §7.3)
        // Message type = 0x01 (DM)
        let message_type = 0x01;

        // Stream I2R (initiator → responder)
        let stream_ctx_i2r = StreamContext {
            stream_id: 0x01, // STREAM_I2R
            message_type,
            suite_id,
        };

        let send_chain_key = derive_initial_chain_key(
            &root_key,
            &transcript_hash,
            &ctx,
            &stream_ctx_i2r,
        );

        // Stream R2I (responder → initiator)
        let stream_ctx_r2i = StreamContext {
            stream_id: 0x02, // STREAM_R2I
            message_type,
            suite_id,
        };

        let recv_chain_key = derive_initial_chain_key(
            &root_key,
            &transcript_hash,
            &ctx,
            &stream_ctx_r2i,
        );

        // Step 7: Compute session binding (for nonce derivation)
        let session_binding = c6p_crypto::compute_session_binding(&ctx);

        // Step 8: Compute KC1 (island-accord-crypto.md §9)
        let kc1 = compute_kc1(
            &kc_key.0,
            &session_id,
            &initiator_device_id,
            &bundle.responder_device_id,
            &transcript_hash,
            suite_id,
        );

        // Step 9: Sign offer (island-accord-crypto.md §8)
        let offer_signature = sign_offer(
            initiator_ik_sig_priv,
            &transcript_hash,
            suite_id,
            &session_id,
            &initiator_device_id,
            &bundle.responder_device_id,
        )?;

        // Step 10: Construct offer
        let offer = Offer {
            version: 0x01,
            suite_id,
            session_id,
            initiator_device_id,
            responder_device_id: bundle.responder_device_id,
            initiator_identity_dh_pub: *initiator_ik_dh_pub,
            initiator_identity_sig_pub: *initiator_ik_sig_pub,
            initiator_ephemeral_dh_pub: *initiator_ek_pub,
            used_spk_id: bundle.spk_id,
            used_spk_pub: bundle.spk_pub,
            used_spk_sig: bundle.spk_sig,
            used_otp_id: bundle.otp_id,
            used_otp_pub: bundle.otp_pub,
            transcript_hash,
            kc1,
            offer_signature,
        };

        // Step 11: Return offer + handshake output
        let output = InitiatorHandshakeOutput {
            root_key: root_key.0,
            kc_key: kc_key.0,
            send_chain_key: send_chain_key.0,
            recv_chain_key: recv_chain_key.0,
            session_binding: session_binding.0,
        };

        Ok((offer, output))
    }

    /// Check if offer uses OTP (4DH handshake)
    pub fn has_otp(&self) -> bool {
        self.used_otp_id.is_some() && self.used_otp_pub.is_some()
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::bundle::PrekeyBundle;

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
        let x_pub = X25519PublicKey::from_bytes(x25519_dalek::x25519(x_priv_bytes, x25519_dalek::X25519_BASEPOINT_BYTES));

        (ed_priv, ed_pub, x_priv, x_pub)
    }

    #[test]
    fn test_offer_construction_3dh() {
        // Create initiator keys
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();

        // Create responder keys (for bundle)
        let (resp_ed_priv, resp_ed_pub, _resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, _spk_priv, spk_pub) = create_test_keys();

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

        // Construct offer
        let result = Offer::construct(
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
        );

        assert!(result.is_ok());
        let (offer, output) = result.unwrap();

        // Verify offer structure
        assert_eq!(offer.version, 0x01);
        assert_eq!(offer.suite_id, 0x01);
        assert!(!offer.has_otp()); // 3DH = no OTP

        // Verify output keys are derived
        assert_ne!(output.root_key, [0u8; 32]);
        assert_ne!(output.kc_key, [0u8; 32]);
        assert_ne!(output.send_chain_key, [0u8; 32]);
        assert_ne!(output.recv_chain_key, [0u8; 32]);
        assert_ne!(output.session_binding, [0u8; 32]);
    }

    #[test]
    fn test_offer_construction_4dh() {
        // Create initiator keys
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();

        // Create responder keys
        let (resp_ed_priv, resp_ed_pub, _resp_x_priv, resp_x_pub) = create_test_keys();
        let (_, _, _spk_priv, spk_pub) = create_test_keys();
        let (_, _, _otp_priv, otp_pub) = create_test_keys();

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
            Some((otp_id, otp_pub)), // WITH OTP
        );

        // Construct offer
        let result = Offer::construct(
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
        );

        assert!(result.is_ok());
        let (offer, output) = result.unwrap();

        // Verify offer structure
        assert_eq!(offer.version, 0x01);
        assert!(offer.has_otp()); // 4DH = with OTP
        assert_eq!(offer.used_otp_id, Some(otp_id));

        // Verify output keys
        assert_ne!(output.root_key, [0u8; 32]);
        assert_ne!(output.kc_key, [0u8; 32]);
    }

    #[test]
    fn test_offer_fails_on_invalid_bundle() {
        let (init_ed_priv, init_ed_pub, init_x_priv, init_x_pub) = create_test_keys();
        let (_, _, init_eph_priv, init_eph_pub) = create_test_keys();
        let (resp_ed_priv, resp_ed_pub, _, resp_x_pub) = create_test_keys();
        let (_, _, _, spk_pub) = create_test_keys();

        let spk_id = SpkId([0x01; 8]);

        // Create INVALID SPK signature (wrong message)
        let spk_sig = ed25519_sign(&resp_ed_priv, b"WRONG MESSAGE").unwrap();

        let bundle = PrekeyBundle::new(
            DeviceId([0xBB; 16]),
            resp_ed_pub,
            resp_x_pub,
            spk_id,
            spk_pub,
            spk_sig,
            None,
        );

        // Should fail during offer construction (bundle validation)
        let result = Offer::construct(
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
        );

        assert!(result.is_err());
    }
}
