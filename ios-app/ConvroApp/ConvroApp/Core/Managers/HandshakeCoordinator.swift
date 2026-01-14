import Foundation
import C6PProtocol

// MARK: - Handshake Coordinator
/// Orchestrates IslandAccord v1 handshake flow between two users
@MainActor
class HandshakeCoordinator: ObservableObject {
    // MARK: - Properties
    @Published var handshakeState: HandshakeState = .idle

    // MARK: - Initiate Handshake (Initiator Flow)

    /// Initiator: Complete handshake with contact
    /// Steps: Fetch prekey bundle → Create offer → Send offer → Wait for accept → Verify accept
    func initiateHandshake(withContact contact: Contact) async throws -> String {
        handshakeState = .fetchingPrekeys

        // Step 1: Fetch contact's prekey bundle from server
        let prekeyBundleResponse = try await APIManager.shared.fetchPrekeyBundle(convroNumber: contact.convroNumber)
        let prekeyBundle = try prekeyBundleResponse.toPrekeyBundle()

        // Step 2: Create handshake offer
        handshakeState = .creatingOffer
        let result = try C6PManager.shared.createHandshakeOffer(responderBundle: prekeyBundle)

        // Step 3: Send offer to server (server forwards to contact)
        handshakeState = .sendingOffer

        // Serialize offer to bytes for sending
        let offerBytes = serializeHandshakeOffer(result.offer)
        let offerData = Data(offerBytes)

        // Send via messages endpoint with handshake type
        _ = try await APIManager.shared.sendMessage(
            toConvroNumber: contact.convroNumber,
            encryptedEnvelope: offerData
        )

        // Step 4: Wait for accept message (received via WebSocket or polling)
        handshakeState = .waitingForAccept
        print("✅ Handshake offer sent to \(contact.convroNumber)")
        print("⏳ Waiting for accept message...")
        // Note: Accept is handled by WebSocketManager → ChatViewModel

        // Step 5: Verify accept (when received)
        // This is called separately via verifyHandshakeAccept()

        // Return session ID
        let sessionId = result.offer.sessionId.toHexString()
        return sessionId
    }

    /// Serialize HandshakeOffer to bytes
    private func serializeHandshakeOffer(_ offer: C6PProtocol.HandshakeOffer) -> [UInt8] {
        // Simple serialization - concatenate all fields
        var bytes: [UInt8] = []
        bytes.append(contentsOf: offer.sessionId)
        bytes.append(contentsOf: offer.initiatorDeviceId)
        bytes.append(contentsOf: offer.responderDeviceId)
        bytes.append(contentsOf: offer.initiatorIdentityDhPub)
        bytes.append(contentsOf: offer.initiatorIdentitySigPub)
        bytes.append(contentsOf: offer.initiatorEphemeralDhPub)
        bytes.append(contentsOf: offer.kc1)
        bytes.append(contentsOf: offer.offerSignature)
        return bytes
    }

    /// Initiator: Verify accept message from responder
    func verifyHandshakeAccept(
        offer: C6PProtocol.HandshakeOffer,
        acceptBytes: [UInt8],
        sessionKeys: C6PProtocol.SessionKeys
    ) async throws {
        handshakeState = .verifying

        // Verify accept message using stored session keys
        try C6PManager.shared.verifyHandshakeAccept(
            offer: offer,
            acceptBytes: acceptBytes,
            sessionKeys: sessionKeys
        )

        handshakeState = .completed
        print("✅ Handshake completed (initiator)")
    }

    // MARK: - Respond to Handshake (Responder Flow)

    /// Responder: Accept handshake offer from initiator
    /// Steps: Accept offer → Send accept → Save session
    func respondToHandshakeOffer(offerBytes: [UInt8]) async throws -> String {
        handshakeState = .creatingOffer // Reusing state for "processing offer"

        // Step 1: Load current signed prekey and optional OTP
        let spk = try await KeychainManager.shared.loadSignedPrekey()

        // OTP is optional (4DH vs 3DH)
        // TODO: Load from database if available
        let otp: C6PProtocol.OneTimePrekey? = nil

        // Step 2: Accept handshake offer
        let result = try C6PManager.shared.acceptHandshakeOffer(
            offerBytes: offerBytes,
            responderSPK: spk,
            responderOTP: otp
        )

        // Step 3: Send accept message to server (server forwards to initiator)
        handshakeState = .sendingOffer // Reusing state for "sending accept"

        // Serialize accept to bytes for sending
        let acceptBytes = serializeHandshakeAccept(result.accept)
        let acceptData = Data(acceptBytes)

        // Extract recipient from accept (initiator's device ID)
        // Note: Server needs to route to initiator - we'll use the session binding
        // For now, send to known contact (this would come from the offer)
        // In production, server routes based on session_id
        _ = try await APIManager.shared.sendMessage(
            toConvroNumber: "", // Server routes by session_id in accept
            encryptedEnvelope: acceptData
        )

        // Mark as completed
        handshakeState = .completed
        print("✅ Handshake accept sent (responder)")
        print("   Session ID: \(result.accept.sessionId.toHexString())")

        // Return session ID
        let sessionId = result.accept.sessionId.toHexString()
        return sessionId
    }

    /// Serialize HandshakeAccept to bytes
    private func serializeHandshakeAccept(_ accept: C6PProtocol.HandshakeAccept) -> [UInt8] {
        // Simple serialization - concatenate all fields
        var bytes: [UInt8] = []
        bytes.append(contentsOf: accept.sessionId)
        bytes.append(contentsOf: accept.initiatorDeviceId)
        bytes.append(contentsOf: accept.responderDeviceId)
        bytes.append(contentsOf: accept.responderIdentityDhPub)
        bytes.append(contentsOf: accept.responderIdentitySigPub)
        bytes.append(contentsOf: accept.responderEphemeralDhPub)
        bytes.append(contentsOf: accept.kc2)
        bytes.append(contentsOf: accept.acceptSignature)
        return bytes
    }

    // MARK: - Helpers

    /// Reset handshake state
    func reset() {
        handshakeState = .idle
    }

    /// Handle handshake failure
    func handleFailure(_ error: Error) {
        handshakeState = .failed(error)
        print("❌ Handshake failed: \(error.localizedDescription)")
    }
}

// MARK: - Handshake State
enum HandshakeState: Equatable {
    case idle
    case fetchingPrekeys
    case creatingOffer
    case sendingOffer
    case waitingForAccept
    case verifying
    case completed
    case failed(Error)

    static func == (lhs: HandshakeState, rhs: HandshakeState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.fetchingPrekeys, .fetchingPrekeys),
             (.creatingOffer, .creatingOffer),
             (.sendingOffer, .sendingOffer),
             (.waitingForAccept, .waitingForAccept),
             (.verifying, .verifying),
             (.completed, .completed):
            return true
        case (.failed, .failed):
            return true
        default:
            return false
        }
    }
}

// MARK: - Errors
enum HandshakeError: LocalizedError {
    case apiNotImplemented(String)
    case prekeyBundleNotFound
    case invalidOffer
    case invalidAccept
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .apiNotImplemented(let message):
            return "API not yet implemented: \(message)"
        case .prekeyBundleNotFound:
            return "Prekey bundle not found for contact"
        case .invalidOffer:
            return "Invalid handshake offer"
        case .invalidAccept:
            return "Invalid handshake accept"
        case .verificationFailed:
            return "Handshake verification failed"
        }
    }
}
