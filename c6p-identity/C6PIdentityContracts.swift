//
//  C6PIdentityContracts.swift
//  C6P-Protocol
//
//  Production wire contracts for Convro Tunnel backend (canonical).
//
//  Backend endpoints (current):
//  - POST /v1/auth/register
//  - POST /v1/auth/login
//  - POST /v1/auth/refresh
//  - POST /v1/auth/logout
//  - GET  /v1/auth/me
//  - POST /v1/auth/devices/register
//  - GET  /v1/auth/devices
//
//  Hard rules:
//  - Convro number: "+99" + exactly 6 digits (canonical)
//  - deviceId: 16 hex lowercase
//

import Foundation

// MARK: - Errors / Validation

public enum C6PIdentityContractError: Error, CustomStringConvertible {
    case invalidUsername
    case invalidFullName
    case invalidPassword
    case invalidDeviceId
    case invalidDeviceLabel
    case invalidPlatform

    public var description: String {
        switch self {
        case .invalidUsername: return "C6PIdentityContractError.invalidUsername"
        case .invalidFullName: return "C6PIdentityContractError.invalidFullName"
        case .invalidPassword: return "C6PIdentityContractError.invalidPassword"
        case .invalidDeviceId: return "C6PIdentityContractError.invalidDeviceId"
        case .invalidDeviceLabel: return "C6PIdentityContractError.invalidDeviceLabel"
        case .invalidPlatform: return "C6PIdentityContractError.invalidPlatform"
        }
    }
}

public enum C6PDevicePlatform: String, Codable {
    case ios
    case android
    case desktop
    case web
    case unknown
}

public enum C6PIdentityValidation {
    /// Matches backend: /^[0-9a-f]{16}$/
    public static func isValidDeviceIdHex16(_ s: String) -> Bool {
        let v = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard v.count == 16 else { return false }
        return v.allSatisfy { ch in
            (ch >= "0" && ch <= "9") || (ch >= "a" && ch <= "f")
        }
    }

    /// Matches backend:
    /// - length 3...64
    /// - allowed: [a-zA-Z0-9_.]
    public static func isValidUsername(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...64).contains(t.count) else { return false }
        return t.allSatisfy { ch in
            (ch >= "a" && ch <= "z") ||
            (ch >= "A" && ch <= "Z") ||
            (ch >= "0" && ch <= "9") ||
            ch == "_" || ch == "."
        }
    }

    /// Backend stores full_name up to 128 (you slice to 128); we mirror that.
    public static func sanitizeFullName(_ s: String?) throws -> String? {
        guard let raw = s else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.count > 128 { return String(t.prefix(128)) }
        // reject control chars
        for u in t.unicodeScalars where CharacterSet.controlCharacters.contains(u) {
            throw C6PIdentityContractError.invalidFullName
        }
        return t
    }

    public static func sanitizeDeviceLabel(_ s: String?) throws -> String? {
        guard let raw = s else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if t.count > 128 { return String(t.prefix(128)) }
        for u in t.unicodeScalars where CharacterSet.controlCharacters.contains(u) {
            throw C6PIdentityContractError.invalidDeviceLabel
        }
        return t
    }
}

// MARK: - Generic API error payload (backend style)

/// Backend errors look like:
/// { "error": "SOME_CODE", "message": "...", "field": "..." }
public struct C6PAPIErrorResponse: Codable, Hashable {
    public let error: String
    public let message: String?
    public let field: String?

    public init(error: String, message: String? = nil, field: String? = nil) {
        self.error = error
        self.message = message
        self.field = field
    }
}

// MARK: - Auth: /v1/auth/register

public struct C6PAuthRegisterRequest: Codable, Hashable {
    public let password: String
    public let username: String?
    public let fullName: String?

    public let deviceId: String?
    public let platform: C6PDevicePlatform?
    public let deviceLabel: String?

    public init(
        password: String,
        username: String?,
        fullName: String?,
        deviceId: String?,
        platform: C6PDevicePlatform?,
        deviceLabel: String?
    ) throws {
        let pw = password
        guard pw.count >= 8 else { throw C6PIdentityContractError.invalidPassword }

        if let u = username {
            let t = u.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && !C6PIdentityValidation.isValidUsername(t) {
                throw C6PIdentityContractError.invalidUsername
            }
            self.username = t.isEmpty ? nil : t
        } else {
            self.username = nil
        }

        self.fullName = try C6PIdentityValidation.sanitizeFullName(fullName)

        if let did = deviceId {
            let v = did.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !v.isEmpty && !C6PIdentityValidation.isValidDeviceIdHex16(v) {
                throw C6PIdentityContractError.invalidDeviceId
            }
            self.deviceId = v.isEmpty ? nil : v
        } else {
            self.deviceId = nil
        }

        self.platform = platform
        self.deviceLabel = try C6PIdentityValidation.sanitizeDeviceLabel(deviceLabel)
        self.password = pw
    }
}

public struct C6PAuthRegisterResponse: Codable, Hashable {
    public let userId: Int64
    public let convroNumber: C6PVirtualNumber
    public let username: String?
    public let fullName: String?
    public let deviceId: String
    public let platform: String
    public let accessToken: String
    public let refreshToken: String
}

// MARK: - Auth: /v1/auth/login

public struct C6PAuthLoginRequest: Codable, Hashable {
    public let password: String
    public let username: String?
    public let convroNumber: String?

    public let deviceId: String?
    public let platform: C6PDevicePlatform?
    public let deviceLabel: String?

    public init(
        password: String,
        username: String?,
        convroNumber: String?,
        deviceId: String?,
        platform: C6PDevicePlatform?,
        deviceLabel: String?
    ) throws {
        let pw = password
        guard pw.count >= 1 else { throw C6PIdentityContractError.invalidPassword }

        let u = username?.trimmingCharacters(in: .whitespacesAndNewlines)
        let vn = convroNumber?.trimmingCharacters(in: .whitespacesAndNewlines)

        if (u == nil || u!.isEmpty) && (vn == nil || vn!.isEmpty) {
            // backend requires one of them
            throw C6PIdentityContractError.invalidUsername
        }

        if let u = u, !u.isEmpty, !C6PIdentityValidation.isValidUsername(u) {
            throw C6PIdentityContractError.invalidUsername
        }

        if let vn = vn, !vn.isEmpty {
            // validate VN canonical or display (your VN type decodes both)
            _ = try C6PVirtualNumber(string: vn)
        }

        if let did = deviceId {
            let v = did.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !v.isEmpty && !C6PIdentityValidation.isValidDeviceIdHex16(v) {
                throw C6PIdentityContractError.invalidDeviceId
            }
            self.deviceId = v.isEmpty ? nil : v
        } else {
            self.deviceId = nil
        }

        self.password = pw
        self.username = (u?.isEmpty == false) ? u : nil
        self.convroNumber = (vn?.isEmpty == false) ? try C6PVirtualNumber(string: vn!).canonicalString : nil
        self.platform = platform
        self.deviceLabel = try C6PIdentityValidation.sanitizeDeviceLabel(deviceLabel)
    }
}

public struct C6PAuthLoginResponse: Codable, Hashable {
    public let userId: Int64
    public let convroNumber: C6PVirtualNumber
    public let username: String?
    public let fullName: String?
    public let deviceId: String
    public let platform: String
    public let accessToken: String
    public let refreshToken: String
}

// MARK: - Auth: /v1/auth/refresh

public struct C6PAuthRefreshRequest: Codable, Hashable {
    public let refreshToken: String

    public init(refreshToken: String) {
        self.refreshToken = refreshToken
    }
}

public struct C6PAuthRefreshResponse: Codable, Hashable {
    public let userId: Int64
    public let deviceId: String
    public let convroNumber: C6PVirtualNumber
    public let username: String?
    public let accessToken: String
    public let refreshToken: String
}

// MARK: - Auth: /v1/auth/logout

public struct C6PAuthLogoutRequest: Codable, Hashable {
    public let refreshToken: String?
    public let allForDevice: Bool?
    public let allForUser: Bool?

    public init(refreshToken: String? = nil, allForDevice: Bool? = nil, allForUser: Bool? = nil) {
        self.refreshToken = refreshToken
        self.allForDevice = allForDevice
        self.allForUser = allForUser
    }
}

public struct C6PAuthLogoutResponse: Codable, Hashable {
    public let ok: Bool
    public let scope: String?
}

// MARK: - Auth: /v1/auth/me

public struct C6PAuthMeResponse: Codable, Hashable {
    public let userId: Int64
    public let deviceId: String
    public let convroNumber: C6PVirtualNumber?
    public let username: String?
}

// MARK: - Devices: /v1/auth/devices/register

public struct C6PAuthDevicesRegisterRequest: Codable, Hashable {
    public let deviceId: String?
    public let platform: C6PDevicePlatform?
    public let deviceLabel: String?

    public init(deviceId: String?, platform: C6PDevicePlatform?, deviceLabel: String?) throws {
        if let did = deviceId {
            let v = did.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !v.isEmpty && !C6PIdentityValidation.isValidDeviceIdHex16(v) {
                throw C6PIdentityContractError.invalidDeviceId
            }
            self.deviceId = v.isEmpty ? nil : v
        } else {
            self.deviceId = nil
        }
        self.platform = platform
        self.deviceLabel = try C6PIdentityValidation.sanitizeDeviceLabel(deviceLabel)
    }
}

public struct C6PAuthDevicesRegisterResponse: Codable, Hashable {
    public let ok: Bool
    public let deviceId: String
    public let platform: String
}

// MARK: - Devices: /v1/auth/devices

public struct C6PDeviceListItem: Codable, Hashable {
    public let deviceId: String
    public let platform: String
    public let deviceLabel: String?
    public let isActive: Bool
    public let createdAt: Date?
    public let lastSeenAt: Date?
}

public struct C6PAuthDevicesListResponse: Codable, Hashable {
    public let devices: [C6PDeviceListItem]
}

// MARK: - JSON helpers (recommended)

public enum C6PJSON {
    /// Use this decoder in your HTTP client for Convro Tunnel.
    public static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let dt = C6PISO8601.parse(s) { return dt }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }
        return d
    }

    public static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, enc in
            var c = enc.singleValueContainer()
            try c.encode(C6PISO8601.format(date))
        }
        return e
    }
}

public enum C6PISO8601 {
    // JS toISOString -> "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
    private static let f1: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let f2: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func parse(_ s: String) -> Date? {
        if let d = f1.date(from: s) { return d }
        if let d = f2.date(from: s) { return d }
        return nil
    }

    public static func format(_ d: Date) -> String {
        // keep fractional seconds for stability
        return f1.string(from: d)
    }
}
