//! Utility functions for iOS bridge

use crate::error::{C6pError, Result};
use rand::RngCore;

/// Convert bytes to hex string
///
/// # Arguments
///
/// * `data` - Bytes to convert
///
/// # Returns
///
/// Lowercase hex string (e.g., "deadbeef")
pub fn bytes_to_hex(data: Vec<u8>) -> String {
    hex::encode(data)
}

/// Convert hex string to bytes
///
/// # Arguments
///
/// * `hex` - Hex string (with or without 0x prefix)
///
/// # Returns
///
/// Decoded bytes
///
/// # Errors
///
/// Returns error if:
/// - String contains non-hex characters
/// - String has odd length
pub fn hex_to_bytes(hex: String) -> Result<Vec<u8>> {
    // Remove 0x prefix if present
    let hex_clean = hex.trim_start_matches("0x");

    hex::decode(hex_clean).map_err(Into::into)
}

/// Generate random bytes
///
/// Uses cryptographically secure random number generator (OsRng).
///
/// # Arguments
///
/// * `length` - Number of random bytes to generate
///
/// # Returns
///
/// Random bytes
///
/// # Errors
///
/// Returns error if RNG fails
pub fn random_bytes(length: u32) -> Result<Vec<u8>> {
    let mut bytes = vec![0u8; length as usize];
    rand::rngs::OsRng
        .try_fill_bytes(&mut bytes)
        .map_err(|e| C6pError::CryptoError(format!("RNG failed: {}", e)))?;
    Ok(bytes)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_hex_roundtrip() {
        let data = vec![0xde, 0xad, 0xbe, 0xef];
        let hex = bytes_to_hex(data.clone());
        assert_eq!(hex, "deadbeef");

        let decoded = hex_to_bytes(hex).unwrap();
        assert_eq!(decoded, data);
    }

    #[test]
    fn test_hex_with_prefix() {
        let hex = "0xdeadbeef".to_string();
        let decoded = hex_to_bytes(hex).unwrap();
        assert_eq!(decoded, vec![0xde, 0xad, 0xbe, 0xef]);
    }

    #[test]
    fn test_random_bytes() {
        let bytes1 = random_bytes(32).unwrap();
        let bytes2 = random_bytes(32).unwrap();

        assert_eq!(bytes1.len(), 32);
        assert_eq!(bytes2.len(), 32);
        assert_ne!(bytes1, bytes2); // Should be different
    }
}
