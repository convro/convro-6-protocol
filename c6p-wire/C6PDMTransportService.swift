//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Production DM transport for Node routes.dm_messages.js (canonical v1.1)
//
//  Endpoints (server):
//  - POST /v1/dm/messages/send       { envelope }
//  - GET  /v1/dm/messages/inbox?afterId=0&limit=50
//  - POST /v1/dm/messages/delivered  { ids: [1,2,3] }
//  - POST /v1/dm/messages/read       { ids: [1,2,3] }
//
//  Server stores envelope_json; server never decrypts.
//

import Foundation

// MARK: - DTOs (Node wire)

struct C6PDmInboxResponse: Codable {
    struct Item: Codable, Hashable {
        let id: Int
        let serverMessageId: String
        let serverTimestamp: String
        let envelope: C6PEnvelope
    }
    let messages: [Item]
    let nextAfterId: Int
}

struct C6PDmSendResponse: Codable {
    let ok: Bool
    let id: Int
    let serverMessageId: String
    let serverTimestamp: String
    let deduped: Bool?
}

// MARK: - HTTP Adapter

protocol C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class C6PURLSessionHTTP: C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await URLSession.shared.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, http)
    }
}

// MARK: - Transport

final class C6PDMTransportService {

    struct Config {
        let apiBaseURL: URL                    // e.g. https://tunnel.convro.eu
        let bearerTokenProvider: () -> String? // JWT access token
    }

    enum TransportError: Error, CustomStringConvertible {
        case authMissing
        case badURL
        case http(status: Int, body: String?)
        case decodeFailed
        case encodeFailed

        var description: String {
            switch self {
            case .authMissing: return "C6PDMTransportService.TransportError.authMissing"
            case .badURL: return "C6PDMTransportService.TransportError.badURL"
            case .http(let s, let b): return "C6PDMTransportService.TransportError.http(status=\(s), body=\(b ?? "nil"))"
            case .decodeFailed: return "C6PDMTransportService.TransportError.decodeFailed"
            case .encodeFailed: return "C6PDMTransportService.TransportError.encodeFailed"
            }
        }
    }

    private let cfg: Config
    private let http: C6PHTTPPerforming
    private let crypto: C6PSessionService

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming = C6PURLSessionHTTP()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
    }

    // MARK: - SEND

    private struct SendBody: Codable {
        let envelope: C6PEnvelope
    }

    /// Encrypt -> POST /v1/dm/messages/send
    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload,
        messageType: C6PMessageType = .dm
    ) async throws -> (envelope: C6PEnvelope, serverDbId: Int, serverMessageId: String, deduped: Bool) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        // IMPORTANT: encryptDM returns C6PEnvelope (updated envelope carries suite/stream/type/counter)
        let envelope = try crypto.encryptDM(
            to: remoteDeviceId,
            suite: suite,
            innerPayload: innerPayload,
            messageType: messageType
        )

        guard let url = URL(string: "/v1/dm/messages/send", relativeTo: cfg.apiBaseURL) else {
            throw TransportError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(SendBody(envelope: envelope))
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        do {
            let decoded = try decoder.decode(C6PDmSendResponse.self, from: data)
            return (envelope, decoded.id, decoded.serverMessageId, decoded.deduped ?? (resp.statusCode == 200))
        } catch {
            throw TransportError.decodeFailed
        }
    }

    // MARK: - INBOX POLL + DECRYPT + ACK DELIVERED

    /// Polls inbox for THIS device (auth token device), decrypts what it can,
    /// and ACKs delivered for successfully decrypted messages.
    ///
    /// Returns decrypted items with original envelope + db id cursor.
    func pollInboxAndDecrypt(
        afterId: Int,
        limit: Int = 50
    ) async throws -> (decrypted: [(dbId: Int, inner: C6PInnerPayload, envelope: C6PEnvelope)], nextAfterId: Int) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        guard var comps = URLComponents(url: cfg.apiBaseURL, resolvingAgainstBaseURL: true) else {
            throw TransportError.badURL
        }
        comps.path = "/v1/dm/messages/inbox"
        comps.queryItems = [
            URLQueryItem(name: "afterId", value: String(max(afterId, 0))),
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

        let decoded: C6PDmInboxResponse
        do {
            decoded = try decoder.decode(C6PDmInboxResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }

        // If one message fails for a given session+sender, skip further ones from that same key this poll.
        struct BlockKey: Hashable {
            let sessionId: C6PSessionId
            let fromDeviceId: C6PDeviceId
        }
        var blocked = Set<BlockKey>()

        var okIds: [Int] = []
        var out: [(Int, C6PInnerPayload, C6PEnvelope)] = []

        for item in decoded.messages {
            guard item.id > 0 else { continue }

            let env = item.envelope
            let key = BlockKey(sessionId: env.sessionId, fromDeviceId: env.fromDeviceId)

            if blocked.contains(key) {
                continue
            }

            do {
                let inner = try crypto.decryptDMInner(from: env.fromDeviceId, envelope: env)
                out.append((item.id, inner, env))
                okIds.append(item.id)
            } catch {
                // Block this session/sender for this poll batch (strict ordering => future items likely fail too)
                blocked.insert(key)
                continue
            }
        }

        if !okIds.isEmpty {
            try await ackDelivered(ids: okIds, bearerToken: token)
        }

        return (out.map { (dbId: $0.0, inner: $0.1, envelope: $0.2) }, decoded.nextAfterId)
    }

    // MARK: - ACK Delivered / Read

    func markDelivered(ids: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }
        try await ack(path: "/v1/dm/messages/delivered", ids: ids, bearerToken: token)
    }

    func markRead(ids: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }
        try await ack(path: "/v1/dm/messages/read", ids: ids, bearerToken: token)
    }

    private func ackDelivered(ids: [Int], bearerToken: String) async throws {
        try await ack(path: "/v1/dm/messages/delivered", ids: ids, bearerToken: bearerToken)
    }

    private struct AckBody: Codable {
        let ids: [Int]
    }

    private func ack(path: String, ids: [Int], bearerToken: String) async throws {
        let clean = Array(Set(ids.filter { $0 > 0 })).sorted()
        guard !clean.isEmpty else { return }

        guard let url = URL(string: path, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(AckBody(ids: Array(clean.prefix(200))))
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }
    }
}


