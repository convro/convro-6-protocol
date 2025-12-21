//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Production DM transport for Node routes.dm_messages.js (canonical v1.1)
//
//  Endpoints (Node):
//  - POST /v1/dm/messages/send      { envelope }
//  - GET  /v1/dm/messages/inbox?afterId=0&limit=50
//  - POST /v1/dm/messages/delivered { ids: [1,2,3] }
//  - POST /v1/dm/messages/read      { ids: [1,2,3] }
//
//  Notes:
//  - Server NEVER decrypts.
//  - Client decrypts strict-in-order. If one fails, stop and do NOT ACK.
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

struct C6PAckResponse: Codable {
    let ok: Bool
    let affected: Int?
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
        let apiBaseURL: URL              // e.g. https://tunnel.convro.eu
        let bearerTokenProvider: () -> String?
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

    private let encoder: JSONEncoder = C6PJSON.makeEncoder()
    private let decoder: JSONDecoder = C6PJSON.makeDecoder()

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming = C6PURLSessionHTTP()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
    }

    // MARK: - Send (encrypt -> POST /send)

    private struct SendBody: Codable { let envelope: C6PEnvelope }

    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (envelope: C6PEnvelope, serverDbId: Int, serverMessageId: String, deduped: Bool) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

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
            return (envelope, decoded.id, decoded.serverMessageId, decoded.deduped == true)
        } catch {
            throw TransportError.decodeFailed
        }
    }

    // MARK: - Poll inbox (GET /inbox) + decrypt + delivered ACK

    /// Polls inbox, decrypts strict-in-order, then ACKs delivered for successfully decrypted ids.
    ///
    /// Returns:
    /// - decrypted: [(dbId, innerPayload, envelope)]
    /// - nextAfterId: cursor for next poll
    func pollInboxAndDecrypt(
        from remoteDeviceId: C6PDeviceId,
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

        var okIds: [Int] = []
        var out: [(Int, C6PInnerPayload, C6PEnvelope)] = []

        for item in decoded.messages {
            do {
                let inner = try crypto.decryptDMInner(from: remoteDeviceId, envelope: item.envelope)
                out.append((item.id, inner, item.envelope))
                okIds.append(item.id)
            } catch {
                // STRICT: do not ACK partial failures; stop here
                break
            }
        }

        if !okIds.isEmpty {
            try await ack(path: "/v1/dm/messages/delivered", ids: okIds, bearerToken: token)
        }

        return (out.map { (dbId: $0.0, inner: $0.1, envelope: $0.2) }, decoded.nextAfterId)
    }

    // MARK: - Read ACK

    func markRead(ids: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }
        try await ack(path: "/v1/dm/messages/read", ids: ids, bearerToken: token)
    }

    // MARK: - ACK helper

    private struct AckBody: Codable { let ids: [Int] }

    private func ack(path: String, ids: [Int], bearerToken: String) async throws {
        let clean = ids.map { $0 }.filter { $0 > 0 }
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

        // optional: parse ok/affected (not required)
        _ = try? decoder.decode(C6PAckResponse.self, from: data)
    }
}

