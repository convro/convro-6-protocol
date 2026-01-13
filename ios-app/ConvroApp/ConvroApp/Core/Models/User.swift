import Foundation

// MARK: - User
struct User: Identifiable, Codable {
    let id: UUID
    let username: String
    let convroNumber: String
    let displayName: String
    let createdAt: Date
    var lastLogin: Date?

    enum CodingKeys: String, CodingKey {
        case id = "user_id"
        case username
        case convroNumber = "convro_number"
        case displayName = "display_name"
        case createdAt = "created_at"
        case lastLogin = "last_login"
    }
}

// MARK: - JWT Tokens
struct AuthTokens: Codable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

// MARK: - Auth Response
struct AuthResponse: Codable {
    let user: User
    let tokens: AuthTokens
}
