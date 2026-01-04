//! IslandAccord offer construction and parsing
//!
//! TODO: Implement offer construction from initiator perspective

use crate::types::*;
use crate::error::Result;

/// IslandAccord offer (from initiator to responder)
#[derive(Debug, Clone)]
pub struct Offer {
    /// Protocol version
    pub version: u8,

    /// Suite ID
    pub suite_id: u16,

    /// Session ID
    pub session_id: SessionId,

    /// Initiator device ID
    pub initiator_device_id: DeviceId,

    /// Responder device ID
    pub responder_device_id: DeviceId,

    /// Initiator identity DH public key
    pub initiator_identity_dh_pub: X25519PublicKey,

    /// Initiator identity signature public key
    pub initiator_identity_sig_pub: Ed25519PublicKey,

    /// Initiator ephemeral DH public key
    pub initiator_ephemeral_dh_pub: X25519PublicKey,

    /// Used SPK ID
    pub used_spk_id: SpkId,

    /// Used SPK public key
    pub used_spk_pub: X25519PublicKey,

    /// Used OTP ID (if any)
    pub used_otp_id: Option<OtpId>,

    /// Transcript hash
    pub transcript_hash: TranscriptHash,

    /// Key confirmation tag (KC1)
    pub kc1: [u8; 32],

    /// Offer signature
    pub offer_signature: Ed25519Signature,
}

impl Offer {
    /// Construct offer from initiator perspective
    ///
    /// TODO: Implement offer construction
    /// See docs/handshake/island-accord-crypto.md §3
    pub fn construct(/* ... */) -> Result<Self> {
        todo!("Implement offer construction")
    }

    /// Parse and validate offer from responder perspective
    ///
    /// TODO: Implement offer parsing and validation
    pub fn parse_and_validate(/* ... */) -> Result<Self> {
        todo!("Implement offer parsing")
    }
}
