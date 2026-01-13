import Foundation

// MARK: - API Response Wrapper
struct APIResponse<T: Codable>: Codable {
    let data: T
    let status: Int
    let message: String?
}

// MARK: - Error Response
struct APIErrorResponse: Codable {
    let error: ErrorDetail
}

struct ErrorDetail: Codable {
    let code: String
    let message: String
    let details: [String: String]?
    let timestamp: Date
    let requestId: String?

    enum CodingKeys: String, CodingKey {
        case code, message, details, timestamp
        case requestId = "request_id"
    }
}
