//! Handshake functions for iOS bridge (IslandAccord v1)

use crate::error::{C6pError, Result};
use crate::types::{
    DeviceIdentity, HandshakeAccept, HandshakeOffer, OneTimePrekey, PrekeyBundle, SessionKeys,
    SignedPrekey,
};
use c6p_handshake::{
    Accept as AcceptCore, DeviceId, Ed25519PrivateKey, Ed25519PublicKey, Ed25519Signature,
    Offer as OfferCore, OtpId, PrekeyBundle as PrekeyBundleCore, SessionId, SpkId,
    X25519PrivateKey, X25519PublicKey,
};
use ed25519_dalek::SigningKey;
use rand::rngs::OsRng;

/// Create handshake offer (initiator side)
///
/// This initiates an IslandAccord v1 handshake using a validated prekey bundle.
///
/// # Arguments
///
/// * `initiator_identity` - Initiator's device identity
/// * `responder_bundle` - Responder's validated prekey bundle
///
/// # Returns
///
/// HandshakeOffer containing:
/// - Offer data (session_id, keys, KC1, signature)
/// - Serialized bytes for sending over network
/// - Internal state needed for `verify_accept`
///
/// # Security
///
/// - Automatically validates bundle SPK signature (fail-closed)
/// - Generates fresh ephemeral key (NEVER reused)
/// - Performs 3DH or 4DH depending on bundle OTP presence
/// - Computes KC1 for key confirmation
/// - Signs offer with initiator Ed25519 key
///
/// # Errors
///
/// Returns error if:
/// - Bundle SPK signature is invalid
/// - Key parsing fails
/// - Cryptographic operations fail
pub fn create_offer(
    initiator_identity: DeviceIdentity,
    responder_bundle: PrekeyBundle,
) -> Result<(HandshakeOffer, SessionKeys)> {
    // Convert bridge types to core types
    let bundle_core = convert_bundle_to_core(responder_bundle)?;

    // Validate bundle (CRITICAL!)
    bundle_core.validate()?;

    // Parse initiator keys
    let initiator_device_id_bytes: [u8; 16] = initiator_identity
        .device_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidDeviceId("Device ID must be 16 bytes".to_string()))?;
    let initiator_device_id = DeviceId(initiator_device_id_bytes);

    let initiator_ik_dh_priv_bytes: [u8; 32] = initiator_identity
        .identity_priv_x25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("X25519 private key must be 32 bytes".to_string()))?;
    let initiator_ik_dh_priv = X25519PrivateKey::from_bytes(initiator_ik_dh_priv_bytes);

    let initiator_ik_dh_pub_bytes: [u8; 32] = initiator_identity
        .identity_pub_x25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("X25519 public key must be 32 bytes".to_string()))?;
    let initiator_ik_dh_pub = X25519PublicKey::from_bytes(initiator_ik_dh_pub_bytes);

    let initiator_ik_sig_keypair: [u8; 64] = initiator_identity
        .identity_priv_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 keypair must be 64 bytes".to_string()))?;
    let signing_key = SigningKey::from_keypair_bytes(&initiator_ik_sig_keypair)
        .map_err(|e| C6pError::InvalidKey(format!("Invalid Ed25519 keypair: {}", e)))?;

    // Extract private key (first 32 bytes) and public key (last 32 bytes)
    let mut initiator_ik_sig_priv_bytes = [0u8; 32];
    initiator_ik_sig_priv_bytes.copy_from_slice(&initiator_ik_sig_keypair[..32]);
    let initiator_ik_sig_priv = Ed25519PrivateKey::from_bytes(initiator_ik_sig_priv_bytes);

    let initiator_ik_sig_pub_bytes: [u8; 32] = initiator_identity
        .identity_pub_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;
    let initiator_ik_sig_pub = Ed25519PublicKey::from_bytes(initiator_ik_sig_pub_bytes);

    // Generate fresh ephemeral key (CRITICAL: never reuse!)
    let mut ek_priv_bytes = [0u8; 32];
    rand::RngCore::fill_bytes(&mut OsRng, &mut ek_priv_bytes);
    let initiator_ek_priv = X25519PrivateKey::from_bytes(ek_priv_bytes);

    let ek_pub_bytes = x25519_dalek::x25519(ek_priv_bytes, x25519_dalek::X25519_BASEPOINT_BYTES);
    let initiator_ek_pub = X25519PublicKey::from_bytes(ek_pub_bytes);

    // Generate random session ID (8 bytes)
    let mut session_id_bytes = [0u8; 8];
    rand::RngCore::fill_bytes(&mut OsRng, &mut session_id_bytes);
    let session_id = SessionId(session_id_bytes);

    // Suite ID: 0x01 = ChaCha20-Poly1305
    let suite_id = 0x01;

    // Construct offer
    let (offer_core, handshake_output) = OfferCore::construct(
        &bundle_core,
        session_id,
        initiator_device_id,
        &initiator_ik_dh_priv,
        &initiator_ik_dh_pub,
        &initiator_ik_sig_priv,
        &initiator_ik_sig_pub,
        &initiator_ek_priv,
        &initiator_ek_pub,
        suite_id,
    )?;

    // Serialize offer to wire format (JSON)
    let serialized = serde_json::to_vec(&c6p_handshake::OfferWire::from(&offer_core))
        .map_err(|e| C6pError::SerializationError(format!("Failed to serialize offer: {}", e)))?;

    // Convert to bridge types
    let offer = HandshakeOffer {
        session_id: offer_core.session_id.0.to_vec(),
        initiator_device_id: offer_core.initiator_device_id.0.to_vec(),
        responder_device_id: offer_core.responder_device_id.0.to_vec(),
        initiator_identity_dh_pub: offer_core.initiator_identity_dh_pub.as_bytes().to_vec(),
        initiator_identity_sig_pub: offer_core.initiator_identity_sig_pub.as_bytes().to_vec(),
        initiator_ephemeral_dh_pub: offer_core.initiator_ephemeral_dh_pub.as_bytes().to_vec(),
        used_spk_id: offer_core.used_spk_id.0.to_vec(),
        used_spk_pub: offer_core.used_spk_pub.as_bytes().to_vec(),
        used_spk_sig: offer_core.used_spk_sig.as_bytes().to_vec(),
        used_otp_id: offer_core.used_otp_id.map(|id| id.0.to_vec()),
        used_otp_pub: offer_core.used_otp_pub.map(|pub_key| pub_key.as_bytes().to_vec()),
        transcript_hash: offer_core.transcript_hash.0.to_vec(),
        kc1: offer_core.kc1.to_vec(),
        offer_signature: offer_core.offer_signature.as_bytes().to_vec(),
        serialized,
    };

    let session_keys = SessionKeys {
        session_id: offer_core.session_id.0.to_vec(),
        root_key: handshake_output.root_key.to_vec(),
        kc_key: handshake_output.kc_key.to_vec(),
        send_chain_key: handshake_output.send_chain_key.to_vec(),
        recv_chain_key: handshake_output.recv_chain_key.to_vec(),
        session_binding: handshake_output.session_binding.to_vec(),
    };

    Ok((offer, session_keys))
}

/// Accept handshake offer (responder side)
///
/// This accepts an IslandAccord v1 offer and derives session keys.
///
/// # Arguments
///
/// * `responder_identity` - Responder's device identity
/// * `responder_spk` - Responder's signed prekey referenced in offer
/// * `responder_otp` - Responder's one-time prekey if used in offer (optional)
/// * `offer_bytes` - Serialized offer bytes received from initiator
///
/// # Returns
///
/// HandshakeAccept containing:
/// - Session ID
/// - KC2 (key confirmation tag)
/// - Accept signature
/// - Serialized bytes for sending back to initiator
/// - Session keys (stored internally for get_session_keys_responder)
///
/// # Security
///
/// - Validates offer signature (Ed25519)
/// - Verifies KC1 matches expected value
/// - Recomputes mirrored DHs (3DH or 4DH)
/// - Derives session keys
/// - Computes KC2 for key confirmation
///
/// # Errors
///
/// Returns error if:
/// - Offer deserialization fails
/// - Offer signature is invalid
/// - KC1 verification fails
/// - SPK/OTP IDs don't match
/// - Device ID mismatch
pub fn accept_offer(
    responder_identity: DeviceIdentity,
    responder_spk: SignedPrekey,
    responder_otp: Option<OneTimePrekey>,
    offer_bytes: Vec<u8>,
) -> Result<(HandshakeAccept, SessionKeys)> {
    // Deserialize offer
    let offer_wire: c6p_handshake::OfferWire = serde_json::from_slice(&offer_bytes)
        .map_err(|e| C6pError::SerializationError(format!("Failed to parse offer: {}", e)))?;

    // Parse SPK signature from responder's bundle
    let spk_sig_bytes: [u8; 64] = responder_spk
        .spk_sig
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidSignature("SPK signature must be 64 bytes".to_string()))?;
    let spk_sig = Ed25519Signature::from_bytes(spk_sig_bytes);

    // Parse OTP public key if present
    let otp_pub = responder_otp.as_ref().and_then(|otp| {
        let bytes: [u8; 32] = otp.otp_pub.as_slice().try_into().ok()?;
        Some(X25519PublicKey::from_bytes(bytes))
    });

    let offer_core = offer_from_wire(offer_wire, spk_sig, otp_pub);

    // Parse responder keys
    let responder_device_id_bytes: [u8; 16] = responder_identity
        .device_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidDeviceId("Device ID must be 16 bytes".to_string()))?;
    let responder_device_id = DeviceId(responder_device_id_bytes);

    let responder_ik_dh_priv_bytes: [u8; 32] = responder_identity
        .identity_priv_x25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("X25519 private key must be 32 bytes".to_string()))?;
    let responder_ik_dh_priv = X25519PrivateKey::from_bytes(responder_ik_dh_priv_bytes);

    let responder_ik_dh_pub_bytes: [u8; 32] = responder_identity
        .identity_pub_x25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("X25519 public key must be 32 bytes".to_string()))?;
    let responder_ik_dh_pub = X25519PublicKey::from_bytes(responder_ik_dh_pub_bytes);

    let responder_ik_sig_pub_bytes: [u8; 32] = responder_identity
        .identity_pub_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;
    let responder_ik_sig_pub = Ed25519PublicKey::from_bytes(responder_ik_sig_pub_bytes);

    // Parse SPK
    let spk_id_bytes: [u8; 8] = responder_spk
        .spk_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("SPK ID must be 8 bytes".to_string()))?;
    let spk_id = SpkId(spk_id_bytes);

    let spk_priv_bytes: [u8; 32] = responder_spk
        .spk_priv
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("SPK private key must be 32 bytes".to_string()))?;
    let spk_priv = X25519PrivateKey::from_bytes(spk_priv_bytes);

    let spk_pub_bytes: [u8; 32] = responder_spk
        .spk_pub
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("SPK public key must be 32 bytes".to_string()))?;
    let spk_pub = X25519PublicKey::from_bytes(spk_pub_bytes);

    // Parse OTP if present
    let otp = if let Some(otp) = responder_otp {
        let otp_id_bytes: [u8; 8] = otp
            .otp_id
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidKey("OTP ID must be 8 bytes".to_string()))?;
        let otp_id = OtpId(otp_id_bytes);

        let otp_priv_bytes: [u8; 32] = otp
            .otp_priv
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidKey("OTP private key must be 32 bytes".to_string()))?;
        let otp_priv = X25519PrivateKey::from_bytes(otp_priv_bytes);

        let otp_pub_bytes: [u8; 32] = otp
            .otp_pub
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidKey("OTP public key must be 32 bytes".to_string()))?;
        let otp_pub = X25519PublicKey::from_bytes(otp_pub_bytes);

        Some((otp_id, otp_priv, otp_pub))
    } else {
        None
    };

    // Construct accept
    let (accept_core, handshake_output) = AcceptCore::construct(
        &offer_core,
        responder_device_id,
        &responder_ik_dh_priv,
        &responder_ik_dh_pub,
        &responder_ik_sig_pub,
        spk_id,
        &spk_priv,
        &spk_pub,
        otp,
    )?;

    // Serialize accept to wire format (JSON)
    let serialized = serde_json::to_vec(&c6p_handshake::AcceptWire::from(&accept_core))
        .map_err(|e| C6pError::SerializationError(format!("Failed to serialize accept: {}", e)))?;

    // Convert to bridge types
    let accept = HandshakeAccept {
        session_id: accept_core.session_id.0.to_vec(),
        kc2: accept_core.kc2.to_vec(),
        accept_signature: vec![], // TODO: Add accept signature to core
        serialized,
    };

    let session_keys = SessionKeys {
        session_id: accept_core.session_id.0.to_vec(),
        root_key: handshake_output.root_key.to_vec(),
        kc_key: handshake_output.kc_key.to_vec(),
        send_chain_key: handshake_output.send_chain_key.to_vec(),
        recv_chain_key: handshake_output.recv_chain_key.to_vec(),
        session_binding: handshake_output.session_binding.to_vec(),
    };

    Ok((accept, session_keys))
}

/// Verify accept and validate key confirmation (initiator side)
///
/// After receiving the accept from the responder, verify KC2.
///
/// # Arguments
///
/// * `offer` - Original offer sent to responder
/// * `accept_bytes` - Serialized accept bytes received from responder
/// * `session_keys` - Session keys from create_offer (contains kc_key)
///
/// # Returns
///
/// () on success - session_keys are already valid, just verified
///
/// # Security
///
/// - Verifies KC2 matches expected HMAC value
/// - Validates session ID matches offer
/// - Constant-time comparison for KC2
///
/// # Errors
///
/// Returns error if:
/// - Accept deserialization fails
/// - KC2 verification fails
/// - Session ID mismatch
pub fn verify_accept(
    offer: HandshakeOffer,
    accept_bytes: Vec<u8>,
    session_keys: SessionKeys,
) -> Result<()> {
    use c6p_crypto::TranscriptHash;
    use c6p_handshake::compute_kc2;

    // Deserialize accept
    let accept_wire: c6p_handshake::AcceptWire = serde_json::from_slice(&accept_bytes)
        .map_err(|e| C6pError::SerializationError(format!("Failed to parse accept: {}", e)))?;

    let accept_core = accept_from_wire(accept_wire);

    // Verify session ID matches
    let offer_session_id: [u8; 8] = offer
        .session_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidInput("Session ID must be 8 bytes".to_string()))?;

    if accept_core.session_id.0 != offer_session_id {
        return Err(C6pError::HandshakeFailed(format!(
            "Session ID mismatch: offer={:?}, accept={:?}",
            offer_session_id, accept_core.session_id
        )));
    }

    // Compute expected KC2
    let kc_key: [u8; 32] = session_keys
        .kc_key
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidInput("KC key must be 32 bytes".to_string()))?;

    let initiator_device_id: [u8; 16] = offer
        .initiator_device_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidInput("Device ID must be 16 bytes".to_string()))?;

    let responder_device_id: [u8; 16] = offer
        .responder_device_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidInput("Device ID must be 16 bytes".to_string()))?;

    let transcript_hash_bytes: [u8; 32] = offer
        .transcript_hash
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidInput("Transcript hash must be 32 bytes".to_string()))?;

    // Extract suite_id from offer (ChaCha20-Poly1305 = 0x01)
    let suite_id = 0x01u16;

    let expected_kc2 = compute_kc2(
        &kc_key,
        &SessionId(offer_session_id),
        &DeviceId(initiator_device_id),
        &DeviceId(responder_device_id),
        &TranscriptHash(transcript_hash_bytes),
        suite_id,
    );

    // Constant-time comparison
    use subtle::ConstantTimeEq;
    let kc2_valid: bool = accept_core.kc2.ct_eq(&expected_kc2).into();

    if !kc2_valid {
        return Err(C6pError::HandshakeFailed(
            "KC2 verification failed - possible MITM or corrupted accept".to_string(),
        ));
    }

    Ok(())
}


// Helper: Convert bridge PrekeyBundle to core PrekeyBundle
fn convert_bundle_to_core(bundle: PrekeyBundle) -> Result<PrekeyBundleCore> {
    let responder_device_id_bytes: [u8; 16] = bundle
        .responder_device_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidDeviceId("Device ID must be 16 bytes".to_string()))?;
    let responder_device_id = DeviceId(responder_device_id_bytes);

    let identity_pub_ed25519_bytes: [u8; 32] = bundle
        .identity_pub_ed25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("Ed25519 public key must be 32 bytes".to_string()))?;
    let identity_pub_ed25519 = Ed25519PublicKey::from_bytes(identity_pub_ed25519_bytes);

    let identity_pub_x25519_bytes: [u8; 32] = bundle
        .identity_pub_x25519
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("X25519 public key must be 32 bytes".to_string()))?;
    let identity_pub_x25519 = X25519PublicKey::from_bytes(identity_pub_x25519_bytes);

    let spk_id_bytes: [u8; 8] = bundle
        .spk_id
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("SPK ID must be 8 bytes".to_string()))?;
    let spk_id = SpkId(spk_id_bytes);

    let spk_pub_bytes: [u8; 32] = bundle
        .spk_pub
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidKey("SPK public key must be 32 bytes".to_string()))?;
    let spk_pub = X25519PublicKey::from_bytes(spk_pub_bytes);

    let spk_sig_bytes: [u8; 64] = bundle
        .spk_sig
        .as_slice()
        .try_into()
        .map_err(|_| C6pError::InvalidSignature("SPK signature must be 64 bytes".to_string()))?;
    let spk_sig = Ed25519Signature::from_bytes(spk_sig_bytes);

    let otp = if let (Some(otp_id), Some(otp_pub)) = (bundle.otp_id, bundle.otp_pub) {
        let otp_id_bytes: [u8; 8] = otp_id
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidKey("OTP ID must be 8 bytes".to_string()))?;

        let otp_pub_bytes: [u8; 32] = otp_pub
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidKey("OTP public key must be 32 bytes".to_string()))?;

        Some((OtpId(otp_id_bytes), X25519PublicKey::from_bytes(otp_pub_bytes)))
    } else {
        None
    };

    Ok(PrekeyBundleCore::new(
        responder_device_id,
        identity_pub_ed25519,
        identity_pub_x25519,
        spk_id,
        spk_pub,
        spk_sig,
        otp,
    ))
}

// Helper: Convert OfferWire to Offer
// Note: Reconstructs fields from responder's bundle data
fn offer_from_wire(
    wire: c6p_handshake::OfferWire,
    spk_sig: Ed25519Signature,
    otp_pub: Option<X25519PublicKey>,
) -> OfferCore {
    use c6p_crypto::TranscriptHash;

    OfferCore {
        version: wire.version,
        suite_id: wire.suite_id,
        session_id: SessionId(wire.session_id),
        initiator_device_id: DeviceId(wire.initiator_device_id),
        responder_device_id: DeviceId(wire.responder_device_id),
        initiator_identity_dh_pub: X25519PublicKey::from_bytes(wire.initiator_identity_dh_pub),
        initiator_identity_sig_pub: Ed25519PublicKey::from_bytes(wire.initiator_identity_sig_pub),
        initiator_ephemeral_dh_pub: X25519PublicKey::from_bytes(wire.initiator_ephemeral_dh_pub),
        used_spk_id: SpkId(wire.used_signed_prekey_id),
        used_spk_pub: X25519PublicKey::from_bytes(wire.used_signed_prekey_public_key_x25519),
        used_spk_sig: spk_sig,  // From bundle, not in wire
        used_otp_id: wire.used_one_time_prekey_id.map(OtpId),
        used_otp_pub: otp_pub,  // From bundle, not in wire
        transcript_hash: TranscriptHash(wire.transcript_hash),
        kc1: wire.kc1,
        offer_signature: Ed25519Signature::from_bytes(wire.offer_signature_ed25519),
    }
}

// Helper: Convert AcceptWire to Accept
fn accept_from_wire(wire: c6p_handshake::AcceptWire) -> AcceptCore {
    AcceptCore {
        session_id: SessionId(wire.session_id),
        responder_device_id: DeviceId(wire.responder_device_id),
        kc2: wire.kc2,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::identity::{generate_identity, generate_one_time_prekey, generate_signed_prekey};

    #[test]
    fn test_handshake_flow_3dh() {
        // Generate identities
        let initiator = generate_identity().unwrap();
        let responder = generate_identity().unwrap();

        // Responder generates SPK (no OTP for 3DH)
        let responder_spk = generate_signed_prekey(responder.clone()).unwrap();

        // Responder publishes bundle
        let bundle = PrekeyBundle {
            responder_device_id: responder.device_id.clone(),
            identity_pub_ed25519: responder.identity_pub_ed25519.clone(),
            identity_pub_x25519: responder.identity_pub_x25519.clone(),
            spk_id: responder_spk.spk_id.clone(),
            spk_pub: responder_spk.spk_pub.clone(),
            spk_sig: responder_spk.spk_sig.clone(),
            otp_id: None,
            otp_pub: None,
        };

        // Initiator creates offer
        let (offer, initiator_keys) = create_offer(initiator.clone(), bundle).unwrap();

        assert_eq!(offer.session_id.len(), 8);
        assert_eq!(offer.initiator_device_id, initiator.device_id);
        assert_eq!(offer.responder_device_id, responder.device_id);

        // Responder accepts offer
        let (accept, responder_keys) = accept_offer(
            responder.clone(),
            responder_spk,
            None,
            offer.serialized.clone(),
        )
        .unwrap();

        assert_eq!(accept.session_id, offer.session_id);

        // Verify session keys were returned
        assert_eq!(initiator_keys.session_id, offer.session_id);
        assert_eq!(responder_keys.session_id, accept.session_id);
    }

    #[test]
    fn test_handshake_flow_4dh() {
        // Generate identities
        let initiator = generate_identity().unwrap();
        let responder = generate_identity().unwrap();

        // Responder generates SPK + OTP (for 4DH)
        let responder_spk = generate_signed_prekey(responder.clone()).unwrap();
        let responder_otp = generate_one_time_prekey().unwrap();

        // Responder publishes bundle with OTP
        let bundle = PrekeyBundle {
            responder_device_id: responder.device_id.clone(),
            identity_pub_ed25519: responder.identity_pub_ed25519.clone(),
            identity_pub_x25519: responder.identity_pub_x25519.clone(),
            spk_id: responder_spk.spk_id.clone(),
            spk_pub: responder_spk.spk_pub.clone(),
            spk_sig: responder_spk.spk_sig.clone(),
            otp_id: Some(responder_otp.otp_id.clone()),
            otp_pub: Some(responder_otp.otp_pub.clone()),
        };

        // Initiator creates offer
        let (offer, initiator_keys) = create_offer(initiator.clone(), bundle).unwrap();

        assert_eq!(offer.used_otp_id.is_some(), true); // 4DH used

        // Responder accepts offer
        let (accept, responder_keys) = accept_offer(
            responder.clone(),
            responder_spk,
            Some(responder_otp),
            offer.serialized.clone(),
        )
        .unwrap();

        assert_eq!(accept.session_id, offer.session_id);

        // Verify session keys were returned
        assert_eq!(initiator_keys.session_id, offer.session_id);
        assert_eq!(responder_keys.session_id, accept.session_id);
    }
}
