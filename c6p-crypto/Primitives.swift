import Foundation
import CryptoKit
import Security

// MARK: - Global constants

/// Global C6P protocol version (used in AAD, etc.)
let C6P_VERSION: UInt8 = 1

/// Canonical algorithm identifiers for C6P v1.
enum C6PAlgorithmId {
    static let dhX25519      = "C6P_DH_X25519_V1"
    static let sigEd25519    = "C6P_SIG_ED25519_V1"
    static let hashSHA256    = "C6P_HASH_SHA256_V1"
    static let kdfHKDFSHA256 = "C6P_KDF_HKDFSHA256_V1"
    static let aeadChaCha20  = "C6P_AEAD_CHACHA20POLY1305_V1"
}

// MARK: - Errors

enum C6PCryptoError: Error {
    case invalidBase64UrlString
    case invalidHexString
    case invalidLength(expected: Int, actual: Int)
    case randomFailed(status: OSStatus)
}

// MARK: - Random bytes (CSPRNG)

enum C6PRandom {

    /// Returns `count` cryptographically secure random bytes using `SecRandomCopyBytes`.
    static func bytes(count: Int) throws -> Data {
        precondition(count > 0, "Count must be > 0")

        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { (ptr: UnsafeMutableRawBufferPointer) -> OSStatus in
            guard let baseAddress = ptr.baseAddress else {
                return errSecParam
            }
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

        let paddingNeeded = 4 - (base64.count % 4)
        if paddingNeeded < 4 {
            base64.append(String(repeating: "=", count: paddingNeeded))
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

    // MARK: Big-endian integers

    static func uint64ToBigEndianData(_ value: UInt64) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: MemoryLayout<UInt64>.size)
    }

    static func uint32ToBigEndianData(_ value: UInt32) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: MemoryLayout<UInt32>.size)
    }

    static func bigEndianDataToUInt64(_ data: Data) -> UInt64 {
        precondition(data.count == 8, "Expected 8 bytes for UInt64")
        return data.withUnsafeBytes { ptr in
            ptr.load(as: UInt64.self).bigEndian
        }
    }

    static func bigEndianDataToUInt32(_ data: Data) -> UInt32 {
        precondition(data.count == 4, "Expected 4 bytes for UInt32")
        return data.withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).bigEndian
        }
    }
}

// MARK: - HKDF (Extract + Expand, RFC 5869)

enum C6PHKDF {

    /// HKDF-Extract(salt, IKM) -> PRK
    static func extract(salt: Data, inputKeyMaterial: Data) -> Data {
        let effectiveSalt: Data
        if salt.isEmpty {
            // RFC 5869: if salt not provided, use zeros of HashLen
            effectiveSalt = Data(repeating: 0, count: 32) // 32 = SHA256 output size
        } else {
            effectiveSalt = salt
        }

        let key = SymmetricKey(data: effectiveSalt)
        let mac = HMAC<SHA256>.authenticationCode(for: inputKeyMaterial, using: key)
        return Data(mac)
    }

    /// HKDF-Expand(PRK, info, L) -> OKM
    static func expand(pseudoRandomKey: Data, info: Data, outputByteCount: Int) -> Data {
        precondition(outputByteCount > 0, "outputByteCount must be > 0")
        // RFC 5869: L <= 255 * HashLen
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

    // MARK: Initializers

    init(value: UInt64) {
        self.value = value
    }

    static func random() throws -> C6PKeyId {
        let v = try C6PRandom.randomUInt64()
        return C6PKeyId(value: v)
    }

    init(data: Data) throws {
        guard data.count == 8 else {
            throw C6PCryptoError.invalidLength(expected: 8, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt64(data)
    }

    init(hexString: String) throws {
        let data = try C6PEncoding.hexDecode(hexString)
        try self.init(data: data)
    }

    // MARK: Encodings

    var data: Data {
        C6PEncoding.uint64ToBigEndianData(value)
    }

    var hexString: String {
        C6PEncoding.hexEncode(data, uppercase: false)
    }

    // MARK: CustomStringConvertible

    var description: String {
        hexString
    }

    // MARK: Codable

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

/// 8-byte identifier for devices, encoded jako lowercase hex w JSON.
struct C6PDeviceId: Hashable, Codable, CustomStringConvertible {

    let value: UInt64

    // MARK: Initializers

    init(value: UInt64) {
        self.value = value
    }

    static func random() throws -> C6PDeviceId {
        let v = try C6PRandom.randomUInt64()
        return C6PDeviceId(value: v)
    }

    init(data: Data) throws {
        guard data.count == 8 else {
            throw C6PCryptoError.invalidLength(expected: 8, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt64(data)
    }

    init(hexString: String) throws {
        let data = try C6PEncoding.hexDecode(hexString)
        try self.init(data: data)
    }

    // MARK: Encodings

    var data: Data {
        C6PEncoding.uint64ToBigEndianData(value)
    }

    var hexString: String {
        C6PEncoding.hexEncode(data, uppercase: false)
    }

    var description: String {
        hexString
    }

    // MARK: Codable

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

/// 4-byte session identifier used in nonces (big-endian UInt32).
struct C6PSessionId: Hashable, Codable, CustomStringConvertible {

    let value: UInt32

    // MARK: Initializers

    init(value: UInt32) {
        self.value = value
    }

    static func random() throws -> C6PSessionId {
        let v = try C6PRandom.randomUInt32()
        return C6PSessionId(value: v)
    }

    init(data: Data) throws {
        guard data.count == 4 else {
            throw C6PCryptoError.invalidLength(expected: 4, actual: data.count)
        }
        self.value = C6PEncoding.bigEndianDataToUInt32(data)
    }

    init(hexString: String) throws {
        let data = try C6PEncoding.hexDecode(hexString)
        try self.init(data: data)
    }

    // MARK: Encodings

    var data: Data {
        C6PEncoding.uint32ToBigEndianData(value)
    }

    /// Hex encoding of session ID (8 hex chars).
    var hexString: String {
        C6PEncoding.hexEncode(data, uppercase: false)
    }

    var description: String {
        hexString
    }

    // MARK: Codable

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

    init(value: UInt64 = 0) {
        self.value = value
    }

    mutating func increment() {
        value &+= 1
    }

    var data: Data {
        C6PEncoding.uint64ToBigEndianData(value)
    }

    var description: String {
        String(value)
    }
}

// MARK: - Message types

enum C6PMessageType: UInt8 {
    case dm      = 0x01
    case group   = 0x02
    case channel = 0x03
    case control = 0x10
}

// MARK: - Fingerprint (IDK)

enum C6PFingerprint {

    /// Computes fingerprint string (8 bytes of SHA256(pubkey), hex uppercase grouped 4x4).
    static func fingerprint(forPublicKey publicKey: Data) -> String {
        let hash = SHA256.hash(data: publicKey)
        let full = Data(hash)
        let first8 = full.prefix(8)

        let hex = C6PEncoding.hexEncode(first8, uppercase: true) // 16 hex chars
        // Format: XXXX-XXXX-XXXX-XXXX
        let chars = Array(hex)
        guard chars.count == 16 else {
            // Should never happen, but fallback: raw hex
            return hex
        }

        let p1 = String(chars[0..<4])
        let p2 = String(chars[4..<8])
        let p3 = String(chars[8..<12])
        let p4 = String(chars[12..<16])
        return "\(p1)-\(p2)-\(p3)-\(p4)"
    }
}
