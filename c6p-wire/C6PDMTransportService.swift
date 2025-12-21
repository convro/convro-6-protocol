//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Production DM transport for Convro Tunnel (canonical v1.x)
//
//  Active endpoints (confirmed):
//   - POST /v1/dm/messages/send
//   - GET  /v1/dm/messages/history
//   - GET  /v1/dm/messages/conversations
//   - POST /v1/dm/messages/receipts
//
//  Notes:
//   - Server never decrypts.
//   - Client uses C6PSessionService for seal/open.
//   - Wire AAD binds routing metadata (sessionId/from/to/clientMessageId) into AEAD.
//

import Foundation

// MARK: - HTTP Adapter

protocol C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class C6PURLSessionHTTP: C6PHTTPPerforming {
    private let session: URLSession

    init(timeoutSeconds: TimeInterval = 20) {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = timeoutSeconds
        cfg.timeoutIntervalForResource = timeoutSeconds
        cfg.httpMaximumConnectionsPerHost = 6
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.urlCache = nil
        self.session = URLSession(configuration: cfg)
    }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Transport Service

final class C6PDMTransportService {

    // MARK: Config

    struct Config {
        let apiBaseURL: URL
        let bearerTokenProvider: () -> String?

        // Paths (canonical)
        var sendPath: String = "/v1/dm/messages/send"
        var historyPath: String = "/v1/dm/messages/history"
        var conversationsPath: String = "/v1/dm/messages/conversations"
        var receiptsPath: String = "/v1/dm/messages/receipts"

        // Limits
        var maxHistoryLimit: Int = 200
        var defaultHistoryLimit: Int = 50

        // If true, adds Accept: application/json always
        var forceJSONAccept: Bool = true
    }

    // MARK: Errors

    enum TransportError: Error, CustomStringConvertible {
        case authMissing
        case badURL
        case http(status: Int, body: String?, serverError: String?)
        case encodeFailed
        case decodeFailed
        case invalidWireShape(String)

        var description: String {
            switch self {
            case .authMissing: return "TransportError.authMissing"
            case .badURL: return "TransportError.badURL"
            case .http(let s, let b, let se):
                return "TransportError.http(status=\(s), serverError=\(se ?? "nil"), body=\(b ?? "nil"))"
            case .encodeFailed: return "TransportError.encodeFailed"
            case .decodeFailed: return "TransportError.decodeFailed"
            case .invalidWireShape(let r): return "TransportError.invalidWireShape(\(r))"
            }
        }
    }

    // MARK: DTOs (wire)

    /// POST /v1/dm/messages/send body (canonical minimum)
    private struct DmSendRequest: Codable {
        let sessionId: String               // 8hex
        let recipientDeviceId: String       // 16hex
        let clientMessageId: String?        // optional <= 64
        let clientTimestamp: Date?          // optional ISO
        let ciphertext: Data               // base64 in JSON
        let authTag: Data                  // base64 (16B)
    }

    struct C6PDmSendResponse: Codable {
        let ok: Bool
        let messageId: Int
        let serverTimestamp: String
        let deliveryState: String
    }

    enum C6PReceiptStatus: String, Codable {
        case delivered = "DELIVERED"
        case read = "READ"
    }

    private struct DmReceiptRequest: Codable {
        let messageId: Int
        let status: C6PReceiptStatus
    }

    private struct DmReceiptResponse: Codable {
        let ok: Bool
    }

    /// GET /v1/dm/messages/history response (tolerant decoding)
    struct C6PDmHistoryResponse: Codable {
        let messages: [C6PDmWireMessage]
        let nextAfterId: Int?
        let nextBeforeId: Int?
    }

    /// GET /v1/dm/messages/conversations response (generic)
    struct C6PDmConversationsResponse: Codable {
        let conversations: [C6PDmConversationSummary]
    }

    struct C6PDmConversationSummary: Codable, Hashable {
        // Keep this tolerant. Server shape can evolve.
        let sessionId: String?
        let peerUserId: Int?
        let peerDeviceId: String?
        let lastMessageId: Int?
        let lastServerTimestamp: String?
        let unreadCount: Int?
    }

    /// One wire message record. We decode many alias keys to avoid fragile coupling.
    struct C6PDmWireMessage: Codable, Hashable {
        let messageId: Int
        let sessionId: String?
        let fromDeviceId: String?
        let toDeviceId: String?

        let clientMessageId: String?
        let clientTimestamp: Date?

        let ciphertext: Data
        let authTag: Data

        let serverTimestamp: String?
        let deliveryState: String?

        // tolerant coding keys
        private enum K: String, CodingKey {
            case messageId, id
            case sessionId
            case fromDeviceId, senderDeviceId
            case toDeviceId, recipientDeviceId
            case clientMessageId
            case clientTimestamp
            case ciphertext
            case authTag
            case serverTimestamp
            case deliveryState
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: K.self)

            // id / messageId
            if let v = try c.decodeIfPresent(Int.self, forKey: .messageId) {
                self.messageId = v
            } else if let v = try c.decodeIfPresent(Int.self, forKey: .id) {
                self.messageId = v
            } else {
                throw DecodingError.keyNotFound(K.messageId, .init(codingPath: decoder.codingPath, debugDescription: "Missing messageId/id"))
            }

            self.sessionId = try c.decodeIfPresent(String.self, forKey: .sessionId)

            // from / sender
            if let v = try c.decodeIfPresent(String.self, forKey: .fromDeviceId) {
                self.fromDeviceId = v
            } else {
                self.fromDeviceId = try c.decodeIfPresent(String.self, forKey: .senderDeviceId)
            }

            // to / recipient
            if let v = try c.decodeIfPresent(String.self, forKey: .toDeviceId) {
                self.toDeviceId = v
            } else {
                self.toDeviceId = try c.decodeIfPresent(String.self, forKey: .recipientDeviceId)
            }

            self.clientMessageId = try c.decodeIfPresent(String.self, forKey: .clientMessageId)
            self.clientTimestamp = try c.decodeIfPresent(Date.self, forKey: .clientTimestamp)

            self.ciphertext = try c.decode(Data.self, forKey: .ciphertext)
            self.authTag = try c.decode(Data.self, forKey: .authTag)

            self.serverTimestamp = try c.decodeIfPresent(String.self, forKey: .serverTimestamp)
            self.deliveryState = try c.decodeIfPresent(String.self, forKey: .deliveryState)
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: K.self)
            try c.encode(messageId, forKey: .messageId)
            try c.encodeIfPresent(sessionId, forKey: .sessionId)
            try c.encodeIfPresent(fromDeviceId, forKey: .fromDeviceId)
            try c.encodeIfPresent(toDeviceId, forKey: .toDeviceId)
            try c.encodeIfPresent(clientMessageId, forKey: .clientMessageId)
            try c.encodeIfPresent(clientTimestamp, forKey: .clientTimestamp)
            try c.encode(ciphertext, forKey: .ciphertext)
            try c.encode(authTag, forKey: .authTag)
            try c.encodeIfPresent(serverTimestamp, forKey: .serverTimestamp)
            try c.encodeIfPresent(deliveryState, forKey: .deliveryState)
        }
    }

    // MARK: - Dependencies

    private let cfg: Config
    private let http: C6PHTTPPerforming
    private let crypto: C6PSessionService

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming = C6PURLSessionHTTP()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
        self.encoder = C6PJSON.makeEncoder()
        self.decoder = C6PJSON.makeDecoder()
    }

    // MARK: - Public API

    /// Encrypts payload -> POST /send -> returns server messageId + timestamps.
    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (envelope: C6PEnvelope, messageId: Int, serverTimestamp: String, deliveryState: C6PDeliveryState) {

        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }
        guard let url = URL(string: cfg.sendPath, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        // Seal into an envelope (routing metadata + sealed payload)
        var envelope = try crypto.encryptDM(to: remoteDeviceId, suite: suite, innerPayload: innerPayload)

        // Map envelope -> canonical send body
        let reqBody = DmSendRequest(
            sessionId: envelope.sessionId.hexString.lowercased(),
            recipientDeviceId: envelope.toDeviceId.hexString.lowercased(),
            clientMessageId: envelope.clientMessageId,      // server toleruje optional; wysyłamy żeby mieć deterministykę
            clientTimestamp: envelope.clientTimestamp,
            ciphertext: envelope.sealed.ciphertext,
            authTag: envelope.sealed.authTag
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyStandardHeaders(&req, bearerToken: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try encoder.encode(reqBody)
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(
                status: resp.statusCode,
                body: String(data: data, encoding: .utf8),
                serverError: decodeServerErrorString(from: data)
            )
        }

        let decoded: C6PDmSendResponse
        do {
            decoded = try decoder.decode(C6PDmSendResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }

        envelope.serverMessageId = String(decoded.messageId)
        envelope.serverTimestamp = C6PJSON.decodeDate(decoded.serverTimestamp) ?? envelope.serverTimestamp
        envelope.deliveryState = C6PDeliveryState(rawValue: decoded.deliveryState) ?? .pending

        return (envelope, decoded.messageId, decoded.serverTimestamp, envelope.deliveryState)
    }

    /// GET /history (raw wire records). Use for UI storage / sync.
    func fetchHistory(
        sessionId: C6PSessionId,
        beforeId: Int? = nil,
        afterId: Int? = nil,
        limit: Int? = nil
    ) async throws -> C6PDmHistoryResponse {

        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }

        guard var comps = URLComponents(url: cfg.apiBaseURL, resolvingAgainstBaseURL: true) else {
            throw TransportError.badURL
        }
        comps.path = cfg.historyPath

        var items: [URLQueryItem] = [
            URLQueryItem(name: "sessionId", value: sessionId.hexString.lowercased())
        ]

        if let b = beforeId, b > 0 { items.append(.init(name: "beforeId", value: String(b))) }
        if let a = afterId, a >= 0 { items.append(.init(name: "afterId", value: String(a))) } // optional future-proof

        let wantLimit = min(max(limit ?? cfg.defaultHistoryLimit, 1), cfg.maxHistoryLimit)
        items.append(.init(name: "limit", value: String(wantLimit)))

        comps.queryItems = items
        guard let url = comps.url else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyStandardHeaders(&req, bearerToken: token)

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(
                status: resp.statusCode,
                body: String(data: data, encoding: .utf8),
                serverError: decodeServerErrorString(from: data)
            )
        }

        // tolerant decode: server might return {messages:[...]} only
        if let decoded = try? decoder.decode(C6PDmHistoryResponse.self, from: data) {
            return decoded
        }

        // fallback: { "messages": [ ... ] } without paging fields
        struct Minimal: Codable { let messages: [C6PDmWireMessage] }
        if let m = try? decoder.decode(Minimal.self, from: data) {
            return C6PDmHistoryResponse(messages: m.messages, nextAfterId: nil, nextBeforeId: nil)
        }

        throw TransportError.decodeFailed
    }

    /// Converts a wire record into a full C6PEnvelope (needed for decrypt).
    /// Throws if the server response is missing required routing fields.
    func envelopeFromWire(_ m: C6PDmWireMessage) throws -> C6PEnvelope {
        guard let sess = m.sessionId else { throw TransportError.invalidWireShape("history item missing sessionId") }
        guard let from = m.fromDeviceId else { throw TransportError.invalidWireShape("history item missing fromDeviceId/senderDeviceId") }
        guard let to = m.toDeviceId else { throw TransportError.invalidWireShape("history item missing toDeviceId/recipientDeviceId") }
        guard let cmid = m.clientMessageId else { throw TransportError.invalidWireShape("history item missing clientMessageId") }
        guard let cts = m.clientTimestamp else { throw TransportError.invalidWireShape("history item missing clientTimestamp") }

        let sessionId = try C6PSessionId(hexString: sess)
        let fromId = try C6PDeviceId(hexString: from)
        let toId = try C6PDeviceId(hexString: to)

        let sealed = try C6PSealedMessage(ciphertext: m.ciphertext, authTag: m.authTag)

        var env = C6PEnvelope(
            fromDeviceId: fromId,
            toDeviceId: toId,
            sessionId: sessionId,
            sealed: sealed,
            clientMessageId: cmid,
            clientTimestamp: cts,
            serverTimestamp: nil,
            serverMessageId: String(m.messageId),
            deliveryState: .pending
        )

        if let st = m.serverTimestamp, let d = C6PJSON.decodeDate(st) {
            env.serverTimestamp = d
        }
        if let ds = m.deliveryState, let s = C6PDeliveryState(rawValue: ds) {
            env.deliveryState = s
        }

        return env
    }

    /// Decrypts in strict order. Stops at first failure (does NOT advance further).
    func decryptInOrder(
        from remoteDeviceId: C6PDeviceId,
        messages: [C6PDmWireMessage]
    ) async throws -> [(messageId: Int, inner: C6PInnerPayload, envelope: C6PEnvelope)] {

        // Important: strict counters require no gaps.
        // You should pass messages in correct chronological order.
        let ordered = messages.sorted { $0.messageId < $1.messageId }

        var out: [(Int, C6PInnerPayload, C6PEnvelope)] = []
        out.reserveCapacity(ordered.count)

        for m in ordered {
            do {
                let env = try envelopeFromWire(m)
                let inner = try crypto.decryptDMInner(from: remoteDeviceId, envelope: env)
                out.append((m.messageId, inner, env))
            } catch {
                // strict: stop on first failure
                break
            }
        }

        return out.map { (messageId: $0.0, inner: $0.1, envelope: $0.2) }
    }

    /// GET /conversations
    func listConversations() async throws -> C6PDmConversationsResponse {
        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }
        guard let url = URL(string: cfg.conversationsPath, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        applyStandardHeaders(&req, bearerToken: token)

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(
                status: resp.statusCode,
                body: String(data: data, encoding: .utf8),
                serverError: decodeServerErrorString(from: data)
            )
        }

        do {
            return try decoder.decode(C6PDmConversationsResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }
    }

    /// POST /receipts (DELIVERED / READ)
    func sendReceipt(messageId: Int, status: C6PReceiptStatus) async throws {
        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }
        guard let url = URL(string: cfg.receiptsPath, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        applyStandardHeaders(&req, bearerToken: token)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            req.httpBody = try encoder.encode(DmReceiptRequest(messageId: messageId, status: status))
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(
                status: resp.statusCode,
                body: String(data: data, encoding: .utf8),
                serverError: decodeServerErrorString(from: data)
            )
        }

        _ = try? decoder.decode(DmReceiptResponse.self, from: data)
    }

    // MARK: - Helpers

    private func applyStandardHeaders(_ req: inout URLRequest, bearerToken: String) {
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        if cfg.forceJSONAccept {
            req.setValue("application/json", forHTTPHeaderField: "Accept")
        }
        req.setValue("convro-ios/1.0", forHTTPHeaderField: "User-Agent")
    }

    /// tries to parse { error: "...", message?: "..." } from server
    private func decodeServerErrorString(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let e = obj["error"] as? String {
                if let m = obj["message"] as? String, !m.isEmpty { return "\(e): \(m)" }
                return e
            }
        }
        return nil
    }
}

