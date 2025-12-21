//
//  C6PDMTransportService.swift
//  C6P-Protocol
//
//  Production DM transport for Node routes.dm_messages.js (CANONICAL v1.1)
//
//  Node endpoints used:
//   - POST /v1/dm/messages/send
//   - GET  /v1/dm/messages/history?session_id=...&after_id=...&limit=...
//   - POST /v1/dm/receipts   { status: "DELIVERED"|"READ", messageIds:[...] }
//
//  Notes:
//   - Server never sees plaintext.
//   - Client reconstructs C6PEnvelope locally from wire row.
//   - Receipts are sent only for successfully decrypted messages.
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

// MARK: - Wire DTOs (from routes.dm_messages.js mapDbRowToWire)

struct C6PDmWireMessage: Codable, Hashable {
    let id: Int
    let c6pVersion: UInt8
    let sessionId: String

    let senderUserId: String?
    let recipientUserId: String?

    let senderDeviceId: String
    let recipientDeviceId: String

    let clientMessageId: String?
    let clientTimestamp: String?
    let serverTimestamp: String?
    let deliveryState: String?

    let ciphertext: String
    let authTag: String
}

struct C6PDmHistoryResponse: Codable {
    let sessionId: String
    let messages: [C6PDmWireMessage]
}

// MARK: - Transport

final class C6PDMTransportService {

    struct Config {
        let apiBaseURL: URL                      // e.g. https://tunnel.convro.eu
        let bearerTokenProvider: () -> String?   // access token (JWT)
    }

    enum TransportError: Error, CustomStringConvertible {
        case authMissing
        case badURL
        case http(status: Int, body: String?)
        case decodeFailed
        case encodeFailed
        case invalidWire(String)

        var description: String {
            switch self {
            case .authMissing: return "TransportError.authMissing"
            case .badURL: return "TransportError.badURL"
            case .http(let s, let b): return "TransportError.http(status=\(s), body=\(b ?? "nil"))"
            case .decodeFailed: return "TransportError.decodeFailed"
            case .encodeFailed: return "TransportError.encodeFailed"
            case .invalidWire(let m): return "TransportError.invalidWire(\(m))"
            }
        }
    }

    private let cfg: Config
    private let http: C6PHTTPPerforming
    private let crypto: C6PSessionService

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(cfg: Config, crypto: C6PSessionService, http: C6PHTTPPerforming = C6PURLSessionHTTP()) {
        self.cfg = cfg
        self.crypto = crypto
        self.http = http
    }

    // MARK: - SEND

    /// Encrypts DM -> POST /v1/dm/messages/send
    /// Returns server db id + reconstructed envelope (same as used for send).
    @discardableResult
    func sendDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) async throws -> (serverDbId: Int, envelope: C6PEnvelope) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        // Encrypt -> envelope (local)
        let envelope = try crypto.encryptDM(
            to: remoteDeviceId,
            suite: suite,
            innerPayload: innerPayload
        )

        guard let url = URL(string: "/v1/dm/messages/send", relativeTo: cfg.apiBaseURL) else {
            throw TransportError.badURL
        }

        // Node expects explicit fields, NOT {"envelope":...}
        let body: [String: Any] = [
            "sessionId": envelope.sessionId.hexString.lowercased(),
            "c6pVersion": Int(envelope.c6pVersion),
            "ciphertext": envelope.sealed.ciphertext.base64EncodedString(),
            "authTag": envelope.sealed.tag.base64EncodedString(),
            "clientMessageId": envelope.clientMessageId,
            "clientTimestampMs": Int64(envelope.clientTimestamp.timeIntervalSince1970 * 1000.0)
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])
        } catch {
            throw TransportError.encodeFailed
        }

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }

        // Node returns mapDbRowToWire (C6PDmWireMessage)
        let decoded: C6PDmWireMessage
        do { decoded = try decoder.decode(C6PDmWireMessage.self, from: data) }
        catch { throw TransportError.decodeFailed }

        return (decoded.id, envelope)
    }

    // MARK: - HISTORY (poll)

    /// GET /v1/dm/messages/history?session_id=&after_id=&limit=
    /// Decrypts what it can and ACKs DELIVERED for successfully decrypted ids.
    func fetchHistoryAndDecrypt(
        sessionId: C6PSessionId,
        remoteDeviceId: C6PDeviceId,
        afterId: Int = 0,
        limit: Int = 50
    ) async throws -> (decrypted: [(dbId: Int, inner: C6PInnerPayload, envelope: C6PEnvelope)], nextAfterId: Int) {

        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }

        guard var comps = URLComponents(url: cfg.apiBaseURL, resolvingAgainstBaseURL: true) else {
            throw TransportError.badURL
        }
        comps.path = "/v1/dm/messages/history"
        comps.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId.hexString.lowercased()),
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

        let decoded: C6PDmHistoryResponse
        do { decoded = try decoder.decode(C6PDmHistoryResponse.self, from: data) }
        catch { throw TransportError.decodeFailed }

        var out: [(Int, C6PInnerPayload, C6PEnvelope)] = []
        var okIds: [Int] = []

        for m in decoded.messages {
            // Reconstruct envelope locally (server does not send it)
            let env = try envelopeFromWire(m)

            do {
                let inner = try crypto.decryptDMInner(from: remoteDeviceId, envelope: env)
                out.append((m.id, inner, env))
                okIds.append(m.id)
            } catch {
                // Strict ordering note:
                // You can choose to continue (skip broken) or break.
                // Conservative: break, so you don't ACK if chain/counters went out.
                break
            }
        }

        if !okIds.isEmpty {
            try await sendReceipts(status: "DELIVERED", messageIds: okIds, bearerToken: token)
        }

        let nextAfter = max(afterId, (decoded.messages.last?.id ?? afterId))
        return (out.map { (dbId: $0.0, inner: $0.1, envelope: $0.2) }, nextAfter)
    }

    // MARK: - RECEIPTS

    func markRead(messageIds: [Int]) async throws {
        let token = cfg.bearerTokenProvider()
        guard let token, !token.isEmpty else { throw TransportError.authMissing }
        try await sendReceipts(status: "READ", messageIds: messageIds, bearerToken: token)
    }

    private func sendReceipts(status: String, messageIds: [Int], bearerToken: String) async throws {
        let ids = Array(Set(messageIds.filter { $0 > 0 })).sorted()
        guard !ids.isEmpty else { return }

        guard let url = URL(string: "/v1/dm/receipts", relativeTo: cfg.apiBaseURL) else {
            throw TransportError.badURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: Any] = [
            "status": status,
            "messageIds": Array(ids.prefix(200))
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await http.perform(req)
        guard (200...299).contains(resp.statusCode) else {
            throw TransportError.http(status: resp.statusCode, body: String(data: data, encoding: .utf8))
        }
    }

    // MARK: - Envelope reconstruction

    private func envelopeFromWire(_ m: C6PDmWireMessage) throws -> C6PEnvelope {
        // Parse IDs (wire sends hex strings)
        let sid = try parseSessionIdHex(m.sessionId)
        let fromDev = try parseDeviceIdHex(m.senderDeviceId)
        let toDev = try parseDeviceIdHex(m.recipientDeviceId)

        let ct = Data(base64Encoded: m.ciphertext) ?? Data()
        let tag = Data(base64Encoded: m.authTag) ?? Data()
        if ct.isEmpty || tag.isEmpty {
            throw TransportError.invalidWire("ciphertext/authTag base64 decode failed")
        }

        let sealed = C6PSealedMessage(ciphertext: ct, tag: tag)

        // clientMessageId and clientTimestamp are optional from server (but should exist)
        let cmid = m.clientMessageId ?? UUID().uuidString
        let cts = Date() // we can ignore wire timestamp for crypto; it's UI-only here

        var env = C6PEnvelope(
            fromDeviceId: fromDev,
            toDeviceId: toDev,
            sessionId: sid,
            sealed: sealed,
            clientMessageId: cmid,
            clientTimestamp: cts
        )
        env.serverMessageId = nil
        env.deliveryState = .pending
        // serverTimestamp optional: keep as string if you want; envelope uses Date? in your model
        return env
    }

    // MARK: - Hex parsing helpers (no guessing, fixed sizes)

    private func parseDeviceIdHex(_ hex: String) throws -> C6PDeviceId {
        let d = try Data(hex: hex, expectedBytes: 8, label: "deviceId")
        return C6PDeviceId(data: d)
    }

    private func parseSessionIdHex(_ hex: String) throws -> C6PSessionId {
        let d = try Data(hex: hex, expectedBytes: 4, label: "sessionId")
        return C6PSessionId(data: d)
    }
}

// MARK: - Data(hex:)

private extension Data {
    init(hex: String, expectedBytes: Int, label: String) throws {
        let s = hex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.count == expectedBytes * 2 else {
            throw C6PDMTransportService.TransportError.invalidWire("\(label) wrong hex length (expected \(expectedBytes*2), got \(s.count))")
        }
        var out = Data()
        out.reserveCapacity(expectedBytes)

        var idx = s.startIndex
        for _ in 0..<expectedBytes {
            let next = s.index(idx, offsetBy: 2)
            let byteStr = s[idx..<next]
            guard let b = UInt8(byteStr, radix: 16) else {
                throw C6PDMTransportService.TransportError.invalidWire("\(label) invalid hex")
            }
            out.append(b)
            idx = next
        }
        self = out
    }
}

