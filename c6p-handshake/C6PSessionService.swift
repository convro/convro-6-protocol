//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  Production-ready DM session service (device-to-device sessions).
//
//  v1 goals:
//  - DM encryption/decryption using C6PHandshake99 + C6PKeySchedule + C6PAEAD
//  - Wire envelope treated as untrusted
//  - Routing binding to AEAD via Variant A: wireAAD = C6PWireAAD.envelopeAAD(...)
//  - “Shape” (dm/group/channel + event kind) lives ONLY inside E2EE payload (C6PInnerPayload)
//  - Fail closed: any inconsistency => mark session .needsReHandshake and throw
//
//  IMPORTANT CANON v1.1:
//  - Initiator MUST POST handshakeOffer to backend: /v1/dm/sessions/open
//  - Responder polls /v1/dm/sessions/incoming, computes secrets locally, then POST /accept
//

import Foundation

// MARK: - Errors

enum C6PSessionServiceError: Error, CustomStringConvertible {
    case invalidEnvelopeProtocolVersion(expected: UInt8, actual: UInt8)
    case invalidRecipient(expected: C6PDeviceId, actual: C6PDeviceId)
    case invalidSender(expected: C6PDeviceId, actual: C6PDeviceId)
    case missingSessionForDecryption(remoteDeviceId: C6PDeviceId, sessionId: C6PSessionId)
    case sessionIdMismatch(expected: C6PSessionId, actual: C6PSessionId)

    case prekeyBundleUnavailable(remoteDeviceId: C6PDeviceId)
    case dmSessionOpenRejected(reason: String)

    case decryptedPayloadNotDM(actual: C6PConversationContext)
    case innerClientMessageIdMismatch(envelope: String, inner: String)
    case decodeInnerPayloadFailed
    case encodeInnerPayloadFailed

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

        case .prekeyBundleUnavailable(let remote):
            return "C6PSessionServiceError.prekeyBundleUnavailable(remote=\(remote.hexString))"
        case .dmSessionOpenRejected(let reason):
            return "C6PSessionServiceError.dmSessionOpenRejected(\(reason))"

        case .decryptedPayloadNotDM(let actual):
            return "C6PSessionServiceError.decryptedPayloadNotDM(actual=\(actual))"
        case .innerClientMessageIdMismatch(let envelope, let inner):
            return "C6PSessionServiceError.innerClientMessageIdMismatch(envelope=\(envelope), inner=\(inner))"
        case .decodeInnerPayloadFailed:
            return "C6PSessionServiceError.decodeInnerPayloadFailed"
        case .encodeInnerPayloadFailed:
            return "C6PSessionServiceError.encodeInnerPayloadFailed"
        }
    }
}

// MARK: - Providers / API contracts

typealias C6PPrekeyBundleProvider = (_ remoteDeviceId: C6PDeviceId) async throws -> C6PPrekeyBundleContract

protocol C6PDmSessionsAPI {
    /// POST /v1/dm/sessions/open
    func open(peerUserId: Int, handshakeOffer: C6PHandshake99Offer) async throws -> C6PDmSessionOpenResponse

    /// GET /v1/dm/sessions/incoming
    func incoming() async throws -> C6PDmIncomingSessionsResponse

    /// POST /v1/dm/sessions/accept
    func accept(sessionDbId: Int) async throws -> C6PDmSessionAcceptResponse
}

struct C6PDmSessionOpenResponse: Codable, Hashable {
    let ok: Bool
    let sessionDbId: Int
    let sessionId: String
    let responderUserId: Int
    let responderDeviceId: String
    let state: String
}

struct C6PDmIncomingSessionsResponse: Codable, Hashable {
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

struct C6PDmSessionAcceptResponse: Codable, Hashable {
    let ok: Bool
    let sessionDbId: Int
    let sessionId: String
    let state: String
}

// MARK: - Session Service (DM only)

final class C6PSessionService {

    // MARK: - Properties

    private let localDeviceId: C6PDeviceId
    private let store: C6PSessionStore

    private let prekeyBundleProvider: C6PPrekeyBundleProvider
    private let dmApi: C6PDmSessionsAPI

    /// Optional identity pinning / TOFU override
    private let remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)?

    /// Cache
    private var sessionCache: [C6PDeviceId: C6PSessionState] = [:]
    private let cacheQueue = DispatchQueue(label: "c6p.session.service.cache.serial")

    // MARK: - Coding (stable)

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
        dmApi: C6PDmSessionsAPI,
        remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.store = store
        self.prekeyBundleProvider = prekeyBundleProvider
        self.dmApi = dmApi
        self.remoteIdentityOverrideProvider = remoteIdentityOverrideProvider
    }

    // MARK: - Public: Outgoing session (initiator)

    /// Creates (if needed) an initiator session and POSTS handshakeOffer to backend (/open).
    /// Returns local session state; backend session state is PENDING until responder accepts.
    @discardableResult
    func ensureOutgoingSession(
        peerUserId: Int,
        responderDeviceId: C6PDeviceId
    ) async throws -> C6PSessionState {

        // 0) Cache/store: if already active we are done (local)
        if let cached = cacheGet(responderDeviceId), cached.status == .active {
            return cached
        }
        if let existing = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: responderDeviceId),
           existing.status == .active {
            cacheSet(responderDeviceId, existing)
            return existing
        }

        // 1) Fetch bundle (network)
        let bundle: C6PPrekeyBundleContract
        do {
            bundle = try await prekeyBundleProvider(responderDeviceId)
        } catch {
            throw C6PSessionServiceError.prekeyBundleUnavailable(remoteDeviceId: responderDeviceId)
        }

        let identityOverride = remoteIdentityOverrideProvider?(responderDeviceId)

        // 2) Handshake as initiator
        let hs = try C6PHandshake99.startAsInitiator(
            localDeviceId: localDeviceId,
            prekeyBundle: bundle,
            identityPublicKeyOverride: identityOverride
        )

        // 3) Persist local session immediately (so we can encrypt right away)
        var session = C6PSessionState(
            sessionId: hs.sessionId,
            localDeviceId: localDeviceId,
            remoteDeviceId: responderDeviceId,
            role: .initiator,
            rootKey: hs.rootKey,
            sendChainKey: hs.sendChainKey,
            recvChainKey: hs.recvChainKey,
            sendCounter: hs.sendCounter,
            recvCounter: hs.recvCounter
        )
        session.markUpdated()
        persistAndCache(session, remoteDeviceId: responderDeviceId)

        // 4) POST offer to backend (/open) — MUST succeed, otherwise mark needsReHandshake
        do {
            let resp = try await dmApi.open(peerUserId: peerUserId, handshakeOffer: hs.offer)
            guard resp.ok else {
                session.markNeedsReHandshake()
                persistAndCache(session, remoteDeviceId: responderDeviceId)
                throw C6PSessionServiceError.dmSessionOpenRejected(reason: "open returned ok=false")
            }
        } catch {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: responderDeviceId)
            throw error
        }

        return session
    }

    // MARK: - Public: Incoming sessions (responder polling)

    /// Poll incoming offers from backend. You still need to:
    /// - compute acceptAsResponder(...) locally (in your accept handler),
    /// - persist session state,
    /// - then call dmApi.accept(sessionDbId).
    func fetchIncomingSessions() async throws -> [C6PDmIncomingSessionsResponse.Item] {
        let resp = try await dmApi.incoming()
        return resp.sessions
    }

    /// Marks DM session as ACTIVE on backend (after local accept).
    func markIncomingAccepted(sessionDbId: Int) async throws {
        let resp = try await dmApi.accept(sessionDbId: sessionDbId)
        guard resp.ok else {
            throw C6PSessionServiceError.dmSessionOpenRejected(reason: "accept returned ok=false")
        }
    }

    // MARK: Encrypt DM (high-level)

    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        kind: C6PEventKind,
        body: Data,
        clientMessageId: String = UUID().uuidString,
        clientTimestamp: Date = Date()
    ) async throws -> C6PEnvelope {

        let inner = C6PInnerPayload(
            context: .dm,
            kind: kind,
            contextId: nil,
            clientMessageId: clientMessageId,
            clientTimestamp: clientTimestamp,
            body: body
        )
        return try await encryptDM(to: remoteDeviceId, innerPayload: inner)
    }

    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        innerPayload: C6PInnerPayload
    ) async throws -> C6PEnvelope {

        precondition(innerPayload.context == .dm, "C6PSessionService encryptDM requires innerPayload.context == .dm")

        // NOTE:
        // This method assumes session already exists OR you created it via ensureOutgoingSession(...)
        // If you want auto-create here, you MUST supply peerUserId somewhere above this layer.

        // 1) Session must exist
        guard var session = cacheGet(remoteDeviceId) ??
                store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        else {
            throw C6PSessionServiceError.prekeyBundleUnavailable(remoteDeviceId: remoteDeviceId)
        }

        // 2) Encode inner payload
        let plaintext: Data
        do {
            plaintext = try encoder.encode(innerPayload)
        } catch {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.encodeInnerPayloadFailed
        }

        // 3) Message key + nonce (DM context => messageType .dm)
        let counter = session.sendCounter
        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.sendChainKey,
            counter: counter,
            messageType: .dm
        )

        let direction: C6PDirection = .sending

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: .dm,
            counter: counter
        )

        // 4) Wire AAD binding (Variant A)
        let wireAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: C6P_VERSION,
            sessionId: session.sessionId,
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            clientMessageId: innerPayload.clientMessageId
        )

        // 5) AEAD seal
        let sealed = try C6PAEAD.seal(
            plaintext: plaintext,
            with: messageKey,
            nonce: nonce,
            sessionId: session.sessionId,
            role: session.role,
            direction: direction,
            messageType: .dm,
            counter: counter,
            extraAAD: wireAAD
        )

        // 6) Build envelope
        let envelope = C6PEnvelope(
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            sealed: sealed,
            clientMessageId: innerPayload.clientMessageId,
            clientTimestamp: innerPayload.clientTimestamp
        )

        // 7) Ratchet forward (SEND)
        session.sendChainKey = C6PKeySchedule.ratchetChainKeyForward(session.sendChainKey)
        session.sendCounter.increment()
        session.markUpdated()
        persistAndCache(session, remoteDeviceId: remoteDeviceId)

        return envelope
    }

    // MARK: Decrypt DM (high-level)

    func decryptDMInner(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelope
    ) throws -> C6PInnerPayload {

        guard envelope.c6pVersion == C6P_VERSION else {
            throw C6PSessionServiceError.invalidEnvelopeProtocolVersion(expected: C6P_VERSION, actual: envelope.c6pVersion)
        }
        guard envelope.toDeviceId == localDeviceId else {
            throw C6PSessionServiceError.invalidRecipient(expected: localDeviceId, actual: envelope.toDeviceId)
        }
        guard envelope.fromDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.invalidSender(expected: remoteDeviceId, actual: envelope.fromDeviceId)
        }

        guard var session = cacheGet(remoteDeviceId) ??
                store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        else {
            throw C6PSessionServiceError.missingSessionForDecryption(
                remoteDeviceId: remoteDeviceId,
                sessionId: envelope.sessionId
            )
        }

        guard session.sessionId == envelope.sessionId else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.sessionIdMismatch(expected: session.sessionId, actual: envelope.sessionId)
        }

        let counter = session.recvCounter
        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.recvChainKey,
            counter: counter,
            messageType: .dm
        )

        let direction: C6PDirection = .receiving

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: .dm,
            counter: counter
        )

        let wireAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: envelope.c6pVersion,
            sessionId: envelope.sessionId,
            fromDeviceId: envelope.fromDeviceId,
            toDeviceId: envelope.toDeviceId,
            clientMessageId: envelope.clientMessageId
        )

        let plaintext: Data
        do {
            plaintext = try C6PAEAD.open(
                sealed: envelope.sealed,
                with: messageKey,
                nonce: nonce,
                sessionId: session.sessionId,
                role: session.role,
                direction: direction,
                messageType: .dm,
                counter: counter,
                extraAAD: wireAAD
            )
        } catch {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw error
        }

        let inner: C6PInnerPayload
        do {
            inner = try decoder.decode(C6PInnerPayload.self, from: plaintext)
        } catch {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.decodeInnerPayloadFailed
        }

        guard inner.context == .dm else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.decryptedPayloadNotDM(actual: inner.context)
        }

        guard inner.clientMessageId == envelope.clientMessageId else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.innerClientMessageIdMismatch(
                envelope: envelope.clientMessageId,
                inner: inner.clientMessageId
            )
        }

        session.recvChainKey = C6PKeySchedule.ratchetChainKeyForward(session.recvChainKey)
        session.recvCounter.increment()
        session.markUpdated()
        persistAndCache(session, remoteDeviceId: remoteDeviceId)

        return inner
    }

    func decryptDMBody(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelope
    ) throws -> (kind: C6PEventKind, body: Data, clientMessageId: String, clientTimestamp: Date) {

        let inner = try decryptDMInner(from: remoteDeviceId, envelope: envelope)
        return (inner.kind, inner.body, inner.clientMessageId, inner.clientTimestamp)
    }

    // MARK: - Debug / Maintenance

    func allSessions() -> [C6PSessionState] {
        store.allSessions(for: localDeviceId)
    }

    func resetAllSessions() {
        store.deleteAllSessions()
        cacheQueue.sync { sessionCache.removeAll() }
    }

    func deleteSession(with remoteDeviceId: C6PDeviceId) {
        store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        cacheRemove(remoteDeviceId)
    }

    // MARK: - Cache + Persistence

    private func cacheGet(_ remoteDeviceId: C6PDeviceId) -> C6PSessionState? {
        cacheQueue.sync { sessionCache[remoteDeviceId] }
    }

    private func cacheSet(_ remoteDeviceId: C6PDeviceId, _ session: C6PSessionState) {
        cacheQueue.sync { sessionCache[remoteDeviceId] = session }
    }

    private func cacheRemove(_ remoteDeviceId: C6PDeviceId) {
        cacheQueue.sync { sessionCache.removeValue(forKey: remoteDeviceId) }
    }

    private func persistAndCache(_ session: C6PSessionState, remoteDeviceId: C6PDeviceId) {
        cacheSet(remoteDeviceId, session)
        store.saveSession(session)
    }
}
