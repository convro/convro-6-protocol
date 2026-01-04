//! Cryptographic operations for IslandAccord v1
//!
//! Implements DH operations, signature verification, and transcript computation.

use crate::types::*;
use crate::error::{HandshakeError, Result};

/// Perform X25519 Diffie-Hellman
///
/// # Arguments
/// * `private_key` - X25519 private key (32 bytes)
/// * `public_key` - X25519 public key (32 bytes)
///
/// # Returns
/// * DH shared secret (32 bytes)
///
/// TODO: Implement using x25519-dalek 2.0 API
pub fn x25519_dh(_private_key: &X25519PrivateKey, _public_key: &X25519PublicKey) -> DhSecret {
    // Placeholder - will implement with proper x25519-dalek 2.0 API
    // See: https://docs.rs/x25519-dalek/2.0.0/x25519_dalek/
    DhSecret([0u8; 32])
}

/// Verify Ed25519 signature
///
/// # Arguments
/// * `public_key` - Ed25519 public key
/// * `message` - Message bytes
/// * `signature` - Ed25519 signature
///
/// # Returns
/// * `Ok(())` if signature is valid
/// * `Err(HandshakeError::InvalidSpkSignature)` if invalid
pub fn ed25519_verify(
    public_key: &Ed25519PublicKey,
    message: &[u8],
    signature: &Ed25519Signature,
) -> Result<()> {
    use ed25519_dalek::{Signature, Verifier, VerifyingKey};

    let verifying_key = VerifyingKey::from_bytes(&public_key.0)
        .map_err(|e| HandshakeError::CryptoError(format!("Invalid Ed25519 public key: {}", e)))?;

    let sig = Signature::from_bytes(&signature.0);

    verifying_key.verify(message, &sig)
        .map_err(|_| HandshakeError::InvalidSpkSignature)?;

    Ok(())
}

/// Compute transcript hash (SHA-256)
///
/// # Arguments
/// * `transcript_bytes` - Full transcript bytes
///
/// # Returns
/// * TranscriptHash (32 bytes)
pub fn compute_transcript_hash(transcript_bytes: &[u8]) -> TranscriptHash {
    use sha2::{Digest, Sha256};

    let mut hasher = Sha256::new();
    hasher.update(transcript_bytes);
    let hash = hasher.finalize();

    TranscriptHash(hash.into())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_x25519_dh() {
        // Test X25519 DH computation
        let alice_private = X25519PrivateKey([1u8; 32]);
        let bob_public = X25519PublicKey([2u8; 32]);

        let _shared = x25519_dh(&alice_private, &bob_public);
        // DH operation should complete without panic
    }

    #[test]
    fn test_transcript_hash() {
        let transcript = b"test transcript";
        let hash = compute_transcript_hash(transcript);

        // Hash should be deterministic
        let hash2 = compute_transcript_hash(transcript);
        assert_eq!(hash.0, hash2.0);
    }
}
