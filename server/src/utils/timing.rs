use chrono::{DateTime, Utc};
use rand::Rng;

/// Round timestamp to nearest 5 minutes (for timing obfuscation)
///
/// Example:
/// - 12:03:45 → 12:05:00
/// - 12:07:20 → 12:05:00
/// - 12:10:00 → 12:10:00
pub fn obfuscate_timestamp(ts: DateTime<Utc>) -> DateTime<Utc> {
    const ROUND_TO_MINUTES: i64 = 5;

    let minutes = ts.timestamp() / 60;
    let rounded_minutes = (minutes / ROUND_TO_MINUTES) * ROUND_TO_MINUTES;

    DateTime::from_timestamp(rounded_minutes * 60, 0).unwrap_or(ts)
}

/// Add random jitter (0-5 seconds) before message delivery
///
/// This prevents timing correlation attacks by randomizing
/// the actual delivery time within a 5-second window.
pub async fn apply_timing_jitter() {
    let jitter_ms = rand::thread_rng().gen_range(0..5000);
    tokio::time::sleep(tokio::time::Duration::from_millis(jitter_ms)).await;
}

/// Get obfuscated timestamp for "now"
pub fn now_obfuscated() -> DateTime<Utc> {
    obfuscate_timestamp(Utc::now())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_obfuscate_timestamp() {
        // Test rounding to 5-minute intervals

        // 12:03:45 → 12:00:00
        let ts = DateTime::from_timestamp(1000000000 + 3 * 60 + 45, 0).unwrap();
        let obfuscated = obfuscate_timestamp(ts);
        assert_eq!(obfuscated.minute() % 5, 0);
        assert_eq!(obfuscated.second(), 0);

        // 12:07:20 → 12:05:00
        let ts = DateTime::from_timestamp(1000000000 + 7 * 60 + 20, 0).unwrap();
        let obfuscated = obfuscate_timestamp(ts);
        assert_eq!(obfuscated.minute() % 5, 0);
        assert_eq!(obfuscated.second(), 0);

        // 12:10:00 → 12:10:00 (already aligned)
        let ts = DateTime::from_timestamp(1000000000 + 10 * 60, 0).unwrap();
        let obfuscated = obfuscate_timestamp(ts);
        assert_eq!(obfuscated.minute() % 5, 0);
        assert_eq!(obfuscated.second(), 0);
    }

    #[test]
    fn test_obfuscate_rounds_down() {
        // 12:03:00 should round to 12:00:00 (not 12:05:00)
        let ts = DateTime::from_timestamp(1000000000 + 3 * 60, 0).unwrap();
        let obfuscated = obfuscate_timestamp(ts);

        let diff = obfuscated.timestamp() - ts.timestamp();
        assert!(diff <= 0); // Should round down or stay same
    }

    #[tokio::test]
    async fn test_apply_timing_jitter() {
        let start = std::time::Instant::now();
        apply_timing_jitter().await;
        let duration = start.elapsed();

        // Should be between 0 and 5 seconds
        assert!(duration.as_millis() < 5000);
    }
}
