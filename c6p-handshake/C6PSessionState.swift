//
//  C6PSessionState.swift
//  Convro-6-Protocol (C6P)
//
//  Full device-to-device session state.
//  Stored locally (Keychain/file/db), restored on app startup.
//
//  C6P sessions are device-scoped (multi-device by design).
//  Crypto properties are enforced client-side; server is routing-only.
//

import Foundation

// MARK: - Session Status

/// Session status from the local device point of view.
enum C6PSessionStatus: String, Codable {
    case active           = "ACTIVE"
    case closed           = "CLOSED"
    case needsReHandshake = "NEEDS_REHANDSHAKE"
}

// MARK: - Replay / ordering policy

/// Receiver policy for handling counters.
enum C6PReplayPolicy: String, Codable {
    /// Accept only strictly in-order counter progression (ctr == expected).
    case strictInOrder = "STRICT_IN_ORDER"

    /// Allow a small window and buffer out-of-order (implementation-dependent).
    case windowed = "WINDOWED"
}

// MARK: - Session State

/// Full session state between (localDeviceId, remoteDeviceId).
///
/// NOTE:
/// - Nonces are deterministic and reconstructed (never transmitted).
/// - Envelopes must carry: suite, sessionId, streamId, counter, messageType to compute nonce/AAD.
struct C6PSessionState: Hashable, Codable, CustomStringConvertible {

    // MARK: - Identifiers

    /// Shared session identifier.
    let sessionId: C6PSessionId

    /// Local device identifier.
    let localDeviceId: C6PDeviceId

    /// Remote device identifier.
    let remoteDeviceId: C6PDeviceId

    /// Local role in this session.
    let role: C6PRole

    // MARK: - Crypto suite (agility)

    /// Negotiated encryption suite for this session.
    /// Must be stable for the lifetime of the session.
    var suite: C6PEncryptionSuite

    // MARK: - Keys

    /// Session root key derived during handshake.
    var rootKey: C6PRootKey

    /// Sending chain key (local -> remote).
    var sendChainKey: C6PChainKey

    /// Receiving chain key (remote -> local).
    var recvChainKey: C6PChainKey

    // MARK: - Counters (wire-stable streams)

    /// Next expected counter for I2R stream.
    /// (Initiator -> Responder direction on the wire)
    var nextI2RCounter: UInt64

    /// Next expected counter for R2I stream.
    /// (Responder -> Initiator direction on the wire)
    var nextR2ICounter: UInt64

    // MARK: - Policy

    /// Counter/replay policy.
    var replayPolicy: C6PReplayPolicy

    /// Optional receive window size for `.windowed` policy.
    /// In v1 you can keep it nil and implement strict only.
    var receiveWindow: UInt32?

    // MARK: - Metadata

    var createdAt: Date
    var updatedAt: Date
    var status: C6PSessionStatus

    // MARK: - Derived helpers

    var isInitiator: Bool { role == .initiator }
    var isResponder: Bool { role == .responder }

    /// Wire-stable stream mapping for *local sending*.
    /// If local is initiator => sending uses I2R, else sending uses R2I.
    var localSendStream: C6PStreamId { isInitiator ? .i2r : .r2i }

    /// Wire-stable stream mapping for *local receiving*.
    var localRecvStream: C6PStreamId { isInitiator ? .r2i : .i2r }

    // MARK: - Init

    init(
        sessionId: C6PSessionId,
        localDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId,
        role: C6PRole,
        suite: C6PEncryptionSuite,
        rootKey: C6PRootKey,
        sendChainKey: C6PChainKey,
        recvChainKey: C6PChainKey,
        nextI2RCounter: UInt64 = 0,
        nextR2ICounter: UInt64 = 0,
        replayPolicy: C6PReplayPolicy = .strictInOrder,
        receiveWindow: UInt32? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        status: C6PSessionStatus = .active
    ) {
        // Session id consistency
        precondition(rootKey.sessionId == sessionId, "RootKey.sessionId must match sessionId")
        precondition(sendChainKey.sessionId == sessionId, "sendChainKey.sessionId must match sessionId")
        precondition(recvChainKey.sessionId == sessionId, "recvChainKey.sessionId must match sessionId")

        // RootKey device binding must match role
        switch role {
        case .initiator:
            precondition(rootKey.initiatorDeviceId == localDeviceId, "role=initiator => rootKey.initiatorDeviceId must be localDeviceId")
            precondition(rootKey.responderDeviceId == remoteDeviceId, "role=initiator => rootKey.responderDeviceId must be remoteDeviceId")
        case .responder:
            precondition(rootKey.initiatorDeviceId == remoteDeviceId, "role=responder => rootKey.initiatorDeviceId must be remoteDeviceId")
            precondition(rootKey.responderDeviceId == localDeviceId, "role=responder => rootKey.responderDeviceId must be localDeviceId")
        }

        // Chain key binding
        precondition(sendChainKey.selfDeviceId == localDeviceId, "sendChainKey.selfDeviceId must be localDeviceId")
        precondition(sendChainKey.remoteDeviceId == remoteDeviceId, "sendChainKey.remoteDeviceId must be remoteDeviceId")
        precondition(recvChainKey.selfDeviceId == localDeviceId, "recvChainKey.selfDeviceId must be localDeviceId")
        precondition(recvChainKey.remoteDeviceId == remoteDeviceId, "recvChainKey.remoteDeviceId must be remoteDeviceId")

        // Role & direction in chain keys
        precondition(sendChainKey.role == role, "sendChainKey.role must match session role")
        precondition(recvChainKey.role == role, "recvChainKey.role must match session role")
        precondition(sendChainKey.direction == .sending, "sendChainKey.direction must be .sending")
        precondition(recvChainKey.direction == .receiving, "recvChainKey.direction must be .receiving")

        // Replay policy sanity
        if replayPolicy == .strictInOrder {
            precondition(receiveWindow == nil, "receiveWindow must be nil for strictInOrder")
        }

        self.sessionId = sessionId
        self.localDeviceId = localDeviceId
        self.remoteDeviceId = remoteDeviceId
        self.role = role
        self.suite = suite
        self.rootKey = rootKey
        self.sendChainKey = sendChainKey
        self.recvChainKey = recvChainKey
        self.nextI2RCounter = nextI2RCounter
        self.nextR2ICounter = nextR2ICounter
        self.replayPolicy = replayPolicy
        self.receiveWindow = receiveWindow
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.status = status
    }

    // MARK: - Counter helpers

    /// Returns the next counter to use for local sending, and increments session state.
    /// This is the only approved way to allocate a new outgoing counter.
    mutating func allocateOutgoingCounter() -> UInt64 {
        let stream = localSendStream
        switch stream {
        case .i2r:
            let c = nextI2RCounter
            nextI2RCounter &+= 1
            updatedAt = Date()
            return c
        case .r2i:
            let c = nextR2ICounter
            nextR2ICounter &+= 1
            updatedAt = Date()
            return c
        }
    }

    /// Returns the next expected incoming counter for a given stream (wire-stable).
    func expectedIncomingCounter(for stream: C6PStreamId) -> UInt64 {
        switch stream {
        case .i2r: return nextI2RCounter
        case .r2i: return nextR2ICounter
        }
    }

    /// Marks that an incoming counter has been accepted for a given stream.
    /// For strictInOrder this must be exactly `expected`.
    mutating func acceptIncomingCounter(_ counter: UInt64, for stream: C6PStreamId) -> Bool {
        switch replayPolicy {
        case .strictInOrder:
            let expected = expectedIncomingCounter(for: stream)
            guard counter == expected else { return false }
            switch stream {
            case .i2r: nextI2RCounter &+= 1
            case .r2i: nextR2ICounter &+= 1
            }
            updatedAt = Date()
            return true

        case .windowed:
            // v1 may keep strict only; windowed buffering is implemented in SessionService.
            // Here we do conservative behavior: still require in-order unless caller implements buffering.
            let expected = expectedIncomingCounter(for: stream)
            guard counter == expected else { return false }
            switch stream {
            case .i2r: nextI2RCounter &+= 1
            case .r2i: nextR2ICounter &+= 1
            }
            updatedAt = Date()
            return true
        }
    }

    // MARK: - Status helpers

    mutating func markUpdated() { updatedAt = Date() }

    mutating func markClosed() {
        status = .closed
        updatedAt = Date()
    }

    mutating func markNeedsReHandshake() {
        status = .needsReHandshake
        updatedAt = Date()
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "C6PSessionState(sessionId=\(sessionId.hexString), local=\(localDeviceId.hexString), remote=\(remoteDeviceId.hexString), role=\(role.rawValue), suite=\(suite), status=\(status.rawValue))"
    }
}

