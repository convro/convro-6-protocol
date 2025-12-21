import Foundation

enum C6PDeliveryState: String, Codable {
    case pending   = "PENDING"
    case delivered = "DELIVERED"
    case read      = "READ"
    case failed    = "FAILED"
}

struct C6PEnvelope: Codable, Hashable, CustomStringConvertible {

    let c6pVersion: UInt8
    let fromDeviceId: C6PDeviceId
    let toDeviceId: C6PDeviceId
    let sessionId: C6PSessionId
    let sealed: C6PSealedMessage

    let clientMessageId: String
    let clientTimestamp: Date

    var serverTimestamp: Date?
    var serverMessageId: String?
    var deliveryState: C6PDeliveryState

    init(
        fromDeviceId: C6PDeviceId,
        toDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
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
        self.sealed = sealed
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.serverTimestamp = serverTimestamp
        self.serverMessageId = serverMessageId
        self.deliveryState = deliveryState
    }

    var description: String {
        "C6PEnvelope(v=\(c6pVersion), session=\(sessionId.hexString), from=\(fromDeviceId.hexString), to=\(toDeviceId.hexString), clientMessageId=\(clientMessageId))"
    }

    // MARK: - Manual Codable (locks JSON shape under Node)

    private enum CodingKeys: String, CodingKey {
        case c6pVersion
        case fromDeviceId
        case toDeviceId
        case sessionId
        case sealed
        case clientMessageId
        case clientTimestamp
        case serverTimestamp
        case serverMessageId
        case deliveryState
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        self.c6pVersion = try c.decode(UInt8.self, forKey: .c6pVersion)

        let fromHex = try c.decode(String.self, forKey: .fromDeviceId)
        let toHex   = try c.decode(String.self, forKey: .toDeviceId)
        let sessHex = try c.decode(String.self, forKey: .sessionId)

        self.fromDeviceId = try C6PDeviceId(hexString: fromHex)
        self.toDeviceId   = try C6PDeviceId(hexString: toHex)
        self.sessionId    = try C6PSessionId(hexString: sessHex)

        self.sealed = try c.decode(C6PSealedMessage.self, forKey: .sealed)

        self.clientMessageId = try c.decode(String.self, forKey: .clientMessageId)
        self.clientTimestamp = try c.decode(Date.self, forKey: .clientTimestamp)

        self.serverTimestamp = try c.decodeIfPresent(Date.self, forKey: .serverTimestamp)
        self.serverMessageId = try c.decodeIfPresent(String.self, forKey: .serverMessageId)
        self.deliveryState = try c.decodeIfPresent(C6PDeliveryState.self, forKey: .deliveryState) ?? .pending
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)

        try c.encode(c6pVersion, forKey: .c6pVersion)
        try c.encode(fromDeviceId.hexString.lowercased(), forKey: .fromDeviceId)
        try c.encode(toDeviceId.hexString.lowercased(), forKey: .toDeviceId)
        try c.encode(sessionId.hexString.lowercased(), forKey: .sessionId)

        try c.encode(sealed, forKey: .sealed)

        try c.encode(clientMessageId, forKey: .clientMessageId)
        try c.encode(clientTimestamp, forKey: .clientTimestamp)

        try c.encodeIfPresent(serverTimestamp, forKey: .serverTimestamp)
        try c.encodeIfPresent(serverMessageId, forKey: .serverMessageId)
        try c.encode(deliveryState, forKey: .deliveryState)
    }
}

