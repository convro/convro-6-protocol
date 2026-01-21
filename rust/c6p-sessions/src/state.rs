//! Session state management
//!
//! Normative reference: dm-ratchet-state-machine.md
//!
//! This module provides the stateful wrapper around the ratchet and replay
//! protection primitives. It manages per-stream state for send and receive
//! operations, enforcing counter monotonicity and replay detection.

use crate::error::{Result, SessionError};
use crate::ratchet::{ratchet_step, RatchetOutput};
use crate::replay::SkipWindow;
use crate::types::{ChainKey, Counter, MessageKeyMaterial, StreamDirection};
use c6p_crypto::{SessionContext, StreamContext, TranscriptHash};

/// Per-stream state for one direction of communication
///
/// Manages the ratchet chain key, send/receive counters, and replay protection.
/// Each session has two StreamState instances (one for each direction: i2r, r2i).
#[derive(Debug, Clone)]
pub struct StreamState {
    /// Stream direction (I2R or R2I)
    direction: StreamDirection,

    /// Current chain key for this stream
    chain_key: ChainKey,

    /// Next counter to use when sending (monotonically increasing)
    send_counter: Counter,

    /// Skip-window for replay detection (receive side)
    skip_window: SkipWindow,

    /// State version (always 1 for v1)
    state_version: u8,
}

impl StreamState {
    /// Create new stream state
    ///
    /// # Arguments
    ///
    /// * `direction` - Stream direction (I2R or R2I)
    /// * `initial_chain_key` - Initial chain key from handshake
    ///
    /// # Returns
    ///
    /// New stream state starting at counter 0
    pub fn new(direction: StreamDirection, initial_chain_key: ChainKey) -> Self {
        Self {
            direction,
            chain_key: initial_chain_key,
            send_counter: Counter::ZERO,
            skip_window: SkipWindow::new(),
            state_version: 1,
        }
    }

    /// Create stream state with specific starting counter
    ///
    /// Useful for testing or resuming from persisted state.
    pub fn with_counter(
        direction: StreamDirection,
        initial_chain_key: ChainKey,
        send_counter: Counter,
        recv_expected: Counter,
    ) -> Self {
        Self {
            direction,
            chain_key: initial_chain_key,
            send_counter,
            skip_window: SkipWindow::with_expected(recv_expected),
            state_version: 1,
        }
    }

    /// Get current stream direction
    pub fn direction(&self) -> StreamDirection {
        self.direction
    }

    /// Get next send counter (without advancing)
    pub fn send_counter(&self) -> Counter {
        self.send_counter
    }

    /// Get recv_expected counter
    pub fn recv_expected(&self) -> Counter {
        self.skip_window.recv_expected()
    }

    /// Get state version
    pub fn state_version(&self) -> u8 {
        self.state_version
    }

    /// Advance send state (ratchet forward for sending a message)
    ///
    /// Normative reference: dm-ratchet-state-machine.md §2 (Send Flow)
    ///
    /// # Arguments
    ///
    /// * `ctx` - Session context (session_id, device_ids)
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context (stream_id, message_type, suite_id)
    ///
    /// # Returns
    ///
    /// * `SendOutput` containing:
    ///   - `counter`: Counter used for this message
    ///   - `mk_material`: Message key material for encryption
    ///
    /// # Side Effects
    ///
    /// Updates internal state:
    /// - Derives new chain key
    /// - Advances send_counter by 1
    ///
    /// # Errors
    ///
    /// Returns error if send_counter would overflow (counter exhaustion).
    pub fn advance_send(
        &mut self,
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> Result<SendOutput> {
        // Current counter for this message
        let counter = self.send_counter;

        // Perform ratchet step to derive message key and next chain key
        let RatchetOutput {
            mk_material,
            next_chain_key,
        } = ratchet_step(&self.chain_key, counter, ctx, transcript_hash, stream_ctx);

        // Advance state
        self.chain_key = next_chain_key;
        self.send_counter = counter
            .checked_increment()
            .ok_or(SessionError::CounterExhausted)?;

        Ok(SendOutput {
            counter,
            mk_material,
        })
    }

    /// Prepare to receive a message (validate counter and derive key)
    ///
    /// Normative reference: dm-ratchet-state-machine.md §3 (Receive Flow)
    ///
    /// This performs counter validation and derives the message key material,
    /// but does NOT update state. Call `mark_received()` after successful
    /// decryption to update the consumed set.
    ///
    /// # Arguments
    ///
    /// * `counter` - Counter from incoming message
    /// * `ctx` - Session context
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context
    ///
    /// # Returns
    ///
    /// * `ReceiveOutput` containing:
    ///   - `mk_material`: Message key material for decryption
    ///
    /// # Errors
    ///
    /// - `SessionError::ReplayDetected` if counter already consumed or below window
    /// - `SessionError::SkipWindowOverflow` if counter too far ahead
    pub fn prepare_receive(
        &self,
        counter: Counter,
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> Result<ReceiveOutput> {
        // Step 1: Validate counter (replay detection)
        self.skip_window.can_accept(counter)?;

        // Step 2: Derive chain key at this counter
        let chain_key_at_counter =
            self.derive_chain_key_at(counter, ctx, transcript_hash, stream_ctx);

        // Step 3: Derive message key material
        let RatchetOutput { mk_material, .. } = ratchet_step(
            &chain_key_at_counter,
            counter,
            ctx,
            transcript_hash,
            stream_ctx,
        );

        Ok(ReceiveOutput { mk_material })
    }

    /// Mark a message as successfully received (update consumed set)
    ///
    /// Call this AFTER successful AEAD decryption.
    ///
    /// # Arguments
    ///
    /// * `counter` - Counter from successfully decrypted message
    /// * `ctx` - Session context
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context
    ///
    /// # Returns
    ///
    /// - `Ok(())` if counter marked successfully
    /// - `Err(SessionError)` if counter outside window or already consumed
    ///
    /// # Side Effects
    ///
    /// - Marks counter as consumed in skip-window
    /// - May advance recv_expected if this fills a gap
    /// - Advances chain_key to match new recv_expected
    pub fn mark_received(
        &mut self,
        counter: Counter,
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> Result<()> {
        let old_recv_expected = self.skip_window.recv_expected();

        // Mark counter as consumed (may advance recv_expected)
        self.skip_window.mark_consumed(counter)?;

        let new_recv_expected = self.skip_window.recv_expected();

        // If recv_expected advanced, advance chain_key to match
        if new_recv_expected.value() > old_recv_expected.value() {
            // Ratchet chain_key forward from old_recv_expected to new_recv_expected
            for c in old_recv_expected.value()..new_recv_expected.value() {
                let counter = Counter::new(c);
                let RatchetOutput { next_chain_key, .. } =
                    ratchet_step(&self.chain_key, counter, ctx, transcript_hash, stream_ctx);
                self.chain_key = next_chain_key;
            }
        }

        Ok(())
    }

    /// Derive chain key at specific counter (skip-forward if needed)
    ///
    /// Normative reference: dm-ratchet-state-machine.md §3.2 (Skip-Forward)
    ///
    /// If counter > recv_expected, performs intermediate ratchet steps to
    /// derive the chain key at the target counter.
    ///
    /// # Arguments
    ///
    /// * `target_counter` - Counter to derive chain key for
    /// * `ctx` - Session context
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context
    ///
    /// # Returns
    ///
    /// Chain key at `target_counter`
    ///
    /// # Implementation Notes
    ///
    /// This is a stateless derivation - it doesn't modify self.chain_key.
    /// The actual chain key is only advanced during send operations.
    fn derive_chain_key_at(
        &self,
        target_counter: Counter,
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> ChainKey {
        let recv_expected = self.skip_window.recv_expected();

        // Case 1: In-order message (counter == recv_expected)
        // Use current chain key directly
        if target_counter == recv_expected {
            return self.chain_key.clone();
        }

        // Case 2: Out-of-order message (counter > recv_expected)
        // Skip-forward by ratcheting from recv_expected to target_counter
        if target_counter.value() > recv_expected.value() {
            let mut ck = self.chain_key.clone();

            // Ratchet forward from recv_expected to target_counter
            for c in recv_expected.value()..target_counter.value() {
                let counter = Counter::new(c);
                let RatchetOutput { next_chain_key, .. } =
                    ratchet_step(&ck, counter, ctx, transcript_hash, stream_ctx);
                ck = next_chain_key;
            }

            return ck;
        }

        // Case 3: Below recv_expected (already consumed or old message)
        // This case should be caught by can_accept(), but if we get here,
        // we can't derive the key (chain keys are not stored).
        //
        // In a production system, you might cache recent chain keys or
        // use a different strategy. For now, we'll use the current chain
        // key (this will cause AEAD failure, which is correct behavior
        // for replay/old messages).
        self.chain_key.clone()
    }

    /// Get skip-window statistics (for debugging/observability)
    pub fn skip_window_stats(&self) -> crate::replay::SkipWindowStats {
        self.skip_window.stats()
    }

    // ========================================================================
    // High-Level API (Encrypt/Decrypt Integration)
    // ========================================================================

    /// Encrypt and send a message (high-level API)
    ///
    /// This is a convenience method that combines:
    /// 1. `advance_send()` - Derive message key and advance ratchet
    /// 2. `encrypt_message()` - Encrypt with AEAD
    ///
    /// # Arguments
    ///
    /// * `plaintext` - Message plaintext
    /// * `ctx` - Session context
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context
    ///
    /// # Returns
    ///
    /// * `Ok((counter, sealed))` - Counter and encrypted message (ciphertext || tag)
    /// * `Err(SessionError)` - On encryption or state advancement failure
    ///
    /// # Side Effects
    ///
    /// - Advances send_counter by 1
    /// - Advances chain_key to next state
    ///
    /// # Example
    ///
    /// ```rust,ignore
    /// let (counter, sealed) = sender.encrypt_and_send(
    ///     b"Hello, C6P!",
    ///     &ctx,
    ///     &transcript_hash,
    ///     &stream_ctx,
    /// )?;
    /// // Send (counter, sealed) over the wire
    /// ```
    pub fn encrypt_and_send(
        &mut self,
        plaintext: &[u8],
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> Result<(Counter, Vec<u8>)> {
        // Step 1: Advance send state (derive mk_material, advance chain_key)
        let SendOutput {
            counter,
            mk_material,
        } = self.advance_send(ctx, transcript_hash, stream_ctx)?;

        // Step 2: Encrypt message with AEAD
        let sealed = crate::aead::encrypt_message(
            plaintext,
            &mk_material,
            counter.value(),
            ctx,
            transcript_hash,
            stream_ctx,
        )?;

        Ok((counter, sealed))
    }

    /// Receive and decrypt a message (high-level API)
    ///
    /// This is a convenience method that combines:
    /// 1. `prepare_receive()` - Validate counter and derive message key
    /// 2. `decrypt_message()` - Decrypt with AEAD
    /// 3. `mark_received()` - Update consumed set and advance recv_expected
    ///
    /// # Arguments
    ///
    /// * `counter` - Message counter from envelope
    /// * `sealed` - Encrypted message (ciphertext || tag)
    /// * `ctx` - Session context
    /// * `transcript_hash` - Transcript hash from handshake
    /// * `stream_ctx` - Stream context
    ///
    /// # Returns
    ///
    /// * `Ok(plaintext)` - Decrypted message
    /// * `Err(SessionError)` - On decryption failure, replay detection, or validation failure
    ///
    /// # Hard Rules
    ///
    /// - On decryption failure: state is NOT advanced (fail-closed)
    /// - On success: counter marked as consumed, recv_expected may advance
    /// - Replay attack: Err(SessionError::ReplayDetected)
    ///
    /// # Example
    ///
    /// ```rust,ignore
    /// // Receive (counter, sealed) from wire
    /// let plaintext = receiver.receive_and_decrypt(
    ///     counter,
    ///     &sealed,
    ///     &ctx,
    ///     &transcript_hash,
    ///     &stream_ctx,
    /// )?;
    /// ```
    pub fn receive_and_decrypt(
        &mut self,
        counter: Counter,
        sealed: &[u8],
        ctx: &SessionContext,
        transcript_hash: &TranscriptHash,
        stream_ctx: &StreamContext,
    ) -> Result<Vec<u8>> {
        // Step 1: Validate counter and derive message key
        let ReceiveOutput { mk_material } =
            self.prepare_receive(counter, ctx, transcript_hash, stream_ctx)?;

        // Step 2: Decrypt message with AEAD (authentication happens here)
        let plaintext = crate::aead::decrypt_message(
            sealed,
            &mk_material,
            counter.value(),
            ctx,
            transcript_hash,
            stream_ctx,
        )?;

        // Step 3: Mark counter as consumed (only after successful decryption)
        self.mark_received(counter, ctx, transcript_hash, stream_ctx)?;

        Ok(plaintext)
    }
}

/// Output from advance_send operation
#[derive(Debug)]
pub struct SendOutput {
    /// Counter used for this message
    pub counter: Counter,

    /// Message key material for encryption
    pub mk_material: MessageKeyMaterial,
}

/// Output from prepare_receive operation
#[derive(Debug)]
pub struct ReceiveOutput {
    /// Message key material for decryption
    pub mk_material: MessageKeyMaterial,
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
            stream_id: 0x01,    // I2R
            message_type: 0x01, // DM
            suite_id: 0x01,     // ChaCha20-Poly1305
        };

        (ctx, transcript_hash, stream_ctx)
    }

    #[test]
    fn test_stream_state_new() {
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let state = StreamState::new(StreamDirection::I2R, chain_key);

        assert_eq!(state.direction(), StreamDirection::I2R);
        assert_eq!(state.send_counter(), Counter::ZERO);
        assert_eq!(state.recv_expected(), Counter::ZERO);
        assert_eq!(state.state_version(), 1);
    }

    #[test]
    fn test_advance_send_sequential() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let mut state = StreamState::new(StreamDirection::I2R, chain_key);

        // Send message 0
        let output_0 = state
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(output_0.counter, Counter::new(0));
        assert_eq!(state.send_counter(), Counter::new(1));

        // Send message 1
        let output_1 = state
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(output_1.counter, Counter::new(1));
        assert_eq!(state.send_counter(), Counter::new(2));

        // Message keys should be different
        assert_ne!(
            output_0.mk_material.as_bytes(),
            output_1.mk_material.as_bytes()
        );
    }

    #[test]
    fn test_receive_in_order() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let mut state = StreamState::new(StreamDirection::I2R, chain_key);

        // Receive counter 0
        let output = state
            .prepare_receive(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert!(output.mk_material.as_bytes().len() == 32);

        // Mark as received
        assert!(state
            .mark_received(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
        assert_eq!(state.recv_expected(), Counter::new(1));

        // Receive counter 1
        let output = state
            .prepare_receive(Counter::new(1), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert!(output.mk_material.as_bytes().len() == 32);

        assert!(state
            .mark_received(Counter::new(1), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
        assert_eq!(state.recv_expected(), Counter::new(2));
    }

    #[test]
    fn test_receive_out_of_order() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let mut state = StreamState::new(StreamDirection::I2R, chain_key);

        // Receive counter 5 first (out of order)
        let output_5 = state
            .prepare_receive(Counter::new(5), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert!(state
            .mark_received(Counter::new(5), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
        assert_eq!(state.recv_expected(), Counter::new(0)); // Not advanced yet

        // Receive counter 0
        let output_0 = state
            .prepare_receive(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert!(state
            .mark_received(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
        assert_eq!(state.recv_expected(), Counter::new(1)); // Advanced to 1

        // Message keys should be different
        assert_ne!(
            output_0.mk_material.as_bytes(),
            output_5.mk_material.as_bytes()
        );
    }

    #[test]
    fn test_replay_detection() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let mut state = StreamState::new(StreamDirection::I2R, chain_key);

        // Receive counter 0
        assert!(state
            .prepare_receive(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
        assert!(state
            .mark_received(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .is_ok());

        // Try to receive counter 0 again (replay)
        let result = state.prepare_receive(Counter::new(0), &ctx, &transcript_hash, &stream_ctx);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::ReplayDetected(0)
        ));
    }

    #[test]
    fn test_skip_window_overflow() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let state = StreamState::new(StreamDirection::I2R, chain_key);

        // Try to receive counter far beyond window
        let far_counter = Counter::new(2048 + 100);
        let result = state.prepare_receive(far_counter, &ctx, &transcript_hash, &stream_ctx);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::SkipWindowOverflow(_)
        ));
    }

    #[test]
    fn test_send_receive_round_trip() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);

        // Create sender and receiver with same initial state
        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Sender sends message 0
        let send_output = sender
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receiver receives message 0
        let recv_output = receiver
            .prepare_receive(send_output.counter, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Message key material should match
        assert_eq!(
            send_output.mk_material.as_bytes(),
            recv_output.mk_material.as_bytes()
        );

        // Mark as received
        assert!(receiver
            .mark_received(send_output.counter, &ctx, &transcript_hash, &stream_ctx)
            .is_ok());
    }

    #[test]
    fn test_send_receive_out_of_order() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Sender sends messages 0, 1, 2
        let output_0 = sender
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let output_1 = sender
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let output_2 = sender
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receiver gets them out of order: 2, 0, 1
        let recv_2 = receiver
            .prepare_receive(output_2.counter, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(
            recv_2.mk_material.as_bytes(),
            output_2.mk_material.as_bytes()
        );
        assert!(receiver
            .mark_received(output_2.counter, &ctx, &transcript_hash, &stream_ctx)
            .is_ok());

        let recv_0 = receiver
            .prepare_receive(output_0.counter, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(
            recv_0.mk_material.as_bytes(),
            output_0.mk_material.as_bytes()
        );
        assert!(receiver
            .mark_received(output_0.counter, &ctx, &transcript_hash, &stream_ctx)
            .is_ok());

        let recv_1 = receiver
            .prepare_receive(output_1.counter, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(
            recv_1.mk_material.as_bytes(),
            output_1.mk_material.as_bytes()
        );
        assert!(receiver
            .mark_received(output_1.counter, &ctx, &transcript_hash, &stream_ctx)
            .is_ok());

        // recv_expected should advance to 3 after all messages consumed
        assert_eq!(receiver.recv_expected(), Counter::new(3));
    }

    #[test]
    fn test_counter_exhaustion() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);

        // Start at max counter - 1
        let mut state = StreamState::with_counter(
            StreamDirection::I2R,
            chain_key,
            Counter::new(u64::MAX - 1),
            Counter::ZERO,
        );

        // Can send at MAX - 1
        assert!(state
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .is_ok());

        // Counter exhausted - should fail
        let result = state.advance_send(&ctx, &transcript_hash, &stream_ctx);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::CounterExhausted
        ));
    }

    #[test]
    fn test_with_counter() {
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let state = StreamState::with_counter(
            StreamDirection::R2I,
            chain_key,
            Counter::new(42),
            Counter::new(100),
        );

        assert_eq!(state.direction(), StreamDirection::R2I);
        assert_eq!(state.send_counter(), Counter::new(42));
        assert_eq!(state.recv_expected(), Counter::new(100));
    }

    #[test]
    fn test_skip_window_stats() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x10; 32]);
        let mut state = StreamState::new(StreamDirection::I2R, chain_key);

        let stats = state.skip_window_stats();
        assert_eq!(stats.recv_expected, Counter::ZERO);
        assert_eq!(stats.consumed_count, 0);

        // Mark some counters consumed
        state
            .mark_received(Counter::new(0), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        state
            .mark_received(Counter::new(5), &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        let stats = state.skip_window_stats();
        assert_eq!(stats.recv_expected, Counter::new(1));
        assert!(stats.consumed_count >= 1); // At least counter 5 is in window
    }

    // ========================================================================
    // High-Level API Tests (Encrypt/Decrypt Integration)
    // ========================================================================

    #[test]
    fn test_high_level_encrypt_and_send() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x42; 32]);
        let mut sender = StreamState::new(StreamDirection::I2R, chain_key);

        let plaintext = b"Hello, C6P!";

        // Encrypt and send message 0
        let (counter, sealed) = sender
            .encrypt_and_send(plaintext, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(counter, Counter::new(0));
        assert_eq!(sealed.len(), plaintext.len() + 16); // plaintext + tag
        assert_eq!(sender.send_counter(), Counter::new(1)); // Advanced
    }

    #[test]
    fn test_high_level_receive_and_decrypt() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x42; 32]);
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let plaintext = b"Hello, C6P!";

        // First, manually create a sealed message
        let output = receiver
            .advance_send(&ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let sealed = crate::aead::encrypt_message(
            plaintext,
            &output.mk_material,
            output.counter.value(),
            &ctx,
            &transcript_hash,
            &stream_ctx,
        )
        .unwrap();

        // Reset receiver state
        let mut receiver = StreamState::new(StreamDirection::I2R, ChainKey::from_bytes([0x42; 32]));

        // Receive and decrypt
        let decrypted = receiver
            .receive_and_decrypt(
                Counter::new(0),
                &sealed,
                &ctx,
                &transcript_hash,
                &stream_ctx,
            )
            .unwrap();

        assert_eq!(decrypted, plaintext);
        assert_eq!(receiver.recv_expected(), Counter::new(1)); // Advanced
    }

    #[test]
    fn test_high_level_full_round_trip() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x99; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let plaintext = b"Full integration test!";

        // Sender encrypts
        let (counter, sealed) = sender
            .encrypt_and_send(plaintext, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receiver decrypts
        let decrypted = receiver
            .receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(decrypted, plaintext);
        assert_eq!(sender.send_counter(), Counter::new(1));
        assert_eq!(receiver.recv_expected(), Counter::new(1));
    }

    #[test]
    fn test_high_level_multiple_messages() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x77; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Send and receive 5 messages
        for i in 0..5 {
            let plaintext = format!("Message {}", i);

            // Send
            let (counter, sealed) = sender
                .encrypt_and_send(plaintext.as_bytes(), &ctx, &transcript_hash, &stream_ctx)
                .unwrap();

            assert_eq!(counter, Counter::new(i));

            // Receive
            let decrypted = receiver
                .receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx)
                .unwrap();

            assert_eq!(decrypted, plaintext.as_bytes());
        }

        assert_eq!(sender.send_counter(), Counter::new(5));
        assert_eq!(receiver.recv_expected(), Counter::new(5));
    }

    #[test]
    fn test_high_level_out_of_order_delivery() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x88; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Send 3 messages
        let (counter_0, sealed_0) = sender
            .encrypt_and_send(b"Message 0", &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let (counter_1, sealed_1) = sender
            .encrypt_and_send(b"Message 1", &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        let (counter_2, sealed_2) = sender
            .encrypt_and_send(b"Message 2", &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receive out of order: 2, 0, 1
        let decrypted_2 = receiver
            .receive_and_decrypt(counter_2, &sealed_2, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(decrypted_2, b"Message 2");
        assert_eq!(receiver.recv_expected(), Counter::new(0)); // Not advanced yet

        let decrypted_0 = receiver
            .receive_and_decrypt(counter_0, &sealed_0, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(decrypted_0, b"Message 0");
        assert_eq!(receiver.recv_expected(), Counter::new(1)); // Advanced to 1

        let decrypted_1 = receiver
            .receive_and_decrypt(counter_1, &sealed_1, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(decrypted_1, b"Message 1");
        assert_eq!(receiver.recv_expected(), Counter::new(3)); // Advanced to 3 (all consumed)
    }

    #[test]
    fn test_high_level_replay_detection() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x55; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Send message
        let (counter, sealed) = sender
            .encrypt_and_send(b"Original", &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Receive once (OK)
        let decrypted = receiver
            .receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();
        assert_eq!(decrypted, b"Original");

        // Try to receive again (replay attack - should fail)
        let result =
            receiver.receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx);

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::ReplayDetected(0)
        ));
    }

    #[test]
    fn test_high_level_decrypt_failure_no_state_change() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x66; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // Send message
        let (counter, mut sealed) = sender
            .encrypt_and_send(b"Tamper test", &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        // Tamper with ciphertext
        sealed[0] ^= 0x01;

        let recv_expected_before = receiver.recv_expected();

        // Try to decrypt (should fail)
        let result =
            receiver.receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx);

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::DecryptionFailed(_)
        ));

        // Verify state was NOT advanced (fail-closed)
        assert_eq!(receiver.recv_expected(), recv_expected_before);
    }

    #[test]
    fn test_high_level_empty_message() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x33; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        let plaintext = b"";

        // Send empty message
        let (counter, sealed) = sender
            .encrypt_and_send(plaintext, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(sealed.len(), 16); // Just the tag

        // Receive empty message
        let decrypted = receiver
            .receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_high_level_large_message() {
        let (ctx, transcript_hash, stream_ctx) = create_test_context();
        let chain_key = ChainKey::from_bytes([0x44; 32]);

        let mut sender = StreamState::new(StreamDirection::I2R, chain_key.clone());
        let mut receiver = StreamState::new(StreamDirection::I2R, chain_key);

        // 10KB message
        let plaintext = vec![0x42u8; 10 * 1024];

        // Send
        let (counter, sealed) = sender
            .encrypt_and_send(&plaintext, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(sealed.len(), plaintext.len() + 16);

        // Receive
        let decrypted = receiver
            .receive_and_decrypt(counter, &sealed, &ctx, &transcript_hash, &stream_ctx)
            .unwrap();

        assert_eq!(decrypted, plaintext);
    }
}
