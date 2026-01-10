//! Bridge types for iOS FFI

/// Device identity with Ed25519 (signing) and X25519 (DH) key pairs
#[derive(Debug, Clone)]
pub struct DeviceIdentity {
    /// Device ID (16 bytes, derived from Ed25519 public key)
    pub device_id: Vec<u8>,

    /// Ed25519 private key (64 bytes)
    pub identity_priv_ed25519: Vec<u8>,

    /// Ed25519 public key (32 bytes)
    pub identity_pub_ed25519: Vec<u8>,

    /// X25519 private key (32 bytes)
    pub identity_priv_x25519: Vec<u8>,

    /// X25519 public key (32 bytes)
    pub identity_pub_x25519: Vec<u8>,

    /// Human-readable fingerprint (Base32, 32 chars)
    pub fingerprint: String,
}

/// Signed prekey pair
#[derive(Debug, Clone)]
pub struct SignedPrekey {
    /// SPK ID (8 bytes)
    pub spk_id: Vec<u8>,

    /// SPK private key (32 bytes)
    pub spk_priv: Vec<u8>,

    /// SPK public key (32 bytes)
    pub spk_pub: Vec<u8>,

    /// SPK signature (64 bytes, Ed25519)
    pub spk_sig: Vec<u8>,
}

/// One-time prekey pair
#[derive(Debug, Clone)]
pub struct OneTimePrekey {
    /// OTP ID (8 bytes)
    pub otp_id: Vec<u8>,

    /// OTP private key (32 bytes)
    pub otp_priv: Vec<u8>,

    /// OTP public key (32 bytes)
    pub otp_pub: Vec<u8>,
}

/// Prekey bundle for publishing
#[derive(Debug, Clone)]
pub struct PrekeyBundle {
    /// Responder device ID (16 bytes)
    pub responder_device_id: Vec<u8>,

    /// Responder Ed25519 public key (32 bytes)
    pub identity_pub_ed25519: Vec<u8>,

    /// Responder X25519 public key (32 bytes)
    pub identity_pub_x25519: Vec<u8>,

    /// SPK ID (8 bytes)
    pub spk_id: Vec<u8>,

    /// SPK public key (32 bytes)
    pub spk_pub: Vec<u8>,

    /// SPK signature (64 bytes)
    pub spk_sig: Vec<u8>,

    /// OTP ID (8 bytes, optional)
    pub otp_id: Option<Vec<u8>>,

    /// OTP public key (32 bytes, optional)
    pub otp_pub: Option<Vec<u8>>,
}

/// Handshake offer from initiator
#[derive(Debug, Clone)]
pub struct HandshakeOffer {
    /// Session ID (8 bytes)
    pub session_id: Vec<u8>,

    /// Initiator device ID (16 bytes)
    pub initiator_device_id: Vec<u8>,

    /// Responder device ID (16 bytes)
    pub responder_device_id: Vec<u8>,

    /// Initiator identity DH public key (32 bytes, X25519)
    pub initiator_identity_dh_pub: Vec<u8>,

    /// Initiator identity signature public key (32 bytes, Ed25519)
    pub initiator_identity_sig_pub: Vec<u8>,

    /// Initiator ephemeral DH public key (32 bytes, X25519)
    pub initiator_ephemeral_dh_pub: Vec<u8>,

    /// Used SPK ID (8 bytes)
    pub used_spk_id: Vec<u8>,

    /// Used SPK public key (32 bytes)
    pub used_spk_pub: Vec<u8>,

    /// Used SPK signature (64 bytes)
    pub used_spk_sig: Vec<u8>,

    /// Used OTP ID (8 bytes, optional)
    pub used_otp_id: Option<Vec<u8>>,

    /// Used OTP public key (32 bytes, optional)
    pub used_otp_pub: Option<Vec<u8>>,

    /// Transcript hash (32 bytes)
    pub transcript_hash: Vec<u8>,

    /// Key confirmation tag KC1 (32 bytes)
    pub kc1: Vec<u8>,

    /// Offer signature (64 bytes, Ed25519)
    pub offer_signature: Vec<u8>,

    /// Serialized offer bytes (for sending over network)
    pub serialized: Vec<u8>,
}

/// Handshake accept from responder
#[derive(Debug, Clone)]
pub struct HandshakeAccept {
    /// Session ID (8 bytes)
    pub session_id: Vec<u8>,

    /// Key confirmation tag KC2 (32 bytes)
    pub kc2: Vec<u8>,

    /// Accept signature (64 bytes, Ed25519)
    pub accept_signature: Vec<u8>,

    /// Serialized accept bytes (for sending over network)
    pub serialized: Vec<u8>,
}

/// Session keys after successful handshake
#[derive(Debug, Clone)]
pub struct SessionKeys {
    /// Session ID (8 bytes)
    pub session_id: Vec<u8>,

    /// Root key (32 bytes)
    pub root_key: Vec<u8>,

    /// Send chain key (32 bytes)
    pub send_chain_key: Vec<u8>,

    /// Receive chain key (32 bytes)
    pub recv_chain_key: Vec<u8>,

    /// Session binding (32 bytes)
    pub session_binding: Vec<u8>,
}

/// Encrypted message
#[derive(Debug, Clone)]
pub struct EncryptedMessage {
    /// Message counter (8 bytes, u64)
    pub counter: u64,

    /// Ciphertext (variable length)
    pub ciphertext: Vec<u8>,

    /// Authentication tag (16 bytes, Poly1305)
    pub tag: Vec<u8>,
}
