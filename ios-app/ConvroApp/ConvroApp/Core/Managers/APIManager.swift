import Foundation

// MARK: - API Manager
/// REST API client for Convro server (18 endpoints)
@MainActor
class APIManager: ObservableObject {
    // MARK: - Singleton
    static let shared = APIManager()

    // MARK: - Properties
    private let baseURL = URL(string: "https://app.convro.eu/v1")!
    private let client: APIClient
    private var accessToken: String?
    private var refreshToken: String?

    private init() {
        self.client = APIClient(baseURL: baseURL)
        Task {
            await loadTokens()
        }
    }

    // MARK: - Authentication (4 endpoints)

    /// POST /auth/register - Register new user
    func register(
        username: String,
        password: String,
        displayName: String,
        deviceIdentity: DeviceIdentity,
        signedPrekey: SignedPrekey,
        oneTimePrekeys: [OneTimePrekey]
    ) async throws -> AuthResponse {
        let body = RegisterRequest(
            username: username,
            password: password,
            displayName: displayName,
            deviceId: deviceIdentity.deviceId.toHexString(),
            identityPubEd25519: deviceIdentity.identityPubEd25519.toHexString(),
            identityPubX25519: deviceIdentity.identityPubX25519.toHexString(),
            spkId: signedPrekey.spkId.toHexString(),
            spkPub: signedPrekey.spkPub.toHexString(),
            spkSig: signedPrekey.spkSig.toHexString(),
            oneTimePrekeys: oneTimePrekeys.map { otp in
                OneTimePrekeyData(
                    otpId: otp.otpId.toHexString(),
                    otpPub: otp.otpPub.toHexString()
                )
            }
        )

        let request = APIRequest(endpoint: .register, body: body)
        let response: AuthResponse = try await client.execute(request)

        // Save tokens
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        await saveTokens()
        client.setAuthToken(response.accessToken)

        return response
    }

    /// POST /auth/login - Login existing user
    func login(username: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(username: username, password: password)
        let request = APIRequest(endpoint: .login, body: body)
        let response: AuthResponse = try await client.execute(request)

        // Save tokens
        accessToken = response.accessToken
        refreshToken = response.refreshToken
        await saveTokens()
        client.setAuthToken(response.accessToken)

        return response
    }

    /// POST /auth/refresh - Refresh access token
    func refreshAccessToken() async throws -> TokenRefreshResponse {
        guard let refreshToken = refreshToken else {
            throw APIError.unauthorized
        }

        let body = RefreshRequest(refreshToken: refreshToken)
        let request = APIRequest(endpoint: .refresh, body: body)
        let response: TokenRefreshResponse = try await client.execute(request)

        // Update access token
        accessToken = response.accessToken
        await saveTokens()
        client.setAuthToken(response.accessToken)

        return response
    }

    /// POST /auth/logout - Logout current session
    func logout() async throws {
        if accessToken != nil {
            let request = APIRequest(endpoint: .logout)
            try? await client.executeVoid(request)
        }

        // Clear tokens
        await clearTokens()
    }

    // MARK: - User Profile (2 endpoints)

    /// GET /users/me - Get current user profile
    func getUserProfile() async throws -> User {
        let request = APIRequest(endpoint: .getUserProfile)
        let response: UserProfileResponse = try await client.execute(request)
        return response.toUser()
    }

    /// PATCH /users/me - Update user profile
    func updateUserProfile(displayName: String) async throws -> User {
        let body = UpdateUserProfileRequest(displayName: displayName)
        let request = APIRequest(endpoint: .updateUserProfile, body: body)
        let response: UserProfileResponse = try await client.execute(request)
        return response.toUser()
    }

    // MARK: - Devices (3 endpoints)

    /// POST /devices - Register device identity
    func registerDevice(
        deviceIdentity: DeviceIdentity,
        signedPrekey: SignedPrekey,
        oneTimePrekeys: [OneTimePrekey]
    ) async throws -> Device {
        let body = RegisterDeviceRequest(
            deviceId: deviceIdentity.deviceId.toHexString(),
            deviceName: "iOS Device",
            platform: "iOS",
            identityPubEd25519: deviceIdentity.identityPubEd25519.toHexString(),
            identityPubX25519: deviceIdentity.identityPubX25519.toHexString(),
            spkId: signedPrekey.spkId.toHexString(),
            spkPub: signedPrekey.spkPub.toHexString(),
            spkSig: signedPrekey.spkSig.toHexString(),
            oneTimePrekeys: oneTimePrekeys.map { otp in
                OneTimePrekeyData(
                    otpId: otp.otpId.toHexString(),
                    otpPub: otp.otpPub.toHexString()
                )
            }
        )

        let request = APIRequest(endpoint: .registerDevice, body: body)
        return try await client.execute(request)
    }

    /// GET /devices - List all devices for current user
    func listDevices() async throws -> [Device] {
        let request = APIRequest(endpoint: .listDevices)
        let response: DevicesResponse = try await client.execute(request)
        return response.devices
    }

    /// DELETE /devices/:id - Deactivate device
    func deactivateDevice(deviceId: UUID) async throws {
        let request = APIRequest(endpoint: .deactivateDevice(deviceId))
        try await client.executeVoid(request)
    }

    // MARK: - Prekeys (3 endpoints)

    /// POST /prekeys - Upload prekeys for device
    func uploadPrekeys(
        signedPrekey: SignedPrekey,
        oneTimePrekeys: [OneTimePrekey]
    ) async throws {
        let body = UploadPrekeysRequest(
            spkId: signedPrekey.spkId.toHexString(),
            spkPub: signedPrekey.spkPub.toHexString(),
            spkSig: signedPrekey.spkSig.toHexString(),
            oneTimePrekeys: oneTimePrekeys.map { otp in
                OneTimePrekeyData(
                    otpId: otp.otpId.toHexString(),
                    otpPub: otp.otpPub.toHexString()
                )
            }
        )

        let request = APIRequest(endpoint: .uploadPrekeys, body: body)
        try await client.executeVoid(request)
    }

    /// GET /prekeys/:convro_number - Fetch prekey bundle for initiating handshake
    func fetchPrekeyBundle(convroNumber: String) async throws -> PrekeyBundleResponse {
        let request = APIRequest(endpoint: .fetchPrekeyBundle(convroNumber))
        return try await client.execute(request)
    }

    /// GET /prekeys/health - Get prekey pool health status
    func getPrekeyHealth() async throws -> PrekeyHealthResponse {
        let request = APIRequest(endpoint: .prekeyHealth)
        return try await client.execute(request)
    }

    // MARK: - Messages (3 endpoints)

    /// POST /messages - Send message (sealed sender or handshake)
    /// - For handshakes: Set messageType to "handshake_offer" or "handshake_accept"
    /// - For regular messages: Leave messageType as nil (uses sealed sender format)
    func sendMessage(toConvroNumber: String, encryptedEnvelope: Data, messageType: String? = nil) async throws -> MessageResponse {
        // encryptedEnvelope is already 64KB padded + base64 encoded from MessageEncryptionService
        // OR it's the serialized handshake offer/accept from FFI (JSON wire format)
        let envelopeString = String(data: encryptedEnvelope, encoding: .utf8) ?? ""

        let body = SendMessageRequest(
            recipientConvroNumber: toConvroNumber,
            encryptedEnvelope: envelopeString,
            messageType: messageType
        )

        let request = APIRequest(endpoint: .sendMessage, body: body)
        return try await client.execute(request)
    }

    /// GET /messages/inbox - Fetch pending sealed sender messages
    func fetchInbox() async throws -> [InboxMessage] {
        let request = APIRequest(endpoint: .fetchInbox)
        let response: InboxResponse = try await client.execute(request)
        return response.messages
    }

    /// POST /messages/:id/delivered - Mark message as delivered
    func markAsDelivered(messageId: UUID) async throws {
        let request = APIRequest(endpoint: .markDelivered(messageId))
        try await client.executeVoid(request)
    }

    // MARK: - Conversations (1 endpoint)

    /// GET /conversations - List all conversations for current user
    func fetchConversations() async throws -> [ConversationResponse] {
        let request = APIRequest(endpoint: .listConversations)
        let response: ConversationsResponse = try await client.execute(request)
        return response.conversations
    }

    // MARK: - Contacts (4 endpoints)

    /// POST /contacts - Add new contact
    func addContact(convroNumber: String, displayName: String?) async throws -> ContactResponse {
        let body = AddContactRequest(
            convroNumber: convroNumber,
            displayName: displayName
        )

        let request = APIRequest(endpoint: .addContact, body: body)
        return try await client.execute(request)
    }

    /// GET /contacts - List all contacts
    func listContacts() async throws -> [ContactResponse] {
        let request = APIRequest(endpoint: .listContacts)
        let response: ContactsResponse = try await client.execute(request)
        return response.contacts
    }

    /// POST /contacts/:id/verify - Verify contact's fingerprint
    func verifyContact(contactId: UUID, verified: Bool) async throws {
        let body = VerifyContactRequest(verified: verified)
        let request = APIRequest(endpoint: .verifyContact(contactId), body: body)
        try await client.executeVoid(request)
    }

    /// DELETE /contacts/:id - Delete contact
    func deleteContact(contactId: UUID) async throws {
        let request = APIRequest(endpoint: .deleteContact(contactId))
        try await client.executeVoid(request)
    }

    // MARK: - Presence (2 endpoints)

    /// POST /presence - Update user's presence status
    func updatePresence(status: String, wsConnectionId: String?) async throws -> PresenceResponse {
        let body = UpdatePresenceRequest(
            status: status,
            wsConnectionId: wsConnectionId
        )

        let request = APIRequest(endpoint: .updatePresence, body: body)
        return try await client.execute(request)
    }

    /// GET /presence?convro_numbers={numbers} - Get presence for contacts
    func getContactPresence(convroNumbers: [String]) async throws -> ContactPresenceResponse {
        let numbersParam = convroNumbers.joined(separator: ",")
        let queryItems = [URLQueryItem(name: "convro_numbers", value: numbersParam)]

        let request = APIRequest(endpoint: .getContactPresence, queryItems: queryItems)
        return try await client.execute(request)
    }

    // MARK: - Push Notifications (2 endpoints)

    /// POST /push/register - Register APNs device token
    func registerPushToken(deviceToken: String) async throws {
        let body = RegisterPushTokenRequest(
            deviceToken: deviceToken,
            platform: "ios"
        )

        let request = APIRequest(endpoint: .registerPushToken, body: body)
        try await client.executeVoid(request)
    }

    /// POST /push/unregister - Unregister APNs device token
    func unregisterPushToken(deviceToken: String) async throws {
        let body = UnregisterPushTokenRequest(
            deviceToken: deviceToken
        )

        let request = APIRequest(endpoint: .unregisterPushToken, body: body)
        try await client.executeVoid(request)
    }

    // MARK: - Token Management

    private func loadTokens() async {
        do {
            self.accessToken = try KeychainManager.shared.retrieveString(forKey: "access_token")
            self.refreshToken = try KeychainManager.shared.retrieveString(forKey: "refresh_token")

            if let token = accessToken {
                client.setAuthToken(token)
            }
        } catch {
            // No tokens found, user needs to login
            self.accessToken = nil
            self.refreshToken = nil
        }
    }

    private func saveTokens() async {
        if let accessToken = accessToken {
            try? KeychainManager.shared.saveString(accessToken, forKey: "access_token")
        }
        if let refreshToken = refreshToken {
            try? KeychainManager.shared.saveString(refreshToken, forKey: "refresh_token")
        }
    }

    private func clearTokens() async {
        accessToken = nil
        refreshToken = nil
        client.clearAuthToken()

        try? KeychainManager.shared.delete(forKey: "access_token")
        try? KeychainManager.shared.delete(forKey: "refresh_token")
    }
}

// MARK: - Request Models

private struct RegisterRequest: Encodable {
    let username: String
    let password: String
    let displayName: String
    let deviceId: String
    let identityPubEd25519: String
    let identityPubX25519: String
    let spkId: String
    let spkPub: String
    let spkSig: String
    let oneTimePrekeys: [OneTimePrekeyData]
}

private struct LoginRequest: Encodable {
    let username: String
    let password: String
}

private struct RefreshRequest: Encodable {
    let refreshToken: String
}

private struct UpdateUserProfileRequest: Encodable {
    let displayName: String
}

private struct RegisterDeviceRequest: Encodable {
    let deviceId: String
    let deviceName: String
    let platform: String
    let identityPubEd25519: String
    let identityPubX25519: String
    let spkId: String
    let spkPub: String
    let spkSig: String
    let oneTimePrekeys: [OneTimePrekeyData]
}

private struct UploadPrekeysRequest: Encodable {
    let spkId: String
    let spkPub: String
    let spkSig: String
    let oneTimePrekeys: [OneTimePrekeyData]
}

private struct OneTimePrekeyData: Codable {
    let otpId: String
    let otpPub: String
}

private struct SendMessageRequest: Encodable {
    let recipientConvroNumber: String
    let encryptedEnvelope: String?
    let messageType: String?
    let encryptedBlob: String?

    enum CodingKeys: String, CodingKey {
        case recipientConvroNumber = "to_convro_number"
        case encryptedEnvelope = "encrypted_envelope"
        case messageType = "message_type"
        case encryptedBlob = "encrypted_blob"
    }

    init(recipientConvroNumber: String, encryptedEnvelope: String, messageType: String?) {
        self.recipientConvroNumber = recipientConvroNumber

        // If message_type is present (handshake), use encrypted_blob field
        // Otherwise (regular message), use encrypted_envelope field
        if let messageType = messageType {
            self.messageType = messageType
            self.encryptedBlob = encryptedEnvelope
            self.encryptedEnvelope = nil
        } else {
            self.messageType = nil
            self.encryptedBlob = nil
            self.encryptedEnvelope = encryptedEnvelope
        }
    }
}

private struct AddContactRequest: Encodable {
    let convroNumber: String
    let displayName: String?
}

private struct VerifyContactRequest: Encodable {
    let verified: Bool
}

private struct UpdatePresenceRequest: Encodable {
    let status: String
    let wsConnectionId: String?
}

private struct RegisterPushTokenRequest: Encodable {
    let deviceToken: String
    let platform: String
}

private struct UnregisterPushTokenRequest: Encodable {
    let deviceToken: String
}

// MARK: - Response Models

struct AuthResponse: Codable {
    let user: UserData
    let accessToken: String
    let refreshToken: String
    let convroNumber: String
}

struct UserData: Codable {
    let id: UUID
    let username: String
    let displayName: String
    let convroNumber: String
    let createdAt: Date
}

struct TokenRefreshResponse: Codable {
    let accessToken: String
}

struct UserProfileResponse: Codable {
    let userId: UUID
    let username: String
    let convroNumber: String
    let displayName: String
    let createdAt: Date
    let lastLogin: Date?

    func toUser() -> User {
        return User(
            id: userId,
            username: username,
            convroNumber: convroNumber,
            displayName: displayName,
            createdAt: createdAt,
            lastLogin: lastLogin
        )
    }
}

struct DevicesResponse: Codable {
    let devices: [Device]
}

struct PrekeyBundleResponse: Codable {
    let responderDeviceId: String
    let identityPubEd25519: String
    let identityPubX25519: String
    let spkId: String
    let spkPub: String
    let spkSig: String
    let otpId: String?
    let otpPub: String?

    /// Convert to C6P PrekeyBundle for handshake
    func toPrekeyBundle() throws -> PrekeyBundle {
        guard let deviceIdBytes = Data(hexString: responderDeviceId),
              let identityEd25519Bytes = Data(hexString: identityPubEd25519),
              let identityX25519Bytes = Data(hexString: identityPubX25519),
              let spkIdBytes = Data(hexString: spkId),
              let spkPubBytes = Data(hexString: spkPub),
              let spkSigBytes = Data(hexString: spkSig) else {
            struct HexDecodingError: Error {}
            throw HexDecodingError()
        }

        var otpIdBytes: [UInt8]? = nil
        var otpPubBytes: [UInt8]? = nil

        if let otpIdHex = otpId, let otpPubHex = otpPub {
            otpIdBytes = Data(hexString: otpIdHex).map { Array($0) }
            otpPubBytes = Data(hexString: otpPubHex).map { Array($0) }
        }

        return PrekeyBundle(
            responderDeviceId: Array(deviceIdBytes),
            identityPubEd25519: Array(identityEd25519Bytes),
            identityPubX25519: Array(identityX25519Bytes),
            spkId: Array(spkIdBytes),
            spkPub: Array(spkPubBytes),
            spkSig: Array(spkSigBytes),
            otpId: otpIdBytes,
            otpPub: otpPubBytes
        )
    }
}

struct PrekeyHealthResponse: Codable {
    let devices: [DevicePrekeyHealth]
}

struct DevicePrekeyHealth: Codable {
    let deviceId: String
    let oneTimePrekeyCount: Int
    let status: String
}

struct MessageResponse: Codable {
    let messageId: UUID
    let createdAt: Date
}

struct InboxResponse: Codable {
    let messages: [InboxMessage]
}

struct InboxMessage: Codable {
    let messageId: UUID
    let encryptedEnvelope: String
    let createdAt: Date
}

struct ConversationsResponse: Codable {
    let conversations: [ConversationResponse]
}

struct ConversationResponse: Codable {
    let conversationId: UUID
    let participantConvroNumber: String
    let participantDisplayName: String?
    let lastMessageAt: Date?
    let unreadCount: Int
}

struct ContactsResponse: Codable {
    let contacts: [ContactResponse]
}

struct ContactResponse: Codable {
    let contactId: UUID
    let convroNumber: String
    let displayName: String?
    let identityPubEd25519: String
    let fingerprint: String
    let verified: Bool
    let createdAt: Date
}

struct PresenceResponse: Codable {
    let userId: UUID
    let status: String
    let updatedAt: Date
}

struct ContactPresenceResponse: Codable {
    let presence: [ContactPresenceInfo]
}

struct ContactPresenceInfo: Codable {
    let convroNumber: String
    let status: String
    let lastSeen: Date
}
