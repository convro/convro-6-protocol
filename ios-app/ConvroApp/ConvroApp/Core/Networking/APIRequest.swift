import Foundation

// MARK: - API Request
struct APIRequest {
    let endpoint: APIEndpoint
    let headers: [String: String]
    let body: Encodable?
    let queryItems: [URLQueryItem]?

    var path: String { endpoint.path }
    var method: HTTPMethod { endpoint.method }

    init(
        endpoint: APIEndpoint,
        headers: [String: String] = [:],
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil
    ) {
        self.endpoint = endpoint
        self.headers = headers
        self.body = body
        self.queryItems = queryItems
    }
}

// MARK: - HTTP Method
enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}
