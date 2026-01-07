//! Device ID derivation from Ed25519 public keys
//!
//! Normative reference: docs/identity/device-identity.md §2.1
//!
//! Device IDs are 16-byte deterministic identifiers derived from Ed25519 identity keys:
//! ```text
//! device_id = SHA-256("C6P_DEVICE_ID_V1" || ed25519_public_key)[0..16]
//! ```

use crate::error::{IdentityError, Result};
use sha2::{Digest, Sha256};

/// Label for device ID derivation (normative)
const LABEL_DEVICE_ID: &[u8] = b"C6P_DEVICE_ID_V1";

/// Device ID (16 bytes)
///
/// Derived from Ed25519 public key using SHA-256 truncation.
/// Wire encoding: hex32 lowercase (32 characters).
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct DeviceId(pub [u8; 16]);

impl DeviceId {
    /// Derive device ID from Ed25519 public key
    ///
    /// # Normative Construction
    ///
    /// ```text
    /// hash_input = "C6P_DEVICE_ID_V1" || ed25519_public_key (17 + 32 = 49 bytes)
    /// hash_output = SHA-256(hash_input) (32 bytes)
    /// device_id = hash_output[0..16] (first 16 bytes)
    /// ```
    ///
    /// # Arguments
    ///
    /// * `public_key` - Ed25519 public key (32 bytes)
    ///
    /// # Returns
    ///
    /// * `Ok(DeviceId)` - Derived 16-byte device ID
    /// * `Err(IdentityError::InvalidKeyLength)` - If public key is not 32 bytes
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::DeviceId;
    /// let public_key = [0x42; 32];
    /// let device_id = DeviceId::from_ed25519_public_key(&public_key).unwrap();
    /// assert_eq!(device_id.as_bytes().len(), 16);
    /// ```
    pub fn from_ed25519_public_key(public_key: &[u8; 32]) -> Result<Self> {
        // Construct hash input: label || public_key
        let mut hasher = Sha256::new();
        hasher.update(LABEL_DEVICE_ID);
        hasher.update(public_key);
        let hash = hasher.finalize();

        // Take first 16 bytes
        let mut device_id = [0u8; 16];
        device_id.copy_from_slice(&hash[0..16]);

        Ok(DeviceId(device_id))
    }

    /// Get raw bytes
    pub fn as_bytes(&self) -> &[u8; 16] {
        &self.0
    }

    /// Get hex representation (wire format: hex32 lowercase)
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::DeviceId;
    /// let device_id = DeviceId([0xAA; 16]);
    /// assert_eq!(device_id.to_hex(), "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
    /// assert_eq!(device_id.to_hex().len(), 32);
    /// ```
    pub fn to_hex(&self) -> String {
        hex::encode(self.0)
    }

    /// Parse from hex (accepts hex32 lowercase or uppercase)
    ///
    /// # Arguments
    ///
    /// * `hex_str` - 32-character hex string
    ///
    /// # Returns
    ///
    /// * `Ok(DeviceId)` - Parsed device ID
    /// * `Err(IdentityError)` - If hex is invalid or wrong length
    ///
    /// # Examples
    ///
    /// ```
    /// # use c6p_identity::DeviceId;
    /// let device_id = DeviceId::from_hex("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa").unwrap();
    /// assert_eq!(device_id.as_bytes(), &[0xAA; 16]);
    /// ```
    pub fn from_hex(hex_str: &str) -> Result<Self> {
        let bytes = hex::decode(hex_str)
            .map_err(|e| IdentityError::EncodingError(format!("Invalid hex: {}", e)))?;

        if bytes.len() != 16 {
            return Err(IdentityError::InvalidDeviceId(format!(
                "Device ID must be 16 bytes (32 hex chars), got {}",
                bytes.len()
            )));
        }

        let mut arr = [0u8; 16];
        arr.copy_from_slice(&bytes);
        Ok(DeviceId(arr))
    }

    /// Create from raw bytes
    pub fn from_bytes(bytes: [u8; 16]) -> Self {
        DeviceId(bytes)
    }
}

impl std::fmt::Display for DeviceId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.to_hex())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_device_id_derivation() {
        // Test vector: deterministic Ed25519 public key
        let public_key = [0x42; 32];

        let device_id =
            DeviceId::from_ed25519_public_key(&public_key).expect("Device ID derivation failed");

        // Verify length
        assert_eq!(device_id.as_bytes().len(), 16);

        // Verify hex encoding
        let hex = device_id.to_hex();
        assert_eq!(hex.len(), 32);

        // Verify determinism (same input → same output)
        let device_id2 = DeviceId::from_ed25519_public_key(&public_key).unwrap();
        assert_eq!(device_id, device_id2);
    }

    #[test]
    fn test_device_id_determinism() {
        let pub1 = [0x11; 32];
        let pub2 = [0x22; 32];

        let id1a = DeviceId::from_ed25519_public_key(&pub1).unwrap();
        let id1b = DeviceId::from_ed25519_public_key(&pub1).unwrap();
        let id2 = DeviceId::from_ed25519_public_key(&pub2).unwrap();

        // Same input → same output
        assert_eq!(id1a, id1b);

        // Different input → different output
        assert_ne!(id1a, id2);
    }

    #[test]
    fn test_device_id_hex_encoding() {
        let device_id = DeviceId([0xAB; 16]);
        let hex = device_id.to_hex();

        assert_eq!(hex, "abababababababababababababababab");
        assert_eq!(hex.len(), 32);

        // Round-trip
        let parsed = DeviceId::from_hex(&hex).unwrap();
        assert_eq!(parsed, device_id);
    }

    #[test]
    fn test_device_id_from_hex() {
        let hex = "0123456789abcdef0123456789abcdef";
        let device_id = DeviceId::from_hex(hex).unwrap();

        assert_eq!(device_id.to_hex(), hex);

        // Uppercase should work too
        let hex_upper = "0123456789ABCDEF0123456789ABCDEF";
        let device_id_upper = DeviceId::from_hex(hex_upper).unwrap();
        assert_eq!(device_id, device_id_upper);
    }

    #[test]
    fn test_device_id_invalid_hex() {
        // Wrong length
        let result = DeviceId::from_hex("abcd");
        assert!(result.is_err());

        // Invalid hex characters
        let result = DeviceId::from_hex("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz");
        assert!(result.is_err());
    }

    #[test]
    fn test_device_id_display() {
        let device_id = DeviceId([0xFF; 16]);
        let display = format!("{}", device_id);
        assert_eq!(display, "ffffffffffffffffffffffffffffffff");
    }
}
