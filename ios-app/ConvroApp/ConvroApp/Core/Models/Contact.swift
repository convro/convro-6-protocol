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

    // C6P identity key (for fingerprint generation)
    let identityPubEd25519: Data?

    enum CodingKeys: String, CodingKey {
        case id = "contact_id"
        case convroNumber = "convro_number"
        case displayName = "display_name"
        case userId = "contact_user_id"
        case isVerified = "is_verified"
        case addedAt = "added_at"
        case verifiedAt = "verified_at"
        case identityPubEd25519 = "identity_pub_ed25519"
    }
}

// MARK: - Contact with Fingerprint
extension Contact {
    var fingerprint: String {
        // Generate fingerprint from Ed25519 public key
        guard let identityKey = identityPubEd25519 else {
            return "NO_IDENTITY_KEY"
        }

        do {
            let ed25519Bytes = Array(identityKey)
            let fingerprint = try C6PManager.shared.computeFingerprint(ed25519Pub: ed25519Bytes)
            return fingerprint // Base32 format (32 chars)
        } catch {
            print("❌ Failed to compute fingerprint: \(error)")
            return "FINGERPRINT_ERROR"
        }
    }
}
