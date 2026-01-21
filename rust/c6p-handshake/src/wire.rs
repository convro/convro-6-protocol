//! Wire format serialization for IslandAccord handshake
//!
//! Normative reference: docs/handshake/island-accord-wire.md
//!
//! This module provides JSON serialization/deserialization for Offer and Accept
//! messages according to the C6P wire format specification.
//!
//! # Wire Format Rules
//!
//! - Hex identifiers: lowercase hex, fixed length (hex16 for 8 bytes, hex32 for 16 bytes)
//! - Binary fields: base64url without padding
//! - Field names: camelCase as per specification
//! - Strict validation: fail-closed on any deviation

use crate::{Accept, Offer};
use serde::{Deserialize, Serialize};

/// Wire format for IslandAccord Offer
///
/// JSON representation matching island-accord-wire.md §5.1.1
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OfferWire {
    /// Protocol version (must be 1)
    pub version: u8,

    /// Suite ID (1 = ChaCha20-Poly1305)
    pub suite_id: u16,

    /// Session ID (8 bytes, hex16 lowercase)
    #[serde(with = "hex_serde")]
    pub session_id: [u8; 8],

    /// Initiator device ID (16 bytes, hex32 lowercase)
    #[serde(with = "hex_serde")]
    pub initiator_device_id: [u8; 16],

    /// Responder device ID (16 bytes, hex32 lowercase)
    #[serde(with = "hex_serde")]
    pub responder_device_id: [u8; 16],

    /// Initiator identity DH public key (X25519, 32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub initiator_identity_dh_pub: [u8; 32],

    /// Initiator identity signature public key (Ed25519, 32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub initiator_identity_sig_pub: [u8; 32],

    /// Initiator ephemeral DH public key (X25519, 32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub initiator_ephemeral_dh_pub: [u8; 32],

    /// Used SPK ID (8 bytes, hex16 lowercase)
    #[serde(with = "hex_serde")]
    pub used_signed_prekey_id: [u8; 8],

    /// Used SPK public key (X25519, 32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub used_signed_prekey_public_key_x25519: [u8; 32],

    /// Used OTP ID (optional, 8 bytes, hex16 lowercase)
    #[serde(skip_serializing_if = "Option::is_none")]
    #[serde(default)]
    #[serde(with = "option_hex_serde")]
    pub used_one_time_prekey_id: Option<[u8; 8]>,

    /// Transcript hash (SHA-256, 32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub transcript_hash: [u8; 32],

    /// Key confirmation tag KC1 (32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub kc1: [u8; 32],

    /// Offer signature (Ed25519, 64 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub offer_signature_ed25519: [u8; 64],
}

/// Wire format for IslandAccord Accept
///
/// JSON representation matching island-accord-wire.md §5.2.1
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct AcceptWire {
    /// Session ID (8 bytes, hex16 lowercase)
    #[serde(with = "hex_serde")]
    pub session_id: [u8; 8],

    /// Responder device ID (16 bytes, hex32 lowercase)
    #[serde(with = "hex_serde")]
    pub responder_device_id: [u8; 16],

    /// Key confirmation tag KC2 (32 bytes, base64url)
    #[serde(with = "base64url_serde")]
    pub kc2: [u8; 32],
}

impl From<&Offer> for OfferWire {
    fn from(offer: &Offer) -> Self {
        OfferWire {
            version: offer.version,
            suite_id: offer.suite_id,
            session_id: offer.session_id.0,
            initiator_device_id: offer.initiator_device_id.0,
            responder_device_id: offer.responder_device_id.0,
            initiator_identity_dh_pub: offer.initiator_identity_dh_pub.0,
            initiator_identity_sig_pub: offer.initiator_identity_sig_pub.0,
            initiator_ephemeral_dh_pub: offer.initiator_ephemeral_dh_pub.0,
            used_signed_prekey_id: offer.used_spk_id.0,
            used_signed_prekey_public_key_x25519: offer.used_spk_pub.0,
            used_one_time_prekey_id: offer.used_otp_id.map(|id| id.0),
            transcript_hash: offer.transcript_hash.0,
            kc1: offer.kc1,
            offer_signature_ed25519: offer.offer_signature.0,
        }
    }
}

impl From<&Accept> for AcceptWire {
    fn from(accept: &Accept) -> Self {
        AcceptWire {
            session_id: accept.session_id.0,
            responder_device_id: accept.responder_device_id.0,
            kc2: accept.kc2,
        }
    }
}

// ============================================================================
// Custom Serde Helpers
// ============================================================================

/// Serialize/deserialize hex strings (lowercase, no 0x prefix)
mod hex_serde {
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S, const N: usize>(bytes: &[u8; N], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        serializer.serialize_str(&hex::encode(bytes))
    }

    pub fn deserialize<'de, D, const N: usize>(deserializer: D) -> Result<[u8; N], D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = hex::decode(&s).map_err(serde::de::Error::custom)?;

        if bytes.len() != N {
            return Err(serde::de::Error::custom(format!(
                "Expected {} bytes, got {}",
                N,
                bytes.len()
            )));
        }

        let mut arr = [0u8; N];
        arr.copy_from_slice(&bytes);
        Ok(arr)
    }
}

/// Serialize/deserialize optional hex strings
mod option_hex_serde {
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S, const N: usize>(
        opt: &Option<[u8; N]>,
        serializer: S,
    ) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        match opt {
            Some(bytes) => serializer.serialize_str(&hex::encode(bytes)),
            None => serializer.serialize_none(),
        }
    }

    pub fn deserialize<'de, D, const N: usize>(deserializer: D) -> Result<Option<[u8; N]>, D::Error>
    where
        D: Deserializer<'de>,
    {
        let opt = Option::<String>::deserialize(deserializer)?;

        match opt {
            Some(s) => {
                let bytes = hex::decode(&s).map_err(serde::de::Error::custom)?;

                if bytes.len() != N {
                    return Err(serde::de::Error::custom(format!(
                        "Expected {} bytes, got {}",
                        N,
                        bytes.len()
                    )));
                }

                let mut arr = [0u8; N];
                arr.copy_from_slice(&bytes);
                Ok(Some(arr))
            }
            None => Ok(None),
        }
    }
}

/// Serialize/deserialize base64url (no padding)
mod base64url_serde {
    use base64::Engine;
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S, const N: usize>(bytes: &[u8; N], serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let encoded = base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes);
        serializer.serialize_str(&encoded)
    }

    pub fn deserialize<'de, D, const N: usize>(deserializer: D) -> Result<[u8; N], D::Error>
    where
        D: Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
            .decode(&s)
            .map_err(serde::de::Error::custom)?;

        if bytes.len() != N {
            return Err(serde::de::Error::custom(format!(
                "Expected {} bytes, got {}",
                N,
                bytes.len()
            )));
        }

        let mut arr = [0u8; N];
        arr.copy_from_slice(&bytes);
        Ok(arr)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::types::*;

    #[test]
    fn test_offer_wire_serialization() {
        // Create a minimal offer for testing
        let offer = Offer {
            version: 1,
            suite_id: 1,
            session_id: SessionId([0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
            initiator_identity_dh_pub: X25519PublicKey([0x01; 32]),
            initiator_identity_sig_pub: Ed25519PublicKey([0x02; 32]),
            initiator_ephemeral_dh_pub: X25519PublicKey([0x03; 32]),
            used_spk_id: SpkId([0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B]),
            used_spk_pub: X25519PublicKey([0x05; 32]),
            used_spk_sig: Ed25519Signature([0x06; 64]),
            used_otp_id: None,
            used_otp_pub: None,
            transcript_hash: TranscriptHash([0x07; 32]),
            kc1: [0x08; 32],
            offer_signature: Ed25519Signature([0x09; 64]),
        };

        let wire: OfferWire = (&offer).into();
        let json = serde_json::to_string_pretty(&wire).expect("Serialization failed");

        println!("Offer JSON:\n{}", json);

        // Verify it's valid JSON
        assert!(json.contains("\"version\": 1"));
        assert!(json.contains("\"suiteId\": 1"));
        assert!(json.contains("\"sessionId\": \"1122334455667788\""));

        // Verify hex is lowercase
        assert!(json.contains("\"aaaa"));
        assert!(json.contains("\"bbbb"));

        // Verify base64url (no padding)
        assert!(!json.contains('='));

        // Round-trip
        let parsed: OfferWire = serde_json::from_str(&json).expect("Deserialization failed");
        assert_eq!(parsed.version, wire.version);
        assert_eq!(parsed.session_id, wire.session_id);
    }

    #[test]
    fn test_accept_wire_serialization() {
        let accept = Accept {
            session_id: SessionId([0x11; 8]),
            responder_device_id: DeviceId([0xCC; 16]),
            kc2: [0x42; 32],
        };

        let wire: AcceptWire = (&accept).into();
        let json = serde_json::to_string_pretty(&wire).expect("Serialization failed");

        println!("Accept JSON:\n{}", json);

        // Verify camelCase
        assert!(json.contains("\"sessionId\""));
        assert!(json.contains("\"responderDeviceId\""));
        assert!(json.contains("\"kc2\""));

        // Verify hex is lowercase
        assert!(json.contains("\"1111111111111111\""));
        assert!(json.contains("\"cccc"));

        // Round-trip
        let parsed: AcceptWire = serde_json::from_str(&json).expect("Deserialization failed");
        assert_eq!(parsed.session_id, wire.session_id);
        assert_eq!(parsed.kc2, wire.kc2);
    }

    #[test]
    fn test_offer_with_otp() {
        let offer = Offer {
            version: 1,
            suite_id: 1,
            session_id: SessionId([0xFF; 8]),
            initiator_device_id: DeviceId([0xAA; 16]),
            responder_device_id: DeviceId([0xBB; 16]),
            initiator_identity_dh_pub: X25519PublicKey([0x01; 32]),
            initiator_identity_sig_pub: Ed25519PublicKey([0x02; 32]),
            initiator_ephemeral_dh_pub: X25519PublicKey([0x03; 32]),
            used_spk_id: SpkId([0x04; 8]),
            used_spk_pub: X25519PublicKey([0x05; 32]),
            used_spk_sig: Ed25519Signature([0x06; 64]),
            used_otp_id: Some(OtpId([0xDD; 8])),
            used_otp_pub: Some(X25519PublicKey([0x0A; 32])),
            transcript_hash: TranscriptHash([0x07; 32]),
            kc1: [0x08; 32],
            offer_signature: Ed25519Signature([0x09; 64]),
        };

        let wire: OfferWire = (&offer).into();
        let json = serde_json::to_string_pretty(&wire).expect("Serialization failed");

        println!("Offer with OTP JSON:\n{}", json);

        // Verify OTP field is present
        assert!(json.contains("\"usedOneTimePrekeyId\""));
        assert!(json.contains("\"dddddddddddddddd\""));
    }

    #[test]
    fn test_hex_encoding_lowercase() {
        let wire = OfferWire {
            version: 1,
            suite_id: 1,
            session_id: [0xAB, 0xCD, 0xEF, 0x12, 0x34, 0x56, 0x78, 0x90],
            initiator_device_id: [0xFF; 16],
            responder_device_id: [0x00; 16],
            initiator_identity_dh_pub: [0x42; 32],
            initiator_identity_sig_pub: [0x43; 32],
            initiator_ephemeral_dh_pub: [0x44; 32],
            used_signed_prekey_id: [0xAA; 8],
            used_signed_prekey_public_key_x25519: [0xBB; 32],
            used_one_time_prekey_id: None,
            transcript_hash: [0xCC; 32],
            kc1: [0xDD; 32],
            offer_signature_ed25519: [0xEE; 64],
        };

        let json = serde_json::to_string(&wire).expect("Serialization failed");

        // All hex must be lowercase
        assert!(json.contains("\"abcdef1234567890\""));
        assert!(json.contains("\"ffffffffffffffffffffffffffffffff\""));
        assert!(!json.contains("ABCDEF")); // No uppercase
    }
}
