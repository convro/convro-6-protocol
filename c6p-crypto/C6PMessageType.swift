import Foundation

/// CRYPTO-level message type (NOT "message kind").
/// This value participates in KDF / nonce derivation, so it MUST be stable forever.
enum C6PMessageType: UInt8, Codable, CaseIterable {
    /// Direct Message (device-to-device / 1:1)
    case dm = 0x01

    /// Group / multi-recipient (reserved for later)
    case group = 0x02

    /// Control/system messages (reserved)
    case system = 0x7F
}
