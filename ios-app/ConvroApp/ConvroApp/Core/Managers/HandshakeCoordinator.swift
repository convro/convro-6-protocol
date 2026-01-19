import Foundation

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

        // Use the serialized offer from FFI (already in JSON wire format)
        let offerData = Data(result.offer.serialized)

        // Send via messages endpoint with handshake_offer type
        _ = try await APIManager.shared.sendMessage(
            toConvroNumber: contact.convroNumber,
            encryptedEnvelope: offerData,
            messageType: "handshake_offer"
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

    /// Initiator: Verify accept message from responder
    func verifyHandshakeAccept(
        offer: HandshakeOffer,
        acceptBytes: [UInt8],
        sessionKeys: SessionKeys
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

        // Step 1: Parse offer to extract used_otp_id
        let offerData = Data(offerBytes)
        let offer = try JSONDecoder().decode(OfferWireFormat.self, from: offerData)

        // Step 2: Load current signed prekey
        let spk = try await KeychainManager.shared.loadSignedPrekey()

        // Step 3: Load OTP if one was used (4DH vs 3DH)
        var otp: OneTimePrekey? = nil
        if let usedOtpIdHex = offer.usedOneTimePrekeyId {
            // Convert hex to bytes
            let otpIdBytes = try C6PManager.shared.hexToBytes(usedOtpIdHex)

            // Load OTP from Keychain
            otp = try await KeychainManager.shared.loadOneTimePrekey(otpId: otpIdBytes)

            if otp == nil {
                print("⚠️ OTP \(usedOtpIdHex) not found in Keychain - falling back to 3DH")
            }
        }

        // Step 4: Accept handshake offer
        let result = try C6PManager.shared.acceptHandshakeOffer(
            offerBytes: offerBytes,
            responderSPK: spk,
            responderOTP: otp
        )

        // Step 5: Delete OTP from Keychain (one-time use!)
        if let usedOtpIdHex = offer.usedOneTimePrekeyId, otp != nil {
            let otpIdBytes = try C6PManager.shared.hexToBytes(usedOtpIdHex)
            try await KeychainManager.shared.deleteOneTimePrekey(otpId: otpIdBytes)
            print("✅ OTP \(usedOtpIdHex) consumed and deleted from Keychain")
        }

        // Step 3: Send accept message to server (server forwards to initiator)
        handshakeState = .sendingOffer // Reusing state for "sending accept"

        // Use the serialized accept from FFI (already in JSON wire format)
        let acceptData = Data(result.accept.serialized)

        // Extract recipient from accept (initiator's device ID)
        // Note: Server needs to route to initiator - we'll use the session binding
        // For now, send to known contact (this would come from the offer)
        // In production, server routes based on session_id
        _ = try await APIManager.shared.sendMessage(
            toConvroNumber: "", // Server routes by session_id in accept
            encryptedEnvelope: acceptData,
            messageType: "handshake_accept"
        )

        // Mark as completed
        handshakeState = .completed
        print("✅ Handshake accept sent (responder)")
        print("   Session ID: \(result.accept.sessionId.toHexString())")

        // Return session ID
        let sessionId = result.accept.sessionId.toHexString()
        return sessionId
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

// MARK: - Wire Format (for parsing offer)

/// Minimal wire format for parsing handshake offer
/// Only decodes fields we need (used_one_time_prekey_id)
private struct OfferWireFormat: Decodable {
    let usedOneTimePrekeyId: String?

    enum CodingKeys: String, CodingKey {
        case usedOneTimePrekeyId = "usedOneTimePrekeyId"
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
