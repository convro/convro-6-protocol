import Foundation

// MARK: - Handshake Offer
struct HandshakeOffer: Codable {
    let offer: Data
    let sessionId: Data

    // TODO: Add C6P offer fields
}

// MARK: - Handshake Accept
struct HandshakeAccept: Codable {
    let accept: Data
    let sessionId: Data

    // TODO: Add C6P accept fields
}
