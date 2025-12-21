//
//  C6PPrekeyHTTPClient.swift
//  C6P-Protocol
//
//  Production HTTP client for C6P Prekeys API (handshake99).
//
//  Implements C6PPrekeyAPIClient using canonical contracts from:
//   - C6PPrekeyContracts.swift (base64url no padding, strict VN)
//
//  Endpoints (expected):
//   - POST /v1/prekeys/upload
//   - GET  /v1/prekeys/bundle?device_id=<hex>
//   - POST /v1/prekeys/consume
//
//  NOTE:
//  If your Node routes use different param names, adjust `fetchPrekeyBundle` query keys.
//

import Foundation

// MARK: - Errors

public enum C6PPrekeyHTTPClientError: Error, CustomStringConvertible {
    case invalidBaseURL
    case missingAccessToken
    case serverError(status: Int, code: String, message: String)
    case unexpectedResponse(status: Int, body: String?)
    case decodingFailed(underlying: Error)
    case encodingFailed(underlying: Error)
    case networkFailed(underlying: Error)

    public var description: String {
        switch self {
        case .invalidBaseURL:
            return "C6PPrekeyHTTPClientError.invalidBaseURL"
        case .missingAccessToken:
            return "C6PPrekeyHTTPClientError.missingAccessToken"
        case .serverError(let status, let code, let message):
            return "C6PPrekeyHTTPClientError.serverError(status=\(status), code=\(code), message=\(message))"
        case .unexpectedResponse(let status, let body):
            return "C6PPrekeyHTTPClientError.unexpectedResponse(status=\(status), body=\(body ?? "nil"))"
        case .decodingFailed(let underlying):
            return "C6PPrekeyHTTPClientError.decodingFailed(\(underlying))"
        case .encodingFailed(let underlying):
            return "C6PPrekeyHTTPClientError.encodingFailed(\(underlying))"
        case .networkFailed(let underlying):
            return "C6PPrekeyHTTPClientError.networkFailed(\(underlying))"
        }
    }
}

// MARK: - Config

public struct C6PPrekeyHTTPClientConfig: Sendable {
    /// Example: https://tunnel.convro.eu
    public let baseURL: URL

    /// Request timeout (seconds).
    public let timeout: TimeInterval

    /// Extra headers if you want (e.g. User-Agent).
    public let defaultHeaders: [String: String]

    public init(
        baseURL: URL,
        timeout: TimeInterval = 12,
        defaultHeaders: [String: String] = [
            "Accept": "application/json"
        ]
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
    }
}

// MARK: - Access Token Provider

/// Must return a valid JWT access token (same one used by your REST + WS).
public typealias C6PAccessTokenProvider = () -> String?

// MARK: - Client

public final class C6PPrekeyHTTPClient: C6PPrekeyAPIClient {

    private let config: C6PPrekeyHTTPClientConfig
    private let urlSession: URLSession
    private let accessTokenProvider: C6PAccessTokenProvider

    // JSON
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        config: C6PPrekeyHTTPClientConfig,
        accessTokenProvider: @escaping C6PAccessTokenProvider,
        urlSession: URLSession? = nil
    ) {
        self.config = config
        self.accessTokenProvider = accessTokenProvider

        // URLSession
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let sessionConfig = URLSessionConfiguration.ephemeral
            sessionConfig.timeoutIntervalForRequest = config.timeout
            sessionConfig.timeoutIntervalForResource = config.timeout
            sessionConfig.waitsForConnectivity = true
            self.urlSession = URLSession(configuration: sessionConfig)
        }

        // JSON encoder/decoder
        let enc = JSONEncoder()
        enc.outputFormatting = [] // keep minimal
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - C6PPrekeyAPIClient

    /// POST /v1/prekeys/upload
    public func publishPrekeys(_ request: C6PPublishPrekeysRequest) async throws -> C6PPublishPrekeysResponse {
        let data: Data
        do {
            data = try encoder.encode(request)
        } catch {
            throw C6PPrekeyHTTPClientError.encodingFailed(underlying: error)
        }

        var req = try makeRequest(method: "POST", path: "/v1/prekeys/upload", queryItems: nil)
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (status, responseData) = try await perform(req)

        guard status == 200 else {
            throw try parseServerError(status: status, data: responseData)
        }

        do {
            return try decoder.decode(C6PPublishPrekeysResponse.self, from: responseData)
        } catch {
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    /// GET /v1/prekeys/bundle?device_id=<hex>
    public func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) async throws -> C6PPrekeyBundleContract {
        let query: [URLQueryItem] = [
            .init(name: "device_id", value: remoteDeviceId.hexString)
        ]

        let req = try makeRequest(method: "GET", path: "/v1/prekeys/bundle", queryItems: query)
        let (status, responseData) = try await perform(req)

        guard status == 200 else {
            throw try parseServerError(status: status, data: responseData)
        }

        do {
            let bundle = try decoder.decode(C6PPrekeyBundleContract.self, from: responseData)
            try bundle.validate()
            return bundle
        } catch {
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    /// POST /v1/prekeys/consume
    public func markOneTimePrekeyConsumed(responderDeviceId: C6PDeviceId, oneTimePrekeyId: C6PKeyId) async throws {
        let reqBody: C6PConsumeOneTimePrekeyRequest
        do {
            reqBody = try C6PConsumeOneTimePrekeyRequest(
                c6pVersion: C6P_VERSION,
                responderDeviceId: responderDeviceId,
                oneTimePrekeyId: oneTimePrekeyId
            )
        } catch {
            throw C6PPrekeyHTTPClientError.encodingFailed(underlying: error)
        }

        let data: Data
        do {
            data = try encoder.encode(reqBody)
        } catch {
            throw C6PPrekeyHTTPClientError.encodingFailed(underlying: error)
        }

        var req = try makeRequest(method: "POST", path: "/v1/prekeys/consume", queryItems: nil)
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (status, responseData) = try await perform(req)

        guard status == 200 else {
            throw try parseServerError(status: status, data: responseData)
        }

        // Optional: parse response for audit/logs
        do {
            _ = try decoder.decode(C6PConsumeOneTimePrekeyResponse.self, from: responseData)
        } catch {
            // If backend returns empty body sometimes, you can relax this.
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    // MARK: - Internals

    private func makeRequest(
        method: String,
        path: String,
        queryItems: [URLQueryItem]?
    ) throws -> URLRequest {

        guard var components = URLComponents(url: config.baseURL, resolvingAgainstBaseURL: false) else {
            throw C6PPrekeyHTTPClientError.invalidBaseURL
        }

        // Stable path composition
        let basePath = components.path
        let joinedPath: String
        if basePath.isEmpty || basePath == "/" {
            joinedPath = path
        } else {
            joinedPath = basePath.hasSuffix("/")
                ? (basePath.dropLast() + path)
                : (basePath + path)
        }
        components.path = String(joinedPath)

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw C6PPrekeyHTTPClientError.invalidBaseURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method

        // headers
        for (k, v) in config.defaultHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        // auth
        guard let token = accessTokenProvider(), !token.isEmpty else {
            throw C6PPrekeyHTTPClientError.missingAccessToken
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return req
    }

    private func perform(_ request: URLRequest) async throws -> (Int, Data) {
        do {
            let (data, resp) = try await urlSession.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (status, data)
        } catch {
            throw C6PPrekeyHTTPClientError.networkFailed(underlying: error)
        }
    }

    private func parseServerError(status: Int, data: Data) throws -> Error {
        if let body = try? decoder.decode(C6PServerErrorBody.self, from: data) {
            return C6PPrekeyHTTPClientError.serverError(
                status: status,
                code: body.error,
                message: body.message
            )
        }

        let raw = String(data: data, encoding: .utf8)
        return C6PPrekeyHTTPClientError.unexpectedResponse(status: status, body: raw)
    }
}

// MARK: - Server error body

private struct C6PServerErrorBody: Codable {
    let error: String
    let message: String
}
