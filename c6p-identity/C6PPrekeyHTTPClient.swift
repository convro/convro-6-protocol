//
//  C6PPrekeyHTTPClient.swift
//  C6P-Protocol
//
//  Production HTTP client for C6P Prekeys API (handshake99).
//
//  Matches Node routes (typical):
//   - POST /v1/prekeys/upload   (requireAuth)
//   - GET  /v1/prekeys/bundle   (requireAuth)
//   - POST /v1/prekeys/consume  (requireAuth)  <-- if you implement anti-reuse endpoint
//
//  Encoding rules:
//  - All binary fields are base64url (no padding) via C6PEncoding
//  - Dates are ISO8601
//

import Foundation

// MARK: - Errors

public enum C6PPrekeyHTTPClientError: Error, CustomStringConvertible {
    case invalidBaseURL
    case missingAccessToken

    case serverError(status: Int, code: String, message: String)
    case unexpectedResponse(status: Int, body: String?)

    case encodingFailed(underlying: Error)
    case decodingFailed(underlying: Error)
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
        case .encodingFailed(let underlying):
            return "C6PPrekeyHTTPClientError.encodingFailed(\(underlying))"
        case .decodingFailed(let underlying):
            return "C6PPrekeyHTTPClientError.decodingFailed(\(underlying))"
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

    /// Endpoint paths (override if your Node routes differ)
    public let uploadPath: String
    public let bundlePath: String
    public let consumePath: String

    /// Optional extra query items for bundle (e.g. Node requires user_id)
    public let extraBundleQueryItems: (@Sendable (_ remoteDeviceId: C6PDeviceId) -> [URLQueryItem])?

    public init(
        baseURL: URL,
        timeout: TimeInterval = 12,
        defaultHeaders: [String: String] = ["Accept": "application/json"],
        uploadPath: String = "/v1/prekeys/upload",
        bundlePath: String = "/v1/prekeys/bundle",
        consumePath: String = "/v1/prekeys/consume",
        extraBundleQueryItems: (@Sendable (_ remoteDeviceId: C6PDeviceId) -> [URLQueryItem])? = nil
    ) {
        self.baseURL = baseURL
        self.timeout = timeout
        self.defaultHeaders = defaultHeaders
        self.uploadPath = uploadPath
        self.bundlePath = bundlePath
        self.consumePath = consumePath
        self.extraBundleQueryItems = extraBundleQueryItems
    }
}

// MARK: - Access Token Provider

/// Must return a valid JWT access token (same one used by your REST + WS).
public typealias C6PAccessTokenProvider = @Sendable () -> String?

// MARK: - Client

/// Production HTTP client that conforms to `C6PPrekeyAPIClient`.
public final class C6PPrekeyHTTPClient: C6PPrekeyAPIClient {

    private let config: C6PPrekeyHTTPClientConfig
    private let session: URLSession
    private let accessTokenProvider: C6PAccessTokenProvider

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(
        config: C6PPrekeyHTTPClientConfig,
        accessTokenProvider: @escaping C6PAccessTokenProvider,
        urlSession: URLSession? = nil
    ) {
        self.config = config
        self.accessTokenProvider = accessTokenProvider

        if let urlSession {
            self.session = urlSession
        } else {
            let sc = URLSessionConfiguration.ephemeral
            sc.timeoutIntervalForRequest = config.timeout
            sc.timeoutIntervalForResource = config.timeout
            sc.waitsForConnectivity = true
            self.session = URLSession(configuration: sc)
        }

        let enc = JSONEncoder()
        enc.outputFormatting = []
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - C6PPrekeyAPIClient

    public func publishPrekeys(_ request: C6PPublishPrekeysRequest) async throws -> C6PPublishPrekeysResponse {
        // contract-level validation (fail-closed)
        try request.validate()

        let bodyData: Data
        do {
            bodyData = try encoder.encode(request)
        } catch {
            throw C6PPrekeyHTTPClientError.encodingFailed(underlying: error)
        }

        var req = try makeRequest(method: "POST", path: config.uploadPath, queryItems: nil)
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (status, data) = try await perform(req)
        guard status == 200 else { throw try parseServerError(status: status, data: data) }

        do {
            return try decoder.decode(C6PPublishPrekeysResponse.self, from: data)
        } catch {
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    public func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) async throws -> C6PPrekeyBundleContract {
        var query: [URLQueryItem] = [
            .init(name: "device_id", value: remoteDeviceId.hexString.lowercased())
        ]

        if let extra = config.extraBundleQueryItems?(remoteDeviceId) {
            query.append(contentsOf: extra)
        }

        let req = try makeRequest(method: "GET", path: config.bundlePath, queryItems: query)
        let (status, data) = try await perform(req)
        guard status == 200 else { throw try parseServerError(status: status, data: data) }

        do {
            let bundle = try decoder.decode(C6PPrekeyBundleContract.self, from: data)
            try bundle.validate()
            return bundle
        } catch {
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    public func markOneTimePrekeyConsumed(responderDeviceId: C6PDeviceId, oneTimePrekeyId: C6PKeyId) async throws {
        // If your backend does not have /consume yet, implement it OR change `consumePath`.
        let reqBody = try C6PConsumeOneTimePrekeyRequest(
            c6pVersion: C6P_VERSION,
            responderDeviceId: responderDeviceId,
            oneTimePrekeyId: oneTimePrekeyId
        )

        let bodyData: Data
        do {
            bodyData = try encoder.encode(reqBody)
        } catch {
            throw C6PPrekeyHTTPClientError.encodingFailed(underlying: error)
        }

        var req = try makeRequest(method: "POST", path: config.consumePath, queryItems: nil)
        req.httpBody = bodyData
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (status, data) = try await perform(req)

        // Accept either 200 with JSON response or 204 no-content.
        if status == 204 { return }
        guard status == 200 else { throw try parseServerError(status: status, data: data) }

        // Optional decode for audit; ignore body if backend returns minimal OK.
        _ = try? decoder.decode(C6PConsumeOneTimePrekeyResponse.self, from: data)
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

        // Stable path join
        let basePath = components.path
        let joinedPath: String
        if basePath.isEmpty || basePath == "/" {
            joinedPath = path
        } else {
            joinedPath = basePath.hasSuffix("/")
                ? (String(basePath.dropLast()) + path)
                : (basePath + path)
        }
        components.path = joinedPath

        if let queryItems, !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw C6PPrekeyHTTPClientError.invalidBaseURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = method

        for (k, v) in config.defaultHeaders {
            req.setValue(v, forHTTPHeaderField: k)
        }

        guard let token = accessTokenProvider(), !token.isEmpty else {
            throw C6PPrekeyHTTPClientError.missingAccessToken
        }
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        return req
    }

    private func perform(_ request: URLRequest) async throws -> (Int, Data) {
        do {
            let (data, resp) = try await session.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (status, data)
        } catch {
            throw C6PPrekeyHTTPClientError.networkFailed(underlying: error)
        }
    }

    private func parseServerError(status: Int, data: Data) throws -> Error {
        if let body = try? decoder.decode(C6PServerErrorBody.self, from: data) {
            return C6PPrekeyHTTPClientError.serverError(status: status, code: body.error, message: body.message)
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
