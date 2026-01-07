//! C6P Key Schedule (v1) - NORMATIVE IMPLEMENTATION
//!
//! **CRITICAL:** This module implements docs/crypto/c6p-key-schedule.md exactly.
//! Any deviation from the normative spec is a protocol violation.
//!
//! Domain separation labels are defined in constants.rs and MUST NOT be changed.

use crate::constants::*;
use crate::primitives::*;
use crate::types::*;

// ============================================================================
// §4: IslandAccord v1 → Initial Root Derivation
// ============================================================================

/// Derive root_key and kc_key from IslandAccord handshake
///
/// Implements c6p-key-schedule.md §4 (Root + KC derivation)
///
/// # Arguments
/// * `ikm` - Input Key Material (DH1 || DH2 || DH3 || [DH4])
///   - 96 bytes (no OTP) or 128 bytes (with OTP)
/// * `transcript_hash` - SHA-256 hash of canonical transcript (32 bytes)
/// * `ctx` - Session context (CTX = session_id || initiator_device_id || responder_device_id)
///
/// # Returns
/// * `(root_key, kc_key)` - Both 32 bytes
///
/// # Specification Reference
/// See docs/crypto/c6p-key-schedule.md §4.2-4.5
pub fn derive_root_and_kc(
    ikm: &[u8],
    transcript_hash: &TranscriptHash,
    ctx: &SessionContext,
) -> (RootKey, KcKey) {
    // §4.2: Transcript hash (already computed by caller)
    let transcript_hash_bytes = &transcript_hash.0;

    // §4.3: Root salt (session + transcript bound)
    let mut salt_root_data = Vec::with_capacity(LABEL_ROOT.len() + 40 + 32);
    salt_root_data.extend_from_slice(LABEL_ROOT); // "C6P_ROOT_V1"
    salt_root_data.extend_from_slice(&ctx.to_bytes()); // CTX (40 bytes)
    salt_root_data.extend_from_slice(transcript_hash_bytes); // transcript_hash (32 bytes)
    let salt_root = sha256(&salt_root_data);

    // §4.4: Root extraction + expansion
    let prk_root = hkdf_extract(&salt_root, ikm);

    // root_key = HKDF-Expand(prk_root, info = "C6P_ROOT_V1" || U8(0x01), L = 32)
    let mut root_info = Vec::with_capacity(LABEL_ROOT.len() + 1);
    root_info.extend_from_slice(LABEL_ROOT);
    root_info.push(0x01);
    let root_key_bytes = hkdf_expand(&prk_root, &root_info, ROOT_KEY_LEN);

    // §4.5: Key confirmation key (from root PRK)
    // kc_key = HKDF-Expand(prk_root, info = "C6P_KC_V1" || U8(0x01) || transcript_hash, L = 32)
    let mut kc_info = Vec::with_capacity(LABEL_KC.len() + 1 + 32);
    kc_info.extend_from_slice(LABEL_KC);
    kc_info.push(0x01);
    kc_info.extend_from_slice(transcript_hash_bytes);
    let kc_key_bytes = hkdf_expand(&prk_root, &kc_info, KC_KEY_LEN);

    // Return as zeroizing types
    let mut root_key_arr = [0u8; ROOT_KEY_LEN];
    let mut kc_key_arr = [0u8; KC_KEY_LEN];
    root_key_arr.copy_from_slice(&root_key_bytes);
    kc_key_arr.copy_from_slice(&kc_key_bytes);

    (RootKey(root_key_arr), KcKey(kc_key_arr))
}

// ============================================================================
// §5: Stream Chain Derivation
// ============================================================================

/// Derive initial chain keys for both streams (i2r and r2i)
///
/// Implements c6p-key-schedule.md §5 (Stream Chain Derivation)
///
/// # Arguments
/// * `root_key` - Root key from §4
/// * `transcript_hash` - SHA-256 hash of canonical transcript
/// * `ctx` - Session context
/// * `stream_ctx` - Per-stream context (stream_id, message_type, suite_id)
///
/// # Returns
/// * `ChainKey` for the specified stream
///
/// # Specification Reference
/// See docs/crypto/c6p-key-schedule.md §5.1-5.3
pub fn derive_initial_chain_key(
    root_key: &RootKey,
    transcript_hash: &TranscriptHash,
    ctx: &SessionContext,
    stream_ctx: &StreamContext,
) -> ChainKey {
    // §5.1: Chain salt
    // salt_chain = SHA256("C6P_CHAIN_V1" || CTX || transcript_hash)
    let mut salt_chain_data = Vec::with_capacity(LABEL_CHAIN.len() + 40 + 32);
    salt_chain_data.extend_from_slice(LABEL_CHAIN);
    salt_chain_data.extend_from_slice(&ctx.to_bytes());
    salt_chain_data.extend_from_slice(&transcript_hash.0);
    let salt_chain = sha256(&salt_chain_data);

    // §5.2: Chain PRK
    // prk_chain = HKDF-Extract(salt = salt_chain, ikm = root_key)
    let prk_chain = hkdf_extract(&salt_chain, &root_key.0);

    // §5.3: Initial chain key (per stream, per suite, per message type)
    // chain_key = HKDF-Expand(prk_chain,
    //   info = "C6P_CHAIN_V1" || U8(0x01) || U8(stream_id) || U8(suite_id) || U8(message_type),
    //   L = 32)
    //
    // NOTE: Spec shows suite_id as u8 in STREAM_CTX but suite_id is u16.
    // We use only the low byte for now (suite IDs 0x01-0x03 fit in u8).
    let mut chain_info = Vec::with_capacity(LABEL_CHAIN.len() + 4);
    chain_info.extend_from_slice(LABEL_CHAIN);
    chain_info.push(0x01); // version
    chain_info.push(stream_ctx.stream_id);
    chain_info.push((stream_ctx.suite_id & 0xFF) as u8); // Low byte of suite_id
    chain_info.push(stream_ctx.message_type);
    let chain_key_bytes = hkdf_expand(&prk_chain, &chain_info, CHAIN_KEY_LEN);

    let mut chain_key_arr = [0u8; CHAIN_KEY_LEN];
    chain_key_arr.copy_from_slice(&chain_key_bytes);
    ChainKey(chain_key_arr)
}

// ============================================================================
// §6: Per-Message Derivation & Ratchet Step
// ============================================================================

/// Derive per-message key material and next chain key
///
/// Implements c6p-key-schedule.md §6 (Per-Message Derivation & Ratchet Step)
///
/// # Arguments
/// * `chain_key` - Current chain key for this stream
/// * `counter` - Message counter (u64, strictly monotonic)
/// * `ctx` - Session context
/// * `transcript_hash` - Transcript hash
/// * `stream_ctx` - Per-stream context
///
/// # Returns
/// * `(mk_material, next_chain_key)` - Message key material (32 bytes) and next chain key (32 bytes)
///
/// # Specification Reference
/// See docs/crypto/c6p-key-schedule.md §6.1-6.4
///
/// **CRITICAL:** This is the core ratchet step. Both send and receive paths MUST use this function.
pub fn derive_per_message(
    chain_key: &ChainKey,
    counter: u64,
    ctx: &SessionContext,
    transcript_hash: &TranscriptHash,
    stream_ctx: &StreamContext,
) -> (MkMaterial, ChainKey) {
    // §6.1: Per-message salt
    // salt_msg = SHA256("C6P_MSG_V1" || CTX || transcript_hash || STREAM_CTX || BE64(counter))
    let mut salt_msg_data = Vec::with_capacity(LABEL_MSG.len() + 40 + 32 + 3 + 8);
    salt_msg_data.extend_from_slice(LABEL_MSG); // "C6P_MSG_V1"
    salt_msg_data.extend_from_slice(&ctx.to_bytes()); // CTX (40 bytes)
    salt_msg_data.extend_from_slice(&transcript_hash.0); // transcript_hash (32 bytes)
    salt_msg_data.extend_from_slice(&stream_ctx.to_bytes()); // STREAM_CTX (3 bytes)
    salt_msg_data.extend_from_slice(&be64(counter)); // BE64(counter) (8 bytes)
    let salt_msg = sha256(&salt_msg_data);

    // §6.2: Per-message PRK
    // prk_msg = HKDF-Extract(salt = salt_msg, ikm = chain_key)
    let prk_msg = hkdf_extract(&salt_msg, &chain_key.0);

    // §6.3: Message key material
    // mk_material = HKDF-Expand(prk_msg, info = "C6P_MSG_V1" || U8(0x01) || STREAM_CTX, L = 32)
    let mut msg_info = Vec::with_capacity(LABEL_MSG.len() + 1 + 3);
    msg_info.extend_from_slice(LABEL_MSG);
    msg_info.push(0x01);
    msg_info.extend_from_slice(&stream_ctx.to_bytes());
    let mk_material_bytes = hkdf_expand(&prk_msg, &msg_info, MK_MATERIAL_LEN);

    // §6.4: Next chain key
    // next_chain_key = HKDF-Expand(prk_msg, info = "C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX || BE64(counter), L = 32)
    let mut chain_info = Vec::with_capacity(LABEL_CHAIN.len() + 1 + 3 + 8);
    chain_info.extend_from_slice(LABEL_CHAIN);
    chain_info.push(0x01);
    chain_info.extend_from_slice(&stream_ctx.to_bytes());
    chain_info.extend_from_slice(&be64(counter));
    let next_chain_key_bytes = hkdf_expand(&prk_msg, &chain_info, CHAIN_KEY_LEN);

    // Return as zeroizing types
    let mut mk_material_arr = [0u8; MK_MATERIAL_LEN];
    let mut next_chain_key_arr = [0u8; CHAIN_KEY_LEN];
    mk_material_arr.copy_from_slice(&mk_material_bytes);
    next_chain_key_arr.copy_from_slice(&next_chain_key_bytes);

    (MkMaterial(mk_material_arr), ChainKey(next_chain_key_arr))
}

// ============================================================================
// §8: Session Binding (for nonce derivation and AAD)
// ============================================================================

/// Compute session binding (for AAD and nonce derivation)
///
/// Implements c6p-key-schedule.md §8.1 and c6p-aead-and-aad.md
///
/// # Arguments
/// * `ctx` - Session context
///
/// # Returns
/// * `SessionBinding` - SHA-256 hash (32 bytes)
///
/// # Specification Reference
/// See docs/crypto/c6p-key-schedule.md §8.1
pub fn compute_session_binding(ctx: &SessionContext) -> SessionBinding {
    // session_binding = SHA-256("C6P_BIND_V1" || session_id || initiator_device_id || responder_device_id)
    let mut binding_data = Vec::with_capacity(LABEL_BIND.len() + 8 + 16 + 16);
    binding_data.extend_from_slice(LABEL_BIND);
    binding_data.extend_from_slice(&ctx.session_id.0);
    binding_data.extend_from_slice(&ctx.initiator_device_id.0);
    binding_data.extend_from_slice(&ctx.responder_device_id.0);
    let binding_hash = sha256(&binding_data);

    SessionBinding(binding_hash)
}

// ============================================================================
// §9: Key Confirmation (IslandAccord v1)
// ============================================================================

/// Compute key confirmation payload (canonical)
///
/// Implements c6p-key-schedule.md §9.1
///
/// # Arguments
/// * `ctx` - Session context
/// * `transcript_hash` - Transcript hash
/// * `suite_id` - Suite ID
///
/// # Returns
/// * SHA-256 hash (32 bytes)
pub fn compute_kc_payload(
    ctx: &SessionContext,
    transcript_hash: &TranscriptHash,
    suite_id: u16,
) -> [u8; 32] {
    // kc_payload = SHA256("C6P_KC_V1" || U8(0x01) || CTX || transcript_hash || U8(suite_id))
    let mut payload_data = Vec::with_capacity(LABEL_KC.len() + 1 + 40 + 32 + 1);
    payload_data.extend_from_slice(LABEL_KC);
    payload_data.push(0x01);
    payload_data.extend_from_slice(&ctx.to_bytes());
    payload_data.extend_from_slice(&transcript_hash.0);
    payload_data.push((suite_id & 0xFF) as u8); // Low byte
    sha256(&payload_data)
}

/// Compute directional key confirmation tag (INIT or RESP)
///
/// Implements c6p-key-schedule.md §9.2-9.3
///
/// # Arguments
/// * `kc_key` - Key confirmation key from §4.5
/// * `kc_payload` - Canonical KC payload from `compute_kc_payload`
/// * `direction` - "INIT" or "RESP" (ASCII bytes)
///
/// # Returns
/// * HMAC-SHA256 tag (32 bytes)
pub fn compute_kc_tag(kc_key: &KcKey, kc_payload: &[u8; 32], direction: &[u8]) -> [u8; 32] {
    // kc_tag = HMAC-SHA256(kc_key, kc_payload || direction)
    let mut data = Vec::with_capacity(32 + direction.len());
    data.extend_from_slice(kc_payload);
    data.extend_from_slice(direction);
    hmac_sha256(&kc_key.0, &data)
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_derive_root_and_kc() {
        // Test with 96-byte IKM (no OTP)
        let ikm = [0x42u8; 96];
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let (root_key, kc_key) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);

        // Verify lengths
        assert_eq!(root_key.0.len(), ROOT_KEY_LEN);
        assert_eq!(kc_key.0.len(), KC_KEY_LEN);

        // Verify determinism (should produce same output for same input)
        let (root_key2, kc_key2) = derive_root_and_kc(&ikm, &transcript_hash, &ctx);
        assert_eq!(root_key.0, root_key2.0);
        assert_eq!(kc_key.0, kc_key2.0);
    }

    #[test]
    fn test_derive_initial_chain_key() {
        let root_key = RootKey([0x42u8; 32]);
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };
        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let chain_key = derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx);

        assert_eq!(chain_key.0.len(), CHAIN_KEY_LEN);

        // Different stream should produce different chain key
        let stream_ctx_r2i = StreamContext {
            stream_id: STREAM_R2I,
            ..stream_ctx
        };
        let chain_key_r2i =
            derive_initial_chain_key(&root_key, &transcript_hash, &ctx, &stream_ctx_r2i);
        assert_ne!(chain_key.0, chain_key_r2i.0);
    }

    #[test]
    fn test_derive_per_message() {
        let chain_key = ChainKey([0x42u8; 32]);
        let counter = 0u64;
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let stream_ctx = StreamContext {
            stream_id: STREAM_I2R,
            message_type: MSG_TYPE_DM,
            suite_id: SUITE_CHACHA20_POLY1305,
        };

        let (mk_material, next_chain_key) =
            derive_per_message(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);

        assert_eq!(mk_material.0.len(), MK_MATERIAL_LEN);
        assert_eq!(next_chain_key.0.len(), CHAIN_KEY_LEN);

        // Next counter with same chain key should produce different mk_material
        let (mk_material2, _) =
            derive_per_message(&chain_key, counter + 1, &ctx, &transcript_hash, &stream_ctx);
        assert_ne!(mk_material.0, mk_material2.0);

        // Ratchet step: using next_chain_key with next counter
        // This simulates proper send flow: derive msg, advance chain, increment counter
        let (mk_material_next, _) = derive_per_message(
            &next_chain_key,
            counter + 1,
            &ctx,
            &transcript_hash,
            &stream_ctx,
        );
        // Should be different from mk_material2 (different chain key input)
        assert_ne!(mk_material2.0, mk_material_next.0);
    }

    #[test]
    fn test_session_binding() {
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };

        let binding = compute_session_binding(&ctx);
        assert_eq!(binding.0.len(), SESSION_BINDING_LEN);

        // Same context should produce same binding
        let binding2 = compute_session_binding(&ctx);
        assert_eq!(binding.0, binding2.0);
    }

    #[test]
    fn test_kc_tags() {
        let kc_key = KcKey([0x42u8; 32]);
        let ctx = SessionContext {
            session_id: SessionId([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]),
            initiator_device_id: DeviceId([0xAAu8; 16]),
            responder_device_id: DeviceId([0xBBu8; 16]),
        };
        let transcript_hash = TranscriptHash([0x11u8; 32]);
        let suite_id = SUITE_CHACHA20_POLY1305;

        let kc_payload = compute_kc_payload(&ctx, &transcript_hash, suite_id);
        let kc1 = compute_kc_tag(&kc_key, &kc_payload, b"INIT");
        let kc2 = compute_kc_tag(&kc_key, &kc_payload, b"RESP");

        assert_eq!(kc1.len(), HMAC_SHA256_TAG_LEN);
        assert_eq!(kc2.len(), HMAC_SHA256_TAG_LEN);
        assert_ne!(kc1, kc2); // Different directions should produce different tags
    }
}
