//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  Production-ready DM session service (device-to-device sessions).
//
//  Canon (v1):
//  - handshake99 bootstraps RootKey + ChainKeys (server never computes secrets)
//  - wire envelope is routing metadata only (UNTRUSTED)
//  - integrity binding: extraAAD = C6PWireAAD.envelopeAAD(...)
//  - strict-in-order receive (no wire counter in envelope)
//
//  IMPORTANT:
//  - This file is consistent with:
//      * C6PSessionState (nextI2RCounter/nextR2ICounter)
//      * C6PEnvelope (no counter fields)
//      * C6PHandshake99
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PSessionServiceError: Error, CustomStringConvertible {

    // Envelope validation
    case invalidEnvelopeProtocolVersion(expected: UInt8, actual: UInt8)
    case invalidRecipient(expected: C6PDeviceId, actual: C6PDeviceId)
    case invalidSender(expected: C6PDeviceId, actual: C6PDeviceId)
    case missingSessionForDecryption(remoteDeviceId: C6PDeviceId, sessionId: C6PSessionId)
    case sessionIdMismatch(expected: C6PSessionId, actual: C6PSessionId)

    // Strict ordering / replay
    case incomingCounterRejected(expected: UInt64, stream: C6PStreamId)

    // Payload
    case decodeInnerPayloadFailed
    case encodeInnerPayloadFailed
    case decryptedPayloadNotDM(actual: C6PConversationContext)
    case innerClientMessageIdMismatch(envelope: String, inner: String)

    // Handshake
    case prekeyBundleUnavailable(remoteDeviceId: C6PDeviceId)

    // DM sessions API
    case apiBadURL
    case apiHTTPError(status: Int, body: String?)
    case apiDecodeFailed
    case apiAuthMissing
    case apiOfferNotForThisDevice(expected: C6PDeviceId, actual: C6PDeviceId)
    case missingOneTimePrekeyLocally(otpId: C6PKeyId)

    var description: String {
        switch self {
        case .invalidEnvelopeProtocolVersion(let expected, let actual):
            return "C6PSessionServiceError.invalidEnvelopeProtocolVersion(expected=\(expected), actual=\(actual))"
        case .invalidRecipient(let expected, let actual):
            return "C6PSessionServiceError.invalidRecipient(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .invalidSender(let expected, let actual):
            return "C6PSessionServiceError.invalidSender(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .missingSessionForDecryption(let remote, let sessionId):
            return "C6PSessionServiceError.missingSessionForDecryption(remote=\(remote.hexString), sessionId=\(sessionId.hexString))"
        case .sessionIdMismatch(let expected, let actual):
            return "C6PSessionServiceError.sessionIdMismatch(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .incomingCounterRejected(let expected, let stream):
            return "C6PSessionServiceError.incomingCounterRejected(expected=\(expected), stream=\(stream))"
        case .decodeInnerPayloadFailed:
            return "C6PSessionServiceError.decodeInnerPayloadFailed"
        case .encodeInnerPayloadFailed:
            return "C6PSessionServiceError.encodeInnerPayloadFailed"
        case .decryptedPayloadNotDM(let actual):
            return "C6PSessionServiceError.decryptedPayloadNotDM(actual=\(actual))"
        case .innerClientMessageIdMismatch(let envelope, let inner):
            return "C6PSessionServiceError.innerClientMessageIdMismatch(envelope=\(envelope), inner=\(inner))"
        case .prekeyBundleUnavailable(let remote):
            return "C6PSessionServiceError.prekeyBundleUnavailable(remote=\(remote.hexString))"
        case .apiBadURL:
            return "C6PSessionServiceError.apiBadURL"
        case .apiHTTPError(let status, let body):
            return "C6PSessionServiceError.apiHTTPError(status=\(status), body=\(body ?? "nil"))"
        case .apiDecodeFailed:
            return "C6PSessionServiceError.apiDecodeFailed"
        case .apiAuthMissing:
            return "C6PSessionServiceError.apiAuthMissing"
        case .apiOfferNotForThisDevice(let expected, let actual):
            return "C6PSessionServiceError.apiOfferNotForThisDevice(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .missingOneTimePrekeyLocally(let otpId):
            return "C6PSessionServiceError.missingOneTimePrekeyLocally(otpId=\(otpId.hexString))"
        }
    }
}

// MARK: - Prekey Bundle Provider

typealias C6PPrekeyBundleProvider = (_ remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundle

// MARK: - Minimal HTTP Adapter (injected)

typealias C6PAuthTokenProvider = () -> String?

protocol C6PHTTPPerforming {
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

final class C6PURLSessionHTTP: C6PHTTPPerforming {
    private let session: URLSession
    init(session: URLSession = .shared) { self.session = session }

    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, resp) = try await session.data(for: request)
        guard let http = resp as? HTTPURLResponse else {
            throw C6PSessionServiceError.apiHTTPError(status: -1, body: "Non-HTTP response")
        }
        return (data, http)
    }
}

// MARK: - DM Sessions API DTOs (matches routes.sessions_dm.js)

struct C6PDmIncomingSessionsResponse: Codable {
    struct Item: Codable, Hashable {
        let sessionDbId: Int
        let sessionId: String
        let initiatorUserId: Int
        let initiatorDeviceId: String
        let handshakeOffer: C6PHandshake99Offer
        let createdAt: String
    }
    let sessions: [Item]
}

struct C6PDmAcceptResponse: Codable {
    let ok: Bool
    let sessionDbId: Int
    let sessionId: String
    let state: String
}

// MARK: - Session Service (DM only)

final class C6PSessionService {

    // MARK: - Core

    private let localDeviceId: C6PDeviceId
    private let store: C6PSessionStore
    private let prekeyBundleProvider: C6PPrekeyBundleProvider
    private let remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)?

    // MARK: - DM Sessions API (incoming/accept)

    private let apiBaseURL: URL?
    private let http: C6PHTTPPerforming
    private let authTokenProvider: C6PAuthTokenProvider?

    // MARK: - Coding

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

    // MARK: - Init

    init(
        localDeviceId: C6PDeviceId,
        store: C6PSessionStore,
        prekeyBundleProvider: @escaping C6PPrekeyBundleProvider,
        remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)? = nil,
        apiBaseURL: URL? = nil,
        http: C6PHTTPPerforming = C6PURLSessionHTTP(),
        authTokenProvider: C6PAuthTokenProvider? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.store = store
        self.prekeyBundleProvider = prekeyBundleProvider
        self.remoteIdentityOverrideProvider = remoteIdentityOverrideProvider
        self.apiBaseURL = apiBaseURL
        self.http = http
        self.authTokenProvider = authTokenProvider
    }

    // MARK: - Session lifecycle

    /// Returns active session or creates a new one (initiator) if missing / not active.
    ///
    /// NOTE: this creates LOCAL crypto state only.
    /// Sending handshake offer to backend is done by your higher layer (or add a method later).
    func getOrCreateSession(with remoteDeviceId: C6PDeviceId, suite: C6PEncryptionSuite) throws -> C6PSessionState {

        if var s = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId) {
            switch s.status {
            case .active:
                return s
            case .closed, .needsReHandshake:
                store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
            }
        }

        // Initiator: fetch bundle -> handshake -> persist session
        let bundle: C6PPrekeyBundle
        do {
            bundle = try prekeyBundleProvider(remoteDeviceId)
        } catch {
            throw C6PSessionServiceError.prekeyBundleUnavailable(remoteDeviceId: remoteDeviceId)
        }

        let identityOverride = remoteIdentityOverrideProvider?(remoteDeviceId)

        let hs = try C6PHandshake99.startAsInitiator(
            localDeviceId: localDeviceId,
            prekeyBundle: bundle,
            identityPublicKeyOverride: identityOverride
        )

        var session = C6PSessionState(
            sessionId: hs.sessionId,
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId,
            role: .initiator,
            suite: suite,
            rootKey: hs.rootKey,
            sendChainKey: hs.sendChainKey,
            recvChainKey: hs.recvChainKey,
            nextI2RCounter: 0,
            nextR2ICounter: 0,
            replayPolicy: .strictInOrder,
            receiveWindow: nil,
            createdAt: Date(),
            updatedAt: Date(),
            status: .active
        )

        session.markUpdated()
        store.saveSession(session)
        return session
    }

    // MARK: - Encrypt DM

    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) throws -> C6PEnvelope {

        precondition(innerPayload.context == .dm, "encryptDM requires innerPayload.context == .dm")

        var session = try getOrCreateSession(with: remoteDeviceId, suite: suite)

        // 1) encode inner
        let plaintext: Data
        do {
            plaintext = try encoder.encode(innerPayload)
        } catch {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.encodeInnerPayloadFailed
        }

        // 2) allocate outgoing counter (wire-stable stream)
        let counter = session.allocateOutgoingCounter()

        // 3) message key + nonce
        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.sendChainKey,
            counter: counter,
            messageType: .dm
        )

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: .sending,
            role: session.role,
            messageType: .dm,
            counter: counter
        )

        // 4) wire AAD binding
        let wireAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: C6P_VERSION,
            sessionId: session.sessionId,
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            clientMessageId: innerPayload.clientMessageId
        )

        // 5) seal
        let sealed = try C6PAEAD.seal(
            plaintext: plaintext,
            with: messageKey,
            nonce: nonce,
            sessionId: session.sessionId,
            role: session.role,
            direction: .sending,
            messageType: .dm,
            counter: counter,
            extraAAD: wireAAD
        )

        // 6) build envelope
        let envelope = C6PEnvelope(
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            sealed: sealed,
            clientMessageId: innerPayload.clientMessageId,
            clientTimestamp: innerPayload.clientTimestamp
        )

        // 7) ratchet forward send chain key
        session.sendChainKey = C6PKeySchedule.ratchetChainKeyForward(session.sendChainKey)
        session.markUpdated()
        store.saveSession(session)

        return envelope
    }

    // MARK: - Decrypt DM (strict in-order)

    func decryptDMInner(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelope
    ) throws -> C6PInnerPayload {

        // 0) protocol version
        guard envelope.c6pVersion == C6P_VERSION else {
            throw C6PSessionServiceError.invalidEnvelopeProtocolVersion(expected: C6P_VERSION, actual: envelope.c6pVersion)
        }

        // 1) recipient
        guard envelope.toDeviceId == localDeviceId else {
            throw C6PSessionServiceError.invalidRecipient(expected: localDeviceId, actual: envelope.toDeviceId)
        }

        // 2) sender
        guard envelope.fromDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.invalidSender(expected: remoteDeviceId, actual: envelope.fromDeviceId)
        }

        // 3) load session
        guard var session = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId) else {
            throw C6PSessionServiceError.missingSessionForDecryption(remoteDeviceId: remoteDeviceId, sessionId: envelope.sessionId)
        }

        // 4) sessionId must match
        guard session.sessionId == envelope.sessionId else {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.sessionIdMismatch(expected: session.sessionId, actual: envelope.sessionId)
        }

        // 5) STRICT: expected counter comes from local session state
        let stream = session.localRecvStream
        let expectedCounter = session.expectedIncomingCounter(for: stream)

        // 6) key + nonce
        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.recvChainKey,
            counter: expectedCounter,
            messageType: .dm
        )

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: .receiving,
            role: session.role,
            messageType: .dm,
            counter: expectedCounter
        )

        // 7) wire AAD binding MUST match sender
        let wireAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: envelope.c6pVersion,
            sessionId: envelope.sessionId,
            fromDeviceId: envelope.fromDeviceId,
            toDeviceId: envelope.toDeviceId,
            clientMessageId: envelope.clientMessageId
        )

        // 8) open
        let plaintext: Data
        do {
            plaintext = try C6PAEAD.open(
                sealed: envelope.sealed,
                with: messageKey,
                nonce: nonce,
                sessionId: session.sessionId,
                role: session.role,
                direction: .receiving,
                messageType: .dm,
                counter: expectedCounter,
                extraAAD: wireAAD
            )
        } catch {
            // Fail-closed
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw error
        }

        // 9) decode inner
        let inner: C6PInnerPayload
        do {
            inner = try decoder.decode(C6PInnerPayload.self, from: plaintext)
        } catch {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.decodeInnerPayloadFailed
        }

        // 10) enforce DM
        guard inner.context == .dm else {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.decryptedPayloadNotDM(actual: inner.context)
        }

        // 11) sanity: ids
        guard inner.clientMessageId == envelope.clientMessageId else {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.innerClientMessageIdMismatch(
                envelope: envelope.clientMessageId,
                inner: inner.clientMessageId
            )
        }

        // 12) accept counter (strict)
        guard session.acceptIncomingCounter(expectedCounter, for: stream) else {
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.incomingCounterRejected(expected: expectedCounter, stream: stream)
        }

        // 13) ratchet recv chain key
        session.recvChainKey = C6PKeySchedule.ratchetChainKeyForward(session.recvChainKey)
        session.markUpdated()
        store.saveSession(session)

        return inner
    }

    // MARK: - DM Sessions API (incoming + accept)

    /// GET /v1/dm/sessions/incoming
    func fetchIncomingDmSessions() async throws -> [C6PDmIncomingSessionsResponse.Item] {
        guard let base = apiBaseURL else { throw C6PSessionServiceError.apiBadURL }
        guard let token = authTokenProvider?() else { throw C6PSessionServiceError.apiAuthMissing }

        guard let url = URL(string: "/v1/dm/sessions/incoming", relativeTo: base) else {
            throw C6PSessionServiceError.apiBadURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, httpResp) = try await http.perform(req)
        guard (200...299).contains(httpResp.statusCode) else {
            throw C6PSessionServiceError.apiHTTPError(
                status: httpResp.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        do {
            let decoded = try decoder.decode(C6PDmIncomingSessionsResponse.self, from: data)
            return decoded.sessions
        } catch {
            throw C6PSessionServiceError.apiDecodeFailed
        }
    }

    /// POST /v1/dm/sessions/accept  { sessionDbId }
    func markIncomingAccepted(sessionDbId: Int) async throws {
        guard let base = apiBaseURL else { throw C6PSessionServiceError.apiBadURL }
        guard let token = authTokenProvider?() else { throw C6PSessionServiceError.apiAuthMissing }

        guard let url = URL(string: "/v1/dm/sessions/accept", relativeTo: base) else {
            throw C6PSessionServiceError.apiBadURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let bodyObj: [String: Any] = ["sessionDbId": sessionDbId]
        req.httpBody = try JSONSerialization.data(withJSONObject: bodyObj, options: [])

        let (data, httpResp) = try await http.perform(req)
        guard (200...299).contains(httpResp.statusCode) else {
            throw C6PSessionServiceError.apiHTTPError(
                status: httpResp.statusCode,
                body: String(data: data, encoding: .utf8)
            )
        }

        // optional decode (nice-to-have)
        _ = try? decoder.decode(C6PDmAcceptResponse.self, from: data)
    }

    // MARK: - Accept incoming offer (Responder) — full canonical flow

    /// Canon accept:
    /// - compute secrets locally
    /// - persist session
    /// - consume OTP locally
    /// - mark backend ACTIVE
    @discardableResult
    func acceptIncomingDmSession(
        incoming: C6PDmIncomingSessionsResponse.Item,
        suite: C6PEncryptionSuite,
        signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        oneTimePrekeyProvider: (_ otpId: C6PKeyId) -> Curve25519.KeyAgreement.PrivateKey?,
        consumeOneTimePrekey: (_ otpId: C6PKeyId) -> Void
    ) async throws -> C6PSessionState {

        let offer = incoming.handshakeOffer

        // Offer must target THIS device
        guard offer.responderDeviceId == localDeviceId else {
            throw C6PSessionServiceError.apiOfferNotForThisDevice(
                expected: localDeviceId,
                actual: offer.responderDeviceId
            )
        }

        let remoteDeviceId = offer.initiatorDeviceId

        // If session already exists & matches offer.sessionId -> return it
        if let existing = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId),
           existing.status == .active,
           existing.sessionId == offer.sessionId {
            // still mark backend accepted (safe idempotent if already ACTIVE)
            try? await markIncomingAccepted(sessionDbId: incoming.sessionDbId)
            return existing
        }

        // Prepare OTP map ONLY if referenced
        var otpMap: [C6PKeyId: Curve25519.KeyAgreement.PrivateKey] = [:]
        if let otpId = offer.usedOneTimePrekeyId {
            guard let otpPriv = oneTimePrekeyProvider(otpId) else {
                throw C6PSessionServiceError.missingOneTimePrekeyLocally(otpId: otpId)
            }
            otpMap[otpId] = otpPriv
        }

        // Compute secrets as responder
        let hs = try C6PHandshake99.acceptAsResponder(
            offer: offer,
            localDeviceId: localDeviceId,
            signedPrekeyPrivateKey: signedPrekeyPrivateKey,
            oneTimePrekeys: otpMap
        )

        // Persist session (responder)
        var session = C6PSessionState(
            sessionId: hs.sessionId,
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId,
            role: .responder,
            suite: suite,
            rootKey: hs.rootKey,
            sendChainKey: hs.sendChainKey,
            recvChainKey: hs.recvChainKey,
            nextI2RCounter: 0,
            nextR2ICounter: 0,
            replayPolicy: .strictInOrder,
            receiveWindow: nil,
            createdAt: Date(),
            updatedAt: Date(),
            status: .active
        )
        session.markUpdated()
        store.saveSession(session)

        // Consume OTP locally AFTER success
        if let consumed = hs.consumedOneTimePrekeyId {
            consumeOneTimePrekey(consumed)
        }

        // Mark backend ACTIVE
        try await markIncomingAccepted(sessionDbId: incoming.sessionDbId)

        return session
    }
}
