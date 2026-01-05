//! Cryptographic operations for IslandAccord v1
//!
//! Implements DH operations, signature verification, and transcript computation.
//! All implementations are normative and MUST match island-accord-crypto.md.

use crate::types::*;
use crate::error::{HandshakeError, Result};
use c6p_crypto::{SessionId, DeviceId, TranscriptHash};
use sha2::{Digest, Sha256};
use hmac::{Hmac, Mac};

type HmacSha256 = Hmac<Sha256>;

// ============================================================================
// Normative Labels (MUST NOT change)
// ============================================================================

/// Label for prekey signature (island-accord-crypto.md §3.2)
const LABEL_PREKEY: &[u8] = b"C6P_PREKEY_V1";

/// Label for handshake transcript (island-accord-crypto.md §6.1)
const LABEL_HANDSHAKE: &[u8] = b"ISLAND_ACCORD_V1";

/// Label for offer signature (island-accord-crypto.md §8.1)
const LABEL_OFFER_SIG: &[u8] = b"IA_OFFER_SIG_V1";

/// Label for KC payload (island-accord-crypto.md §9.1, references c6p-key-schedule.md §9.1)
const LABEL_KC: &[u8] = b"C6P_KC_V1";

/// Direction tag for KC1 (initiator) (island-accord-crypto.md §9.2)
const KC_DIRECTION_INIT: &[u8] = b"INIT";

/// Direction tag for KC2 (responder) (island-accord-crypto.md §9.2)
const KC_DIRECTION_RESP: &[u8] = b"RESP";

// ============================================================================
// Protocol Versions
// ============================================================================

/// C6P protocol version (island-accord-crypto.md §1.1)
const C6P_VERSION: u8 = 0x01;

/// IslandAccord version (island-accord-crypto.md §1.1)
const IA_VERSION: u8 = 0x01;

// ============================================================================
// X25519 Diffie-Hellman
// ============================================================================

/// Perform X25519 Diffie-Hellman
///
/// Normative reference: island-accord-crypto.md §5
///
/// # Arguments
/// * `private_key` - X25519 private key (32 bytes)
/// * `public_key` - X25519 public key (32 bytes)
///
/// # Returns
/// * DH shared secret (32 bytes)
///
/// # Security
/// - Constant-time operation (x25519-dalek guarantees)
/// - Small-subgroup attacks mitigated by clamping (x25519-dalek)
pub fn x25519_dh(private_key: &X25519PrivateKey, public_key: &X25519PublicKey) -> DhSecret {
    // x25519-dalek 2.0 uses x25519 function directly
    let shared_secret = x25519_dalek::x25519(private_key.0, public_key.0);
    DhSecret(shared_secret)
}

// ============================================================================
// Ed25519 Signature Operations
// ============================================================================

/// Verify Ed25519 signature
///
/// Normative reference: island-accord-crypto.md §3.2 (SPK signature)
///
/// # Arguments
/// * `public_key` - Ed25519 public key
/// * `message` - Message bytes
/// * `signature` - Ed25519 signature
///
/// # Returns
/// * `Ok(())` if signature is valid
/// * `Err(HandshakeError::InvalidSpkSignature)` if invalid
///
/// # Security
/// - Constant-time verification (ed25519-dalek guarantees)
pub fn ed25519_verify(
    public_key: &Ed25519PublicKey,
    message: &[u8],
    signature: &Ed25519Signature,
) -> Result<()> {
    use ed25519_dalek::{Signature, Verifier, VerifyingKey};

    let verifying_key = VerifyingKey::from_bytes(&public_key.0)
        .map_err(|e| HandshakeError::CryptoError(format!("Invalid Ed25519 public key: {}", e)))?;

    let sig = Signature::from_bytes(&signature.0);

    verifying_key
        .verify(message, &sig)
        .map_err(|_| HandshakeError::InvalidSpkSignature)?;

    Ok(())
}

/// Sign message with Ed25519 private key
///
/// Normative reference: island-accord-crypto.md §8 (offer signature)
///
/// # Arguments
/// * `private_key` - Ed25519 private key
/// * `message` - Message bytes
///
/// # Returns
/// * Ed25519 signature (64 bytes)
pub fn ed25519_sign(
    private_key: &Ed25519PrivateKey,
    message: &[u8],
) -> Result<Ed25519Signature> {
    use ed25519_dalek::{Signature, Signer, SigningKey};

    let signing_key = SigningKey::from_bytes(&private_key.0);
    let signature: Signature = signing_key.sign(message);

    Ok(Ed25519Signature(signature.to_bytes()))
}

// ============================================================================
// Prekey Signature
// ============================================================================

/// Verify SPK signature
///
/// Normative reference: island-accord-crypto.md §3.2
///
/// MSG = LABEL_PREKEY || spkId_bytes(8) || spkPub_bytes(32)
/// Verify: Ed25519.Verify(B_IK_sig_pub, spkSig, MSG) == true
///
/// CRITICAL: This MUST be called BEFORE any DH operations (fail-closed)
pub fn verify_spk_signature(
    identity_pub_ed25519: &Ed25519PublicKey,
    spk_id: &SpkId,
    spk_pub: &X25519PublicKey,
    spk_sig: &Ed25519Signature,
) -> Result<()> {
    let mut message = Vec::with_capacity(LABEL_PREKEY.len() + 8 + 32);
    message.extend_from_slice(LABEL_PREKEY);
    message.extend_from_slice(&spk_id.0);
    message.extend_from_slice(&spk_pub.0);

    ed25519_verify(identity_pub_ed25519, &message, spk_sig)
        .map_err(|_| HandshakeError::InvalidSpkSignature)
}

// ============================================================================
// Transcript Hash
// ============================================================================

/// Build canonical transcript bytes
///
/// Normative reference: island-accord-crypto.md §6.2
///
/// Transcript fields (exact order):
/// 1) LABEL_HANDSHAKE
/// 2) U8(IA_VERSION)
/// 3) U8(C6P_VERSION)
/// 4) U8(suite_id)
/// 5) sessionId_bytes (8)
/// 6) A_deviceId_bytes (16)
/// 7) B_deviceId_bytes (16)
/// 8) A_IK_dh_pub (32)
/// 9) A_IK_sig_pub (32)
/// 10) A_EK_pub (32)
/// 11) B_IK_dh_pub (32)
/// 12) B_IK_sig_pub (32)
/// 13) spkId_bytes (8)
/// 14) spkPub (32)
/// 15) spkSig (64)
/// 16) otpFlag (1 byte: 0x01 if OTP used, 0x00 otherwise)
/// 17) if otpFlag == 0x01: otpId_bytes(8) || otpPub(32)
pub fn build_transcript(
    suite_id: u16,
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
    initiator_ik_dh_pub: &X25519PublicKey,
    initiator_ik_sig_pub: &Ed25519PublicKey,
    initiator_ek_pub: &X25519PublicKey,
    responder_ik_dh_pub: &X25519PublicKey,
    responder_ik_sig_pub: &Ed25519PublicKey,
    spk_id: &SpkId,
    spk_pub: &X25519PublicKey,
    spk_sig: &Ed25519Signature,
    otp: Option<(&OtpId, &X25519PublicKey)>,
) -> Vec<u8> {
    let mut transcript = Vec::with_capacity(512); // Pre-allocate

    // 1) Label
    transcript.extend_from_slice(LABEL_HANDSHAKE);

    // 2) IA version
    transcript.push(IA_VERSION);

    // 3) C6P version
    transcript.push(C6P_VERSION);

    // 4) Suite ID (as single byte - suite_id is u16 but wire uses u8)
    transcript.push(suite_id as u8);

    // 5) Session ID
    transcript.extend_from_slice(&session_id.0);

    // 6) Initiator device ID
    transcript.extend_from_slice(&initiator_device_id.0);

    // 7) Responder device ID
    transcript.extend_from_slice(&responder_device_id.0);

    // 8) Initiator IK DH public key
    transcript.extend_from_slice(&initiator_ik_dh_pub.0);

    // 9) Initiator IK sig public key
    transcript.extend_from_slice(&initiator_ik_sig_pub.0);

    // 10) Initiator ephemeral public key
    transcript.extend_from_slice(&initiator_ek_pub.0);

    // 11) Responder IK DH public key
    transcript.extend_from_slice(&responder_ik_dh_pub.0);

    // 12) Responder IK sig public key
    transcript.extend_from_slice(&responder_ik_sig_pub.0);

    // 13) SPK ID
    transcript.extend_from_slice(&spk_id.0);

    // 14) SPK public key
    transcript.extend_from_slice(&spk_pub.0);

    // 15) SPK signature
    transcript.extend_from_slice(&spk_sig.0);

    // 16) OTP flag
    if let Some((otp_id, otp_pub)) = otp {
        transcript.push(0x01); // OTP present
        // 17) OTP ID
        transcript.extend_from_slice(&otp_id.0);
        // 17) OTP public key
        transcript.extend_from_slice(&otp_pub.0);
    } else {
        transcript.push(0x00); // No OTP
    }

    transcript
}

/// Compute transcript hash (SHA-256)
///
/// Normative reference: island-accord-crypto.md §6.3
///
/// transcript_hash = SHA-256(T)
pub fn compute_transcript_hash(transcript_bytes: &[u8]) -> TranscriptHash {
    let mut hasher = Sha256::new();
    hasher.update(transcript_bytes);
    let hash = hasher.finalize();

    TranscriptHash(hash.into())
}

// ============================================================================
// Offer Signature
// ============================================================================

/// Compute offer signature input
///
/// Normative reference: island-accord-crypto.md §8.2
///
/// sig_input = SHA256(
///   LABEL_OFFER_SIG ||
///   transcript_hash(32) ||
///   U8(C6P_VERSION) ||
///   U8(suite_id) ||
///   sessionId_bytes(8) ||
///   A_deviceId_bytes(16) ||
///   B_deviceId_bytes(16)
/// )
pub fn compute_offer_signature_input(
    transcript_hash: &TranscriptHash,
    suite_id: u16,
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
) -> [u8; 32] {
    let mut hasher = Sha256::new();

    hasher.update(LABEL_OFFER_SIG);
    hasher.update(&transcript_hash.0);
    hasher.update(&[C6P_VERSION]);
    hasher.update(&[suite_id as u8]);
    hasher.update(&session_id.0);
    hasher.update(&initiator_device_id.0);
    hasher.update(&responder_device_id.0);

    hasher.finalize().into()
}

/// Sign offer (initiator side)
///
/// Normative reference: island-accord-crypto.md §8.3
pub fn sign_offer(
    initiator_ik_sig_priv: &Ed25519PrivateKey,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
) -> Result<Ed25519Signature> {
    let sig_input = compute_offer_signature_input(
        transcript_hash,
        suite_id,
        session_id,
        initiator_device_id,
        responder_device_id,
    );

    ed25519_sign(initiator_ik_sig_priv, &sig_input)
}

/// Verify offer signature (responder side)
///
/// Normative reference: island-accord-crypto.md §8.3
pub fn verify_offer_signature(
    initiator_ik_sig_pub: &Ed25519PublicKey,
    offer_signature: &Ed25519Signature,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
) -> Result<()> {
    let sig_input = compute_offer_signature_input(
        transcript_hash,
        suite_id,
        session_id,
        initiator_device_id,
        responder_device_id,
    );

    ed25519_verify(initiator_ik_sig_pub, &sig_input, offer_signature)
        .map_err(|_| HandshakeError::InvalidOfferSignature)
}

// ============================================================================
// Key Confirmation (KC)
// ============================================================================

/// Compute KC payload
///
/// Normative reference: island-accord-crypto.md §9.1, c6p-key-schedule.md §9.1
///
/// kc_payload = SHA256(
///   "C6P_KC_V1" ||
///   U8(C6P_VERSION) ||
///   CTX ||
///   transcript_hash ||
///   U8(suite_id)
/// )
///
/// Where CTX = session_id(8) || initiator_device_id(16) || responder_device_id(16)
pub fn compute_kc_payload(
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
) -> [u8; 32] {
    let mut hasher = Sha256::new();

    hasher.update(LABEL_KC);
    hasher.update(&[C6P_VERSION]);
    // CTX
    hasher.update(&session_id.0);
    hasher.update(&initiator_device_id.0);
    hasher.update(&responder_device_id.0);
    // transcript_hash
    hasher.update(&transcript_hash.0);
    hasher.update(&[suite_id as u8]);

    hasher.finalize().into()
}

/// Compute KC tag (KC1 or KC2)
///
/// Normative reference: island-accord-crypto.md §9.2, c6p-key-schedule.md §9.3
///
/// kc1 = HMAC-SHA256(kc_key, kc_payload || "INIT")
/// kc2 = HMAC-SHA256(kc_key, kc_payload || "RESP")
pub fn compute_kc_tag(kc_key: &[u8; 32], kc_payload: &[u8; 32], direction: &[u8]) -> [u8; 32] {
    let mut mac = HmacSha256::new_from_slice(kc_key).expect("HMAC accepts any key length");

    mac.update(kc_payload);
    mac.update(direction);

    mac.finalize().into_bytes().into()
}

/// Compute KC1 (initiator tag)
pub fn compute_kc1(
    kc_key: &[u8; 32],
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
) -> [u8; 32] {
    let kc_payload = compute_kc_payload(
        session_id,
        initiator_device_id,
        responder_device_id,
        transcript_hash,
        suite_id,
    );

    compute_kc_tag(kc_key, &kc_payload, KC_DIRECTION_INIT)
}

/// Compute KC2 (responder tag)
pub fn compute_kc2(
    kc_key: &[u8; 32],
    session_id: &SessionId,
    initiator_device_id: &DeviceId,
    responder_device_id: &DeviceId,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
) -> [u8; 32] {
    let kc_payload = compute_kc_payload(
        session_id,
        initiator_device_id,
        responder_device_id,
        transcript_hash,
        suite_id,
    );

    compute_kc_tag(kc_key, &kc_payload, KC_DIRECTION_RESP)
}

// ============================================================================
// IKM Construction
// ============================================================================

/// Construct Input Key Material (IKM) from DH outputs
///
/// Normative reference: island-accord-crypto.md §5.3
///
/// IKM = DH1 || DH2 || DH3 || [DH4]
///
/// Length:
/// - without OTP: 96 bytes (3 × 32)
/// - with OTP: 128 bytes (4 × 32)
pub fn construct_ikm(dh1: &DhSecret, dh2: &DhSecret, dh3: &DhSecret, dh4: Option<&DhSecret>) -> Vec<u8> {
    let mut ikm = Vec::with_capacity(if dh4.is_some() { 128 } else { 96 });

    ikm.extend_from_slice(&dh1.0);
    ikm.extend_from_slice(&dh2.0);
    ikm.extend_from_slice(&dh3.0);

    if let Some(dh4_secret) = dh4 {
        ikm.extend_from_slice(&dh4_secret.0);
    }

    ikm
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_x25519_dh() {
        // Test with known values from RFC 7748
        let scalar = X25519PrivateKey([
            0xa5, 0x46, 0xe3, 0x6b, 0xf0, 0x52, 0x7c, 0x9d,
            0x3b, 0x16, 0x15, 0x4b, 0x82, 0x46, 0x5e, 0xdd,
            0x62, 0x14, 0x4c, 0x0a, 0xc1, 0xfc, 0x5a, 0x18,
            0x50, 0x6a, 0x22, 0x44, 0xba, 0x44, 0x9a, 0xc4,
        ]);

        let point = X25519PublicKey([
            0xe6, 0xdb, 0x68, 0x67, 0x58, 0x30, 0x30, 0xdb,
            0x35, 0x94, 0xc1, 0xa4, 0x24, 0xb1, 0x5f, 0x7c,
            0x72, 0x66, 0x24, 0xec, 0x26, 0xb3, 0x35, 0x3b,
            0x10, 0xa9, 0x03, 0xa6, 0xd0, 0xab, 0x1c, 0x4c,
        ]);

        let shared = x25519_dh(&scalar, &point);

        let expected = [
            0xc3, 0xda, 0x55, 0x37, 0x9d, 0xe9, 0xc6, 0x90,
            0x8e, 0x94, 0xea, 0x4d, 0xf2, 0x8d, 0x08, 0x4f,
            0x32, 0xec, 0xcf, 0x03, 0x49, 0x1c, 0x71, 0xf7,
            0x54, 0xb4, 0x07, 0x55, 0x77, 0xa2, 0x85, 0x52,
        ];

        assert_eq!(shared.0, expected);
    }

    #[test]
    fn test_transcript_hash_deterministic() {
        let transcript = b"test transcript";
        let hash1 = compute_transcript_hash(transcript);
        let hash2 = compute_transcript_hash(transcript);

        assert_eq!(hash1.0, hash2.0);
    }

    #[test]
    fn test_kc_payload_deterministic() {
        let session_id = SessionId([0x01; 8]);
        let initiator_device_id = DeviceId([0xAA; 16]);
        let responder_device_id = DeviceId([0xBB; 16]);
        let transcript_hash = TranscriptHash([0x42; 32]);
        let suite_id = 0x01;

        let payload1 = compute_kc_payload(
            &session_id,
            &initiator_device_id,
            &responder_device_id,
            &transcript_hash,
            suite_id,
        );

        let payload2 = compute_kc_payload(
            &session_id,
            &initiator_device_id,
            &responder_device_id,
            &transcript_hash,
            suite_id,
        );

        assert_eq!(payload1, payload2);
    }

    #[test]
    fn test_kc1_kc2_different() {
        let kc_key = [0x11; 32];
        let session_id = SessionId([0x01; 8]);
        let initiator_device_id = DeviceId([0xAA; 16]);
        let responder_device_id = DeviceId([0xBB; 16]);
        let transcript_hash = TranscriptHash([0x42; 32]);
        let suite_id = 0x01;

        let kc1 = compute_kc1(
            &kc_key,
            &session_id,
            &initiator_device_id,
            &responder_device_id,
            &transcript_hash,
            suite_id,
        );

        let kc2 = compute_kc2(
            &kc_key,
            &session_id,
            &initiator_device_id,
            &responder_device_id,
            &transcript_hash,
            suite_id,
        );

        // KC1 and KC2 must be different (different direction tags)
        assert_ne!(kc1, kc2);
    }

    #[test]
    fn test_ikm_construction_3dh() {
        let dh1 = DhSecret([0x01; 32]);
        let dh2 = DhSecret([0x02; 32]);
        let dh3 = DhSecret([0x03; 32]);

        let ikm = construct_ikm(&dh1, &dh2, &dh3, None);

        assert_eq!(ikm.len(), 96); // 3 × 32
        assert_eq!(&ikm[0..32], &dh1.0);
        assert_eq!(&ikm[32..64], &dh2.0);
        assert_eq!(&ikm[64..96], &dh3.0);
    }

    #[test]
    fn test_ikm_construction_4dh() {
        let dh1 = DhSecret([0x01; 32]);
        let dh2 = DhSecret([0x02; 32]);
        let dh3 = DhSecret([0x03; 32]);
        let dh4 = DhSecret([0x04; 32]);

        let ikm = construct_ikm(&dh1, &dh2, &dh3, Some(&dh4));

        assert_eq!(ikm.len(), 128); // 4 × 32
        assert_eq!(&ikm[0..32], &dh1.0);
        assert_eq!(&ikm[32..64], &dh2.0);
        assert_eq!(&ikm[64..96], &dh3.0);
        assert_eq!(&ikm[96..128], &dh4.0);
    }
}
