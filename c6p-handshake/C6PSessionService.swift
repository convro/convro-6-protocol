//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  Production E2EE session crypto service for DM transport.
//
//  Key points:
//  - Server is routing-only: NEVER decrypts.
//  - Message shape (dm/group/channel + kind + contextId) lives INSIDE E2EE payload (C6PInnerPayload).
//  - Envelope is UNTRUSTED metadata; integrity binding is via AEAD extraAAD = C6PWireAAD.envelopeAAD(...)
//  - Strict in-order (v1.1): envelope does NOT need to carry counter; receiver uses local expected counter.
//    If a message fails to decrypt, we STOP (do not advance state).
//

import Foundation

// MARK: - Errors

enum C6PSessionServiceError: Error, CustomStringConvertible {
    case sessionNotFound
    case sessionNotActive
    case suiteMismatch(expected: C6PEncryptionSuite, actual: C6PEncryptionSuite)
    case envelopeMismatch(reason: String)
    case encodeFailed
    case decodeFailed
    case decryptFailed

    var description: String {
        switch self {
        case .sessionNotFound: return "C6PSessionServiceError.sessionNotFound"
        case .sessionNotActive: return "C6PSessionServiceError.sessionNotActive"
        case .suiteMismatch(let e, let a): return "C6PSessionServiceError.suiteMismatch(expected=\(e), actual=\(a))"
        case .envelopeMismatch(let r): return "C6PSessionServiceError.envelopeMismatch(\(r))"
        case .encodeFailed: return "C6PSessionServiceError.encodeFailed"
        case .decodeFailed: return "C6PSessionServiceError.decodeFailed"
        case .decryptFailed: return "C6PSessionServiceError.decryptFailed"
        }
    }
}

// MARK: - Service

/// Single responsibility:
/// - take an active C6PSessionState from store
/// - ratchet keys/counters
/// - seal/open DM inner payloads
final class C6PSessionService {

    private let store: C6PSessionStoring
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(store: C6PSessionStoring) {
        self.store = store
        self.encoder = C6PJSON.makeEncoder()
        self.decoder = C6PJSON.makeDecoder()
    }

    // MARK: - Encrypt (DM)

    /// Encrypts inner payload to a wire envelope for Node /v1/dm/messages/send
    ///
    /// Strict v1.1:
    /// - outgoing counter is taken from local session state (nextI2RCounter / nextR2ICounter)
    /// - receiver must process in-order (its expected counter must match)
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        suite: C6PEncryptionSuite,
        innerPayload: C6PInnerPayload
    ) throws -> C6PEnvelope {

        // Load active session
        let localDeviceId = try store.requireActiveLocalDeviceId()
        var session = try store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        guard var session else { throw C6PSessionServiceError.sessionNotFound }
        guard session.state == .active else { throw C6PSessionServiceError.sessionNotActive }
        guard session.suite == suite else { throw C6PSessionServiceError.suiteMismatch(expected: session.suite, actual: suite) }

        // Prepare payload bytes
        guard let payloadData = try? encoder.encode(innerPayload) else {
            throw C6PSessionServiceError.encodeFailed
        }

        // Strict send counter (from local state)
        let counter = currentSendCounterAndAdvance(&session)

        // Derive message key + ratchet chain key (forward secrecy)
        // IMPORTANT: messageType is CRYPTO-level (.dm), not "message kind" (that stays in innerPayload).
        let streamId = session.localSendStream
        let (messageKey, nextChainKey) = try C6PKeySchedule.deriveMessageKeyAndRatchet(
            suite: session.suite,
            sessionId: session.sessionId,
            streamId: streamId,
            messageType: .dm,
            counter: counter,
            chainKey: session.sendChainKey
        )

        // Bind envelope routing metadata into AEAD (fixed-length, safe for server-visible fields)
        let clientMessageId = UUID().uuidString
        let extraAAD = C6PWireAAD.envelopeAAD(
            sessionId: session.sessionId,
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            clientMessageId: clientMessageId
        )

        // Seal
        let sealed: C6PSealedMessage
        do {
            sealed = try C6PAEAD.seal(
                plaintext: payloadData,
                with: messageKey,
                extraAAD: extraAAD
            )
        } catch {
            throw C6PSessionServiceError.decryptFailed
        }

        // Persist ratchet (only after successful seal)
        session.sendChainKey = nextChainKey
        session.updatedAt = Date()
        try store.saveSession(session)

        // Build envelope (routing-only)
        return C6PEnvelope(
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            sealed: sealed,
            clientMessageId: clientMessageId,
            clientTimestamp: Date(),
            serverTimestamp: nil,
            serverMessageId: nil,
            deliveryState: .pending
        )
    }

    // MARK: - Decrypt (DM)

    /// Decrypts envelope into inner payload.
    ///
    /// Strict in-order:
    /// - uses local expected recv counter from session state
    /// - if decrypt fails, DO NOT advance anything
    func decryptDMInner(
        from remoteDeviceId: C6PDeviceId,
        envelope: C6PEnvelope
    ) throws -> C6PInnerPayload {

        // Basic envelope invariants (routing-only, but we still validate hard)
        guard envelope.c6pVersion == C6P_VERSION else {
            throw C6PSessionServiceError.envelopeMismatch(reason: "bad c6pVersion")
        }
        guard envelope.fromDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.envelopeMismatch(reason: "fromDeviceId mismatch")
        }

        let localDeviceId = envelope.toDeviceId

        // Load session for this device pair
        var session = try store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
        guard var session else { throw C6PSessionServiceError.sessionNotFound }
        guard session.state == .active else { throw C6PSessionServiceError.sessionNotActive }

        guard session.sessionId == envelope.sessionId else {
            throw C6PSessionServiceError.envelopeMismatch(reason: "sessionId mismatch")
        }
        guard session.localDeviceId == localDeviceId else {
            throw C6PSessionServiceError.envelopeMismatch(reason: "localDeviceId mismatch")
        }
        guard session.remoteDeviceId == remoteDeviceId else {
            throw C6PSessionServiceError.envelopeMismatch(reason: "remoteDeviceId mismatch")
        }

        // Strict recv counter (expected)
        let counter = currentRecvCounter(&session)

        // Derive message key + next recv chain key, but DO NOT COMMIT unless decrypt succeeds
        let streamId = session.localRecvStream
        let (messageKey, nextChainKey) = try C6PKeySchedule.deriveMessageKeyAndRatchet(
            suite: session.suite,
            sessionId: session.sessionId,
            streamId: streamId,
            messageType: .dm,
            counter: counter,
            chainKey: session.recvChainKey
        )

        // Same binding as sender used
        let extraAAD = C6PWireAAD.envelopeAAD(
            sessionId: session.sessionId,
            fromDeviceId: envelope.fromDeviceId,
            toDeviceId: envelope.toDeviceId,
            clientMessageId: envelope.clientMessageId
        )

        // Open
        let plaintext: Data
        do {
            plaintext = try C6PAEAD.open(
                sealed: envelope.sealed,
                with: messageKey,
                extraAAD: extraAAD
            )
        } catch {
            // Strict: fail closed, do not advance
            throw C6PSessionServiceError.decryptFailed
        }

        // Decode
        guard let inner = try? decoder.decode(C6PInnerPayload.self, from: plaintext) else {
            // NOTE: decrypt ok but payload malformed -> still fail closed and do not ratchet
            throw C6PSessionServiceError.decodeFailed
        }

        // Commit ratchet ONLY after successful decrypt + decode
        advanceRecvCounter(&session)
        session.recvChainKey = nextChainKey
        session.updatedAt = Date()
        try store.saveSession(session)

        return inner
    }

    // MARK: - Counters (strict v1.1)

    /// Returns current send counter and increments session next* counter.
    private func currentSendCounterAndAdvance(_ session: inout C6PSessionState) -> UInt64 {
        // localSendStream depends on role:
        // - initiator sends I->R using nextI2RCounter
        // - responder sends R->I using nextR2ICounter
        switch session.localSendStream {
        case .I_to_R:
            let c = session.nextI2RCounter
            session.nextI2RCounter &+= 1
            return c
        case .R_to_I:
            let c = session.nextR2ICounter
            session.nextR2ICounter &+= 1
            return c
        }
    }

    /// Returns current expected recv counter (does NOT modify).
    private func currentRecvCounter(_ session: inout C6PSessionState) -> UInt64 {
        // localRecvStream depends on role:
        // - initiator receives R->I using nextR2ICounter
        // - responder receives I->R using nextI2RCounter
        switch session.localRecvStream {
        case .I_to_R:
            return session.nextI2RCounter
        case .R_to_I:
            return session.nextR2ICounter
        }
    }

    /// Advances recv counter by +1 for the correct stream.
    private func advanceRecvCounter(_ session: inout C6PSessionState) {
        switch session.localRecvStream {
        case .I_to_R:
            session.nextI2RCounter &+= 1
        case .R_to_I:
            session.nextR2ICounter &+= 1
        }
    }
}
