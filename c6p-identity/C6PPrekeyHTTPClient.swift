//
//  C6PPrekeyHTTPClient.swift
//  C6P-Protocol
//
//  Production HTTP client for C6P Prekeys API (handshake99).
//
//  Matches Node routes:
//   - POST /v1/prekeys/upload   (requireAuth)
//   - GET  /v1/prekeys/bundle   (requireAuth)
//
//  Notes:
//  - Data fields are base64 in JSON (Swift JSONEncoder/Decoder default behavior).
//  - ExpiresAt is ISO8601 string (Node expects ISO-ish input; we send strict ISO8601).
//

import Foundation

// MARK: - Errors

enum C6PPrekeyHTTPClientError: Error, CustomStringConvertible {
    case invalidBaseURL
    case missingAccessToken
    case invalidUserId
    case invalidDeviceIdHex
    case invalidKeyIdHex
    case invalidKeyLength(label: String, expected: Int, actual: Int)
    case serverError(status: Int, code: String, message: String)
    case unexpectedResponse(status: Int, body: String?)
    case decodingFailed(underlying: Error)
    case networkFailed(underlying: Error)

    var description: String {
        switch self {
        case .invalidBaseURL:
            return "C6PPrekeyHTTPClientError.invalidBaseURL"
        case .missingAccessToken:
            return "C6PPrekeyHTTPClientError.missingAccessToken"
        case .invalidUserId:
            return "C6PPrekeyHTTPClientError.invalidUserId"
        case .invalidDeviceIdHex:
            return "C6PPrekeyHTTPClientError.invalidDeviceIdHex"
        case .invalidKeyIdHex:
            return "C6PPrekeyHTTPClientError.invalidKeyIdHex"
        case .invalidKeyLength(let label, let expected, let actual):
            return "C6PPrekeyHTTPClientError.invalidKeyLength(label=\(label), expected=\(expected), actual=\(actual))"
        case .serverError(let status, let code, let message):
            return "C6PPrekeyHTTPClientError.serverError(status=\(status), code=\(code), message=\(message))"
        case .unexpectedResponse(let status, let body):
            return "C6PPrekeyHTTPClientError.unexpectedResponse(status=\(status), body=\(body ?? "nil"))"
        case .decodingFailed(let underlying):
            return "C6PPrekeyHTTPClientError.decodingFailed(\(underlying))"
        case .networkFailed(let underlying):
            return "C6PPrekeyHTTPClientError.networkFailed(\(underlying))"
        }
    }
}

// MARK: - Config

struct C6PPrekeyHTTPClientConfig: Sendable {
    /// Example: https://tunnel.convro.eu
    let baseURL: URL

    /// Request timeout (seconds).
    let timeout: TimeInterval

    /// Extra headers if you want (e.g. User-Agent).
    let defaultHeaders: [String: String]

    init(
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
typealias C6PAccessTokenProvider = () -> String?

// MARK: - Client

/// Production HTTP client matching `routes.prekeys.js`.
final class C6PPrekeyHTTPClient {

    private let config: C6PPrekeyHTTPClientConfig
    private let urlSession: URLSession
    private let accessTokenProvider: C6PAccessTokenProvider

    // JSON
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
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
        // responses here do not contain dates; keep default
        self.decoder = dec
    }

    // MARK: - Public API

    /// POST /v1/prekeys/upload
    ///
    /// Body:
    /// {
    ///  identity: { publicKeyEd25519: "<base64>", fingerprint?: "..." },
    ///  signedPrekey: { publicKeyX25519: "<base64>", signatureEd25519: "<base64>", expiresAt?: "<iso8601>" },
    ///  oneTimePrekeys: [{ keyId: "<16hex>", publicKeyX25519: "<base64>" }]
    /// }
    ///
    /// Returns:
    /// { ok: true, userDeviceId: number, storedOneTimePrekeys: number }
    func uploadPrekeys(
        identityPublicKeyEd25519: Data,
        identityFingerprint: String?,
        signedPrekeyPublicKeyX25519: Data,
        signedPrekeySignatureEd25519: Data,
        signedPrekeyExpiresAt: Date?,
        oneTimePrekeys: [(keyIdHex16: String, publicKeyX25519: Data)]
    ) async throws -> C6PPrekeysUploadResponse {

        try validateLength(identityPublicKeyEd25519, expected: 32, label: "identity.publicKeyEd25519")
        try validateLength(signedPrekeyPublicKeyX25519, expected: 32, label: "signedPrekey.publicKeyX25519")
        try validateLength(signedPrekeySignatureEd25519, expected: 64, label: "signedPrekey.signatureEd25519")

        var otps: [UploadDTO.OneTimePrekey] = []
        otps.reserveCapacity(oneTimePrekeys.count)

        for item in oneTimePrekeys {
            let keyId = item.keyIdHex16.lowercased()
            guard Self.isHex16(keyId) else {
                throw C6PPrekeyHTTPClientError.invalidKeyIdHex
            }
            try validateLength(item.publicKeyX25519, expected: 32, label: "oneTimePrekeys[\(keyId)].publicKeyX25519")
            otps.append(.init(keyId: keyId, publicKeyX25519: item.publicKeyX25519))
        }

        let body = UploadDTO(
            identity: .init(
                publicKeyEd25519: identityPublicKeyEd25519,
                fingerprint: identityFingerprint?.isEmpty == true ? nil : identityFingerprint
            ),
            signedPrekey: .init(
                publicKeyX25519: signedPrekeyPublicKeyX25519,
                signatureEd25519: signedPrekeySignatureEd25519,
                expiresAt: signedPrekeyExpiresAt
            ),
            oneTimePrekeys: otps
        )

        let data = try encoder.encode(body)

        var req = try makeRequest(
            method: "POST",
            path: "/v1/prekeys/upload",
            queryItems: nil
        )
        req.httpBody = data
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (status, responseData) = try await perform(req)

        guard status == 200 else {
            throw try parseServerError(status: status, data: responseData)
        }

        do {
            return try decoder.decode(C6PPrekeysUploadResponse.self, from: responseData)
        } catch {
            throw C6PPrekeyHTTPClientError.decodingFailed(underlying: error)
        }
    }

    /// GET /v1/prekeys/bundle?user_id=...&device_id=...
    ///
    /// Returns C6PPrekeyBundle compatible with Swift Codable.
    func fetchPrekeyBundle(
        responderUserId: Int,
        responderDeviceIdHex16: String? = nil
    ) async throws -> C6PPrekeyBundle {

        guard responderUserId > 0 else {
            throw C6PPrekeyHTTPClientError.invalidUserId
        }

        var query: [URLQueryItem] = [
            .init(name: "user_id", value: String(responderUserId))
        ]

        if let deviceId = responderDeviceIdHex16 {
            let d = deviceId.lowercased()
            guard Self.isHex16(d) else {
                throw C6PPrekeyHTTPClientError.invalidDeviceIdHex
            }
            query.append(.init(name: "device_id", value: d))
        }

        let req = try makeRequest(
            method: "GET",
            path: "/v1/prekeys/bundle",
            queryItems: query
        )

        let (status, responseData) = try await perform(req)

        guard status == 200 else {
            throw try parseServerError(status: status, data: responseData)
        }

        do {
            let bundle = try decoder.decode(C6PPrekeyBundle.self, from: responseData)

            // Hard validation (defensive)
            try validateLength(bundle.identityPublicKeyEd25519, expected: 32, label: "bundle.identityPublicKeyEd25519")
            try validateLength(bundle.signedPrekeyPublicKeyX25519, expected: 32, label: "bundle.signedPrekeyPublicKeyX25519")
            try validateLength(bundle.signedPrekeySignature, expected: 64, label: "bundle.signedPrekeySignature")

            if let otpPub = bundle.oneTimePrekeyPublicKeyX25519 {
                try validateLength(otpPub, expected: 32, label: "bundle.oneTimePrekeyPublicKeyX25519")
            }

            return bundle
        } catch {
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

        // Ensure path composition is stable
        let basePath = components.path
        let joinedPath: String
        if basePath.isEmpty || basePath == "/" {
            joinedPath = path
        } else {
            // Prevent accidental double slashes
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

    private func validateLength(_ data: Data, expected: Int, label: String) throws {
        guard data.count == expected else {
            throw C6PPrekeyHTTPClientError.invalidKeyLength(
                label: label,
                expected: expected,
                actual: data.count
            )
        }
    }

    private static func isHex16(_ s: String) -> Bool {
        // exactly 16 lowercase hex chars
        // (server lowercases anyway, we enforce)
        guard s.count == 16 else { return false }
        return s.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil
    }
}

// MARK: - DTOs / Response bodies

private struct C6PServerErrorBody: Codable {
    let error: String
    let message: String
}

/// Response from POST /v1/prekeys/upload
struct C6PPrekeysUploadResponse: Codable, Hashable {
    let ok: Bool
    let userDeviceId: UInt64
    let storedOneTimePrekeys: Int
}

/// POST body DTO – matches Node.
private struct UploadDTO: Codable {
    struct Identity: Codable {
        let publicKeyEd25519: Data
        let fingerprint: String?
    }

    struct SignedPrekey: Codable {
        let publicKeyX25519: Data
        let signatureEd25519: Data
        let expiresAt: Date?
    }

    struct OneTimePrekey: Codable {
        let keyId: String          // 16 hex chars
        let publicKeyX25519: Data  // base64
    }

    let identity: Identity
    let signedPrekey: SignedPrekey
    let oneTimePrekeys: [OneTimePrekey]
}
