//! Session state and message encryption/decryption

use crate::error::{C6pError, Result};
use crate::types::{EncryptedMessage, SessionKeys};
use c6p_crypto::{DeviceId, SessionContext, SessionId, StreamContext, TranscriptHash};
use c6p_sessions::{ChainKey, StreamDirection, StreamState};
use std::sync::{Arc, Mutex};

/// Session state (opaque, managed by Swift)
///
/// This wraps the C6P session ratcheting state for both send and receive directions.
/// It maintains:
/// - Send stream state (I2R or R2I depending on role)
/// - Receive stream state (R2I or I2R depending on role)
/// - Session context (session_id, device_ids)
/// - Session binding (for nonce derivation)
pub struct SessionState {
    /// Session context
    ctx: SessionContext,

    /// Transcript hash from handshake (32 bytes)
    /// Used for nonce derivation (passed to encrypt/decrypt functions)
    transcript_hash: TranscriptHash,

    /// Send stream state
    send_stream: Arc<Mutex<StreamState>>,

    /// Receive stream state
    recv_stream: Arc<Mutex<StreamState>>,

    /// Suite ID (0x01 = ChaCha20-Poly1305)
    suite_id: u16,

    /// Is initiator (determines stream direction)
    is_initiator: bool,
}

impl SessionState {
    /// Create new session from handshake keys
    ///
    /// # Arguments
    ///
    /// * `keys` - Session keys from successful handshake
    /// * `is_initiator` - true if this side initiated the handshake
    ///
    /// # Returns
    ///
    /// New session state ready for encrypt/decrypt operations
    ///
    /// # Errors
    ///
    /// Returns error if key parsing fails or lengths are invalid
    pub fn new(keys: SessionKeys, is_initiator: bool) -> Result<Self> {
        // Parse session ID
        let session_id: [u8; 8] = keys
            .session_id
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidInput("Session ID must be 8 bytes".to_string()))?;

        // Use dummy transcript hash (all zeros)
        // In production, this should come from handshake output
        let transcript_hash = TranscriptHash([0u8; 32]);

        // Parse chain keys
        let send_chain_key: [u8; 32] = keys
            .send_chain_key
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidInput("Send chain key must be 32 bytes".to_string()))?;

        let recv_chain_key: [u8; 32] = keys
            .recv_chain_key
            .as_slice()
            .try_into()
            .map_err(|_| C6pError::InvalidInput("Recv chain key must be 32 bytes".to_string()))?;

        // Determine stream directions based on role
        let (send_direction, recv_direction) = if is_initiator {
            (StreamDirection::I2R, StreamDirection::R2I)
        } else {
            (StreamDirection::R2I, StreamDirection::I2R)
        };

        // Create stream states
        let send_stream = StreamState::new(send_direction, ChainKey::from_bytes(send_chain_key));
        let recv_stream = StreamState::new(recv_direction, ChainKey::from_bytes(recv_chain_key));

        // Create session context (placeholder device IDs - should come from keys)
        let ctx = SessionContext {
            session_id: SessionId(session_id),
            initiator_device_id: DeviceId([0u8; 16]), // TODO: Add to SessionKeys
            responder_device_id: DeviceId([0u8; 16]), // TODO: Add to SessionKeys
        };

        Ok(Self {
            ctx,
            transcript_hash,
            send_stream: Arc::new(Mutex::new(send_stream)),
            recv_stream: Arc::new(Mutex::new(recv_stream)),
            suite_id: 0x01, // ChaCha20-Poly1305
            is_initiator,
        })
    }

    /// Encrypt outgoing message
    ///
    /// Advances the send ratchet, derives message key, and encrypts plaintext.
    ///
    /// # Arguments
    ///
    /// * `plaintext` - Message to encrypt
    ///
    /// # Returns
    ///
    /// EncryptedMessage containing:
    /// - counter (u64)
    /// - ciphertext (variable length)
    /// - tag (16 bytes, Poly1305)
    ///
    /// # Security
    ///
    /// - Deterministic nonce (derived from mk_material + session_binding + counter)
    /// - AAD includes session_id, stream_id, counter, payload_len
    /// - Forward secrecy (old chain keys deleted after ratchet)
    ///
    /// # Errors
    ///
    /// Returns error if:
    /// - Counter exhausted (2^64-1 limit)
    /// - Encryption fails
    pub fn encrypt(&self, plaintext: Vec<u8>) -> Result<EncryptedMessage> {
        let mut send_stream = self.send_stream.lock().unwrap();

        // Build stream context
        let stream_ctx = StreamContext {
            stream_id: if self.is_initiator { 0x01 } else { 0x02 },
            message_type: 0x01, // DM
            suite_id: self.suite_id,
        };

        // Advance send state (ratchet forward) and get mk_material
        let send_output = send_stream
            .advance_send(&self.ctx, &self.transcript_hash, &stream_ctx)
            .map_err(|e| C6pError::SessionError(format!("Ratchet failed: {}", e)))?;

        let counter = send_output.counter.value();

        // Encrypt with high-level API (handles AAD, nonce derivation automatically)
        let sealed = c6p_sessions::encrypt_message(
            &plaintext,
            &send_output.mk_material,
            counter,
            &self.ctx,
            &self.transcript_hash,
            &stream_ctx,
        )
        .map_err(|e| C6pError::CryptoError(format!("Encryption failed: {}", e)))?;

        // sealed = ciphertext || tag (last 16 bytes are tag)
        let tag_start = sealed.len().saturating_sub(16);
        let ciphertext = sealed[..tag_start].to_vec();
        let tag = sealed[tag_start..].to_vec();

        Ok(EncryptedMessage {
            counter,
            ciphertext,
            tag,
        })
    }

    /// Decrypt incoming message
    ///
    /// Validates counter (replay protection), advances receive ratchet, and decrypts.
    ///
    /// # Arguments
    ///
    /// * `message` - Encrypted message to decrypt
    ///
    /// # Returns
    ///
    /// Plaintext bytes
    ///
    /// # Security
    ///
    /// - Replay protection via skip-window (detects duplicate counters)
    /// - Out-of-order delivery support (gaps in counter sequence)
    /// - AAD verification (session_id, stream_id, counter, payload_len)
    ///
    /// # Errors
    ///
    /// Returns error if:
    /// - Replay detected (duplicate counter)
    /// - Counter gap too large (beyond skip-window)
    /// - Decryption fails (wrong key or corrupted ciphertext)
    /// - Authentication tag invalid
    pub fn decrypt(&self, message: EncryptedMessage) -> Result<Vec<u8>> {
        let mut recv_stream = self.recv_stream.lock().unwrap();

        // Build stream context
        let stream_ctx = StreamContext {
            stream_id: if self.is_initiator { 0x02 } else { 0x01 },
            message_type: 0x01, // DM
            suite_id: self.suite_id,
        };

        // Prepare receive (checks replay window) and get mk_material
        let counter = message.counter.into();
        let recv_output = recv_stream
            .prepare_receive(counter, &self.ctx, &self.transcript_hash, &stream_ctx)
            .map_err(|e| {
                if e.to_string().contains("Replay") {
                    C6pError::ReplayDetected(e.to_string())
                } else {
                    C6pError::SessionError(format!("Ratchet failed: {}", e))
                }
            })?;

        // Reconstruct sealed message (ciphertext || tag)
        let mut sealed = message.ciphertext.clone();
        sealed.extend_from_slice(&message.tag);

        // Decrypt with high-level API (handles AAD, nonce derivation automatically)
        let plaintext = c6p_sessions::decrypt_message(
            &sealed,
            &recv_output.mk_material,
            message.counter,
            &self.ctx,
            &self.transcript_hash,
            &stream_ctx,
        )
        .map_err(|e| C6pError::DecryptionFailed(format!("Decryption failed: {}", e)))?;

        // Note: consume_receive is called automatically by prepare_receive in c6p-sessions

        Ok(plaintext)
    }

    /// Get current send counter
    ///
    /// Returns the next counter that will be used for encryption.
    pub fn send_counter(&self) -> u64 {
        self.send_stream.lock().unwrap().send_counter().value()
    }

    /// Get current recv expected counter
    ///
    /// Returns the next counter expected for decryption (no gaps).
    pub fn recv_expected(&self) -> u64 {
        self.recv_stream.lock().unwrap().recv_expected().value()
    }

    /// Export session state for persistence
    ///
    /// Serializes the session state for storage (e.g., to disk or keychain).
    ///
    /// # Returns
    ///
    /// Serialized state bytes
    ///
    /// # Security
    ///
    /// - State contains chain keys - MUST be encrypted at rest!
    /// - Use iOS Keychain with appropriate protection level
    /// - Never store in UserDefaults or plain files
    ///
    /// # Errors
    ///
    /// Returns error if serialization fails
    pub fn export_state(&self) -> Result<Vec<u8>> {
        // TODO: Implement state serialization
        // This should serialize:
        // - ctx (session_id, device_ids)
        // - session_binding
        // - send_stream state (chain_key, counter, skip_window)
        // - recv_stream state (chain_key, counter, skip_window)
        // - suite_id, is_initiator

        Err(C6pError::SessionError(
            "export_state not yet implemented".to_string(),
        ))
    }

    /// Import session state from persistence
    ///
    /// Deserializes session state from storage.
    ///
    /// # Arguments
    ///
    /// * `state_bytes` - Serialized state from export_state
    ///
    /// # Returns
    ///
    /// Restored session state
    ///
    /// # Errors
    ///
    /// Returns error if:
    /// - Deserialization fails
    /// - State format is invalid
    /// - Version mismatch
    pub fn import_state(state_bytes: Vec<u8>) -> Result<Self> {
        // TODO: Implement state deserialization
        Err(C6pError::SessionError(
            "import_state not yet implemented".to_string(),
        ))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_session_roundtrip() {
        // Create mock session keys
        let keys = SessionKeys {
            session_id: vec![0x01; 8],
            root_key: vec![0x02; 32],
            kc_key: vec![0x06; 32],
            send_chain_key: vec![0x03; 32],
            recv_chain_key: vec![0x04; 32],
            session_binding: vec![0x05; 32],
        };

        // Create initiator session
        let initiator_session = SessionState::new(keys.clone(), true).unwrap();

        // Create responder session (swapped chain keys)
        let responder_keys = SessionKeys {
            session_id: keys.session_id.clone(),
            root_key: keys.root_key.clone(),
            kc_key: keys.kc_key.clone(),
            send_chain_key: keys.recv_chain_key.clone(), // Swapped
            recv_chain_key: keys.send_chain_key.clone(), // Swapped
            session_binding: keys.session_binding.clone(),
        };
        let responder_session = SessionState::new(responder_keys, false).unwrap();

        // Test encrypt/decrypt
        let plaintext = b"Hello, Convro!".to_vec();

        let encrypted = initiator_session.encrypt(plaintext.clone()).unwrap();
        assert_eq!(encrypted.counter, 0);
        assert!(encrypted.ciphertext.len() > 0);
        assert_eq!(encrypted.tag.len(), 16);

        let decrypted = responder_session.decrypt(encrypted).unwrap();
        assert_eq!(decrypted, plaintext);
    }

    #[test]
    fn test_counter_advancement() {
        let keys = SessionKeys {
            session_id: vec![0x01; 8],
            root_key: vec![0x02; 32],
            kc_key: vec![0x06; 32],
            send_chain_key: vec![0x03; 32],
            recv_chain_key: vec![0x04; 32],
            session_binding: vec![0x05; 32],
        };

        let initiator = SessionState::new(keys.clone(), true).unwrap();

        // Test that counter advances with each encryption
        assert_eq!(initiator.send_counter(), 0);

        let _msg1 = initiator.encrypt(b"Message 1".to_vec()).unwrap();
        assert_eq!(initiator.send_counter(), 1);

        let _msg2 = initiator.encrypt(b"Message 2".to_vec()).unwrap();
        assert_eq!(initiator.send_counter(), 2);

        let _msg3 = initiator.encrypt(b"Message 3".to_vec()).unwrap();
        assert_eq!(initiator.send_counter(), 3);
    }
}
