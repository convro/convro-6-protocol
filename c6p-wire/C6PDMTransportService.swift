//
//  C6PDMTransportService.swift
//  Convro-6-Protocol (C6P)
//
//  Production DM transport for Node routes.dm_messages.js (canonical v1.1)
//
//  Node endpoints (server-visible, routing only):
//   POST /v1/dm/messages/send
//   GET  /v1/dm/messages/history?session_id=...&after_id=...&limit=...
//   GET  /v1/dm/conversations?limit=...
//   POST /v1/dm/receipts   { status: "DELIVERED"|"READ", messageId|messageIds }
//
//  Requires your crypto service API:
//   - crypto.encryptDM(to:suite:innerPayload:) -> C6PEnvelope
//   - crypto.decryptDMInner(from:envelope:) -> C6PInnerPayload
//

import Foundation

// MARK: - HTTP Adapter

protocol C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class C6PURLSessionHTTP: C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Wire DTOs (exactly what Node returns)

struct C6PDmHistoryResponse: Codable {
    let sessionId: String
    let messages: [C6PDmWireMessage]
}

struct C6PDmConversationsResponse: Codable {
    let conversations: [C6PDmConversation]
}

struct C6PDmConversation: Codable, Hashable {
    let sessionId: String
    let state: String
    let peerUserId: String
    let peerDeviceId: String
    let lastActivityAt: String?
    let lastMessage: C6PDmWireMessage?
}

/// One DB row mapped by mapDbRowToWire() in routes.dm_messages.js
struct C6PDmWireMessage: Codable, Hashable {
    let id: Int
    let c6pVersion: Int
    let sessionId: String

    let senderUserId: String?
    let recipientUserId: String?

    let senderDeviceId: String
    let recipientDeviceId: String

    let clientMessageId: String?
    let clientTimestamp: String?
    let serverTimestamp: String?
    let deliveryState: String?

    let ciphertext: String? // base64
    let authTag: String?    // base64 (16 bytes)

    // serverMessageId exists in your envelope model, but Node may return it null
    let serverMessageId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case c6pVersion
        case sessionId
        case senderUserId
        case recipientUserId
        case senderDeviceId
        case recipientDeviceId
        case clientMessageId
        case clientTimestamp
        case serverTimestamp
        case deliveryState
        case ciphertext
        case authTag
        case serverMessageId
    }
}

struct C6PReceiptsResponse: Codable {
    let ok: Bool
    let updated: Int?
}

// MARK: - Service

final class C6PDMTransportService {

    struct Config {
        let apiBaseURL: URL              // e.g. https://tunnel.convro.eu
        let bearerTokenProvider: () -> String?
    }

    enum TransportError: Error, CustomStringConvertible {
        case authMissing
        case badURL
        case http(status: Int, body: String?)
        case decodeFailed
        case encodeFailed
        case invalidWireMessage(String)

        var description: String {
            switch self {
            case .authMissing: return "TransportError.authMissing"
            case .badURL: return "TransportError.badURL"
            case .http(let s, let b): return "TransportError.http(status=\(s), body=\(b ?? "nil"))"
            case .decodeFailed: return "TransportError.decodeFailed"
            case .encodeFailed: return "TransportError.encodeFailed"
            case .invalidWireMessage(let m): return "TransportError.invalidWireMessage(\(m))"
            }
        }
    }

    private let cfg: Config
    private let http: C6PHTTPPerforming
    private let crypto: C6PSessionService

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming = C6PURLSessionHTTP()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
    }

    // MARK: - SEND (encrypt -> POST /v1/dm/messages/send)

    /// Returns server wire row + envelope you actually sent.
    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (envelope: C6PEnvelope, wire: C6PDmWireMessage) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        // Encrypt locally -> we get envelope with sealed(ciphertext+tag)
        let envelope = try crypto.encryptDM(
            to: remoteDeviceId,
            suite: suite,
            innerPayload: innerPayload
        )

        guard let url = URL(string: "/v1/dm/messages/send", relativeTo: cfg.apiBaseURL) else {
            throw TransportError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        // Node expects: sessionId(8 hex), c6pVersion, ciphertext(b64), authTag(b64), clientMessageId, clientTimestampMs
        let bodyObj: [String: Any] = [
            "sessionId": envelope.sessionId.hexString.lowercased(),
            "c6pVersion": Int(envelope.c6pVersion),
            "ciphertext": envelope.sealed.ciphertext.base64EncodedString(),
            "authTag": envelope.sealed.tag.base64EncodedString(),
            "clientMessageId": envelope.clientMessageId,
            "clientTimestampMs": Int(envelope.clientTimestamp.timeIntervalSince1970 * 1000.0)
        ]

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj, options: [])
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        let wire: C6PDmWireMessage
        do {
            wire = try JSONDecoder().decode(C6PDmWireMessage.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }

        return (envelope, wire)
    }

    // MARK: - HISTORY (pull messages)  GET /v1/dm/messages/history

    func history(
        sessionId: String,
        afterId: Int = 0,
        limit: Int = 50
    ) async throws -> C6PDmHistoryResponse {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        guard var comps = URLComponents(url: cfg.apiBaseURL, resolvingAgainstBaseURL: true) else {
            throw TransportError.badURL
        }
        comps.path = "/v1/dm/messages/history"
        comps.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId.lowercased()),
            URLQueryItem(name: "after_id", value: String(max(afterId, 0))),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))
        ]
        guard let url = comps.url else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(C6PDmHistoryResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }
    }

    // MARK: - CONVERSATIONS  GET /v1/dm/conversations

    func conversations(limit: Int = 50) async throws -> C6PDmConversationsResponse {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        guard var comps = URLComponents(url: cfg.apiBaseURL, resolvingAgainstBaseURL: true) else {
            throw TransportError.badURL
        }
        comps.path = "/v1/dm/conversations"
        comps.queryItems = [URLQueryItem(name: "limit", value: String(min(max(limit, 1), 200)))]
        guard let url = comps.url else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            return try JSONDecoder().decode(C6PDmConversationsResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }
    }

    // MARK: - RECEIPTS  POST /v1/dm/receipts

    func markDelivered(messageIds: [Int]) async throws {
        try await receipts(status: "DELIVERED", messageIds: messageIds)
    }

    func markRead(messageIds: [Int]) async throws {
        try await receipts(status: "READ", messageIds: messageIds)
    }

    private func receipts(status: String, messageIds: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        let clean = Array(Set(messageIds.filter { $0 > 0 })).sorted()
        guard !clean.isEmpty else { return }

        guard let url = URL(string: "/v1/dm/receipts", relativeTo: cfg.apiBaseURL) else {
            throw TransportError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyObj: [String: Any] = [
            "status": status,
            "messageIds": Array(clean.prefix(200))
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj, options: [])

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        _ = try? JSONDecoder().decode(C6PReceiptsResponse.self, from: data)
    }

    // MARK: - DECRYPT helpers (wire row -> envelope -> inner)

    /// Converts Node wire row to C6PEnvelope, then decrypts inner payload.
    func decryptWireMessage(_ wire: C6PDmWireMessage) throws -> (envelope: C6PEnvelope, inner: C6PInnerPayload) {

        guard
            let ctB64 = wire.ciphertext,
            let tagB64 = wire.authTag,
            let ct = Data(base64Encoded: ctB64),
            let tag = Data(base64Encoded: tagB64)
        else {
            throw TransportError.invalidWireMessage("ciphertext/authTag missing or invalid base64")
        }

        let fromDev = try C6PDeviceId(hex: wire.senderDeviceId)
        let toDev = try C6PDeviceId(hex: wire.recipientDeviceId)
        let sid = try C6PSessionId(hex: wire.sessionId)

        // clientTimestamp may be null if client didn’t send it; fallback to now
        let clientMsgId = wire.clientMessageId ?? UUID().uuidString
        let clientTs = Date() // safe fallback for envelope object; UI ordering should use inner payload timestamp anyway

        let sealed = C6PSealedMessage(ciphertext: ct, tag: tag)

        let env = C6PEnvelope(
            fromDeviceId: fromDev,
            toDeviceId: toDev,
            sessionId: sid,
            sealed: sealed,
            clientMessageId: clientMsgId,
            clientTimestamp: clientTs,
            serverTimestamp: nil,
            serverMessageId: wire.serverMessageId,
            deliveryState: .pending
        )

        let inner = try crypto.decryptDMInner(from: fromDev, envelope: env)
        return (env, inner)
    }
}
