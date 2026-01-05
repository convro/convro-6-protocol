//! Core types for C6P session management
//!
//! Normative reference: c6p-key-schedule.md, c6p-replay-and-skip-window.md

use serde::{Deserialize, Serialize};
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Chain key (32 bytes)
///
/// Used for symmetric ratcheting. Each message derives a new chain key.
/// MUST be zeroized on drop to prevent key leakage.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct ChainKey(pub [u8; 32]);

impl ChainKey {
    /// Create a new chain key from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        ChainKey(bytes)
    }

    /// Get the inner bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Debug for ChainKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "ChainKey([REDACTED])")
    }
}

/// Message key material (32 bytes)
///
/// Derived from chain key for each message.
/// Used to derive suite-specific AEAD key.
/// MUST be zeroized on drop.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct MessageKeyMaterial(pub [u8; 32]);

impl MessageKeyMaterial {
    /// Create from bytes
    pub fn from_bytes(bytes: [u8; 32]) -> Self {
        MessageKeyMaterial(bytes)
    }

    /// Get inner bytes
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Debug for MessageKeyMaterial {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "MessageKeyMaterial([REDACTED])")
    }
}

/// Message counter (u64)
///
/// Normative reference: c6p-key-schedule.md §1.3
/// - Wire format: decimal string
/// - Canonical bytes: BE64(counter)
/// - Range: 0 to 2^64-1
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Serialize, Deserialize)]
pub struct Counter(pub u64);

impl Counter {
    /// Zero counter (initial value)
    pub const ZERO: Counter = Counter(0);

    /// Maximum counter value (2^64 - 1)
    pub const MAX: Counter = Counter(u64::MAX);

    /// Create from u64
    pub fn new(value: u64) -> Self {
        Counter(value)
    }

    /// Get u64 value
    pub fn value(&self) -> u64 {
        self.0
    }

    /// Convert to canonical bytes (BE64)
    pub fn to_be_bytes(&self) -> [u8; 8] {
        self.0.to_be_bytes()
    }

    /// Parse from canonical bytes (BE64)
    pub fn from_be_bytes(bytes: [u8; 8]) -> Self {
        Counter(u64::from_be_bytes(bytes))
    }

    /// Increment counter (checked)
    ///
    /// Returns None if counter would overflow.
    pub fn checked_increment(&self) -> Option<Counter> {
        self.0.checked_add(1).map(Counter)
    }

    /// Decrement counter (checked)
    ///
    /// Returns None if counter would underflow.
    pub fn checked_decrement(&self) -> Option<Counter> {
        self.0.checked_sub(1).map(Counter)
    }

    /// Add to counter (checked)
    pub fn checked_add(&self, n: u64) -> Option<Counter> {
        self.0.checked_add(n).map(Counter)
    }

    /// Subtract from counter (checked)
    pub fn checked_sub(&self, n: u64) -> Option<Counter> {
        self.0.checked_sub(n).map(Counter)
    }

    /// Distance between two counters (saturating)
    pub fn distance(&self, other: Counter) -> u64 {
        self.0.saturating_sub(other.0)
    }
}

impl From<u64> for Counter {
    fn from(value: u64) -> Self {
        Counter(value)
    }
}

impl From<Counter> for u64 {
    fn from(counter: Counter) -> u64 {
        counter.0
    }
}

/// Stream direction
///
/// Normative reference: c6p-crypto-registry.md
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
pub enum StreamDirection {
    /// Initiator → Responder (stream_id = 0x01)
    I2R,
    /// Responder → Initiator (stream_id = 0x02)
    R2I,
}

impl StreamDirection {
    /// Get stream ID byte
    pub fn stream_id(&self) -> u8 {
        match self {
            StreamDirection::I2R => 0x01,
            StreamDirection::R2I => 0x02,
        }
    }

    /// Parse from stream ID byte
    pub fn from_stream_id(id: u8) -> Option<Self> {
        match id {
            0x01 => Some(StreamDirection::I2R),
            0x02 => Some(StreamDirection::R2I),
            _ => None,
        }
    }

    /// Get opposite direction
    pub fn reverse(&self) -> Self {
        match self {
            StreamDirection::I2R => StreamDirection::R2I,
            StreamDirection::R2I => StreamDirection::I2R,
        }
    }
}

/// Session state
///
/// State machine for session lifecycle.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum SessionState {
    /// Session is pending (handshake in progress)
    Pending,

    /// Session is active (can send/receive messages)
    Active,

    /// Session is closed (no more messages)
    Closed,

    /// Session is in error state (fatal error occurred)
    Error,
}

impl SessionState {
    /// Check if session can send messages
    pub fn can_send(&self) -> bool {
        matches!(self, SessionState::Active)
    }

    /// Check if session can receive messages
    pub fn can_receive(&self) -> bool {
        matches!(self, SessionState::Active | SessionState::Pending)
    }

    /// Check if session is terminated
    pub fn is_terminated(&self) -> bool {
        matches!(self, SessionState::Closed | SessionState::Error)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_counter_increment() {
        let c = Counter::new(0);
        assert_eq!(c.checked_increment(), Some(Counter::new(1)));

        let max = Counter::MAX;
        assert_eq!(max.checked_increment(), None); // Overflow
    }

    #[test]
    fn test_counter_distance() {
        let c1 = Counter::new(100);
        let c2 = Counter::new(50);
        assert_eq!(c1.distance(c2), 50);
        assert_eq!(c2.distance(c1), 0); // Saturating
    }

    #[test]
    fn test_counter_be_bytes() {
        let c = Counter::new(0x0102030405060708);
        let bytes = c.to_be_bytes();
        assert_eq!(bytes, [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);
        assert_eq!(Counter::from_be_bytes(bytes), c);
    }

    #[test]
    fn test_stream_direction() {
        assert_eq!(StreamDirection::I2R.stream_id(), 0x01);
        assert_eq!(StreamDirection::R2I.stream_id(), 0x02);
        assert_eq!(StreamDirection::from_stream_id(0x01), Some(StreamDirection::I2R));
        assert_eq!(StreamDirection::from_stream_id(0x02), Some(StreamDirection::R2I));
        assert_eq!(StreamDirection::from_stream_id(0x99), None);
        assert_eq!(StreamDirection::I2R.reverse(), StreamDirection::R2I);
        assert_eq!(StreamDirection::R2I.reverse(), StreamDirection::I2R);
    }

    #[test]
    fn test_session_state() {
        assert!(SessionState::Active.can_send());
        assert!(!SessionState::Pending.can_send());
        assert!(SessionState::Active.can_receive());
        assert!(SessionState::Pending.can_receive());
        assert!(!SessionState::Closed.can_receive());
        assert!(SessionState::Closed.is_terminated());
        assert!(SessionState::Error.is_terminated());
    }

    #[test]
    fn test_chain_key_zeroization() {
        let key = ChainKey::from_bytes([0x42; 32]);
        drop(key);
        // Zeroization happens automatically on drop
    }

    #[test]
    fn test_message_key_zeroization() {
        let mk = MessageKeyMaterial::from_bytes([0x42; 32]);
        drop(mk);
        // Zeroization happens automatically on drop
    }
}
