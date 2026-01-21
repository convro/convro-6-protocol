//! Replay protection with sliding skip-window
//!
//! Normative reference: c6p-replay-and-skip-window.md
//!
//! This module implements bounded replay protection using a sliding window bitmap
//! to track consumed message counters. Out-of-order messages are accepted within
//! the window, while replays and counters outside the window are rejected.
//!
//! # Skip-Window Design
//!
//! - Window size: 2048 counters (normative for DM v1)
//! - Bitmap representation: 32 x u64 = 2048 bits
//! - Memory: 256 bytes per stream direction
//!
//! # Acceptance Rules
//!
//! For incoming counter `c` with `recv_expected = R`:
//! - `c < R`: Reject (below window or replay)
//! - `c == R`: Accept, advance R
//! - `R < c <= R + 2048`: Accept out-of-order if not consumed
//! - `c > R + 2048`: Reject (too far ahead)

use crate::error::{Result, SessionError};
use crate::types::Counter;

/// Skip-window size for DM messages (normative)
///
/// Reference: c6p-replay-and-skip-window.md §2.1
pub const SKIP_WINDOW_DM_V1: u64 = 2048;

/// Number of u64 elements needed for bitmap (2048 bits / 64 bits/u64 = 32)
const BITMAP_SIZE: usize = 32;

/// Skip-window for replay detection
///
/// Tracks consumed message counters using a sliding bitmap window.
/// Provides O(1) lookup and update for counters within the window.
#[derive(Debug, Clone)]
pub struct SkipWindow {
    /// Next expected counter (lower bound of window)
    ///
    /// All counters < recv_expected are considered consumed or expired.
    recv_expected: Counter,

    /// Bitmap of consumed counters within [recv_expected, recv_expected + 2048)
    ///
    /// - bitmap[0] bit 0 = recv_expected + 0
    /// - bitmap[0] bit 1 = recv_expected + 1
    /// - ...
    /// - bitmap[31] bit 63 = recv_expected + 2047
    ///
    /// A set bit (1) means the counter was consumed.
    consumed: [u64; BITMAP_SIZE],
}

impl SkipWindow {
    /// Create new skip-window starting at counter 0
    pub fn new() -> Self {
        Self {
            recv_expected: Counter::ZERO,
            consumed: [0u64; BITMAP_SIZE],
        }
    }

    /// Create skip-window starting at specific counter
    pub fn with_expected(recv_expected: Counter) -> Self {
        Self {
            recv_expected,
            consumed: [0u64; BITMAP_SIZE],
        }
    }

    /// Get current recv_expected counter
    pub fn recv_expected(&self) -> Counter {
        self.recv_expected
    }

    /// Check if counter can be accepted (not replay, within window)
    ///
    /// # Returns
    /// - `Ok(true)` if counter can be accepted
    /// - `Err(SessionError::ReplayDetected)` if counter already consumed or below window
    /// - `Err(SessionError::SkipWindowOverflow)` if counter too far ahead
    ///
    /// # Acceptance Rules (Normative: §3)
    /// - `c < recv_expected`: REJECT (replay or expired)
    /// - `c >= recv_expected && c < recv_expected + 2048`: Accept if not consumed
    /// - `c >= recv_expected + 2048`: Reject (outside window)
    pub fn can_accept(&self, counter: Counter) -> Result<bool> {
        let c = counter.value();
        let r = self.recv_expected.value();

        // Case 1: Below window (normative §3.4)
        // "Anything below recv_expected that is not already known-consumed is always rejected"
        if c < r {
            // Always reject below-window counters
            // (They're either replays or expired/never-tracked)
            return Err(SessionError::ReplayDetected(c));
        }

        // Case 2: Within window
        if c < r + SKIP_WINDOW_DM_V1 {
            // Check if already consumed
            if self.is_consumed_unchecked(counter) {
                return Err(SessionError::ReplayDetected(c));
            }
            return Ok(true);
        }

        // Case 3: Too far ahead
        let gap = c - r;
        Err(SessionError::SkipWindowOverflow(gap))
    }

    /// Check if counter is already consumed (internal, no bounds check)
    fn is_consumed_unchecked(&self, counter: Counter) -> bool {
        let c = counter.value();
        let r = self.recv_expected.value();

        // Outside tracked range
        if c < r || c >= r + SKIP_WINDOW_DM_V1 {
            return false;
        }

        let offset = (c - r) as usize;
        let word_idx = offset / 64;
        let bit_idx = offset % 64;

        (self.consumed[word_idx] & (1u64 << bit_idx)) != 0
    }

    /// Mark counter as consumed
    ///
    /// # Arguments
    /// * `counter` - Counter to mark as consumed
    ///
    /// # Returns
    /// - `Ok(())` if counter marked successfully
    /// - `Err(SessionError)` if counter outside window or already consumed
    ///
    /// # Side Effects
    /// If `counter == recv_expected`, advances recv_expected and slides window.
    pub fn mark_consumed(&mut self, counter: Counter) -> Result<()> {
        let c = counter.value();
        let r = self.recv_expected.value();

        // Verify counter is within acceptable range
        if c < r {
            return Err(SessionError::ReplayDetected(c));
        }

        if c >= r + SKIP_WINDOW_DM_V1 {
            let gap = c - r;
            return Err(SessionError::SkipWindowOverflow(gap));
        }

        // Check not already consumed
        if self.is_consumed_unchecked(counter) {
            return Err(SessionError::ReplayDetected(c));
        }

        // Mark consumed in bitmap
        let offset = (c - r) as usize;
        let word_idx = offset / 64;
        let bit_idx = offset % 64;
        self.consumed[word_idx] |= 1u64 << bit_idx;

        // If this is recv_expected, advance and slide window
        if c == r {
            self.advance_window();
        }

        Ok(())
    }

    /// Advance recv_expected over contiguous consumed counters
    ///
    /// Slides the window forward, clearing bits for expired counters.
    fn advance_window(&mut self) {
        let mut advance_count = 0u64;

        // Find how many contiguous consumed counters we have starting from recv_expected
        for offset in 0..SKIP_WINDOW_DM_V1 {
            let word_idx = (offset / 64) as usize;
            let bit_idx = (offset % 64) as usize;

            if (self.consumed[word_idx] & (1u64 << bit_idx)) != 0 {
                advance_count += 1;
            } else {
                break;
            }
        }

        if advance_count == 0 {
            return;
        }

        // Advance recv_expected
        self.recv_expected = self
            .recv_expected
            .checked_add(advance_count)
            .expect("Counter overflow in advance_window");

        // Slide bitmap by advance_count bits
        self.slide_bitmap(advance_count);
    }

    /// Slide bitmap left by `shift` bits, filling with zeros
    fn slide_bitmap(&mut self, shift: u64) {
        if shift == 0 {
            return;
        }

        if shift >= SKIP_WINDOW_DM_V1 {
            // Shift entire window, clear everything
            self.consumed = [0u64; BITMAP_SIZE];
            return;
        }

        let shift_words = (shift / 64) as usize;
        let shift_bits = (shift % 64) as usize;

        if shift_bits == 0 {
            // Word-aligned shift
            for i in 0..BITMAP_SIZE {
                if i + shift_words < BITMAP_SIZE {
                    self.consumed[i] = self.consumed[i + shift_words];
                } else {
                    self.consumed[i] = 0;
                }
            }
        } else {
            // Bit-aligned shift
            for i in 0..BITMAP_SIZE {
                if i + shift_words < BITMAP_SIZE {
                    let low = self.consumed[i + shift_words] >> shift_bits;
                    let high = if i + shift_words + 1 < BITMAP_SIZE {
                        self.consumed[i + shift_words + 1] << (64 - shift_bits)
                    } else {
                        0
                    };
                    self.consumed[i] = low | high;
                } else {
                    self.consumed[i] = 0;
                }
            }
        }
    }

    /// Get window statistics (for debugging/testing)
    pub fn stats(&self) -> SkipWindowStats {
        let mut consumed_count = 0;
        for word in &self.consumed {
            consumed_count += word.count_ones();
        }

        SkipWindowStats {
            recv_expected: self.recv_expected,
            window_size: SKIP_WINDOW_DM_V1,
            consumed_count: consumed_count as u64,
        }
    }
}

impl Default for SkipWindow {
    fn default() -> Self {
        Self::new()
    }
}

/// Skip-window statistics
#[derive(Debug, Clone, Copy)]
pub struct SkipWindowStats {
    /// Next expected counter
    pub recv_expected: Counter,
    /// Window size
    pub window_size: u64,
    /// Number of consumed counters in window
    pub consumed_count: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_skip_window_new() {
        let window = SkipWindow::new();
        assert_eq!(window.recv_expected(), Counter::ZERO);
        assert_eq!(window.stats().consumed_count, 0);
    }

    #[test]
    fn test_in_order_acceptance() {
        let mut window = SkipWindow::new();

        // Accept counter 0
        assert!(window.can_accept(Counter::new(0)).unwrap());
        assert!(window.mark_consumed(Counter::new(0)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1));

        // Accept counter 1
        assert!(window.can_accept(Counter::new(1)).unwrap());
        assert!(window.mark_consumed(Counter::new(1)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(2));
    }

    #[test]
    fn test_out_of_order_acceptance() {
        let mut window = SkipWindow::new();

        // Accept counter 5 (out of order)
        assert!(window.can_accept(Counter::new(5)).unwrap());
        assert!(window.mark_consumed(Counter::new(5)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(0)); // Not advanced yet

        // Accept counter 0
        assert!(window.can_accept(Counter::new(0)).unwrap());
        assert!(window.mark_consumed(Counter::new(0)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1)); // Advanced

        // Try counter 5 again (should be replay)
        assert!(window.can_accept(Counter::new(5)).is_err());
    }

    #[test]
    fn test_replay_detection() {
        let mut window = SkipWindow::new();

        // Accept counter 0
        assert!(window.mark_consumed(Counter::new(0)).is_ok());

        // Try counter 0 again (replay)
        let result = window.can_accept(Counter::new(0));
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::ReplayDetected(0)
        ));
    }

    #[test]
    fn test_window_overflow() {
        let window = SkipWindow::new();

        // Counter far beyond window
        let far_counter = Counter::new(SKIP_WINDOW_DM_V1 + 100);
        let result = window.can_accept(far_counter);
        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            SessionError::SkipWindowOverflow(_)
        ));
    }

    #[test]
    fn test_window_edge() {
        let mut window = SkipWindow::new();

        // Accept counter at edge of window (2047)
        let edge_counter = Counter::new(SKIP_WINDOW_DM_V1 - 1);
        assert!(window.can_accept(edge_counter).unwrap());
        assert!(window.mark_consumed(edge_counter).is_ok());

        // Counter just beyond window (2048)
        let beyond_counter = Counter::new(SKIP_WINDOW_DM_V1);
        assert!(window.can_accept(beyond_counter).is_err());
    }

    #[test]
    fn test_contiguous_advance() {
        let mut window = SkipWindow::new();

        // Mark 0, 1, 2 consumed
        assert!(window.mark_consumed(Counter::new(0)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1));

        assert!(window.mark_consumed(Counter::new(1)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(2));

        assert!(window.mark_consumed(Counter::new(2)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(3));
    }

    #[test]
    fn test_skip_then_fill() {
        let mut window = SkipWindow::new();

        // Accept 0, 2, 3 (skip 1)
        assert!(window.mark_consumed(Counter::new(0)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1)); // Advanced to 1

        assert!(window.mark_consumed(Counter::new(2)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1)); // Still waiting for 1

        assert!(window.mark_consumed(Counter::new(3)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1)); // Still waiting for 1

        // Fill gap with 1
        assert!(window.mark_consumed(Counter::new(1)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(4)); // Now advanced to 4
    }

    #[test]
    fn test_large_gap() {
        let mut window = SkipWindow::new();

        // Accept counter 0
        assert!(window.mark_consumed(Counter::new(0)).is_ok());

        // Accept counter 1000 (large gap but within window)
        assert!(window.can_accept(Counter::new(1000)).unwrap());
        assert!(window.mark_consumed(Counter::new(1000)).is_ok());
        assert_eq!(window.recv_expected(), Counter::new(1));

        // Counter 1000 should now be consumed
        assert!(window.can_accept(Counter::new(1000)).is_err());
    }

    #[test]
    fn test_window_slide() {
        let mut window = SkipWindow::new();

        // Fill first 100 counters
        for i in 0..100 {
            assert!(window.mark_consumed(Counter::new(i)).is_ok());
        }
        assert_eq!(window.recv_expected(), Counter::new(100));

        // Counter 50 should now be below window (reject as replay/expired)
        let result = window.can_accept(Counter::new(50));
        assert!(result.is_err()); // Below window = replay error
        assert!(matches!(
            result.unwrap_err(),
            SessionError::ReplayDetected(_)
        ));
    }

    #[test]
    fn test_bitmap_stats() {
        let mut window = SkipWindow::new();

        // Mark some counters consumed
        assert!(window.mark_consumed(Counter::new(0)).is_ok());
        assert!(window.mark_consumed(Counter::new(5)).is_ok());
        assert!(window.mark_consumed(Counter::new(10)).is_ok());

        let stats = window.stats();
        assert_eq!(stats.recv_expected, Counter::new(1));
        assert!(stats.consumed_count >= 2); // At least 5 and 10 are still in window
    }
}
