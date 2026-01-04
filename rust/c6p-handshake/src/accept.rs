//! IslandAccord accept construction and parsing
//!
//! TODO: Implement accept construction from responder perspective

use crate::types::*;
use crate::error::Result;

/// IslandAccord accept (from responder to initiator)
#[derive(Debug, Clone)]
pub struct Accept {
    /// Session ID
    pub session_id: SessionId,

    /// Key confirmation tag (KC2)
    pub kc2: [u8; 32],
}

impl Accept {
    /// Construct accept from responder perspective
    ///
    /// TODO: Implement accept construction
    /// See docs/handshake/island-accord-crypto.md §4
    pub fn construct(/* ... */) -> Result<Self> {
        todo!("Implement accept construction")
    }

    /// Parse and validate accept from initiator perspective
    ///
    /// TODO: Implement accept parsing and validation
    pub fn parse_and_validate(/* ... */) -> Result<Self> {
        todo!("Implement accept parsing")
    }
}
