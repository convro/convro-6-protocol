import Foundation

// MARK: - API Client
class APIClient {
    // MARK: - Properties
    private let baseURL: URL
    private let session: URLSession
    private var authToken: String?

    // MARK: - Initialization
    init(baseURL: URL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    // MARK: - Authentication

    /// Set JWT token for authenticated requests
    func setAuthToken(_ token: String) {
        self.authToken = token
    }

    /// Clear authentication token (logout)
    func clearAuthToken() {
        self.authToken = nil
    }

    // MARK: - Request Execution

    /// Execute API request and decode response
    func execute<T: Decodable>(_ request: APIRequest) async throws -> T {
        let urlRequest = try buildURLRequest(from: request)

        #if DEBUG
        print("📡 API Request: \(request.method.rawValue) \(request.path)")
        #endif

        let (data, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        #if DEBUG
        print("📡 API Response: \(httpResponse.statusCode) for \(request.path)")
        #endif

        // Handle error responses
        guard (200...299).contains(httpResponse.statusCode) else {
            // Try to decode error response
            if let errorResponse = try? JSONDecoder().decode(APIErrorResponse.self, from: data) {
                throw APIError.serverError(
                    statusCode: httpResponse.statusCode,
                    message: errorResponse.message
                )
            }

            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }

        // Decode success response
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("❌ Decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("Response data: \(jsonString)")
            }
            #endif
            throw APIError.decodingError(error)
        }
    }

    /// Execute API request without response body (for DELETE, etc.)
    func executeVoid(_ request: APIRequest) async throws {
        let urlRequest = try buildURLRequest(from: request)

        #if DEBUG
        print("📡 API Request: \(request.method.rawValue) \(request.path)")
        #endif

        let (_, response) = try await session.data(for: urlRequest)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode)
        }
    }

    // MARK: - Request Building

    private func buildURLRequest(from request: APIRequest) throws -> URLRequest {
        // Build URL with query parameters if needed
        var components = URLComponents(url: baseURL.appendingPathComponent(request.path), resolvingAgainstBaseURL: true)!

        if let queryItems = request.queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        // Add auth token if available
        if let token = authToken {
            urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add custom headers
        request.headers.forEach { key, value in
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }

        // Add body
        if let body = request.body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            urlRequest.httpBody = try encoder.encode(body)
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return urlRequest
    }
}

// MARK: - API Error
enum APIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int)
    case serverError(statusCode: Int, message: String)
    case networkError(Error)
    case decodingError(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Decoding error: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - please login"
        }
    }
}

// MARK: - API Error Response
struct APIErrorResponse: Codable {
    let message: String
    let code: String?
}
