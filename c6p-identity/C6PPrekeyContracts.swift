//
//  C6PPrekeyContracts.swift
//  C6P-Protocol
//
//  Canonical wire contracts for C6P prekey distribution (handshake99).
//
//  This file is a SINGLE source of truth for:
//  - publishing signed prekey + one-time prekeys to backend,
//  - fetching prekey bundle for initiator,
//  - consuming one-time prekey (server-side anti-reuse),
//  - strict, auditable encoding rules.
//
//  IMPORTANT DESIGN GOALS:
//  1) Transport encoding is deterministic and Rust-friendly.
//  2) Data fields are base64url (no padding) by default.
//  3) Virtual Number (VN) is canonical: "+99" + 6 digits, no spaces.
//     UI can display "+99 xxx xxx", but wire MUST be canonical.
//  4) No protocol logic here: only contracts + validation helpers.
//

import Foundation

// MARK: - Contract Errors

enum C6PPrekeyContractError: Error, CustomStringConvertible {
    case invalidVirtualNumber(String)
    case invalidBase64UrlData
    case invalidPublicKeyLength(expected: Int, actual: Int)
    case inconsistentOneTimePrekeyFields
    case invalidC6PVersion(expected: UInt8, actual: UInt8)

    var description: String {
        switch self {
        case .invalidVirtualNumber(let s):
            return "C6PPrekeyContractError.invalidVirtualNumber(\(s)) – expected canonical '+99' + 6 digits (no spaces)"
        case .invalidBase64UrlData:
            return "C6PPrekeyContractError.invalidBase64UrlData – base64url decode failed"
        case .invalidPublicKeyLength(let expected, let actual):
            return "C6PPrekeyContractError.invalidPublicKeyLength(expected=\(expected), actual=\(actual))"
        case .inconsistentOneTimePrekeyFields:
            return "C6PPrekeyContractError.inconsistentOneTimePrekeyFields – otpId and otpPublicKey must be both present or both nil"
        case .invalidC6PVersion(let expected, let actual):
            return "C6PPrekeyContractError.invalidC6PVersion(expected=\(expected), actual=\(actual))"
        }
    }
}

// MARK: - Base64Url Data wrapper (no padding)

/// Deterministic binary encoding for JSON:
/// - Encodes Data as **base64url without padding**.
/// - Decodes base64url without padding.
/// - Stable across Swift / Rust / Node implementations.
///
/// NOTE:
/// Uses `C6PEncoding.base64URLEncode` / `base64URLDecode` from `c6p-crypto/Primitives.swift`.
struct C6PBase64UrlData: Hashable, Codable, CustomStringConvertible {
    let data: Data

    init(_ data: Data) {
        self.data = data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        do {
            self.data = try C6PEncoding.base64URLDecode(s)
        } catch {
            throw C6PPrekeyContractError.invalidBase64UrlData
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(C6PEncoding.base64URLEncode(data))
    }

    var description: String {
        "C6PBase64UrlData(\(data.count)B)"
    }
}

// MARK: - Virtual Number (VN)

/// Canonical Virtual Number for Convro/C6P.
/// WIRE FORMAT (canonical):
///   +99XXXXXX   (exactly 6 digits, no spaces)
///
/// UI FORMAT (display):
///   +99 XXX XXX
struct C6PVirtualNumber: Hashable, Codable, CustomStringConvertible {
    /// Canonical representation: "+99" + 6 digits, no spaces.
    let canonical: String

    init(canonical: String) throws {
        let trimmed = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isValidCanonical(trimmed) else {
            throw C6PPrekeyContractError.invalidVirtualNumber(trimmed)
        }
        self.canonical = trimmed
    }

    /// Convenience: accepts UI-formatted VN like "+99 123 456" and normalizes to canonical.
    static func fromDisplay(_ display: String) throws -> C6PVirtualNumber {
        let normalized = display
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return try C6PVirtualNumber(canonical: normalized)
    }

    /// Returns UI display format: "+99 XXX XXX".
    var display: String {
        // canonical: +99 + 6 digits => total length 9
        // Example: +99123456 -> +99 123 456
        let s = canonical
        guard s.count == 9 else { return canonical }
        let start = s.prefix(3) // "+99"
        let digits = s.suffix(6)
        let a = digits.prefix(3)
        let b = digits.suffix(3)
        return "\(start) \(a) \(b)"
    }

    var description: String { canonical }

    // MARK: Codable

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let s = try c.decode(String.self)
        try self.init(canonical: s)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(canonical)
    }

    // MARK: Validation

    static func isValidCanonical(_ s: String) -> Bool {
        // "+99" + 6 digits
        guard s.count == 9 else { return false }
        guard s.hasPrefix("+99") else { return false }
        let tail = s.dropFirst(3)
        guard tail.count == 6 else { return false }
        return tail.allSatisfy { $0 >= "0" && $0 <= "9" }
    }
}

// MARK: - Prekey Public Records

/// Public Signed Prekey record published to backend.
/// - publicKeyX25519: 32 bytes
/// - signatureEd25519: signature over label || publicKeyX25519
struct C6PSignedPrekeyPublicRecord: Codable, Hashable {
    let publicKeyX25519: C6PBase64UrlData
    let signatureEd25519: C6PBase64UrlData
    let createdAt: Date

    func validate() throws {
        let pubLen = publicKeyX25519.data.count
        guard pubLen == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: pubLen)
        }
        // Signature length for Ed25519 is 64 bytes in standard libs.
        // We don't hard-fail on signature length here to allow future agility,
        // but you CAN enforce 64 if you want strict v1:
        // guard signatureEd25519.data.count == 64 else ...
    }
}

/// Public One-Time Prekey record published to backend.
/// - prekeyId: stable ID
/// - publicKeyX25519: 32 bytes
struct C6POneTimePrekeyPublicRecord: Codable, Hashable {
    let prekeyId: C6PKeyId
    let publicKeyX25519: C6PBase64UrlData
    let createdAt: Date

    func validate() throws {
        let pubLen = publicKeyX25519.data.count
        guard pubLen == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: pubLen)
        }
    }
}

// MARK: - Publish Prekeys (client -> backend)

struct C6PPublishPrekeysRequest: Codable, Hashable {

    /// Global protocol version (C6P_VERSION).
    let c6pVersion: UInt8

    /// Canonical VN: "+99" + 6 digits, no spaces.
    let virtualNumber: C6PVirtualNumber

    /// Device that owns these prekeys.
    let deviceId: C6PDeviceId

    /// Identity public key (Ed25519, 32 bytes).
    let identityPublicKeyEd25519: C6PBase64UrlData

    /// Signed prekey (X25519) record.
    let signedPrekey: C6PSignedPrekeyPublicRecord

    /// Newly generated OTPs to add to pool.
    /// Server may accept all or subset.
    let oneTimePrekeys: [C6POneTimePrekeyPublicRecord]

    init(
        c6pVersion: UInt8,
        virtualNumber: C6PVirtualNumber,
        deviceId: C6PDeviceId,
        identityPublicKeyEd25519: Data,
        signedPrekey: C6PSignedPrekeyPublicRecord,
        oneTimePrekeys: [C6POneTimePrekeyPublicRecord]
    ) throws {
        self.c6pVersion = c6pVersion
        self.virtualNumber = virtualNumber
        self.deviceId = deviceId
        self.identityPublicKeyEd25519 = C6PBase64UrlData(identityPublicKeyEd25519)
        self.signedPrekey = signedPrekey
        self.oneTimePrekeys = oneTimePrekeys
        try validate()
    }

    func validate() throws {
        // Strict c6pVersion check (v1)
        guard c6pVersion == C6P_VERSION else {
            throw C6PPrekeyContractError.invalidC6PVersion(expected: C6P_VERSION, actual: c6pVersion)
        }
        // Identity pubkey len
        let idLen = identityPublicKeyEd25519.data.count
        guard idLen == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: idLen)
        }
        try signedPrekey.validate()
        try oneTimePrekeys.forEach { try $0.validate() }
    }
}

struct C6PPublishPrekeysResponse: Codable, Hashable {
    /// If false -> request rejected.
    let accepted: Bool

    /// If accepted, backend may return list of accepted OTP ids.
    /// (Allows server to enforce quotas / reject duplicates.)
    let acceptedOneTimePrekeyIds: [C6PKeyId]

    /// UTC server time (auditable).
    let serverTime: Date

    /// Optional message for logs.
    let message: String?
}

// MARK: - Fetch Prekey Bundle (initiator <- backend)

/// This is the bundle initiator fetches for handshake99.
/// It contains only public material.
///
/// NOTE:
/// - identityPublicKeyEd25519: 32 bytes
/// - signedPrekeyPublicKeyX25519: 32 bytes
/// - signedPrekeySignature: signature over label||SPK_pub (typically 64 bytes)
/// - oneTimePrekey fields are optional; if present must be consistent.
struct C6PPrekeyBundleContract: Codable, Hashable {

    let responderDeviceId: C6PDeviceId

    let identityPublicKeyEd25519: C6PBase64UrlData
    let signedPrekeyPublicKeyX25519: C6PBase64UrlData
    let signedPrekeySignature: C6PBase64UrlData

    let oneTimePrekeyId: C6PKeyId?
    let oneTimePrekeyPublicKeyX25519: C6PBase64UrlData?

    func validate() throws {
        let idLen = identityPublicKeyEd25519.data.count
        guard idLen == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: idLen)
        }
        let spkLen = signedPrekeyPublicKeyX25519.data.count
        guard spkLen == 32 else {
            throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: spkLen)
        }

        // OTP consistency:
        let hasId = (oneTimePrekeyId != nil)
        let hasPub = (oneTimePrekeyPublicKeyX25519 != nil)
        guard hasId == hasPub else {
            throw C6PPrekeyContractError.inconsistentOneTimePrekeyFields
        }
        if let otpPub = oneTimePrekeyPublicKeyX25519 {
            let otpLen = otpPub.data.count
            guard otpLen == 32 else {
                throw C6PPrekeyContractError.invalidPublicKeyLength(expected: 32, actual: otpLen)
            }
        }
    }
}

// MARK: - Consume One-Time Prekey (client -> backend)

struct C6PConsumeOneTimePrekeyRequest: Codable, Hashable {
    let c6pVersion: UInt8
    let responderDeviceId: C6PDeviceId
    let oneTimePrekeyId: C6PKeyId

    init(
        c6pVersion: UInt8,
        responderDeviceId: C6PDeviceId,
        oneTimePrekeyId: C6PKeyId
    ) throws {
        self.c6pVersion = c6pVersion
        self.responderDeviceId = responderDeviceId
        self.oneTimePrekeyId = oneTimePrekeyId
        try validate()
    }

    func validate() throws {
        guard c6pVersion == C6P_VERSION else {
            throw C6PPrekeyContractError.invalidC6PVersion(expected: C6P_VERSION, actual: c6pVersion)
        }
    }
}

struct C6PConsumeOneTimePrekeyResponse: Codable, Hashable {
    let consumed: Bool
    let serverTime: Date
    let message: String?
}
