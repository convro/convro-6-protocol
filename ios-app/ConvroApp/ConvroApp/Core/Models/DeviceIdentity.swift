import Foundation

// MARK: - Device Identity
struct DeviceIdentity: Codable {
    let deviceId: Data
    let identityKey: Data
    let deviceName: String
    let platform: String
    let osVersion: String
    let appVersion: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case identityKey = "identity_key"
        case deviceName = "device_name"
        case platform = "device_platform"
        case osVersion = "device_os_version"
        case appVersion = "app_version"
    }
}

// MARK: - Device (Server response)
struct Device: Identifiable, Codable {
    let id: UUID
    let deviceId: Data
    let deviceName: String
    let platform: String
    let registeredAt: Date
    var lastSeen: Date
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id = "device_identity_id"
        case deviceId = "device_id"
        case deviceName = "device_name"
        case platform = "device_platform"
        case registeredAt = "registered_at"
        case lastSeen = "last_seen"
        case isActive = "is_active"
    }
}
