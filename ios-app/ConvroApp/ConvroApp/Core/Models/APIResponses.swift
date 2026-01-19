import Foundation

// MARK: - API Response Types
// These types represent server responses from the Convro API

// MARK: - Authentication & User
struct LoginResponse: Codable {
    let accessToken: String
    let refreshToken: String
    let userId: UUID
    let convroNumber: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case userId = "user_id"
        case convroNumber = "convro_number"
    }
}

struct RefreshResponse: Codable {
    let accessToken: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
    }
}

struct UserProfileResponse: Codable {
    let userId: UUID
    let convroNumber: String
    let displayName: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case convroNumber = "convro_number"
        case displayName = "display_name"
        case createdAt = "created_at"
    }
}

// MARK: - Devices & Prekeys
struct DeviceResponse: Codable {
    let deviceIdentityId: UUID
    let deviceId: String
    let deviceName: String
    let platform: String
    let registeredAt: Date
    let lastSeen: Date
    let isActive: Bool

    enum CodingKeys: String, CodingKey {
        case deviceIdentityId = "device_identity_id"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform
        case registeredAt = "registered_at"
        case lastSeen = "last_seen"
        case isActive = "is_active"
    }
}

struct PrekeyBundleResponse: Codable {
    let userId: UUID
    let convroNumber: String
    let deviceIdentityId: UUID
    let deviceId: String
    let identityPubEd25519: String
    let identityPubX25519: String
    let spkId: Int
    let spkPub: String
    let spkSig: String
    let otpId: String?
    let otpPub: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case convroNumber = "convro_number"
        case deviceIdentityId = "device_identity_id"
        case deviceId = "device_id"
        case identityPubEd25519 = "identity_pub_ed25519"
        case identityPubX25519 = "identity_pub_x25519"
        case spkId = "spk_id"
        case spkPub = "spk_pub"
        case spkSig = "spk_sig"
        case otpId = "otp_id"
        case otpPub = "otp_pub"
    }

    /// Convert API response to UniFFI PrekeyBundle for cryptographic operations
    func toPrekeyBundle() throws -> PrekeyBundle {
        // Decode hex strings to bytes
        guard let deviceIdBytes = Data(hexString: deviceId),
              let identityEd25519Bytes = Data(hexString: identityPubEd25519),
              let identityX25519Bytes = Data(hexString: identityPubX25519),
              let spkIdBytes = withUnsafeBytes(of: spkId.bigEndian, Array.init),
              let spkPubBytes = Data(hexString: spkPub),
              let spkSigBytes = Data(hexString: spkSig) else {
            throw APIError.invalidData
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
            spkId: spkIdBytes,
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

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case oneTimePrekeyCount = "one_time_prekey_count"
        case status
    }
}

// MARK: - Messages
struct MessageResponse: Codable {
    let messageId: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case createdAt = "created_at"
    }
}

struct InboxResponse: Codable {
    let messages: [InboxMessage]
}

struct InboxMessage: Codable {
    let messageId: UUID
    let encryptedEnvelope: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case encryptedEnvelope = "encrypted_envelope"
        case createdAt = "created_at"
    }
}

// MARK: - Conversations
struct ConversationsResponse: Codable {
    let conversations: [ConversationResponse]
}

struct ConversationResponse: Codable {
    let conversationId: UUID
    let participantConvroNumber: String
    let participantDisplayName: String?
    let lastMessageAt: Date?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case participantConvroNumber = "participant_convro_number"
        case participantDisplayName = "participant_display_name"
        case lastMessageAt = "last_message_at"
        case unreadCount = "unread_count"
    }
}

// MARK: - Contacts
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

    enum CodingKeys: String, CodingKey {
        case contactId = "contact_id"
        case convroNumber = "convro_number"
        case displayName = "display_name"
        case identityPubEd25519 = "identity_pub_ed25519"
        case fingerprint
        case verified
        case createdAt = "created_at"
    }
}

// MARK: - Presence
struct PresenceResponse: Codable {
    let userId: UUID
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case status
        case updatedAt = "updated_at"
    }
}

struct ContactPresenceResponse: Codable {
    let presence: [ContactPresenceInfo]
}

struct ContactPresenceInfo: Codable {
    let convroNumber: String
    let status: String
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case convroNumber = "convro_number"
        case status
        case updatedAt = "updated_at"
    }
}

// MARK: - API Error
enum APIError: Error {
    case invalidData
    case networkError
    case unauthorized
    case serverError(String)
}

