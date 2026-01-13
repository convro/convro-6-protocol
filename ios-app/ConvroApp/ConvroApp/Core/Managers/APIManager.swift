import Foundation

// MARK: - API Manager
/// REST API client for Convro server
@MainActor
class APIManager: ObservableObject {
    // MARK: - Singleton
    static let shared = APIManager()

    // MARK: - Properties
    private let baseURL = "https://api.convro.app/v1"
    private var accessToken: String?
    private var refreshToken: String?

    private init() {
        loadTokens()
    }

    // MARK: - Authentication
    func register(username: String, password: String, displayName: String) async throws -> User {
        // TODO: POST /auth/register
        fatalError("Not implemented")
    }

    func login(username: String, password: String) async throws -> User {
        // TODO: POST /auth/login
        fatalError("Not implemented")
    }

    func logout() async throws {
        // TODO: POST /auth/logout
        clearTokens()
    }

    func refreshAccessToken() async throws {
        // TODO: POST /auth/refresh
        fatalError("Not implemented")
    }

    // MARK: - Devices
    func registerDevice(_ identity: DeviceIdentity) async throws {
        // TODO: POST /devices
        fatalError("Not implemented")
    }

    func listDevices() async throws -> [Device] {
        // TODO: GET /devices
        fatalError("Not implemented")
    }

    // MARK: - Prekeys
    func uploadPrekeys(_ bundle: PrekeyBundle) async throws {
        // TODO: POST /prekeys
        fatalError("Not implemented")
    }

    func fetchPrekeyBundle(convroNumber: String) async throws -> PrekeyBundle {
        // TODO: GET /prekeys/:convro_number
        fatalError("Not implemented")
    }

    // MARK: - Messages
    func sendMessage(toConvroNumber: String, encryptedEnvelope: Data) async throws -> Message {
        // TODO: POST /messages
        fatalError("Not implemented")
    }

    func fetchInbox() async throws -> [Message] {
        // TODO: GET /messages/inbox
        fatalError("Not implemented")
    }

    func markAsDelivered(messageId: String) async throws {
        // TODO: POST /messages/:id/delivered
        fatalError("Not implemented")
    }

    // MARK: - Conversations
    func fetchConversations() async throws -> [Conversation] {
        // TODO: GET /conversations
        fatalError("Not implemented")
    }

    // MARK: - Contacts
    func addContact(convroNumber: String, displayName: String) async throws -> Contact {
        // TODO: POST /contacts
        fatalError("Not implemented")
    }

    func listContacts() async throws -> [Contact] {
        // TODO: GET /contacts
        fatalError("Not implemented")
    }

    // MARK: - Token Management
    private func loadTokens() {
        // TODO: Load from Keychain
    }

    private func saveTokens() {
        // TODO: Save to Keychain
    }

    private func clearTokens() {
        accessToken = nil
        refreshToken = nil
        // TODO: Delete from Keychain
    }
}
