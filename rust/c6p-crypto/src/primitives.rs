//! C6P Cryptographic Primitives
//!
//! Low-level crypto wrappers (SHA-256, HKDF, HMAC)

use sha2::{Digest, Sha256};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};

/// SHA-256 hash
pub fn sha256(data: &[u8]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    hasher.update(data);
    hasher.finalize().into()
}

/// HKDF-Extract with SHA-256
pub fn hkdf_extract(salt: &[u8], ikm: &[u8]) -> [u8; 32] {
    let (prk, _) = Hkdf::<Sha256>::extract(Some(salt), ikm);
    prk.into()
}

/// HKDF-Expand with SHA-256
pub fn hkdf_expand(prk: &[u8; 32], info: &[u8], length: usize) -> Vec<u8> {
    let hk = Hkdf::<Sha256>::from_prk(prk).expect("PRK length is always 32 bytes for SHA-256");
    let mut okm = vec![0u8; length];
    hk.expand(info, &mut okm).expect("Expand length must be <= 255 * HashLen");
    okm
}

/// HMAC-SHA256
pub fn hmac_sha256(key: &[u8], data: &[u8]) -> [u8; 32] {
    let mut mac = Hmac::<Sha256>::new_from_slice(key)
        .expect("HMAC can take key of any size");
    mac.update(data);
    mac.finalize().into_bytes().into()
}
