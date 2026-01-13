use crate::errors::{AppError, AppResult};

/// Fixed size for sealed sender envelopes (64 KB)
pub const SEALED_ENVELOPE_SIZE: usize = 65536;

/// Pad data to fixed size (64 KB) with length prefix
///
/// Format:
/// - Bytes 0-3: Length of actual data (u32, big-endian)
/// - Bytes 4-N: Actual data
/// - Bytes N+1 to 65535: Zero padding
pub fn pad_sealed_envelope(data: Vec<u8>) -> AppResult<Vec<u8>> {
    let data_len = data.len();

    // Check if data fits (4 bytes for length + data)
    if data_len > SEALED_ENVELOPE_SIZE - 4 {
        return Err(AppError::PayloadTooLarge(format!(
            "Data size {} exceeds maximum {} (after 4-byte length prefix)",
            data_len,
            SEALED_ENVELOPE_SIZE - 4
        )));
    }

    // Create padded buffer
    let mut padded = vec![0u8; SEALED_ENVELOPE_SIZE];

    // Write length prefix (big-endian u32)
    padded[0..4].copy_from_slice(&(data_len as u32).to_be_bytes());

    // Write actual data
    padded[4..4 + data_len].copy_from_slice(&data);

    // Rest is already zeros (padding)

    Ok(padded)
}

/// Remove padding from sealed envelope
///
/// Reads length prefix and extracts actual data
pub fn unpad_sealed_envelope(padded: Vec<u8>) -> AppResult<Vec<u8>> {
    // Verify size
    if padded.len() != SEALED_ENVELOPE_SIZE {
        return Err(AppError::ValidationError(format!(
            "Invalid padded envelope size: {} (expected {})",
            padded.len(),
            SEALED_ENVELOPE_SIZE
        )));
    }

    // Read length prefix
    let length = u32::from_be_bytes([padded[0], padded[1], padded[2], padded[3]]) as usize;

    // Validate length
    if length > SEALED_ENVELOPE_SIZE - 4 {
        return Err(AppError::ValidationError(format!(
            "Invalid length prefix: {} (max {})",
            length,
            SEALED_ENVELOPE_SIZE - 4
        )));
    }

    // Extract actual data
    Ok(padded[4..4 + length].to_vec())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pad_and_unpad() {
        let data = b"Hello, World!".to_vec();

        let padded = pad_sealed_envelope(data.clone()).unwrap();
        assert_eq!(padded.len(), SEALED_ENVELOPE_SIZE);

        let unpadded = unpad_sealed_envelope(padded).unwrap();
        assert_eq!(unpadded, data);
    }

    #[test]
    fn test_pad_empty() {
        let data = Vec::new();

        let padded = pad_sealed_envelope(data.clone()).unwrap();
        assert_eq!(padded.len(), SEALED_ENVELOPE_SIZE);

        let unpadded = unpad_sealed_envelope(padded).unwrap();
        assert_eq!(unpadded, data);
    }

    #[test]
    fn test_pad_max_size() {
        let data = vec![0u8; SEALED_ENVELOPE_SIZE - 4];

        let padded = pad_sealed_envelope(data.clone()).unwrap();
        assert_eq!(padded.len(), SEALED_ENVELOPE_SIZE);

        let unpadded = unpad_sealed_envelope(padded).unwrap();
        assert_eq!(unpadded, data);
    }

    #[test]
    fn test_pad_too_large() {
        let data = vec![0u8; SEALED_ENVELOPE_SIZE]; // Too large (no room for length prefix)

        let result = pad_sealed_envelope(data);
        assert!(result.is_err());
    }

    #[test]
    fn test_unpad_wrong_size() {
        let padded = vec![0u8; 1000]; // Wrong size

        let result = unpad_sealed_envelope(padded);
        assert!(result.is_err());
    }
}
