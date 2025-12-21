//
//  C6PHandshakeContracts.swift
//  C6P-Protocol
//
//  Canonical wire contracts for handshake99.
//
//  Single source of truth for data shapes that go over backend:
//
//  - C6PHandshake99OfferContract: initiator -> responder (via server store)
//  - (Future) ack / list responses can live here too.
//
//  Encoding rules:
//  - Binary fields use C6PBase64UrlData (base64url, no padding).
//

import Foundation

/// handshake99 version (NOT the same as global C6P_VERSION).
public let C6P_HANDSHAKE99_VERSION: UInt8 = 1

/// First handshake message sent by initiator to responder via backend.
/// Deterministic + auditable. Server never computes secrets.
public struct C6PHandshake99OfferContract: Codable, Hashable {

    public let version: UInt8

    public let initiatorDeviceId: C6PDeviceId
    public let responderDeviceId: C6PDeviceId

    public let sessionId: C6PSessionId

    /// Initiator ephemeral X25519 public key (32B)
    public let ephemeralPublicKeyX25519: C6PBase64UrlData

    /// Signed-prekey public key the initiator used (32B)
    /// Lets responder validate server isn't splicing offers with different SPK.
    public let usedSignedPrekeyPublicKeyX25519: C6PBase64UrlData

    /// Optional consumed OTP id.
    /// (OTP is reserved/consumed by server at bundle fetch; responder deletes locally on accept.)
    public let usedOneTimePrekeyId: C6PKeyId?

    public init(
        version: UInt8 = C6P_HANDSHAKE99_VERSION,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        ephemeralPublicKeyX25519: Data,
        usedSignedPrekeyPublicKeyX25519: Data,
        usedOneTimePrekeyId: C6PKeyId?
    ) throws {
        self.version = version
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.sessionId = sessionId
        self.ephemeralPublicKeyX25519 = C6PBase64UrlData(ephemeralPublicKeyX25519)
        self.usedSignedPrekeyPublicKeyX25519 = C6PBase64UrlData(usedSignedPrekeyPublicKeyX25519)
        self.usedOneTimePrekeyId = usedOneTimePrekeyId

        try validate()
    }

    public func validate() throws {
        guard version == C6P_HANDSHAKE99_VERSION else {
            throw C6PPrekeyContractError.invalidC6PVersion(expected: C6P_HANDSHAKE99_VERSION, actual: version)
        }
        // length checks (strict v1)
        guard ephemeralPublicKeyX25519.data.count == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: ephemeralPublicKeyX25519.data.count)
        }
        guard usedSignedPrekeyPublicKeyX25519.data.count == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: usedSignedPrekeyPublicKeyX25519.data.count)
        }
    }
}
