import Foundation

// MARK: - Prekey Bundle (API Response)
// Note: Renamed to avoid conflict with UniFFI-generated PrekeyBundle
// This is the API/server response format, UniFFI types contain crypto internals
struct ApiPrekeyBundle: Codable {
    let userId: UUID
    let convroNumber: String
    let deviceIdentityId: UUID
    let deviceId: Data
    let identityKey: Data
    let signedPrekey: ApiSignedPrekey
    let oneTimePrekey: ApiOneTimePrekey?

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

// MARK: - Signed Prekey (API Response)
// Note: Renamed to avoid conflict with UniFFI-generated SignedPrekey
// This is public key only (API), UniFFI type contains private key too
struct ApiSignedPrekey: Codable {
    let spkId: Int
    let publicKey: Data
    let signature: Data

    enum CodingKeys: String, CodingKey {
        case spkId = "spk_id"
        case publicKey = "public_key"
        case signature
    }
}

// MARK: - One-Time Prekey (API Response)
// Note: Renamed to avoid conflict with UniFFI-generated OneTimePrekey
// This is public key only (API), UniFFI type contains private key too
struct ApiOneTimePrekey: Codable {
    let otpId: UUID
    let publicKey: Data

    enum CodingKeys: String, CodingKey {
        case otpId = "otp_id"
        case publicKey = "public_key"
    }
}
