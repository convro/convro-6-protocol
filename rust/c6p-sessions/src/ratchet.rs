//! Symmetric-key ratchet implementation
//!
//! Normative reference: c6p-key-schedule.md §6 (Per-Message Derivation & Ratchet Step)
//!
//! This module implements the core symmetric ratchet that derives per-message
//! key material and advances the chain key for forward secrecy.
//!
//! # Ratchet Process
//!
//! For each message at counter `c`:
//! 1. Derive `mk_material` (32 bytes) from current `chain_key`
//! 2. Derive `next_chain_key` (32 bytes) for the next message
//! 3. Return `(mk_material, next_chain_key)`
//!
//! # Security Properties
//!
//! - **Forward secrecy:** Compromising `chain_key_N` does not reveal `chain_key_N-1`
//! - **Determinism:** Same inputs always produce same outputs (cross-platform compatibility)
//! - **Domain separation:** mk_material and next_chain_key use different info strings
//! - **Context binding:** All derivations bind to session context and stream context

use crate::types::{ChainKey, Counter, MessageKeyMaterial};
use c6p_crypto::{SessionContext, StreamContext, TranscriptHash};
use sha2::{Digest, Sha256};
use hkdf::Hkdf;

/// Labels for ratchet derivation (normative)
const LABEL_MSG: &[u8] = b"C6P_MSG_V1";
const LABEL_CHAIN: &[u8] = b"C6P_CHAIN_V1";

/// Ratchet output containing derived message key material and next chain key
#[derive(Debug)]
pub struct RatchetOutput {
    /// Message key material (32 bytes)
    ///
    /// Used to derive suite-specific AEAD key for this message.
    pub mk_material: MessageKeyMaterial,

    /// Next chain key (32 bytes)
    ///
    /// Used for ratcheting to the next message.
    pub next_chain_key: ChainKey,
}

/// Perform symmetric ratchet step
///
/// Normative reference: c6p-key-schedule.md §6
///
/// # Arguments
///
/// * `chain_key` - Current chain key (32 bytes)
/// * `counter` - Message counter (u64)
/// * `ctx` - Session context (session_id, initiator_device_id, responder_device_id)
/// * `transcript_hash` - Transcript hash from handshake (32 bytes)
/// * `stream_ctx` - Stream context (stream_id, message_type, suite_id)
///
/// # Returns
///
/// * `RatchetOutput` containing:
///   - `mk_material`: Message key material for this counter
///   - `next_chain_key`: Chain key for counter+1
///
/// # Normative Algorithm
///
/// ```text
/// 1. salt_msg = SHA256( "C6P_MSG_V1" || CTX || transcript_hash || STREAM_CTX || BE64(counter) )
/// 2. prk_msg = HKDF-Extract( salt = salt_msg, ikm = chain_key )
/// 3. mk_material = HKDF-Expand( prk_msg, info = "C6P_MSG_V1" || U8(0x01) || STREAM_CTX, L = 32 )
/// 4. next_chain_key = HKDF-Expand( prk_msg, info = "C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX || BE64(counter), L = 32 )
/// ```
///
/// Where:
/// - CTX = session_id (8B) || initiator_device_id (16B) || responder_device_id (16B)
/// - STREAM_CTX = stream_id (1B) || message_type (1B) || suite_id (2B, BE)
/// - BE64(counter) = counter as 8-byte big-endian
///
/// # Examples
///
/// ```rust,ignore
/// let output = ratchet_step(
///     &chain_key,
///     Counter::new(0),
///     &ctx,
///     &transcript_hash,
///     &stream_ctx,
/// );
///
/// // Use mk_material to derive AEAD key
/// let aead_key = derive_suite_key(&output.mk_material, suite_id);
///
/// // Update state with next_chain_key for counter+1
/// chain_key = output.next_chain_key;
/// ```
pub fn ratchet_step(
    chain_key: &ChainKey,
    counter: Counter,
    ctx: &SessionContext,
    transcript_hash: &TranscriptHash,
    stream_ctx: &StreamContext,
) -> RatchetOutput {
    // Step 1: Compute salt_msg
    // salt_msg = SHA256( "C6P_MSG_V1" || CTX || transcript_hash || STREAM_CTX || BE64(counter) )
    let mut hasher = Sha256::new();
    hasher.update(LABEL_MSG);
    hasher.update(&ctx.session_id.0);
    hasher.update(&ctx.initiator_device_id.0);
    hasher.update(&ctx.responder_device_id.0);
    hasher.update(&transcript_hash.0);
    hasher.update(&[stream_ctx.stream_id]);
    hasher.update(&[stream_ctx.message_type]);
    hasher.update(&stream_ctx.suite_id.to_be_bytes());
    hasher.update(&counter.to_be_bytes());
    let salt_msg = hasher.finalize();

    // Step 2: HKDF-Extract
    // prk_msg = HKDF-Extract( salt = salt_msg, ikm = chain_key )
    let hkdf = Hkdf::<Sha256>::new(Some(&salt_msg), chain_key.as_bytes());

    // Step 3: Derive mk_material
    // mk_material = HKDF-Expand( prk_msg, info = "C6P_MSG_V1" || U8(0x01) || STREAM_CTX, L = 32 )
    let mut mk_info = Vec::with_capacity(LABEL_MSG.len() + 1 + 4);
    mk_info.extend_from_slice(LABEL_MSG);
    mk_info.push(0x01); // Sequence byte
    mk_info.push(stream_ctx.stream_id);
    mk_info.push(stream_ctx.message_type);
    mk_info.extend_from_slice(&stream_ctx.suite_id.to_be_bytes());

    let mut mk_material_bytes = [0u8; 32];
    hkdf.expand(&mk_info, &mut mk_material_bytes)
        .expect("HKDF expand failed (mk_material)");

    // Step 4: Derive next_chain_key
    // next_chain_key = HKDF-Expand( prk_msg, info = "C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX || BE64(counter), L = 32 )
    let mut chain_info = Vec::with_capacity(LABEL_CHAIN.len() + 1 + 4 + 8);
    chain_info.extend_from_slice(LABEL_CHAIN);
    chain_info.push(0x01); // Sequence byte
    chain_info.push(stream_ctx.stream_id);
    chain_info.push(stream_ctx.message_type);
    chain_info.extend_from_slice(&stream_ctx.suite_id.to_be_bytes());
    chain_info.extend_from_slice(&counter.to_be_bytes());

    let mut next_chain_key_bytes = [0u8; 32];
    hkdf.expand(&chain_info, &mut next_chain_key_bytes)
        .expect("HKDF expand failed (next_chain_key)");

    RatchetOutput {
        mk_material: MessageKeyMaterial::from_bytes(mk_material_bytes),
        next_chain_key: ChainKey::from_bytes(next_chain_key_bytes),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use c6p_crypto::{DeviceId, SessionId};

    /// Helper: Create test context
    fn create_test_context() -> (SessionContext, TranscriptHash, StreamContext) {
        let ctx = SessionContext {
            session_id: SessionId([0x01; 8]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
        };

        let transcript_hash = TranscriptHash([0x42; 32]);

        let stream_ctx = StreamContext {
            stream_id: 0x01, // I2R
            message_type: 0x01, // DM
            suite_id: 0x01, // ChaCha20-Poly1305
        };

        (ctx, transcript_hash, stream_ctx)
    }

    #[test]
    fn test_ratchet_step_determinism() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let counter = Counter::new(0);

        // Call ratchet twice with same inputs
        let output1 = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);
        let output2 = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);

        // Outputs must be identical
        assert_eq!(output1.mk_material.as_bytes(), output2.mk_material.as_bytes());
        assert_eq!(output1.next_chain_key.as_bytes(), output2.next_chain_key.as_bytes());
    }

    #[test]
    fn test_ratchet_step_different_counters() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);

        let output0 = ratchet_step(&chain_key, Counter::new(0), &ctx, &transcript_hash, &stream_ctx);
        let output1 = ratchet_step(&chain_key, Counter::new(1), &ctx, &transcript_hash, &stream_ctx);

        // Different counters must produce different outputs
        assert_ne!(output0.mk_material.as_bytes(), output1.mk_material.as_bytes());
        assert_ne!(output0.next_chain_key.as_bytes(), output1.next_chain_key.as_bytes());
    }

    #[test]
    fn test_ratchet_chain_forward() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key_0 = ChainKey::from_bytes([0x10; 32]);

        // Ratchet at counter 0
        let output_0 = ratchet_step(&chain_key_0, Counter::new(0), &ctx, &transcript_hash, &stream_ctx);

        // Ratchet at counter 1 using next_chain_key from counter 0
        let output_1 = ratchet_step(&output_0.next_chain_key, Counter::new(1), &ctx, &transcript_hash, &stream_ctx);

        // Should produce valid outputs
        assert_ne!(output_0.mk_material.as_bytes(), output_1.mk_material.as_bytes());
        assert_ne!(output_0.next_chain_key.as_bytes(), output_1.next_chain_key.as_bytes());
    }

    #[test]
    fn test_ratchet_different_streams() {
        let (ctx, transcript_hash, _) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let counter = Counter::new(0);

        let stream_ctx_i2r = StreamContext {
            stream_id: 0x01, // I2R
            message_type: 0x01,
            suite_id: 0x01,
        };

        let stream_ctx_r2i = StreamContext {
            stream_id: 0x02, // R2I
            message_type: 0x01,
            suite_id: 0x01,
        };

        let output_i2r = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx_i2r);
        let output_r2i = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx_r2i);

        // Different streams must produce different outputs
        assert_ne!(output_i2r.mk_material.as_bytes(), output_r2i.mk_material.as_bytes());
        assert_ne!(output_i2r.next_chain_key.as_bytes(), output_r2i.next_chain_key.as_bytes());
    }

    #[test]
    fn test_ratchet_mk_and_chain_different() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let counter = Counter::new(0);

        let output = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);

        // mk_material and next_chain_key must be different (domain separation)
        assert_ne!(output.mk_material.as_bytes(), output.next_chain_key.as_bytes());
    }

    #[test]
    fn test_ratchet_output_lengths() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let counter = Counter::new(0);

        let output = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);

        // Both outputs must be 32 bytes
        assert_eq!(output.mk_material.as_bytes().len(), 32);
        assert_eq!(output.next_chain_key.as_bytes().len(), 32);
    }

    #[test]
    fn test_ratchet_high_counter() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);

        // Test with high counter value
        let counter = Counter::new(0x0102030405060708);
        let output = ratchet_step(&chain_key, counter, &ctx, &transcript_hash, &stream_ctx);

        // Should produce valid outputs
        assert_ne!(output.mk_material.as_bytes(), &[0u8; 32]);
        assert_ne!(output.next_chain_key.as_bytes(), &[0u8; 32]);
    }
}
