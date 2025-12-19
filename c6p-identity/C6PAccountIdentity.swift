//
//  C6PAccountIdentity.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Account identity model for Convro (VN + profile + device bindings).
//
//  v1 goals:
//  - account addressed by a Convro Virtual Number (VN) in +99 namespace
//  - username is optional alias, must be unique (enforced by backend policy)
//  - devices are first-class: account can have multiple device identities
//  - keep metadata explicit and minimal
//

import Foundation

// MARK: - Errors

enum C6PAccountIdentityError: Error, CustomStringConvertible {
    case invalidUsername
    case invalidDisplayName
    case invalidAvatarReference
    case duplicateDeviceId(deviceId: C6PDeviceId)
    case missingPrimaryDevice
    case deviceNotFound(deviceId: C6PDeviceId)

    var description: String {
        switch self {
        case .invalidUsername:
            return "C6PAccountIdentityError.invalidUsername – username does not meet v1 rules"
        case .invalidDisplayName:
            return "C6PAccountIdentityError.invalidDisplayName – display name does not meet v1 rules"
        case .invalidAvatarReference:
            return "C6PAccountIdentityError.invalidAvatarReference – invalid avatar reference for v1"
        case .duplicateDeviceId(let id):
            return "C6PAccountIdentityError.duplicateDeviceId(deviceId=\(id.hexString))"
        case .missingPrimaryDevice:
            return "C6PAccountIdentityError.missingPrimaryDevice – account must have a primary device in v1"
        case .deviceNotFound(let id):
            return "C6PAccountIdentityError.deviceNotFound(deviceId=\(id.hexString))"
        }
    }
}

// MARK: - Username (alias) rules

/// v1 username rules (client-side validation).
///
/// NOTE: uniqueness is enforced server-side.
/// Client should validate format only.
enum C6PUsernamePolicy {

    /// Allowed characters: a-z, 0-9, underscore, dot
    /// Must start with a letter.
    /// Length: 3...24
    static func isValid(_ username: String) -> Bool {
        let u = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard u.count >= 3 && u.count <= 24 else { return false }

        // must start with a letter
        guard let first = u.unicodeScalars.first, CharacterSet.letters.contains(first) else {
            return false
        }

        // allowed set
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789_.")
        for scalar in u.lowercased().unicodeScalars {
            if !allowed.contains(scalar) { return false }
        }

        return true
    }
}

// MARK: - Display name rules

enum C6PDisplayNamePolicy {

    /// v1: human-friendly name, optional.
    /// Keep it conservative: 0...64, no control chars.
    static func isValid(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard n.count <= 64 else { return false }
        // Disallow control characters
        for scalar in n.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
        }
        return true
    }
}

// MARK: - Avatar reference

/// v1 avatar reference.
/// Keep it explicit: no remote URL by default (privacy & tracking).
///
/// Policy:
/// - store a local asset identifier OR a backend media id
/// - do not allow arbitrary http(s) URLs as avatar reference in v1
///
/// If later you want CDN URLs, do it as a versioned extension.
enum C6PAvatarReference: Hashable, Codable {
    case none
    case localAssetId(String)      // e.g., "avatar_default_01"
    case backendMediaId(String)    // e.g., "med_8f1d..."; opaque id

    var isValidV1: Bool {
        switch self {
        case .none:
            return true
        case .localAssetId(let s), .backendMediaId(let s):
            return C6PAccountIdentityPolicy.isSafeOpaqueId(s)
        }
    }
}

// MARK: - Account identity policy helpers

enum C6PAccountIdentityPolicy {

    /// Conservative "opaque id" check:
    /// - 1...128 chars
    /// - allowed: letters, digits, underscore, dash, dot
    static func isSafeOpaqueId(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty && t.count <= 128 else { return false }

        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.")

        for scalar in t.unicodeScalars {
            if !allowed.contains(scalar) { return false }
        }
        return true
    }
}

// MARK: - Device binding entry

/// Public device entry as linked to an account.
/// This is the account-level view (not private keys).
struct C6PAccountDeviceEntry: Hashable, Codable, CustomStringConvertible {

    let publicIdentity: C6PPublicDeviceIdentity

    /// Mark one device as "primary" for account lifecycle operations in v1
    /// (e.g., first registration device).
    var isPrimary: Bool

    /// When this device was linked to the account (client-side timestamp).
    var linkedAt: Date

    init(
        publicIdentity: C6PPublicDeviceIdentity,
        isPrimary: Bool,
        linkedAt: Date = Date()
    ) {
        self.publicIdentity = publicIdentity
        self.isPrimary = isPrimary
        self.linkedAt = linkedAt
    }

    var description: String {
        "C6PAccountDeviceEntry(deviceId=\(publicIdentity.deviceId.hexString), primary=\(isPrimary))"
    }
}

// MARK: - Account Identity

/// Account identity (VN namespace + profile + bound devices).
///
/// IMPORTANT:
/// - VN is stable account address.
/// - username is optional alias (unique server-side).
/// - devices are first-class; account is not "one magic key".
struct C6PAccountIdentity: Hashable, Codable, CustomStringConvertible {

    // MARK: Core

    /// Convro Virtual Number: +99 + 6 digits
    let virtualNumber: C6PVirtualNumber

    /// Optional username alias, without leading "@"
    /// Display layer can render "@username".
    var username: String?

    /// Optional profile name(s)
    var firstName: String?
    var lastName: String?

    /// Avatar reference (no arbitrary URL by default)
    var avatar: C6PAvatarReference

    // MARK: Devices

    /// Devices linked to the account (public identities only).
    private(set) var devices: [C6PAccountDeviceEntry]

    // MARK: Metadata

    var createdAt: Date
    var updatedAt: Date

    // MARK: Init

    init(
        virtualNumber: C6PVirtualNumber,
        username: String?,
        firstName: String?,
        lastName: String?,
        avatar: C6PAvatarReference = .none,
        devices: [C6PAccountDeviceEntry],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) throws {

        // Validate username format (if present)
        if let u = username, !u.isEmpty {
            guard C6PUsernamePolicy.isValid(u) else {
                throw C6PAccountIdentityError.invalidUsername
            }
        }

        // Validate names (if present)
        if let fn = firstName, !fn.isEmpty {
            guard C6PDisplayNamePolicy.isValid(fn) else {
                throw C6PAccountIdentityError.invalidDisplayName
            }
        }
        if let ln = lastName, !ln.isEmpty {
            guard C6PDisplayNamePolicy.isValid(ln) else {
                throw C6PAccountIdentityError.invalidDisplayName
            }
        }

        // Validate avatar policy
        guard avatar.isValidV1 else {
            throw C6PAccountIdentityError.invalidAvatarReference
        }

        // Validate devices: unique deviceIds + must have primary
        var seen = Set<C6PDeviceId>()
        var hasPrimary = false
        for d in devices {
            let id = d.publicIdentity.deviceId
            if seen.contains(id) {
                throw C6PAccountIdentityError.duplicateDeviceId(deviceId: id)
            }
            seen.insert(id)
            if d.isPrimary { hasPrimary = true }
        }

        guard hasPrimary else {
            throw C6PAccountIdentityError.missingPrimaryDevice
        }

        self.virtualNumber = virtualNumber
        self.username = (username?.isEmpty == true) ? nil : username
        self.firstName = (firstName?.isEmpty == true) ? nil : firstName
        self.lastName = (lastName?.isEmpty == true) ? nil : lastName
        self.avatar = avatar
        self.devices = devices
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    // MARK: - Computed

    var displayHandle: String {
        if let u = username, !u.isEmpty {
            return "@\(u)"
        }
        return virtualNumber.displayString
    }

    var displayName: String {
        let fn = (firstName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = (lastName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        if !fn.isEmpty && !ln.isEmpty { return "\(fn) \(ln)" }
        if !fn.isEmpty { return fn }
        if !ln.isEmpty { return ln }
        return displayHandle
    }

    var primaryDeviceId: C6PDeviceId {
        // Safe due to init validation
        devices.first(where: { $0.isPrimary })!.publicIdentity.deviceId
    }

    // MARK: - Mutating profile updates

    mutating func updateUsername(_ username: String?) throws {
        if let u = username, !u.isEmpty {
            guard C6PUsernamePolicy.isValid(u) else {
                throw C6PAccountIdentityError.invalidUsername
            }
            self.username = u
        } else {
            self.username = nil
        }
        markUpdated()
    }

    mutating func updateName(firstName: String?, lastName: String?) throws {
        if let fn = firstName, !fn.isEmpty {
            guard C6PDisplayNamePolicy.isValid(fn) else { throw C6PAccountIdentityError.invalidDisplayName }
            self.firstName = fn
        } else {
            self.firstName = nil
        }

        if let ln = lastName, !ln.isEmpty {
            guard C6PDisplayNamePolicy.isValid(ln) else { throw C6PAccountIdentityError.invalidDisplayName }
            self.lastName = ln
        } else {
            self.lastName = nil
        }

        markUpdated()
    }

    mutating func updateAvatar(_ avatar: C6PAvatarReference) throws {
        guard avatar.isValidV1 else {
            throw C6PAccountIdentityError.invalidAvatarReference
        }
        self.avatar = avatar
        markUpdated()
    }

    // MARK: - Device management

    mutating func addDevice(_ publicIdentity: C6PPublicDeviceIdentity, makePrimary: Bool = false) throws {
        let id = publicIdentity.deviceId
        if devices.contains(where: { $0.publicIdentity.deviceId == id }) {
            throw C6PAccountIdentityError.duplicateDeviceId(deviceId: id)
        }

        if makePrimary {
            // Demote existing primary
            for i in devices.indices { devices[i].isPrimary = false }
        }

        devices.append(C6PAccountDeviceEntry(publicIdentity: publicIdentity, isPrimary: makePrimary))
        // Ensure still has a primary (if list previously had one, it remains)
        if !devices.contains(where: { $0.isPrimary }) {
            // if none, first device becomes primary
            devices[0].isPrimary = true
        }

        markUpdated()
    }

    mutating func removeDevice(deviceId: C6PDeviceId) throws {
        guard let idx = devices.firstIndex(where: { $0.publicIdentity.deviceId == deviceId }) else {
            throw C6PAccountIdentityError.deviceNotFound(deviceId: deviceId)
        }

        let wasPrimary = devices[idx].isPrimary
        devices.remove(at: idx)

        // v1: cannot end up with zero devices
        // (If you want account tombstone state, define it explicitly in a future extension.)
        if devices.isEmpty {
            // This is a design-time invariant violation; treat as fatal in dev builds.
            // In production you may want a different error type.
            throw C6PAccountIdentityError.missingPrimaryDevice
        }

        // If primary removed -> promote first remaining
        if wasPrimary {
            for i in devices.indices { devices[i].isPrimary = false }
            devices[0].isPrimary = true
        }

        markUpdated()
    }

    mutating func setPrimaryDevice(deviceId: C6PDeviceId) throws {
        guard devices.contains(where: { $0.publicIdentity.deviceId == deviceId }) else {
            throw C6PAccountIdentityError.deviceNotFound(deviceId: deviceId)
        }
        for i in devices.indices {
            devices[i].isPrimary = (devices[i].publicIdentity.deviceId == deviceId)
        }
        markUpdated()
    }

    // MARK: - Metadata

    mutating func markUpdated() {
        updatedAt = Date()
    }

    // MARK: - CustomStringConvertible

    var description: String {
        "C6PAccountIdentity(vn=\(virtualNumber.canonicalString), handle=\(displayHandle), devices=\(devices.count))"
    }
}
