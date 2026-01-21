import Foundation

// MARK: - Handshake Offer
/// Wrapper for C6P handshake offer data
/// Note: The actual C6P offer structure is defined in the C6PProtocol Rust module.
/// This Swift struct provides a convenient wrapper for API serialization.
struct HandshakeOffer: Codable {
    /// Serialized handshake offer from C6P (JSON wire format)
    let offer: Data
    
    /// Session ID for this handshake
    let sessionId: Data
    
    /// Initiator's device ID
    let initiatorDeviceId: String
    
    /// Responder's device ID (from prekey bundle)
    let responderDeviceId: String
    
    /// Timestamp when offer was created
    let timestamp: Date
    
    init(offer: Data, sessionId: Data, initiatorDeviceId: String, responderDeviceId: String, timestamp: Date = Date()) {
        self.offer = offer
        self.sessionId = sessionId
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.timestamp = timestamp
    }
}

// MARK: - Handshake Accept
/// Wrapper for C6P handshake accept data
/// Note: The actual C6P accept structure is defined in the C6PProtocol Rust module.
/// This Swift struct provides a convenient wrapper for API serialization.
struct HandshakeAccept: Codable {
    /// Serialized handshake accept from C6P (JSON wire format)
    let accept: Data
    
    /// Session ID for this handshake (matches the offer)
    let sessionId: Data
    
    /// Responder's device ID
    let responderDeviceId: String
    
    /// Timestamp when accept was created
    let timestamp: Date
    
    init(accept: Data, sessionId: Data, responderDeviceId: String, timestamp: Date = Date()) {
        self.accept = accept
        self.sessionId = sessionId
        self.responderDeviceId = responderDeviceId
        self.timestamp = timestamp
    }
}
