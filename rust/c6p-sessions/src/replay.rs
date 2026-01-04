//! Replay protection with sliding skip-window
//!
//! TODO: Implement skip-window replay detection
//! See docs/sessions/c6p-sessions-replay.md

use crate::error::Result;

/// Skip-window for replay detection
#[derive(Debug, Clone)]
pub struct SkipWindow {
    /// Current receive counter
    pub recv_counter: u64,

    /// Bitmap of recently received messages
    pub bitmap: u64,

    /// Window size (default: 64)
    pub window_size: usize,
}

impl SkipWindow {
    /// Create new skip-window
    pub fn new() -> Self {
        Self {
            recv_counter: 0,
            bitmap: 0,
            window_size: 64,
        }
    }

    /// Check if counter is valid (not a replay)
    ///
    /// TODO: Implement replay check logic
    pub fn check_counter(&self, _counter: u64) -> Result<bool> {
        todo!("Implement skip-window check")
    }

    /// Mark counter as received
    ///
    /// TODO: Implement bitmap update
    pub fn mark_received(&mut self, _counter: u64) -> Result<()> {
        todo!("Implement skip-window update")
    }
}

impl Default for SkipWindow {
    fn default() -> Self {
        Self::new()
    }
}
