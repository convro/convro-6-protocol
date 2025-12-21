//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Production DM transport for Node routes.dm_messages.js (canonical v1.1)
//
//  Requires:
//  - C6PSessionService (crypto + session state)
//  - C6PEnvelope Codable
//  - C6PInnerPayload Codable
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

protocol C6PHTTPPerforming2 {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class C6PURLSessionHTTP2: C6PHTTPPerforming2 {
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
    private let http: C6PHTTPPerforming2
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

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming2 = C6PURLSessionHTTP2()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
    }

    // MARK: - Send (encrypt -> POST /send)

    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (envelope: C6PEnvelope, serverDbId: Int, serverMessageId: String) {

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

        let bodyObj: [String: Any] = [
            "envelope": try jsonObject(from: envelope)
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

        do {
            let decoded = try decoder.decode(C6PDmSendResponse.self, from: data)
            return (envelope, decoded.id, decoded.serverMessageId)
        } catch {
            throw TransportError.decodeFailed
        }
    }

    // MARK: - Poll inbox (GET /inbox) + decrypt + delivered ack

    /// Polls inbox, decrypts messages (strict in-order), and ACKs delivered for successfully decrypted items.
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
            URLQueryItem(name: "afterId", value: String(afterId)),
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
                // strict-in-order: jeśli coś się wywali, NIE ACKuj i przerwij,
                // bo następne i tak będą się wysypywać (brak wire counter)
                break
            }
        }

        if !okIds.isEmpty {
            try await ackDelivered(ids: okIds, bearerToken: token)
        }

        return (out.map { (dbId: $0.0, inner: $0.1, envelope: $0.2) }, decoded.nextAfterId)
    }

    // MARK: - ACK Delivered / Read

    func markRead(ids: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }
        try await ack(path: "/v1/dm/messages/read", ids: ids, bearerToken: token)
    }

    private func ackDelivered(ids: [Int], bearerToken: String) async throws {
        try await ack(path: "/v1/dm/messages/delivered", ids: ids, bearerToken: bearerToken)
    }

    private func ack(path: String, ids: [Int], bearerToken: String) async throws {
        let clean = ids.filter { $0 > 0 }
        guard !clean.isEmpty else { return }

        guard let url = URL(string: path, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyObj: [String: Any] = ["ids": Array(clean.prefix(200))]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj, options: [])

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Helpers

    private func jsonObject(from envelope: C6PEnvelope) throws -> [String: Any] {
        do {
            let data = try encoder.encode(envelope)
            let obj = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = obj as? [String: Any] else { throw TransportError.encodeFailed }
            return dict
        } catch {
            throw TransportError.encodeFailed
        }
    }
}
