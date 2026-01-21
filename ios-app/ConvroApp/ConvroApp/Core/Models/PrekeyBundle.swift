import Foundation

// MARK: - Prekey Bundle
struct PrekeyBundle: Codable {
    let userId: UUID
    let convroNumber: String
    let deviceIdentityId: UUID
    let deviceId: Data
    let identityKey: Data
    let signedPrekey: SignedPrekey
    let oneTimePrekey: OneTimePrekey?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case convroNumber = "convro_number"
        case deviceIdentityId = "device_identity_id"
        case deviceId = "device_id"
        case identityKey = "identity_key"
        case signedPrekey = "signed_prekey"
        case oneTimePrekey = "one_time_prekey"
    }
}

// MARK: - Signed Prekey
struct SignedPrekey: Codable {
    let spkId: Int
    let publicKey: Data
    let signature: Data

    enum CodingKeys: String, CodingKey {
        case spkId = "spk_id"
        case publicKey = "public_key"
        case signature
    }
}

// MARK: - One-Time Prekey
struct OneTimePrekey: Codable {
    let otpId: UUID
    let publicKey: Data

    enum CodingKeys: String, CodingKey {
        case otpId = "otp_id"
        case publicKey = "public_key"
    }
}
