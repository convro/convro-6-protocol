import Foundation

// MARK: - Contact
struct Contact: Identifiable, Codable {
    let id: UUID
    let convroNumber: String
    let displayName: String
    let userId: UUID
    var isVerified: Bool
    let addedAt: Date
    var verifiedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "contact_id"
        case convroNumber = "convro_number"
        case displayName = "display_name"
        case userId = "contact_user_id"
        case isVerified = "is_verified"
        case addedAt = "added_at"
        case verifiedAt = "verified_at"
    }
}

// MARK: - Contact with Fingerprint
extension Contact {
    var fingerprint: String {
        // TODO: Generate fingerprint from identity key
        return "FINGERPRINT_PLACEHOLDER"
    }
}
