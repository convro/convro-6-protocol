//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Canonical DM transport for Node routes.dm_messages.js (v1.1)
//
//  Endpoints:
//  - POST /v1/dm/messages/send      { envelope }
//  - GET  /v1/dm/messages/inbox?afterId=0&limit=50
//  - POST /v1/dm/messages/delivered { ids: [Int] }
//  - POST /v1/dm/messages/read      { ids: [Int] }
//
//  Notes:
//  - Server never decrypts.
//  - Client decrypts strict-in-order (because wire doesn't carry counter).
//

import Foundation

// MARK: - Wire DTOs (match Node exactly)

private struct DmSendRequest: Codable {
    let envelope: C6PEnvelope
}

struct C6PDmSendResponse: Codable {
    let ok: Bool
    let id: Int
    let serverMessageId: String
    let serverTimestamp: String
    let deduped: Bool?
}

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

private struct DmAckRequest: Codable {
    let ids: [Int]
}

private struct DmAckResponse: Codable {
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
        guard let http = resp as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

// MARK: - Transport

final class C6PDMTransportService {

    struct Config {
        let apiBaseURL: URL                    // e.g. https://tunnel.convro.eu
        let bearerTokenProvider: () -> String? // accessToken (JWT)
    }

    enum TransportError: Error, CustomStringConvertible {
        case authMissing
        case badURL
        case http(status: Int, body: String?)
        case encodeFailed
        case decodeFailed

        var description: String {
            switch self {
            case .authMissing: return "TransportError.authMissing"
            case .badURL: return "TransportError.badURL"
            case .http(let s, let b): return "TransportError.http(status=\(s), body=\(b ?? "nil"))"
            case .encodeFailed: return "TransportError.encodeFailed"
            case .decodeFailed: return "TransportError.decodeFailed"
            }
        }
    }

    private let cfg: Config
    private let http: C6PHTTPPerforming
    private let crypto: C6PSessionService

    private let encoder: JSONEncoder = {
        // spójnie z resztą pakietu: ISO8601 dla Date
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

    // MARK: - Send DM (encrypt -> POST /send)

    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (envelope: C6PEnvelope, serverDbId: Int, serverMessageId: String, serverTimestamp: String) {

        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }
        guard let url = URL(string: "/v1/dm/messages/send", relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        // Encrypt -> envelope
        var envelope = try crypto.encryptDM(
            to: remoteDeviceId,
            suite: suite,
            innerPayload: innerPayload
        )

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(DmSendRequest(envelope: envelope))
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        let decoded: C6PDmSendResponse
        do {
            decoded = try decoder.decode(C6PDmSendResponse.self, from: data)
        } catch {
            throw TransportError.decodeFailed
        }

        // Node w inbox dołącza serverMessageId/serverTimestamp do envelope,
        // ale po /send też zwracamy je na response -> możemy je zapisać lokalnie:
        envelope.serverMessageId = decoded.serverMessageId
        envelope.serverTimestamp = iso8601ToDate(decoded.serverTimestamp) ?? envelope.serverTimestamp
        envelope.deliveryState = .pending

        return (envelope, decoded.id, decoded.serverMessageId, decoded.serverTimestamp)
    }

    // MARK: - Poll inbox + decrypt (strict-in-order) + delivered ACK

    func pollInboxAndDecrypt(
        from remoteDeviceId: C6PDeviceId,
        afterId: Int,
        limit: Int = 50
    ) async throws -> (decrypted: [(dbId: Int, inner: C6PInnerPayload, envelope: C6PEnvelope)], nextAfterId: Int) {

        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }

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
                // strict-in-order: jak coś nie siądzie, przerywamy i nie ACKujemy dalej
                break
            }
        }

        if !okIds.isEmpty {
            try await ack(path: "/v1/dm/messages/delivered", ids: okIds, bearerToken: token)
        }

        return (out.map { (dbId: $0.0, inner: $0.1, envelope: $0.2) }, decoded.nextAfterId)
    }

    // MARK: - Read receipts

    func markRead(ids: [Int]) async throws {
        guard let token = cfg.bearerTokenProvider(), !token.isEmpty else { throw TransportError.authMissing }
        try await ack(path: "/v1/dm/messages/read", ids: ids, bearerToken: token)
    }

    // MARK: - ACK helper

    private func ack(path: String, ids: [Int], bearerToken: String) async throws {
        let clean = ids.map { Int($0) }.filter { $0 > 0 }
        guard !clean.isEmpty else { return }

        guard let url = URL(string: path, relativeTo: cfg.apiBaseURL) else { throw TransportError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try encoder.encode(DmAckRequest(ids: Array(clean.prefix(200))))
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        // Response optional — ale dekodujmy żeby wykryć syf na serwerze
        _ = try? decoder.decode(DmAckResponse.self, from: data)
    }

    // MARK: - ISO8601 helper

    private func iso8601ToDate(_ s: String) -> Date? {
        // Node zwraca .toISOString()
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }

        // fallback bez fractional seconds
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}

