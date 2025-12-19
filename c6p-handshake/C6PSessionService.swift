//
//  C6PSessionService.swift
//  C6P-Protocol
//
//  High-level client service for managing C6P sessions.
//
//  Responsibilities (v1 ideal):
//  - get/create sessions via Handshake99 + SessionStore
//  - encrypt DM -> C6PEnvelopeDM
//  - decrypt DM from C6PEnvelopeDM
//  - ratchet (chain keys + counters) only after successful crypto
//  - strict validation of envelopes (fail-closed)
//  - deterministic mandatory wire-AAD binding (prevents envelope swapping)
//
//  Notes:
//  - v1 assumes in-order delivery for DM (no heavy out-of-order support).
//  - on crypto mismatch, session is marked NEEDS_REHANDSHAKE.
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PSessionServiceError: Error, CustomStringConvertible {
    case prekeyBundleUnavailable(remoteDeviceId: C6PDeviceId)

    case invalidEnvelopeVersion(expected: UInt8, actual: UInt8)
    case invalidEnvelopeMessageType(C6PMessageType)

    case invalidRecipient(expected: C6PDeviceId, actual: C6PDeviceId)
    case invalidSender(expected: C6PDeviceId, actual: C6PDeviceId)

    case missingSessionForDecryption(sessionId: C6PSessionId)
    case sessionRemoteMismatch(expected: C6PDeviceId, actual: C6PDeviceId)
    case sessionStatusNotActive(status: C6PSessionStatus)

    case sessionIdMismatch(expected: C6PSessionId, actual: C6PSessionId)

    /// Raised when AEAD fails (auth tag mismatch, wrong key/nonce/AAD, corrupted data).
    case decryptFailedAndSessionFlagged(sessionId: C6PSessionId)

    var description: String {
        switch self {
        case .prekeyBundleUnavailable(let remote):
            return "C6PSessionServiceError.prekeyBundleUnavailable(remote=\(remote.hexString))"

        case .invalidEnvelopeVersion(let expected, let actual):
            return "C6PSessionServiceError.invalidEnvelopeVersion(expected=\(expected), actual=\(actual))"
        case .invalidEnvelopeMessageType(let t):
            return "C6PSessionServiceError.invalidEnvelopeMessageType(\(t)) – expected .dm"

        case .invalidRecipient(let expected, let actual):
            return "C6PSessionServiceError.invalidRecipient(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .invalidSender(let expected, let actual):
            return "C6PSessionServiceError.invalidSender(expected=\(expected.hexString), actual=\(actual.hexString))"

        case .missingSessionForDecryption(let sessionId):
            return "C6PSessionServiceError.missingSessionForDecryption(sessionId=\(sessionId.hexString))"
        case .sessionRemoteMismatch(let expected, let actual):
            return "C6PSessionServiceError.sessionRemoteMismatch(expected=\(expected.hexString), actual=\(actual.hexString))"
        case .sessionStatusNotActive(let status):
            return "C6PSessionServiceError.sessionStatusNotActive(status=\(status.rawValue))"

        case .sessionIdMismatch(let expected, let actual):
            return "C6PSessionServiceError.sessionIdMismatch(expected=\(expected.hexString), actual=\(actual.hexString))"

        case .decryptFailedAndSessionFlagged(let sessionId):
            return "C6PSessionServiceError.decryptFailedAndSessionFlagged(sessionId=\(sessionId.hexString))"
        }
    }
}

// MARK: - Prekey Bundle Provider

/// Provider returning a remote device prekey bundle (typically fetched from backend).
typealias C6PPrekeyBundleProvider = (_ remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundle

// MARK: - Session Service

/// High-level session service.
///
/// v1 posture:
/// - 1 active session per (localDeviceId, remoteDeviceId)
/// - DM decrypt expects in-order delivery per session direction
/// - fail-closed: AEAD mismatch -> mark session NEEDS_REHANDSHAKE
final class C6PSessionService {

    // MARK: - Properties

    private let localDeviceId: C6PDeviceId
    private let store: C6PSessionStore
    private let prekeyBundleProvider: C6PPrekeyBundleProvider
    private let remoteIdentityOverrideProvider: ((_ remoteDeviceId: C6PDeviceId) -> Data?)?

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

    /// Load an existing active session with remote device or create a new one (initiator).
    func getOrCreateSession(with remoteDeviceId: C6PDeviceId) throws -> C6PSessionState {

        if var session = store.loadSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId) {
            switch session.status {
            case .active:
                return session
            case .closed, .needsReHandshake:
                store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
            }
        }

        // Need a new handshake as initiator
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
        store.saveSession(session)
        return session
    }

    /// Encrypt DM to a remote device -> returns wire envelope ready for JSON.
    ///
    /// `extraAAD` is optional *additional* authenticated data.
    /// The service already adds mandatory wire-binding AAD (see `makeWireAAD_DM`).
    func encryptDM(
        to remoteDeviceId: C6PDeviceId,
        plaintext: Data,
        extraAAD: Data? = nil
    ) throws -> C6PEnvelopeDM {

        var session = try getOrCreateSession(with: remoteDeviceId)

        guard session.status == .active else {
            throw C6PSessionServiceError.sessionStatusNotActive(status: session.status)
        }

        // v1: DM only
        let messageType: C6PMessageType = .dm
        let direction: C6PDirection = .sending
        let counter = session.sendCounter

        // Generate clientMessageId first so we can bind it in mandatory AAD.
        let clientMessageId = UUID().uuidString

        // Mandatory wire-level AAD binds envelope routing/meta to ciphertext (prevents swapping).
        let mandatoryAAD = try makeWireAAD_DM(
            fromDeviceId: localDeviceId,
            toDeviceId: remoteDeviceId,
            sessionId: session.sessionId,
            clientMessageId: clientMessageId
        )

        let finalExtraAAD = concatAAD(mandatory: mandatoryAAD, extra: extraAAD)

        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.sendChainKey,
            counter: counter,
            messageType: messageType
        )

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: messageType,
            counter: counter
        )

        let sealed = try C6PAEAD.seal(
            plaintext: plaintext,
            with: messageKey,
            nonce: nonce,
            sessionId: session.sessionId,
            role: session.role,
            direction: direction,
            messageType: messageType,
            counter: counter,
            extraAAD: finalExtraAAD
        )

        var envelope = C6PEnvelopeDM(
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

        // Ratchet after successful seal
        session.sendChainKey = C6PKeySchedule.ratchetChainKeyForward(session.sendChainKey)
        session.sendCounter.increment()
        session.markUpdated()
        store.saveSession(session)

        return envelope
    }

    /// Decrypt DM envelope received from backend.
    ///
    /// v1 expects in-order delivery for a given session.
    /// On AEAD mismatch, session is marked NEEDS_REHANDSHAKE (fail-closed).
    func decryptDM(
        envelope: C6PEnvelopeDM,
        extraAAD: Data? = nil
    ) throws -> Data {

        // 1) Strict envelope validation (cheap checks first)
        guard envelope.c6pVersion == C6P_VERSION else {
            throw C6PSessionServiceError.invalidEnvelopeVersion(expected: C6P_VERSION, actual: envelope.c6pVersion)
        }

        guard envelope.messageType == .dm else {
            throw C6PSessionServiceError.invalidEnvelopeMessageType(envelope.messageType)
        }

        guard envelope.toDeviceId == localDeviceId else {
            throw C6PSessionServiceError.invalidRecipient(expected: localDeviceId, actual: envelope.toDeviceId)
        }

        // 2) Load session by (localDeviceId, sessionId) — envelope-driven lookup.
        guard var session = store.loadSession(localDeviceId: localDeviceId, sessionId: envelope.sessionId) else {
            throw C6PSessionServiceError.missingSessionForDecryption(sessionId: envelope.sessionId)
        }

        // 3) Session sanity
        guard session.sessionId == envelope.sessionId else {
            throw C6PSessionServiceError.sessionIdMismatch(expected: session.sessionId, actual: envelope.sessionId)
        }

        guard session.status == .active else {
            throw C6PSessionServiceError.sessionStatusNotActive(status: session.status)
        }

        // Envelope sender must match session.remoteDeviceId (prevents cross-session injection)
        guard envelope.fromDeviceId == session.remoteDeviceId else {
            throw C6PSessionServiceError.sessionRemoteMismatch(
                expected: session.remoteDeviceId,
                actual: envelope.fromDeviceId
            )
        }

        // 4) Derive recv key/nonce for current recv counter
        let direction: C6PDirection = .receiving
        let counter = session.recvCounter
        let messageType: C6PMessageType = .dm

        let messageKey = C6PKeySchedule.deriveMessageKey(
            from: session.recvChainKey,
            counter: counter,
            messageType: messageType
        )

        let nonce = try C6PNonceSequencer.makeNonce(
            sessionId: session.sessionId,
            direction: direction,
            role: session.role,
            messageType: messageType,
            counter: counter
        )

        // Mandatory wire-level AAD must be identical to sender’s for this envelope
        let mandatoryAAD = try makeWireAAD_DM(
            fromDeviceId: envelope.fromDeviceId,
            toDeviceId: envelope.toDeviceId,
            sessionId: envelope.sessionId,
            clientMessageId: envelope.clientMessageId
        )

        let finalExtraAAD = concatAAD(mandatory: mandatoryAAD, extra: extraAAD)

        // 5) AEAD open (fail-closed)
        do {
            let plaintext = try C6PAEAD.open(
                sealed: envelope.sealed,
                with: messageKey,
                nonce: nonce,
                sessionId: session.sessionId,
                role: session.role,
                direction: direction,
                messageType: messageType,
                counter: counter,
                extraAAD: finalExtraAAD
            )

            // Ratchet after successful open
            session.recvChainKey = C6PKeySchedule.ratchetChainKeyForward(session.recvChainKey)
            session.recvCounter.increment()
            session.markUpdated()
            store.saveSession(session)

            return plaintext

        } catch {
            // Mark session as compromised/desynced and fail closed.
            session.markNeedsReHandshake()
            store.saveSession(session)
            throw C6PSessionServiceError.decryptFailedAndSessionFlagged(sessionId: session.sessionId)
        }
    }

    // MARK: - Debug / Maintenance

    func allSessions() -> [C6PSessionState] {
        store.allSessions(for: localDeviceId)
    }

    func resetAllSessions() {
        store.deleteAllSessions()
    }

    func deleteSession(with remoteDeviceId: C6PDeviceId) {
        store.deleteSession(localDeviceId: localDeviceId, remoteDeviceId: remoteDeviceId)
    }

    // MARK: - Mandatory Wire AAD (DM)

    /// Mandatory DM wire-AAD (authenticated, not encrypted) to prevent envelope swapping.
    ///
    /// This binds routing/meta fields already visible on the wire to the ciphertext integrity:
    /// - fromDeviceId
    /// - toDeviceId
    /// - sessionId
    /// - clientMessageId
    ///
    /// IMPORTANT: If you ever change this schema, bump the label/version here.
    private func makeWireAAD_DM(
        fromDeviceId: C6PDeviceId,
        toDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        clientMessageId: String
    ) throws -> Data {
        // Hard cap to keep AAD predictable and avoid memory abuse
        let maxIdBytes = 256
        let idBytes = Array(clientMessageId.utf8)
        let clipped = idBytes.prefix(maxIdBytes)

        var aad = Data()
        aad.append("C6P_WIRE_AAD_DM_V1".data(using: .utf8)!)
        aad.append(C6P_VERSION)
        aad.append(C6PMessageType.dm.rawValue)

        aad.append(fromDeviceId.data)  // 8 bytes
        aad.append(toDeviceId.data)    // 8 bytes
        aad.append(sessionId.data)     // 4 bytes

        aad.appendUInt16BE(UInt16(clipped.count))
        aad.append(contentsOf: clipped)

        return aad
    }

    private func concatAAD(mandatory: Data, extra: Data?) -> Data {
        if let extra, extra.isEmpty == false {
            var out = Data()
            out.append(mandatory)
            out.append(extra)
            return out
        }
        return mandatory
    }
}

// MARK: - Small Data helpers

private extension Data {
    mutating func appendUInt16BE(_ value: UInt16) {
        var be = value.bigEndian
        withUnsafeBytes(of: &be) { buf in
            append(buf.bindMemory(to: UInt8.self))
        }
    }
}

// MARK: - Compatibility bridge (if your MessageKey type still exposes `symmetricKey`)

/// If your current `C6PMessageKey` has only `symmetricKey` (as in your earlier draft),
/// this bridge makes it compatible with `C6PAEAD` expecting `.key` and `.suite`.
///
/// If you already have these fields in the type, remove this extension.
extension C6PMessageKey {
    var key: SymmetricKey { self.symmetricKey }
    var suite: C6PEncryptionSuite { .v1_chachaPoly }
}
