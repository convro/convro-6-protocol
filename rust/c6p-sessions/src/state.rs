//! Session state management
//!
//! TODO: Implement session state persistence
//! See docs/sessions/c6p-sessions-state.md

use crate::error::Result;
use c6p_crypto::{ChainKey, SessionId};
use crate::replay::SkipWindow;

/// Session state (per direction)
#[derive(Debug, Clone)]
pub struct SessionState {
    /// Session ID
    pub session_id: SessionId,

    /// Current chain key (send or receive)
    pub chain_key: ChainKey,

    /// Message counter
    pub counter: u64,

    /// Skip-window for replay detection (receive only)
    pub skip_window: Option<SkipWindow>,
}

impl SessionState {
    /// Create new session state
    ///
    /// TODO: Initialize session state from handshake output
    pub fn new(_session_id: SessionId, _chain_key: ChainKey, _is_sender: bool) -> Self {
        todo!("Implement session state initialization")
    }

    /// Serialize state for persistence
    ///
    /// TODO: Implement state serialization
    pub fn serialize(&self) -> Result<Vec<u8>> {
        todo!("Implement state serialization")
    }

    /// Deserialize state from storage
    ///
    /// TODO: Implement state deserialization
    pub fn deserialize(_data: &[u8]) -> Result<Self> {
        todo!("Implement state deserialization")
    }
}
