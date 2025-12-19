import Foundation

// MARK: - Delivery

/// Delivery state from client PoV.
/// Server may have richer internal states; these are enough for UI and retry logic.
enum C6PDeliveryState: String, Codable {
    case pending   = "PENDING"
    case delivered = "DELIVERED"
    case read      = "READ"
    case failed    = "FAILED"
}

// MARK: - Envelope kind / routing target

/// High-level routing target for the message.
/// This is *metadata* (not trusted). Crypto validity is enforced by AEAD/AAD.
enum C6PTarget: Codable, Hashable, CustomStringConvertible {
    case dm(toDeviceId: C6PDeviceId)
    case group(groupId: String)     // server-side identifier, policy-defined
    case channel(channelId: String) // server-side identifier, policy-defined

    var description: String {
        switch self {
        case .dm(let to): return "DM(toDeviceId=\(to.hexString))"
        case .group(let gid): return "GROUP(groupId=\(gid))"
        case .channel(let cid): return "CHANNEL(channelId=\(cid))"
        }
    }
}

// MARK: - Envelope

/// Wire-level envelope for C6P messages.
/// This is exactly what:
/// - client sends to backend (JSON),
/// - backend stores,
/// - backend returns on pull/poll,
/// - client deserializes and decrypts.
///
/// IMPORTANT:
/// - Everything outside `sealed` is untrusted metadata.
/// - However, some fields are required as **pre-decrypt routing hints**
///   to compute nonce/AAD deterministically and select the right session state:
///   `suite`, `sessionId`, `streamId`, `counter`, `messageType`.
struct C6PEnvelope: Codable, Hashable, CustomStringConvertible {

    // MARK: - Protocol / type

    /// Protocol version.
    let c6pVersion: UInt8

    /// Message semantic type (dm/group/channel/control).
    let messageType: C6PMessageType

    /// AEAD suite used for sealing this payload (nonce length + AAD binding).
    let suite: C6PEncryptionSuite

    // MARK: - Routing (untrusted)

    /// Sender device id (routing metadata).
    let fromDeviceId: C6PDeviceId

    /// Target (DM device, group id, channel id).
    let target: C6PTarget

    /// Session identifier used to locate the proper C6P session state on receiver.
    let sessionId: C6PSessionId

    // MARK: - Crypto routing hints (must be present pre-decrypt)

    /// Wire-stable stream id (I2R / R2I). Required for deterministic nonce/AAD.
    let streamId: C6PStreamId

    /// Monotonic counter for this stream within the session.
    /// Used for nonce construction and replay/out-of-order policy.
    let counter: UInt64

    // MARK: - Payload

    /// Ciphertext + tag (nonce is deterministic and not transmitted).
    let sealed: C6PSealedMessage

    // MARK: - App ids / timestamps / delivery

    /// Client-generated message id (dedupe / retries).
    let clientMessageId: String

    /// Sender timestamp (local clock, informational).
    let clientTimestamp: Date

    /// Server receive timestamp (UTC), set by backend.
    var serverTimestamp: Date?

    /// Optional server message id (DB primary key / UUID).
    var serverMessageId: String?

    /// Delivery state for UI.
    var deliveryState: C6PDeliveryState

    // MARK: - Init

    init(
        messageType: C6PMessageType,
        suite: C6PEncryptionSuite,
        fromDeviceId: C6PDeviceId,
        target: C6PTarget,
        sessionId: C6PSessionId,
        streamId: C6PStreamId,
        counter: UInt64,
        sealed: C6PSealedMessage,
        clientMessageId: String = UUID().uuidString,
        clientTimestamp: Date = Date(),
        serverTimestamp: Date? = nil,
        serverMessageId: String? = nil,
        deliveryState: C6PDeliveryState = .pending
    ) {
        self.c6pVersion = C6P_VERSION
        self.messageType = messageType
        self.suite = suite
        self.fromDeviceId = fromDeviceId
        self.target = target
        self.sessionId = sessionId
        self.streamId = streamId
        self.counter = counter
        self.sealed = sealed
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.serverTimestamp = serverTimestamp
        self.serverMessageId = serverMessageId
        self.deliveryState = deliveryState
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "C6PEnvelope(v=\(c6pVersion), type=\(messageType), suite=\(suite), sessionId=\(sessionId.hexString), stream=\(streamId), ctr=\(counter), from=\(fromDeviceId.hexString), target=\(target))"
    }
}

// MARK: - Convenience aliases (optional)

typealias C6PEnvelopeDM = C6PEnvelope
