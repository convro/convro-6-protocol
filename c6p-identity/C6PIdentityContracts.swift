//
//  C6PIdentityContracts.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Wire contracts (request/response) for identity & registration flows.
//
//  This file intentionally contains NO networking code.
//  It defines stable payload schemas used by:
//  - client registration UI flow
//  - backend identity service
//
//  v1 principles:
//  - account addressed by Virtual Number in +99 namespace (6 digits)
//  - username is an optional alias (server-enforced uniqueness)
//  - device identities are first-class (multi-device by design)
//  - public keys are uploaded; private keys never leave the device
//  - keep metadata explicit, minimal, auditable
//

import Foundation

// MARK: - API Versioning

/// Identity API contract version (not the crypto protocol version).
/// Useful if backend evolves independently from crypto primitive version.
let C6P_IDENTITY_API_VERSION: UInt8 = 1

// MARK: - Errors

enum C6PIdentityContractError: Error, CustomStringConvertible {
    case invalidUsernameFormat
    case invalidDisplayName
    case invalidVirtualNumberFormat
    case invalidPublicKeyLength(expected: Int, actual: Int)
    case invalidSignatureLength
    case invalidDeviceName
    case invalidAvatarReference

    var description: String {
        switch self {
        case .invalidUsernameFormat:
            return "C6PIdentityContractError.invalidUsernameFormat"
        case .invalidDisplayName:
            return "C6PIdentityContractError.invalidDisplayName"
        case .invalidVirtualNumberFormat:
            return "C6PIdentityContractError.invalidVirtualNumberFormat"
        case .invalidPublicKeyLength(let e, let a):
            return "C6PIdentityContractError.invalidPublicKeyLength(expected=\(e), actual=\(a))"
        case .invalidSignatureLength:
            return "C6PIdentityContractError.invalidSignatureLength"
        case .invalidDeviceName:
            return "C6PIdentityContractError.invalidDeviceName"
        case .invalidAvatarReference:
            return "C6PIdentityContractError.invalidAvatarReference"
        }
    }
}

// MARK: - Common types

/// Canonical server-side representation of VN in v1:
/// "+99" + 6 digits, no spaces.
/// Example: "+99123456"
///
/// UI display can format as: "+99 123 456"
struct C6PVirtualNumberString: Hashable, Codable, CustomStringConvertible {
    let value: String

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard C6PVirtualNumberString.isValidCanonical(trimmed) else {
            throw C6PIdentityContractError.invalidVirtualNumberFormat
        }
        self.value = trimmed
    }

    static func isValidCanonical(_ s: String) -> Bool {
        // "+99" + exactly 6 digits
        guard s.count == 9 else { return false }
        guard s.hasPrefix("+99") else { return false }
        let digits = s.dropFirst(3)
        return digits.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    var description: String { value }
}

/// Username alias, canonical form without leading "@"
/// UI may display with "@", but payload uses raw handle.
struct C6PUsernameHandle: Hashable, Codable, CustomStringConvertible {
    let value: String

    init(_ value: String) throws {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard C6PUsernameHandle.isValid(trimmed) else {
            throw C6PIdentityContractError.invalidUsernameFormat
        }
        self.value = trimmed.lowercased()
    }

    static func isValid(_ s: String) -> Bool {
        // 3–24, start letter, allowed [a-z0-9_.]
        let lower = s.lowercased()
        guard lower.count >= 3 && lower.count <= 24 else { return false }
        guard let first = lower.first, (first >= "a" && first <= "z") else { return false }
        for ch in lower {
            if (ch >= "a" && ch <= "z") || (ch >= "0" && ch <= "9") || ch == "_" || ch == "." {
                continue
            }
            return false
        }
        return true
    }

    var description: String { value }
}

/// Optional profile display name fields.
struct C6PProfileName: Hashable, Codable {
    let firstName: String?
    let lastName: String?

    init(firstName: String?, lastName: String?) throws {
        func validate(_ s: String?) throws -> String? {
            guard let v = s else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            guard t.count <= 64 else { throw C6PIdentityContractError.invalidDisplayName }
            // reject control characters
            for u in t.unicodeScalars {
                if CharacterSet.controlCharacters.contains(u) {
                    throw C6PIdentityContractError.invalidDisplayName
                }
            }
            return t
        }

        self.firstName = try validate(firstName)
        self.lastName = try validate(lastName)
    }
}

// MARK: - Avatar reference (server-side)

/// Avatar is stored/served by backend.
/// In v1 contracts we do not accept arbitrary URLs.
enum C6PAvatarContractRef: Hashable, Codable {
    case none
    case mediaId(String)

    private enum CodingKeys: String, CodingKey { case kind, value }

    private enum Kind: String, Codable { case none, mediaId }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .none:
            self = .none
        case .mediaId:
            let v = try c.decode(String.self, forKey: .value)
            let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false, trimmed.count <= 256 else {
                throw C6PIdentityContractError.invalidAvatarReference
            }
            self = .mediaId(trimmed)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:
            try c.encode(Kind.none, forKey: .kind)
        case .mediaId(let id):
            try c.encode(Kind.mediaId, forKey: .kind)
            try c.encode(id, forKey: .value)
        }
    }
}

// MARK: - Device public identity contract

/// Public keys uploaded to backend for a device.
/// In C6P v1 we use:
/// - Ed25519 public key (32 bytes) for signatures/attestation
/// - X25519 public key (32 bytes) for DH / prekeys
struct C6PDevicePublicIdentityContract: Hashable, Codable {
    let deviceIdHex: String

    /// 32 bytes, base64url in transport.
    let ed25519PublicKeyB64u: String

    /// 32 bytes, base64url in transport.
    let x25519PublicKeyB64u: String

    /// Optional device label for UI/debug ("iPhone 15 Pro", "MacBook", etc.)
    let deviceName: String?

    /// Client-declared platform (not security-critical).
    let platform: String?

    /// Client-declared app version/build (not security-critical).
    let appVersion: String?

    init(
        deviceIdHex: String,
        ed25519PublicKey: Data,
        x25519PublicKey: Data,
        deviceName: String?,
        platform: String?,
        appVersion: String?
    ) throws {
        let did = deviceIdHex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard did.count == 16 else {
            // device id is 8 bytes -> 16 hex chars
            throw C6PIdentityContractError.invalidDataFallback()
        }

        guard ed25519PublicKey.count == 32 else {
            throw C6PIdentityContractError.invalidPublicKeyLength(expected: 32, actual: ed25519PublicKey.count)
        }
        guard x25519PublicKey.count == 32 else {
            throw C6PIdentityContractError.invalidPublicKeyLength(expected: 32, actual: x25519PublicKey.count)
        }

        func validateDeviceName(_ s: String?) throws -> String? {
            guard let v = s else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            guard t.count <= 64 else { throw C6PIdentityContractError.invalidDeviceName }
            for u in t.unicodeScalars {
                if CharacterSet.controlCharacters.contains(u) {
                    throw C6PIdentityContractError.invalidDeviceName
                }
            }
            return t
        }

        func validateShort(_ s: String?, max: Int) -> String? {
            guard let v = s else { return nil }
            let t = v.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { return nil }
            return String(t.prefix(max))
        }

        self.deviceIdHex = did.lowercased()
        self.ed25519PublicKeyB64u = C6PEncoding.base64URLEncode(ed25519PublicKey)
        self.x25519PublicKeyB64u = C6PEncoding.base64URLEncode(x25519PublicKey)
        self.deviceName = try validateDeviceName(deviceName)
        self.platform = validateShort(platform, max: 32)
        self.appVersion = validateShort(appVersion, max: 32)
    }
}

// Helper for one internal exceptional validation
private extension C6PIdentityContractError {
    static func invalidDataFallback() -> C6PIdentityContractError { .invalidAvatarReference }
}

// MARK: - Username availability / reservation

struct C6PUsernameCheckRequest: Codable, Hashable {
    let apiVersion: UInt8
    let username: C6PUsernameHandle

    init(username: C6PUsernameHandle) {
        self.apiVersion = C6P_IDENTITY_API_VERSION
        self.username = username
    }
}

struct C6PUsernameCheckResponse: Codable, Hashable {
    let apiVersion: UInt8
    let username: C6PUsernameHandle
    let available: Bool
    let reason: String? // backend may return policy reason ("reserved", "banned", etc.)
}

/// Optional reservation flow: reserve handle for a short time while user continues onboarding.
struct C6PUsernameReserveRequest: Codable, Hashable {
    let apiVersion: UInt8
    let username: C6PUsernameHandle

    /// Optional client nonce/id for idempotency.
    let requestId: String

    init(username: C6PUsernameHandle, requestId: String = UUID().uuidString) {
        self.apiVersion = C6P_IDENTITY_API_VERSION
        self.username = username
        self.requestId = requestId
    }
}

struct C6PUsernameReserveResponse: Codable, Hashable {
    let apiVersion: UInt8
    let username: C6PUsernameHandle
    let reserved: Bool

    /// Reservation token to include in final create (prevents racing).
    let reservationToken: String?

    /// Expiration UTC timestamp (server authoritative).
    let expiresAt: Date?
}

// MARK: - VN assignment (+99 namespace)

/// VN is generated by backend to ensure global uniqueness.
/// Client may request generation, but server is authoritative.
struct C6PAssignVirtualNumberRequest: Codable, Hashable {
    let apiVersion: UInt8
    let requestId: String

    init(requestId: String = UUID().uuidString) {
        self.apiVersion = C6P_IDENTITY_API_VERSION
        self.requestId = requestId
    }
}

struct C6PAssignVirtualNumberResponse: Codable, Hashable {
    let apiVersion: UInt8

    /// canonical VN: "+99" + 6 digits
    let virtualNumber: C6PVirtualNumberString

    /// Server timestamp for audit/debug
    let assignedAt: Date
}

// MARK: - Account creation (finalization)

/// This is the final step of onboarding:
/// - bind VN
/// - (optionally) bind username
/// - store profile data
/// - register primary device public identity
///
/// The crypto private keys never leave device.
/// Backend receives only public keys + metadata.
struct C6PCreateAccountRequest: Codable, Hashable {
    let apiVersion: UInt8

    /// Canonical virtual number.
    let virtualNumber: C6PVirtualNumberString

    /// Optional @handle (without "@").
    let username: C6PUsernameHandle?

    /// Optional reservation token if using reserve flow.
    let usernameReservationToken: String?

    /// Optional profile name.
    let profileName: C6PProfileName

    /// Avatar reference in v1: none or backend mediaId.
    let avatar: C6PAvatarContractRef

    /// Primary device public identity.
    let primaryDevice: C6PDevicePublicIdentityContract

    /// Idempotency / dedupe.
    let requestId: String

    init(
        virtualNumber: C6PVirtualNumberString,
        username: C6PUsernameHandle?,
        usernameReservationToken: String?,
        profileName: C6PProfileName,
        avatar: C6PAvatarContractRef,
        primaryDevice: C6PDevicePublicIdentityContract,
        requestId: String = UUID().uuidString
    ) {
        self.apiVersion = C6P_IDENTITY_API_VERSION
        self.virtualNumber = virtualNumber
        self.username = username
        self.usernameReservationToken = usernameReservationToken
        self.profileName = profileName
        self.avatar = avatar
        self.primaryDevice = primaryDevice
        self.requestId = requestId
    }
}

struct C6PCreateAccountResponse: Codable, Hashable {
    let apiVersion: UInt8

    /// Server-acknowledged VN.
    let virtualNumber: C6PVirtualNumberString

    /// Final username (might be nil if not set).
    let username: C6PUsernameHandle?

    /// Account internal id (server side), optional if you want it.
    let accountId: String?

    /// Server time of creation.
    let createdAt: Date

    /// Whether the device is set as primary.
    let primaryDeviceIdHex: String
}

// MARK: - Add/Remove devices (multi-device)

struct C6PRegisterDeviceRequest: Codable, Hashable {
    let apiVersion: UInt8

    let virtualNumber: C6PVirtualNumberString
    let device: C6PDevicePublicIdentityContract

    /// Optional client-side signed statement could be added later.
    /// For v1: keep minimal.
    let requestId: String

    init(
        virtualNumber: C6PVirtualNumberString,
        device: C6PDevicePublicIdentityContract,
        requestId: String = UUID().uuidString
    ) {
        self.apiVersion = C6P_IDENTITY_API_VERSION
        self.virtualNumber = virtualNumber
        self.device = device
        self.requestId = requestId
    }
}

struct C6PRegisterDeviceResponse: Codable, Hashable {
    let apiVersion: UInt8
    let virtualNumber: C6PVirtualNumberString
    let deviceIdHex: String
    let registeredAt: Date
}

/// Optional: device removal (server-side authorization rules apply)
struct C6PRemoveDeviceRequest: Codable, Hashable {
    let apiVersion: UInt8
    let virtualNumber: C6PVirtualNumberString
    let deviceIdHex: String
    let requestId: String
}

struct C6PRemoveDeviceResponse: Codable, Hashable {
    let apiVersion: UInt8
    let virtualNumber: C6PVirtualNumberString
    let deviceIdHex: String
    let removed: Bool
    let removedAt: Date?
}

// MARK: - Profile updates (optional in v1)

struct C6PUpdateProfileRequest: Codable, Hashable {
    let apiVersion: UInt8
    let virtualNumber: C6PVirtualNumberString

    let username: C6PUsernameHandle?
    let profileName: C6PProfileName
    let avatar: C6PAvatarContractRef

    let requestId: String
}

struct C6PUpdateProfileResponse: Codable, Hashable {
    let apiVersion: UInt8
    let virtualNumber: C6PVirtualNumberString
    let updatedAt: Date
}
