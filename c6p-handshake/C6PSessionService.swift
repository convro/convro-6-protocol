//
//  C6PSessionService.swift
//  Convro-6-Protocol (C6P)
//
//  CANONICAL v1.2 (production)
//
//  Responsibilities:
//  - Load/validate session state (C6PSessionStore)
//  - Derive per-message key deterministically from chain key + (sessionId, streamId, messageType, counter)
//  - Seal/open with C6PAEAD using extraAAD = C6PWireAAD.envelopeAAD(...)
//  - Strict counter acceptance + atomic session updates (store.saveSession)
//
//  NOTE:
//  This service enforces STRICT_IN_ORDER semantics (v1).
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PSessionServiceError: Error, LocalizedError, CustomStringConvertible {
    case sessionNotFound
    case sessionNotActive(state: C6PSessionStatus)
    case suiteMismatch(expected: C6PEncryptionSuite, got: C6PEncryptionSuite)
    case deviceMismatch
    case remoteMismatch
    case streamMismatch(expected: C6PStreamId, got: C6PStreamId)
    case counterRejected(expected: UInt64, got: UInt64)
    case innerDecodeFailed
    case innerClientMessageIdMismatch
    case sealEncodeFailed
    case openFailed(underlying: Error)

    var errorDescription: String? { description }

    var description: String {
        switch self {
        case .sessionNotFound:
            return "C6PSessionServiceError.sessionNotFound"
        case .sessionNotActive(let s):
            return "C6PSessionServiceError.sessionNotActive(state=\(s.rawValue))"
        case .suiteMismatch(let e, let g):
            return "C6PSessionServiceError.suiteMismatch(expected=\(e), got=\(g))"
        case .deviceMismatch:
            return "C6PSessionServiceError.deviceMismatch (envelope.toDeviceId != localDeviceId)"
        case .remoteMismatch:
            return "C6PSessionServiceError.remoteMismatch (envelope.fromDeviceId != expected remoteDeviceId)"
        case .streamMismatch(let e, let g):
            return "C6PSessionServiceError.streamMismatch(expected=\(e), got=\(g))"
        case .counterRejected(let e, let g):
            return "C6PSessionServiceError.counterRejected(expected=\(e), got=\(g))"
        case .innerDecodeFailed:
            return "C6PSessionServiceError.innerDecodeFailed"
        case .innerClientMessageIdMismatch:
            return "C6PSessionServiceError.innerClientMessageIdMismatch"
        case .sealEncodeFailed:
            return "C6PSessionServiceError.sealEncodeFailed"
        case .openFailed(let u):
            return "C6PSessionServiceError.openFailed(underlying=\(u))"
        }
    }
}

// MARK: - Service

final class C6PSessionService {

    // MARK: Config

    struct Config {
        /// Local device id (this client device).
        let localDeviceId: C6PDeviceId

        /// If true, verifies innerPayload.clientMessageId == envelope.clientMessageId.
        let enforceInnerClientMessageIdBinding: Bool

        init(
            localDeviceId: C6PDeviceId,
            enforceInnerClientMessageIdBinding: Bool = true
        ) {
            self.localDeviceId = localDeviceId
            self.enforceInnerClientMessageIdBinding = enforceInnerClientMessageIdBinding
        }
    }

    private let cfg: Config
    private let store: C6PSessionStore

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

    init(cfg: Config, store: C6PSessionStore) {
        self.cfg = cfg
        self.store = store
    }

    // MARK: - Public: Session helpers

    func loadSession(with remoteDeviceId: C6PDeviceId) -> C6PSessionState? {
        store.loadSession(localDeviceId: cfg.localDeviceId, remoteDeviceId: remoteDeviceId)
    }

    func saveSession(_ session: C6PSessionState) {
        store.saveSession(session)
    }

    func deleteSession(with remoteDeviceId: C6PDeviceId) {
        store.deleteSession(localDeviceId: cfg.localDeviceId, remoteDeviceId: remoteDeviceId)
    }

    // MARK: - DM Encrypt (InnerPayload -> EnvelopeDM)

    /// Encrypts DM inner payload into DM envelope.
    ///
    /// Requires an ACTIVE session for (localDeviceId, remoteDeviceId).
    /// Uses strict counters and advances send chain key atomically.
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload,
        messageType: C6PMessageType = .dm   // <-- jeśli w Twoim enum nazywa się inaczej, zmień TYLKO to
    ) throws -> C6PEnvelopeDM {

        var session = try mustLoadActiveSession(remoteDeviceId: remoteDeviceId)

        // suite must match negotiated session suite
        guard session.suite == suite else {
            throw C6PSessionServiceError.suiteMismatch(expected: session.suite, got: suite)
        }

        // allocate counter (and bump session timestamps)
        let counter = session.allocateOutgoingCounter()
        let streamId = session.localSendStream

        // encode plaintext
        let plaintext: Data
        do {
            plaintext = try encoder.encode(innerPayload)
        } catch {
            throw C6PSessionServiceError.sealEncodeFailed
        }

        // derive per-message key and next chain key (strict in-order)
        let derived = try deriveMessageKeyAndAdvanceChainKey(
            chainKey: &session.sendChainKey,
            suite: suite,
            sessionId: session.sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter
        )

        // extraAAD binds envelope routing metadata (server-visible) to AEAD tag
        // (prevents server rewriting from/to/session/clientMessageId without detection)
        let extraAAD = C6PWireAAD.envelopeAAD(
            c6pVersion: C6P_VERSION,
            sessionId: session.sessionId,
            fromDeviceId: cfg.localDeviceId,
            toDeviceId: remoteDeviceId,
            clientMessageId: innerPayload.clientMessageId
        )

        let sealed: C6PSealedMessage
        do {
            sealed = try C6PAEAD.seal(
                plaintext: plaintext,
                with: derived.messageKey,
                extraAAD: extraAAD
            )
        } catch {
            throw C6PSessionServiceError.openFailed(underlying: error)
        }

        // persist updated session (counter + advanced sendChainKey)
        store.saveSession(session)

        // Build DM envelope.
        //
        // IMPORTANT: This assumes your C6PEnvelopeDM carries:
        //  - c6pVersion, fromDeviceId, toDeviceId, sessionId
        //  - suite, streamId, messageType, counter
        //  - sealed (ciphertext+tag)
        //  - clientMessageId, clientTimestamp (+ optional server fields)
        //
        // If your property names differ, adjust ONLY this initializer mapping.
        let env = C6PEnvelopeDM(
            fromDeviceId: cfg.localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            suite: suite,
            streamId: streamId,
            messageType: messageType,
            counter: counter,
            sealed: sealed,
            clientMessageId: innerPayload.clientMessageId,
            clientTimestamp: innerPayload.clientTimestamp
        )

        return env
    }

    // MARK: - DM Decrypt (EnvelopeDM -> InnerPayload)

    /// Decrypts DM envelope into inner payload.
    ///
    /// Enforces:
    /// - envelope.toDeviceId == localDeviceId
    /// - remoteDeviceId matches envelope.fromDeviceId
    /// - session exists + ACTIVE
    /// - streamId matches expected local receive stream
    /// - counter matches expected (strict in-order)
    /// - advances recv chain key only after successful decrypt + accept counter
    func decryptDMInner(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelopeDM
    ) throws -> C6PInnerPayload {

        // basic routing sanity
        guard envelope.toDeviceId == cfg.localDeviceId else {
            throw C6PSessionServiceError.deviceMismatch
        }
        guard envelope.fromDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.remoteMismatch
        }

        // session lookup MUST be by (localDeviceId, sessionId) for wire envelopes
        guard var session = store.loadSession(localDeviceId: cfg.localDeviceId, sessionId: envelope.sessionId) else {
            throw C6PSessionServiceError.sessionNotFound
        }
        guard session.status == .active else {
            throw C6PSessionServiceError.sessionNotActive(state: session.status)
        }

        // suite must match
        guard session.suite == envelope.suite else {
            throw C6PSessionServiceError.suiteMismatch(expected: session.suite, got: envelope.suite)
        }

        // stream must be the expected incoming stream for this local role
        let expectedStream = session.localRecvStream
        guard envelope.streamId == expectedStream else {
            throw C6PSessionServiceError.streamMismatch(expected: expectedStream, got: envelope.streamId)
        }

        // strict counter check BEFORE decrypt (prevents key advancement on junk)
        let expectedCounter = session.expectedIncomingCounter(for: envelope.streamId)
        guard envelope.counter == expectedCounter else {
            throw C6PSessionServiceError.counterRejected(expected: expectedCounter, got: envelope.counter)
        }

        // derive message key from current recvChainKey (same derivation as sender)
        let derived = try deriveMessageKeyAndAdvanceChainKey(
            chainKey: &session.recvChainKey,
            suite: envelope.suite,
            sessionId: session.sessionId,
            streamId: envelope.streamId,
            messageType: envelope.messageType,
            counter: envelope.counter
        )

        // extraAAD binding must match sender side exactly
        let extraAAD = C6PWireAAD.envelopeAAD(
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
                with: derived.messageKey,
                extraAAD: extraAAD
            )
        } catch {
            // do NOT mutate stored session on failure
            throw C6PSessionServiceError.openFailed(underlying: error)
        }

        // decode inner
        let inner: C6PInnerPayload
        do {
            inner = try decoder.decode(C6PInnerPayload.self, from: plaintext)
        } catch {
            throw C6PSessionServiceError.innerDecodeFailed
        }

        // optional: ensure inner clientMessageId matches outer (defense in depth)
        if cfg.enforceInnerClientMessageIdBinding {
            guard inner.clientMessageId == envelope.clientMessageId else {
                throw C6PSessionServiceError.innerClientMessageIdMismatch
            }
        }

        // accept counter (mutates session counters) AFTER successful open+decode
        let accepted = session.acceptIncomingCounter(envelope.counter, for: envelope.streamId)
        guard accepted else {
            throw C6PSessionServiceError.counterRejected(expected: expectedCounter, got: envelope.counter)
        }

        // persist updated session (recvChainKey advanced + counters bumped)
        store.saveSession(session)

        return inner
    }

    // MARK: - Internals

    private func mustLoadActiveSession(remoteDeviceId: C6PDeviceId) throws -> C6PSessionState {
        guard let s = store.loadSession(localDeviceId: cfg.localDeviceId, remoteDeviceId: remoteDeviceId) else {
            throw C6PSessionServiceError.sessionNotFound
        }
        guard s.status == .active else {
            throw C6PSessionServiceError.sessionNotActive(state: s.status)
        }
        return s
    }

    private struct DerivedKeyResult {
        let messageKey: C6PMessageKey
    }

    /// Deterministic key derivation:
    /// messageKey  = HKDF(chainKey.key, info = "C6P_MSG" + ctx)
    /// nextChainKey = HKDF(chainKey.key, info = "C6P_CK" + ctx)
    ///
    /// ctx binds: sessionId + streamId + messageType + counter
    ///
    /// v1 strict-in-order => we can safely advance chainKey per message.
    private func deriveMessageKeyAndAdvanceChainKey(
        chainKey: inout C6PChainKey,
        suite: C6PEncryptionSuite,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: UInt64
    ) throws -> DerivedKeyResult {

        // This assumes C6PChainKey has mutable `key: SymmetricKey`.
        // If your field name differs, change ONLY these two lines:
        let ck = chainKey.key
        let ctx = buildKdfContext(sessionId: sessionId, streamId: streamId, messageType: messageType, counter: counter)

        // message key
        let mk = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ck,
            salt: SymmetricKey(data: Data("C6P_SALT_V1".utf8)),
            info: Data("C6P_MSG_V1".utf8) + ctx,
            outputByteCount: 32
        )

        // next chain key
        let nextCk = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: ck,
            salt: SymmetricKey(data: Data("C6P_SALT_V1".utf8)),
            info: Data("C6P_CK_V1".utf8) + ctx,
            outputByteCount: 32
        )

        // advance chain key atomically in memory (store.saveSession done by caller)
        chainKey.key = nextCk

        let messageKey = C6PMessageKey(
            suite: suite,
            sessionId: sessionId,
            streamId: streamId,
            messageType: messageType,
            counter: counter,
            key: mk
        )

        return DerivedKeyResult(messageKey: messageKey)
    }

    private func buildKdfContext(
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: UInt64
    ) -> Data {
        var data = Data()
        data.reserveCapacity(4 + 1 + 1 + 8)

        data.append(sessionId.data)       // 4 bytes (v1)
        data.append(streamId.rawValue)    // 1
        data.append(messageType.rawValue) // 1

        var be = counter.bigEndian
        withUnsafeBytes(of: &be) { data.append(contentsOf: $0) } // 8

        return data
    }
}
