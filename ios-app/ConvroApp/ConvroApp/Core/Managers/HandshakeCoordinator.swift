import Foundation

// MARK: - Handshake Coordinator
/// Orchestrates handshake flow between two users
@MainActor
class HandshakeCoordinator: ObservableObject {
    // MARK: - Properties
    @Published var handshakeState: HandshakeState = .idle

    // MARK: - Initiate Handshake
    func initiateHandshake(withContact contact: Contact) async throws {
        // TODO: Fetch contact's prekey bundle
        // TODO: Create handshake offer
        // TODO: Send offer via API
        // TODO: Wait for accept
        // TODO: Verify accept
        // TODO: Save session
        fatalError("Not implemented")
    }

    // MARK: - Respond to Handshake
    func respondToHandshakeOffer(_ offer: HandshakeOffer) async throws {
        // TODO: Accept offer
        // TODO: Send accept via API
        // TODO: Save session
        fatalError("Not implemented")
    }
}

// MARK: - Handshake State
enum HandshakeState {
    case idle
    case fetchingPrekeys
    case creatingOffer
    case sendingOffer
    case waitingForAccept
    case verifying
    case completed
    case failed(Error)
}
