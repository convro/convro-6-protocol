import Foundation

// MARK: - API Response Types
// Additional response types not defined in APIManager.swift

// MARK: - Authentication (additional types)
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

// MARK: - Devices (additional types)
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
