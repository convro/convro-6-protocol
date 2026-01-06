//! Human-readable fingerprint generation
//!
//! Normative reference: docs/identity/device-identity.md §3.2
//!
//! Fingerprints provide human-readable identity verification using SHA-256 hashing.

use crate::error::{IdentityError, Result};
use sha2::{Digest, Sha256};

/// Label for fingerprint derivation (normative)
const LABEL_FINGERPRINT: &[u8] = b"C6P_FINGERPRINT_V1";

/// Human-readable fingerprint for identity verification
///
/// Full fingerprint is 32 bytes (SHA-256 hash), encoded as base64url without padding (43 chars).
/// Short fingerprint is first 8 bytes, encoded as hex16 lowercase (16 chars).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Fingerprint {
    /// Full SHA-256 hash (32 bytes)
    hash: [u8; 32],
}

impl Fingerprint {
    /// Generate fingerprint from Ed25519 public key
    ///
    /// # Normative Construction
    ///
    /// ```text
    /// hash_input = "C6P_FINGERPRINT_V1" || ed25519_public_key (18 + 32 = 50 bytes)
    /// fingerprint_hash = SHA-256(hash_input) (32 bytes)
    /// ```
    ///
    /// # Arguments
    ///
    /// * `public_key` - Ed25519 public key (32 bytes)
    ///
    /// # Returns
    ///
    /// * `Ok(Fingerprint)` - Generated fingerprint
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::Fingerprint;
    /// let public_key = [0x42; 32];
    /// let fingerprint = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
    /// let fp_str = fingerprint.to_base64url();
    /// assert_eq!(fp_str.len(), 43); // 32 bytes → 43 chars base64url
    /// ```
    pub fn from_ed25519_public_key(public_key: &[u8; 32]) -> Result<Self> {
        // Construct hash input: label || public_key
        let mut hasher = Sha256::new();
        hasher.update(LABEL_FINGERPRINT);
        hasher.update(public_key);
        let hash = hasher.finalize();

        let mut hash_array = [0u8; 32];
        hash_array.copy_from_slice(&hash);

        Ok(Fingerprint { hash: hash_array })
    }

    /// Get full fingerprint hash (32 bytes)
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.hash
    }

    /// Get base64url encoding (no padding) - 43 characters
    ///
    /// This is the canonical wire format for full fingerprints.
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::Fingerprint;
    /// let public_key = [0x00; 32];
    /// let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
    /// let b64 = fp.to_base64url();
    /// assert_eq!(b64.len(), 43);
    /// assert!(!b64.contains('=')); // No padding
    /// ```
    pub fn to_base64url(&self) -> String {
        use base64::Engine;
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(&self.hash)
    }

    /// Get short fingerprint (first 8 bytes, hex16 lowercase)
    ///
    /// Short fingerprints are useful for quick visual verification.
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::Fingerprint;
    /// let public_key = [0xFF; 32];
    /// let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
    /// let short = fp.short_hex();
    /// assert_eq!(short.len(), 16); // 8 bytes → 16 hex chars
    /// ```
    pub fn short_hex(&self) -> String {
        hex::encode(&self.hash[0..8])
    }

    /// Get formatted fingerprint (with hyphens for readability)
    ///
    /// Format: 8 groups of 4 characters separated by hyphens
    /// Example: "ABCD-EFGH-IJKL-MNOP-QRST-UVWX-YZ01-2345"
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::Fingerprint;
    /// let public_key = [0xAB; 32];
    /// let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
    /// let formatted = fp.formatted();
    /// assert!(formatted.contains('-'));
    /// ```
    pub fn formatted(&self) -> String {
        let b64 = self.to_base64url();

        // Split into groups of 4 characters with hyphens
        let mut formatted = String::new();
        for (i, chunk) in b64.chars().collect::<Vec<_>>().chunks(4).enumerate() {
            if i > 0 {
                formatted.push('-');
            }
            formatted.extend(chunk);
        }

        formatted
    }

    /// Parse from base64url (no padding)
    pub fn from_base64url(b64: &str) -> Result<Self> {
        use base64::Engine;

        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(b64)
            .map_err(|e| IdentityError::EncodingError(format!("Invalid base64url: {}", e)))?;

        if bytes.len() != 32 {
            return Err(IdentityError::InvalidFingerprint(format!(
                "Fingerprint must be 32 bytes, got {}",
                bytes.len()
            )));
        }

        let mut hash = [0u8; 32];
        hash.copy_from_slice(&bytes);

        Ok(Fingerprint { hash })
    }

    /// Get hex encoding of full hash (64 characters)
    pub fn to_hex(&self) -> String {
        hex::encode(&self.hash)
    }
}

impl std::fmt::Display for Fingerprint {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.formatted())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_fingerprint_generation() {
        let public_key = [0x42; 32];

        let fingerprint = Fingerprint::from_ed25519_public_key(&public_key)
            .expect("Fingerprint generation failed");

        // Verify hash is 32 bytes
        assert_eq!(fingerprint.as_bytes().len(), 32);

        // Verify base64url encoding
        let b64 = fingerprint.to_base64url();
        assert_eq!(b64.len(), 43); // 32 bytes → 43 chars base64url
        assert!(!b64.contains('=')); // No padding
    }

    #[test]
    fn test_fingerprint_determinism() {
        let pub1 = [0x11; 32];
        let pub2 = [0x22; 32];

        let fp1a = Fingerprint::from_ed25519_public_key(&pub1).unwrap();
        let fp1b = Fingerprint::from_ed25519_public_key(&pub1).unwrap();
        let fp2 = Fingerprint::from_ed25519_public_key(&pub2).unwrap();

        // Same input → same output
        assert_eq!(fp1a, fp1b);

        // Different input → different output
        assert_ne!(fp1a, fp2);
    }

    #[test]
    fn test_fingerprint_short_hex() {
        let public_key = [0xFF; 32];
        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();

        let short = fp.short_hex();
        assert_eq!(short.len(), 16); // 8 bytes → 16 hex chars

        // Verify it's hex lowercase
        assert!(short.chars().all(|c| c.is_ascii_hexdigit() && !c.is_uppercase()));
    }

    #[test]
    fn test_fingerprint_formatted() {
        let public_key = [0xAB; 32];
        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();

        let formatted = fp.formatted();

        // Should contain hyphens
        assert!(formatted.contains('-'));

        // Count hyphens (should be 10 for 11 groups of 4 chars from 43-char string)
        let hyphen_count = formatted.chars().filter(|&c| c == '-').count();
        assert_eq!(hyphen_count, 10);
    }

    #[test]
    fn test_fingerprint_base64url_roundtrip() {
        let public_key = [0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0,
                          0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88,
                          0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11,
                          0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0x99];

        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();
        let b64 = fp.to_base64url();
        let parsed = Fingerprint::from_base64url(&b64).unwrap();

        assert_eq!(fp, parsed);
    }

    #[test]
    fn test_fingerprint_to_hex() {
        let public_key = [0x00; 32];
        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();

        let hex = fp.to_hex();
        assert_eq!(hex.len(), 64); // 32 bytes → 64 hex chars
    }

    #[test]
    fn test_fingerprint_display() {
        let public_key = [0x42; 32];
        let fp = Fingerprint::from_ed25519_public_key(&public_key).unwrap();

        let display = format!("{}", fp);
        assert!(display.contains('-')); // Should be formatted with hyphens
    }

    #[test]
    fn test_fingerprint_invalid_base64url() {
        // Wrong length
        let result = Fingerprint::from_base64url("abc");
        assert!(result.is_err());

        // Invalid base64 characters
        let result = Fingerprint::from_base64url("!!!invalid!!!");
        assert!(result.is_err());
    }
}
