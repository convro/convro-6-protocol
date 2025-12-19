//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  Production-ready DM session service (device-to-device sessions).
//
//  v1 goals:
//  - DM encryption/decryption using existing C6PHandshake99 + C6PKeySchedule + C6PAEAD
//  - Wire envelope is metadata-minimal (C6PEnvelope) and treated as untrusted
//  - Routing binding to AEAD via Variant A: wireAAD = C6PWireAAD.envelopeAAD(...)
//  - “Shape” (dm/group/channel + event kind) lives ONLY inside E2EE payload (C6PInnerPayload)
//  - Fail closed: any inconsistency => mark session .needsReHandshake and throw
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

// MARK: - Prekey Bundle Provider

typealias C6PPrekeyBundleProvider = (_ remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundle

// MARK: - Session Service (DM only)

final class C6PSessionService {

    // MARK: - Properties

    private let localDeviceId: C6PDeviceId
    private let store: C6PSessionStore
    private let prekeyBundleProvider: C6PPrekeyBundleProvider
    private let remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)?

    /// In-process cache to avoid relying on store write timing (some stores may be async internally).
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
        remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)? = nil
    ) {
        self.localDeviceId = localDeviceId
        self.store = store
        self.prekeyBundleProvider = prekeyBundleProvider
        self.remoteIdentityOverrideProvider = remoteIdentityOverrideProvider
    }

    // MARK: - Public API

    /// Returns active session or creates a new one (initiator) if missing / not active.
    func getOrCreateSession(with remoteDeviceId: C6PDeviceId) throws -> C6PSessionState {
        // 0) Cache first
        if let cached = cacheGet(remoteDeviceId), cached.status == .active {
            return cached
        }

        // 1) Store
        if var session = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId) {
            switch session.status {
            case .active:
                cacheSet(remoteDeviceId, session)
                return session
            case .closed, .needsReHandshake:
                store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
                cacheRemove(remoteDeviceId)
            }
        }

        // 2) Need new handshake as initiator
        let bundle: C6PPrekeyBundle
        do {
            bundle = try prekeyBundleProvider(remoteDeviceId)
        } catch {
            throw C6PSessionServiceError.prekeyBundleUnavailable(remoteDeviceId: remoteDeviceId)
        }

        let identityOverride = remoteIdentityOverrideProvider?(remoteDeviceId)

        let result = try C6PHandshake99.startAsInitiator(
            localDeviceId: localDeviceId,
            prekeyBundle: bundle,
            identityPublicKeyOverride: identityOverride
        )

        var session = C6PSessionState(
            sessionId: result.sessionId,
            localDeviceId: localDeviceId,
            remoteDeviceId: remoteDeviceId,
            role: .initiator,
            rootKey: result.rootKey,
            sendChainKey: result.sendChainKey,
            recvChainKey: result.recvChainKey,
            sendCounter: result.sendCounter,
            recvCounter: result.recvCounter
        )

        session.markUpdated()
        persistAndCache(session, remoteDeviceId: remoteDeviceId)
        return session
    }

    // MARK: Encrypt DM (high-level)

    /// Convenience: encrypt a DM event (inner payload built here).
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        kind: C6PEventKind,
        body: Data,
        clientMessageId: String = UUID().uuidString,
        clientTimestamp: Date = Date()
    ) throws -> C6PEnvelope {

        let inner = C6PInnerPayload(
            context: .dm,
            kind: kind,
            contextId: nil,
            clientMessageId: clientMessageId,
            clientTimestamp: clientTimestamp,
            body: body
        )
        return try encryptDM(to: remoteDeviceId, innerPayload: inner)
    }

    /// Encrypt DM using a fully prepared inner payload (must be .dm).
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        innerPayload: C6PInnerPayload
    ) throws -> C6PEnvelope {

        precondition(innerPayload.context == .dm, "C6PSessionService encryptDM requires innerPayload.context == .dm")

        // 1) Session
        var session = try getOrCreateSession(with: remoteDeviceId)

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

        // 5) AEAD seal (extraAAD = wireAAD)
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

    /// Decrypts envelope and returns decoded inner payload (must be .dm).
    func decryptDMInner(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelope
    ) throws -> C6PInnerPayload {

        // 0) Fail closed if protocol version mismatch
        guard envelope.c6pVersion == C6P_VERSION else {
            throw C6PSessionServiceError.invalidEnvelopeProtocolVersion(expected: C6P_VERSION, actual: envelope.c6pVersion)
        }

        // 1) Envelope recipient check
        guard envelope.toDeviceId == localDeviceId else {
            throw C6PSessionServiceError.invalidRecipient(expected: localDeviceId, actual: envelope.toDeviceId)
        }

        // 2) Sender check (caller passes “remoteDeviceId”, envelope must match)
        guard envelope.fromDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.invalidSender(expected: remoteDeviceId, actual: envelope.fromDeviceId)
        }

        // 3) Load session
        guard var session = cacheGet(remoteDeviceId) ??
            store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        else {
            throw C6PSessionServiceError.missingSessionForDecryption(
                remoteDeviceId: remoteDeviceId,
                sessionId: envelope.sessionId
            )
        }

        // 4) sessionId must match
        guard session.sessionId == envelope.sessionId else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.sessionIdMismatch(expected: session.sessionId, actual: envelope.sessionId)
        }

        // 5) Message key + nonce (DM context => messageType .dm)
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

        // 6) Wire AAD binding (Variant A) — MUST match what sender used
        let wireAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: envelope.c6pVersion,
            sessionId: envelope.sessionId,
            fromDeviceId: envelope.fromDeviceId,
            toDeviceId: envelope.toDeviceId,
            clientMessageId: envelope.clientMessageId
        )

        // 7) AEAD open
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
            // Fail closed: mark for re-handshake (potential corruption / attack / out-of-order)
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw error
        }

        // 8) Decode inner payload
        let inner: C6PInnerPayload
        do {
            inner = try decoder.decode(C6PInnerPayload.self, from: plaintext)
        } catch {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.decodeInnerPayloadFailed
        }

        // 9) Must be DM (shape is encrypted, but we enforce the service contract)
        guard inner.context == .dm else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.decryptedPayloadNotDM(actual: inner.context)
        }

        // 10) Sanity: message id should match envelope (collision practically impossible with AAD hash, but check anyway)
        guard inner.clientMessageId == envelope.clientMessageId else {
            session.markNeedsReHandshake()
            persistAndCache(session, remoteDeviceId: remoteDeviceId)
            throw C6PSessionServiceError.innerClientMessageIdMismatch(envelope: envelope.clientMessageId, inner: inner.clientMessageId)
        }

        // 11) Ratchet forward (RECV)
        session.recvChainKey = C6PKeySchedule.ratchetChainKeyForward(session.recvChainKey)
        session.recvCounter.increment()
        session.markUpdated()
        persistAndCache(session, remoteDeviceId: remoteDeviceId)

        return inner
    }

    /// Decrypt DM and returns raw body (innerPayload.body).
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

