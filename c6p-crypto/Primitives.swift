import Foundation
import CryptoKit
import Security

// MARK: - Global constants

/// Global C6P protocol version (used in AAD, KDF info, envelopes, etc.)
let C6P_VERSION: UInt8 = 1

// MARK: - Canonical algorithm identifiers (string constants)

/// Canonical algorithm identifiers for C6P v1 (spec-facing, human/audit readable).
enum C6PAlgorithmId {
    static let dhX25519        = "C6P_DH_X25519_V1"
    static let sigEd25519      = "C6P_SIG_ED25519_V1"

    static let hashSHA256      = "C6P_HASH_SHA256_V1"
    static let kdfHKDFSHA256   = "C6P_KDF_HKDFSHA256_V1"

    // AEAD identifiers (protocol-level)
    static let aeadChaCha20Poly1305  = "C6P_AEAD_CHACHA20POLY1305_V1"
    static let aeadXChaCha20Poly1305 = "C6P_AEAD_XCHACHA20POLY1305_V1"
    static let aeadAegis128L         = "C6P_AEAD_AEGIS_128L_V1"
}

// MARK: - AEAD suite ids (wire-level, compact)

/// Compact suite identifiers (wire-level).
/// Keep these stable forever once shipped.
enum C6PEncryptionSuite: UInt8, Codable, CustomStringConvertible {
    /// Swift reference via CryptoKit
    case v1_chachaPoly   = 0x01

    /// Preferred protocol suite (when available)
    case v1_aegis128l    = 0x02

    /// Fallback suite (when available)
    case v1_xchachaPoly  = 0x03

    var description: String {
        switch self {
        case .v1_chachaPoly:  return "C6P_SUITE_CHACHA20_POLY1305_V1"
        case .v1_aegis128l:   return "C6P_SUITE_AEGIS_128L_V1"
        case .v1_xchachaPoly: return "C6P_SUITE_XCHACHA20_POLY1305_V1"
        }
    }
}

// MARK: - Wire-stable stream id

/// Wire-stable stream identifier:
/// - i2r: Initiator -> Responder
/// - r2i: Responder -> Initiator
///
/// This is the canonical “direction” used in:
/// - chain key separation
/// - message key derivation context
/// - nonce construction
/// - AEAD AAD binding
enum C6PStreamId: UInt8, Codable, CustomStringConvertible {
    case i2r = 0x01
    case r2i = 0x02

    var description: String {
        switch self {
        case .i2r: return "I2R"
        case .r2i: return "R2I"
        }
    }
}

// MARK: - Errors

enum C6PCryptoError: Error, CustomStringConvertible {
    case invalidBase64UrlString
    case invalidHexString
    case invalidLength(expected: Int, actual: Int)
    case randomFailed(status: OSStatus)

    var description: String {
        switch self {
        case .invalidBase64UrlString:
            return "C6PCryptoError.invalidBase64UrlString"
        case .invalidHexString:
            return "C6PCryptoError.invalidHexString"
        case .invalidLength(let expected, let actual):
            return "C6PCryptoError.invalidLength(expected=\(expected), actual=\(actual))"
        case .randomFailed(let status):
            return "C6PCryptoError.randomFailed(status=\(status))"
        }
    }
}

// MARK: - Random bytes (CSPRNG)

enum C6PRandom {

    /// Returns `count` cryptographically secure random bytes using `SecRandomCopyBytes`.
    static func bytes(count: Int) throws -> Data {
        precondition(count > 0, "Count must be > 0")

        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let baseAddress = ptr.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }

        guard status == errSecSuccess else {
            throw C6PCryptoError.randomFailed(status: status)
        }
        return data
    }

    /// Returns a random UInt64 value generated via CSPRNG.
    static func randomUInt64() throws -> UInt64 {
        let data = try bytes(count: 8)
        return C6PEncoding.bigEndianDataToUInt64(data)
    }

    /// Returns a random UInt32 value generated via CSPRNG.
    static func randomUInt32() throws -> UInt32 {
        let data = try bytes(count: 4)
        return C6PEncoding.bigEndianDataToUInt32(data)
    }
}

// MARK: - Encoding helpers (hex, base64url, big-endian integers)

enum C6PEncoding {

    // MARK: Base64Url (no padding)

    static func base64URLEncode(_ data: Data) -> String {
        let base64 = data.base64EncodedString()
        var urlSafe = base64
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
        urlSafe.removeAll(where: { $0 == "=" })
        return urlSafe
    }

    static func base64URLDecode(_ string: String) throws -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // pad to multiple of 4
        let mod = base64.count % 4
        if mod != 0 {
            base64.append(String(repeating: "=", count: 4 - mod))
        }

        guard let data = Data(base64Encoded: base64) else {
            throw C6PCryptoError.invalidBase64UrlString
        }
        return data
    }

    // MARK: Hex

    static func hexEncode(_ data: Data, uppercase: Bool = false) -> String {
        let map = uppercase ? "0123456789ABCDEF" : "0123456789abcdef"
        var chars: [Character] = []
        chars.reserveCapacity(data.count * 2)

        for byte in data {
            let hi = Int((byte & 0xF0) >> 4)
            let lo = Int(byte & 0x0F)
            chars.append(map[map.index(map.startIndex, offsetBy: hi)])
            chars.append(map[map.index(map.startIndex, offsetBy: lo)])
        }
        return String(chars)
    }

    static func hexDecode(_ string: String) throws -> Data {
        let clean = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count % 2 == 0 else {
            throw C6PCryptoError.invalidHexString
        }

        var data = Data()
        data.reserveCapacity(clean.count / 2)

        var index = clean.startIndex
        while index < clean.endIndex {
            let nextIndex = clean.index(index, offsetBy: 2)
            let byteString = clean[index..<nextIndex]
            guard let byte = UInt8(byteString, radix: 16) else {
                throw C6PCryptoError.invalidHexString
            }
            data.append(byte)
            index = nextIndex
        }
        return data
    }

    // MARK: Big-endian integers (safe, no alignment assumptions)

    static func uint64ToBigEndianData(_ value: UInt64) -> Data {
        var out = [UInt8](repeating: 0, count: 8)
        for i in 0..<8 {
            let shift = (7 - i) * 8
            out[i] = UInt8((value >> UInt64(shift)) & 0xFF)
        }
        return Data(out)
    }

    static func uint32ToBigEndianData(_ value: UInt32) -> Data {
        var out = [UInt8](repeating: 0, count: 4)
        for i in 0..<4 {
            let shift = (3 - i) * 8
            out[i] = UInt8((value >> UInt32(shift)) & 0xFF)
        }
        return Data(out)
    }

    static func bigEndianDataToUInt64(_ data: Data) -> UInt64 {
        precondition(data.count == 8, "Expected 8 bytes for UInt64")
        var value: UInt64 = 0
        for b in data {
            value = (value << 8) | UInt64(b)
        }
        return value
    }

    static func bigEndianDataToUInt32(_ data: Data) -> UInt32 {
        precondition(data.count == 4, "Expected 4 bytes for UInt32")
        var value: UInt32 = 0
        for b in data {
            value = (value << 8) | UInt32(b)
        }
        return value
    }
}

// MARK: - HKDF (Extract + Expand, RFC 5869) — HKDF-SHA256

enum C6PHKDF {

    /// HKDF-Extract(salt, IKM) -> PRK
    static func extract(salt: Data, inputKeyMaterial: Data) -> Data {
        let effectiveSalt: Data = salt.isEmpty
            ? Data(repeating: 0, count: 32) // SHA-256 output size
            : salt

        let key = SymmetricKey(data: effectiveSalt)
        let mac = HMAC<SHA256>.authenticationCode(for: inputKeyMaterial, using: key)
        return Data(mac)
    }

    /// HKDF-Expand(PRK, info, L) -> OKM
    static func expand(pseudoRandomKey: Data, info: Data, outputByteCount: Int) -> Data {
        precondition(outputByteCount > 0, "outputByteCount must be > 0")
        precondition(outputByteCount <= 255 * 32, "outputByteCount too large for HKDF-SHA256")

        let prk = SymmetricKey(data: pseudoRandomKey)

        var result = Data()
        result.reserveCapacity(outputByteCount)

        var previousBlock = Data()
        var counter: UInt8 = 1

        while result.count < outputByteCount {
            var blockInput = Data()
            blockInput.append(previousBlock)
            blockInput.append(info)
            blockInput.append(counter)

            let mac = HMAC<SHA256>.authenticationCode(for: blockInput, using: prk)
            previousBlock = Data(mac)
            result.append(previousBlock)

            counter &+= 1
        }

        return result.prefix(outputByteCount)
    }

    /// Single-call HKDF for convenience: HKDF-Extract + HKDF-Expand.
    static func deriveKey(inputKeyMaterial: Data, salt: Data, info: Data, outputByteCount: Int) -> Data {
        let prk = extract(salt: salt, inputKeyMaterial: inputKeyMaterial)
        return expand(pseudoRandomKey: prk, info: info, outputByteCount: outputByteCount)
    }
}

// MARK: - KeyId, DeviceId, SessionId, MessageCounter

/// 8-byte identifier for keys (identity / prekeys etc.), encoded as lowercase hex for JSON.
struct C6PKeyId: Hashable, Codable, CustomStringConvertible {

    let value: UInt64

    init(value: UInt64) { self.value = value }

    static func random() throws -> C6PKeyId {
        C6PKeyId(value: try C6PRandom.randomUInt64())
    }

    init(data: Data) throws {
        guard data.count == 8 else {
            throw C6PCryptoError.invalidLength(expected: 8, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt64(data)
    }

    init(hexString: String) throws {
        try self.init(data: C6PEncoding.hexDecode(hexString))
    }

    var data: Data { C6PEncoding.uint64ToBigEndianData(value) }
    var hexString: String { C6PEncoding.hexEncode(data, uppercase: false) }

    var description: String { hexString }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        try self.init(hexString: hex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// 8-byte identifier for devices, encoded as lowercase hex in JSON.
struct C6PDeviceId: Hashable, Codable, CustomStringConvertible {

    let value: UInt64

    init(value: UInt64) { self.value = value }

    static func random() throws -> C6PDeviceId {
        C6PDeviceId(value: try C6PRandom.randomUInt64())
    }

    init(data: Data) throws {
        guard data.count == 8 else {
            throw C6PCryptoError.invalidLength(expected: 8, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt64(data)
    }

    init(hexString: String) throws {
        try self.init(data: C6PEncoding.hexDecode(hexString))
    }

    var data: Data { C6PEncoding.uint64ToBigEndianData(value) }
    var hexString: String { C6PEncoding.hexEncode(data, uppercase: false) }

    var description: String { hexString }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        try self.init(hexString: hex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// 4-byte session identifier used in v1 layouts (big-endian UInt32).
/// NOTE: In the “ideal future” we may widen this to 8 bytes, but v1 keeps 4.
struct C6PSessionId: Hashable, Codable, CustomStringConvertible {

    let value: UInt32

    init(value: UInt32) { self.value = value }

    static func random() throws -> C6PSessionId {
        C6PSessionId(value: try C6PRandom.randomUInt32())
    }

    init(data: Data) throws {
        guard data.count == 4 else {
            throw C6PCryptoError.invalidLength(expected: 4, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt32(data)
    }

    init(hexString: String) throws {
        try self.init(data: C6PEncoding.hexDecode(hexString))
    }

    var data: Data { C6PEncoding.uint32ToBigEndianData(value) }
    var hexString: String { C6PEncoding.hexEncode(data, uppercase: false) }

    var description: String { hexString }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let hex = try container.decode(String.self)
        try self.init(hexString: hex)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hexString)
    }
}

/// Monotonic message counter (uint64).
struct C6PMessageCounter: Hashable, Codable, CustomStringConvertible {

    private(set) var value: UInt64

    init(value: UInt64 = 0) { self.value = value }

    mutating func increment() { value &+= 1 }

    var data: Data { C6PEncoding.uint64ToBigEndianData(value) }
    var description: String { String(value) }
}

// MARK: - Message types

enum C6PMessageType: UInt8, Codable, CustomStringConvertible {
    case dm      = 0x01
    case group   = 0x02
    case channel = 0x03
    case control = 0x10

    var description: String {
        switch self {
        case .dm: return "DM"
        case .group: return "GROUP"
        case .channel: return "CHANNEL"
        case .control: return "CONTROL"
        }
    }
}

// MARK: - Fingerprint (UI / verification aid)

enum C6PFingerprint {

    /// Computes a short fingerprint string:
    /// first 8 bytes of SHA256(pubkey), uppercase hex grouped 4-4-4-4.
    static func fingerprint(forPublicKey publicKey: Data) -> String {
        let hash = SHA256.hash(data: publicKey)
        let full = Data(hash)
        let first8 = full.prefix(8)

        let hex = C6PEncoding.hexEncode(first8, uppercase: true) // 16 hex chars
        let chars = Array(hex)
        guard chars.count == 16 else { return hex }

        let p1 = String(chars[0..<4])
        let p2 = String(chars[4..<8])
        let p3 = String(chars[8..<12])
        let p4 = String(chars[12..<16])
        return "\(p1)-\(p2)-\(p3)-\(p4)"
    }
}
