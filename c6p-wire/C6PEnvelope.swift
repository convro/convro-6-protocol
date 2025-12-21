//
//  C6PEnvelope.swift
//  C6P-Protocol
//
//  Generic wire-level envelope for all message contexts (DM / group / channel / control).
//
//  IMPORTANT:
//  - Envelope is ROUTING METADATA ONLY (server-visible).
//  - Message "shape" (dm/group/channel + kind + contextId) is inside E2EE payload (C6PInnerPayload).
//  - Everything outside `sealed` is UNTRUSTED from a crypto POV.
//  - Integrity binding is done via AEAD extraAAD = C6PWireAAD.envelopeAAD(...).
//
//  CANONICAL v1.2:
//  - Adds suite/streamId/messageType/counter required for deterministic nonce & strict ordering.
//

import Foundation

// MARK: - Delivery State (client-side UI)

enum C6PDeliveryState: String, Codable {
    case pending   = "PENDING"
    case delivered = "DELIVERED"
    case read      = "READ"
    case failed    = "FAILED"
}

// MARK: - Envelope

struct C6PEnvelope: Codable, Hashable, CustomStringConvertible {

    // MARK: Core routing

    /// Global C6P version (C6P_VERSION).
    let c6pVersion: UInt8

    /// Sender device (the device that sealed the payload).
    let fromDeviceId: C6PDeviceId

    /// Recipient device (a concrete device, not an account).
    let toDeviceId: C6PDeviceId

    /// Session used to seal payload (lookup key for local session state).
    let sessionId: C6PSessionId

    // MARK: Crypto metadata (required for deterministic nonce/AAD)

    /// Negotiated encryption suite for this message/session.
    let suite: C6PEncryptionSuite

    /// Wire-stable stream id (I2R / R2I).
    let streamId: C6PStreamId

    /// Message type used in AEAD AAD/nonce derivation (protocol-defined).
    let messageType: C6PMessageType

    /// Strict counter for the wire-stable stream (UInt64).
    let counter: UInt64

    /// Sealed payload (ciphertext + tag). Nonce is derived deterministically.
    let sealed: C6PSealedMessage

    // MARK: Client identifiers

    /// Client-side message id used for dedupe/retry.
    /// Also bound into AEAD extraAAD via C6PWireAAD (hashed to fixed length).
    let clientMessageId: String

    /// Client-side timestamp (local clock). Server must treat as advisory.
    let clientTimestamp: Date

    // MARK: Server fields (optional)

    /// Server-side timestamp (UTC) assigned on ingest.
    var serverTimestamp: Date?

    /// Optional server-side message id (DB UUID etc.).
    var serverMessageId: String?

    /// Optional client-side delivery state for UI.
    var deliveryState: C6PDeliveryState

    // MARK: Init

    init(
        fromDeviceId: C6PDeviceId,
        toDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        suite: C6PEncryptionSuite,
        streamId: C6PStreamId,
        messageType: C6PMessageType,
        counter: UInt64,
        sealed: C6PSealedMessage,
        clientMessageId: String = UUID().uuidString,
        clientTimestamp: Date = Date(),
        serverTimestamp: Date? = nil,
        serverMessageId: String? = nil,
        deliveryState: C6PDeliveryState = .pending
    ) {
        self.c6pVersion = C6P_VERSION
        self.fromDeviceId = fromDeviceId
        self.toDeviceId = toDeviceId
        self.sessionId = sessionId
        self.suite = suite
        self.streamId = streamId
        self.messageType = messageType
        self.counter = counter
        self.sealed = sealed
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.serverTimestamp = serverTimestamp
        self.serverMessageId = serverMessageId
        self.deliveryState = deliveryState
    }

    // MARK: Description

    var description: String {
        "C6PEnvelope(v=\(c6pVersion), session=\(sessionId.hexString), suite=\(suite), stream=\(streamId), type=\(messageType), ctr=\(counter), from=\(fromDeviceId.hexString), to=\(toDeviceId.hexString), clientMessageId=\(clientMessageId))"
    }
}

