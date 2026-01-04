//! Device ID derivation from Ed25519 public keys
//!
//! TODO: Implement device ID derivation
//! See docs/identity/c6p-identity-format.md

use crate::error::Result;

/// Device ID (16 bytes)
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct DeviceId(pub [u8; 16]);

impl DeviceId {
    /// Derive device ID from Ed25519 public key
    ///
    /// device_id = SHA-256("C6P_DEVICE_ID_V1" || ed25519_public_key)[0..16]
    ///
    /// TODO: Implement derivation
    pub fn from_ed25519_public_key(_public_key: &[u8; 32]) -> Result<Self> {
        todo!("Implement device ID derivation")
    }

    /// Get hex representation
    pub fn to_hex(&self) -> String {
        hex::encode(&self.0)
    }

    /// Parse from hex
    pub fn from_hex(hex_str: &str) -> Result<Self> {
        let bytes = hex::decode(hex_str)
            .map_err(|e| crate::IdentityError::EncodingError(format!("Invalid hex: {}", e)))?;

        if bytes.len() != 16 {
            return Err(crate::IdentityError::InvalidDeviceId(
                "Device ID must be 16 bytes".to_string(),
            ));
        }

        let mut arr = [0u8; 16];
        arr.copy_from_slice(&bytes);
        Ok(DeviceId(arr))
    }
}
