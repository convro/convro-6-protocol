//
//  C6PPrekeyContracts.swift
//  C6P-Protocol
//
//  Canonical wire contracts for C6P prekey distribution (handshake99).
//
//  SINGLE source of truth for:
//  - publishing signed prekey + one-time prekeys to backend,
//  - fetching prekey bundle for initiator,
//  - consuming one-time prekey (server-side anti-reuse),
//  - strict, auditable encoding rules.
//
//  Encoding rules:
//  - Binary fields are base64url (no padding)
//  - VN is canonical via C6PVirtualNumberString ("+99" + 6 digits)
//

import Foundation

// MARK: - Contract Errors

public enum C6PPrekeyContractError: Error, CustomStringConvertible {
    case invalidC6PVersion(expected: UInt8, actual: UInt8)
    case invalidVirtualNumber(String)

    case invalidBase64Url(String)
    case invalidPublicKeyLength(label: String, expected: Int, actual: Int)
    case inconsistentOneTimePrekeyFields

    public var description: String {
        switch self {
        case .invalidC6PVersion(let e, let a):
            return "C6PPrekeyContractError.invalidC6PVersion(expected=\(e), actual=\(a))"
        case .invalidVirtualNumber(let s):
            return "C6PPrekeyContractError.invalidVirtualNumber(\(s))"
        case .invalidBase64Url(let label):
            return "C6PPrekeyContractError.invalidBase64Url(\(label))"
        case .invalidPublicKeyLength(let label, let e, let a):
            return "C6PPrekeyContractError.invalidPublicKeyLength(label=\(label), expected=\(e), actual=\(a))"
        case .inconsistentOneTimePrekeyFields:
            return "C6PPrekeyContractError.inconsistentOneTimePrekeyFields"
        }
    }
}

// MARK: - Base64url validation helpers

public enum C6PPrekeyContractValidation {

    @inline(__always)
    public static func requireB64uDecodes(_ s: String, label: String) throws -> Data {
        do {
            return try C6PEncoding.base64URLDecode(s)
        } catch {
            throw C6PPrekeyContractError.invalidBase64Url(label)
        }
    }

    @inline(__always)
    public static func requireB64uLen(_ s: String, expected: Int, label: String) throws {
        let d = try requireB64uDecodes(s, label: label)
        if d.count != expected {
            throw C6PPrekeyContractError.invalidPublicKeyLength(label: label, expected: expected, actual: d.count)
        }
    }

    @inline(__always)
    public static func requireVNCanonical(_ vn: String) throws {
        guard C6PVirtualNumberString.isValidCanonical(vn) else {
            throw C6PPrekeyContractError.invalidVirtualNumber(vn)
        }
    }
}

// MARK: - Public records

public struct C6PSignedPrekeyPublicRecord: Codable, Hashable {
    /// 32 bytes X25519 public key, base64url (no padding)
    public let publicKeyX25519B64u: String

    /// Ed25519 signature bytes over: label || publicKeyX25519, base64url (no padding)
    public let signatureEd25519B64u: String

    public let createdAt: Date

    public func validate() throws {
        try C6PPrekeyContractValidation.requireB64uLen(publicKeyX25519B64u, expected: 32, label: "signedPrekey.publicKeyX25519B64u")
        // Signature length commonly 64 for Ed25519; enforce strict v1:
        try C6PPrekeyContractValidation.requireB64uLen(signatureEd25519B64u, expected: 64, label: "signedPrekey.signatureEd25519B64u")
    }
}

public struct C6POneTimePrekeyPublicRecord: Codable, Hashable {
    public let prekeyId: C6PKeyId

    /// 32 bytes X25519 public key, base64url (no padding)
    public let publicKeyX25519B64u: String

    public let createdAt: Date

    public func validate() throws {
        try C6PPrekeyContractValidation.requireB64uLen(publicKeyX25519B64u, expected: 32, label: "oneTimePrekeys[\(prekeyId.hexString)].publicKeyX25519B64u")
    }
}

// MARK: - Publish (client -> backend)

public struct C6PPublishPrekeysRequest: Codable, Hashable {
    public let c6pVersion: UInt8

    /// canonical "+99######" (no spaces)
    public let virtualNumber: String

    public let deviceId: C6PDeviceId

    /// 32 bytes Ed25519 public key, base64url
    public let identityPublicKeyEd25519B64u: String

    public let signedPrekey: C6PSignedPrekeyPublicRecord
    public let oneTimePrekeys: [C6POneTimePrekeyPublicRecord]

    public init(
        c6pVersion: UInt8,
        virtualNumber: String,
        deviceId: C6PDeviceId,
        identityPublicKeyEd25519B64u: String,
        signedPrekey: C6PSignedPrekeyPublicRecord,
        oneTimePrekeys: [C6POneTimePrekeyPublicRecord]
    ) throws {
        self.c6pVersion = c6pVersion
        self.virtualNumber = virtualNumber
        self.deviceId = deviceId
        self.identityPublicKeyEd25519B64u = identityPublicKeyEd25519B64u
        self.signedPrekey = signedPrekey
        self.oneTimePrekeys = oneTimePrekeys
        try validate()
    }

    public func validate() throws {
        if c6pVersion != C6P_VERSION {
            throw C6PPrekeyContractError.invalidC6PVersion(expected: C6P_VERSION, actual: c6pVersion)
        }
        try C6PPrekeyContractValidation.requireVNCanonical(virtualNumber)
        try C6PPrekeyContractValidation.requireB64uLen(identityPublicKeyEd25519B64u, expected: 32, label: "identityPublicKeyEd25519B64u")
        try signedPrekey.validate()
        for o in oneTimePrekeys { try o.validate() }
    }
}

public struct C6PPublishPrekeysResponse: Codable, Hashable {
    public let accepted: Bool
    public let acceptedOneTimePrekeyIds: [C6PKeyId]
    public let serverTime: Date
    public let message: String?
}

// MARK: - Bundle (initiator <- backend)

public struct C6PPrekeyBundleContract: Codable, Hashable {
    public let responderDeviceId: C6PDeviceId

    public let identityPublicKeyEd25519B64u: String
    public let signedPrekeyPublicKeyX25519B64u: String
    public let signedPrekeySignatureB64u: String

    public let oneTimePrekeyId: C6PKeyId?
    public let oneTimePrekeyPublicKeyX25519B64u: String?

    public func validate() throws {
        try C6PPrekeyContractValidation.requireB64uLen(identityPublicKeyEd25519B64u, expected: 32, label: "bundle.identityPublicKeyEd25519B64u")
        try C6PPrekeyContractValidation.requireB64uLen(signedPrekeyPublicKeyX25519B64u, expected: 32, label: "bundle.signedPrekeyPublicKeyX25519B64u")
        try C6PPrekeyContractValidation.requireB64uLen(signedPrekeySignatureB64u, expected: 64, label: "bundle.signedPrekeySignatureB64u")

        let hasId = (oneTimePrekeyId != nil)
        let hasPub = (oneTimePrekeyPublicKeyX25519B64u != nil)
        guard hasId == hasPub else {
            throw C6PPrekeyContractError.inconsistentOneTimePrekeyFields
        }

        if let otpPub = oneTimePrekeyPublicKeyX25519B64u {
            try C6PPrekeyContractValidation.requireB64uLen(otpPub, expected: 32, label: "bundle.oneTimePrekeyPublicKeyX25519B64u")
        }
    }
}

// MARK: - Consume OTP (client -> backend)

public struct C6PConsumeOneTimePrekeyRequest: Codable, Hashable {
    public let c6pVersion: UInt8
    public let responderDeviceId: C6PDeviceId
    public let oneTimePrekeyId: C6PKeyId

    public init(
        c6pVersion: UInt8,
        responderDeviceId: C6PDeviceId,
        oneTimePrekeyId: C6PKeyId
    ) throws {
        self.c6pVersion = c6pVersion
        self.responderDeviceId = responderDeviceId
        self.oneTimePrekeyId = oneTimePrekeyId
        try validate()
    }

    public func validate() throws {
        if c6pVersion != C6P_VERSION {
            throw C6PPrekeyContractError.invalidC6PVersion(expected: C6P_VERSION, actual: c6pVersion)
        }
    }
}

public struct C6PConsumeOneTimePrekeyResponse: Codable, Hashable {
    public let consumed: Bool
    public let serverTime: Date
    public let message: String?
}
