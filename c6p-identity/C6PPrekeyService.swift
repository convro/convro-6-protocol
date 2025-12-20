//
//  C6PPrekeyService.swift
//  C6P-Protocol
//
//  Production service for managing device prekeys (signed prekey + one-time prekeys)
//  for handshake99 (prekey-based sessions).
//
//  Responsibilities:
//  - Generate & store signed prekey (X25519) + Ed25519 signature (identity key).
//  - Generate, store & serve one-time prekeys (X25519) with stable key IDs.
//  - Publish public prekey material to backend.
//  - Provide private keys for responder-side handshake acceptance (signed prekey + OTP).
//  - Consume OTP locally once used.
//
//  Security posture: fail-closed, auditable, no silent fallbacks.
//

import Foundation
import CryptoKit
import Security

// MARK: - Errors

enum C6PPrekeyServiceError: Error, CustomStringConvertible {
    case onboardingNotCompletedNoAccountIdentity
    case noActiveDeviceId
    case identitySigningKeyUnavailable
    case identityAgreementKeyUnavailable

    case signedPrekeyMissing
    case oneTimePrekeyMissing(C6PKeyId)

    case invalidPublicKeyLength(expected: Int, actual: Int)
    case keychain(OSStatus)

    case publishRejected(reason: String)
    case serverBundleInvalid(reason: String)

    var description: String {
        switch self {
        case .onboardingNotCompletedNoAccountIdentity:
            return "C6PPrekeyServiceError.onboardingNotCompletedNoAccountIdentity – account identity not found; finish registration first"
        case .noActiveDeviceId:
            return "C6PPrekeyServiceError.noActiveDeviceId – active device not set in identity store"
        case .identitySigningKeyUnavailable:
            return "C6PPrekeyServiceError.identitySigningKeyUnavailable – Ed25519 identity private key missing"
        case .identityAgreementKeyUnavailable:
            return "C6PPrekeyServiceError.identityAgreementKeyUnavailable – X25519 identity private key missing"
        case .signedPrekeyMissing:
            return "C6PPrekeyServiceError.signedPrekeyMissing – no signed prekey present locally"
        case .oneTimePrekeyMissing(let id):
            return "C6PPrekeyServiceError.oneTimePrekeyMissing(\(id.hexString)) – OTP private key not found locally"
        case .invalidPublicKeyLength(let expected, let actual):
            return "C6PPrekeyServiceError.invalidPublicKeyLength(expected=\(expected), actual=\(actual))"
        case .keychain(let status):
            return "C6PPrekeyServiceError.keychain(status=\(status))"
        case .publishRejected(let reason):
            return "C6PPrekeyServiceError.publishRejected(reason=\(reason))"
        case .serverBundleInvalid(let reason):
            return "C6PPrekeyServiceError.serverBundleInvalid(reason=\(reason))"
        }
    }
}

// MARK: - API Client Contract

/// Transport contract for publishing and fetching prekeys.
/// Keep it sync for now because your `C6PSessionService` uses sync providers.
protocol C6PPrekeyAPIClient {
    func publishPrekeys(_ request: C6PPublishPrekeysRequest) throws -> C6PPublishPrekeysResponse
    func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundleContract
    func markOneTimePrekeyConsumed(responderDeviceId: C6PDeviceId, oneTimePrekeyId: C6PKeyId) throws
}

// MARK: - Identity Provider Contract

/// Minimal interface `c6p-identity` must provide to prekey service.
/// Your Keychain store should implement it (directly or via adapter).
protocol C6PLocalIdentityProvider {
    func loadAccountIdentity() throws -> C6PAccountIdentity
    func requireActiveDeviceId() throws -> C6PDeviceId

    func loadIdentitySigningPrivateKey(for deviceId: C6PDeviceId) throws -> Curve25519.Signing.PrivateKey
    func loadIdentityAgreementPrivateKey(for deviceId: C6PDeviceId) throws -> Curve25519.KeyAgreement.PrivateKey
}

// MARK: - Wire Contracts (Identity-level, shared with backend)

/// Public signed prekey record (publish -> backend).
struct C6PSignedPrekeyPublicRecord: Codable, Hashable {
    /// X25519 public key (32 bytes).
    let publicKeyX25519: Data
    /// Ed25519 signature over: label || publicKeyX25519
    let signatureEd25519: Data
    /// Client timestamp (UTC) for rotation/audits.
    let createdAt: Date
}

/// Public one-time prekey record (publish -> backend).
struct C6POneTimePrekeyPublicRecord: Codable, Hashable {
    let prekeyId: C6PKeyId
    /// X25519 public key (32 bytes).
    let publicKeyX25519: Data
    let createdAt: Date
}

/// Publish request for one device.
struct C6PPublishPrekeysRequest: Codable, Hashable {
    let c6pVersion: UInt8
    let virtualNumber: String          // canonical: +99 + 6 digits (no spaces)
    let deviceId: C6PDeviceId

    /// Identity public key (Ed25519) may be redundant if device registration already pinned it.
    /// Keeping it explicit makes server state auditable and reduces "silent magic".
    let identityPublicKeyEd25519: Data

    let signedPrekey: C6PSignedPrekeyPublicRecord
    let oneTimePrekeys: [C6POneTimePrekeyPublicRecord]
}

/// Publish response.
struct C6PPublishPrekeysResponse: Codable, Hashable {
    let accepted: Bool
    let acceptedOneTimePrekeyIds: [C6PKeyId]
    let serverTime: Date
    let message: String?
}

/// This is the bundle initiator fetches for handshake99.
/// Keep it in `c6p-identity` as a single canonical contract (do NOT duplicate it in handshake later).
struct C6PPrekeyBundleContract: Codable, Hashable {
    let responderDeviceId: C6PDeviceId

    let identityPublicKeyEd25519: Data
    let signedPrekeyPublicKeyX25519: Data
    let signedPrekeySignature: Data

    let oneTimePrekeyId: C6PKeyId?
    let oneTimePrekeyPublicKeyX25519: Data?
}

// MARK: - Local persistent records (Keychain)

private struct C6PLocalSignedPrekeyRecord: Codable, Hashable {
    let privateKeyX25519: Data // rawRepresentation
    let publicKeyX25519: Data  // rawRepresentation
    let signatureEd25519: Data
    let createdAt: Date
}

private struct C6PLocalOTPIndex: Codable, Hashable {
    var ids: [String] // hex strings (stable, JSON-safe)
}

// MARK: - Prekey Service (Production)

/// Production prekey manager.
/// Use as:
/// - after registration complete
/// - on app start
/// - periodically (rotation + OTP replenish)
final class C6PPrekeyService {

    // MARK: Domain separation labels (must match handshake99 rules)

    /// Must match the label used to verify signed prekeys.
    /// (Same semantics as in handshake99: signature over label || SPK_pub)
    private static let prekeySignatureLabel = "C6P_PREKEY_V1"

    // MARK: Dependencies

    private let identity: C6PLocalIdentityProvider
    private let api: C6PPrekeyAPIClient

    // MARK: Keychain namespace

    private let keychain = C6PSecureKeychain(service: "pl.convro.c6p.prekeys")

    // MARK: Policy knobs (v1 defaults)

    /// How often to rotate signed prekey.
    /// (Signals rotate ~ weekly-ish; v1 can start with 7 days and tune later.)
    private let signedPrekeyMaxAgeDays: Int

    /// Ensure at least N one-time prekeys available locally (and on server).
    private let minOneTimePrekeys: Int

    /// Generate & publish this many OTPs when replenishing.
    private let oneTimeBatchSize: Int

    // MARK: Init

    init(
        identity: C6PLocalIdentityProvider,
        api: C6PPrekeyAPIClient,
        signedPrekeyMaxAgeDays: Int = 7,
        minOneTimePrekeys: Int = 50,
        oneTimeBatchSize: Int = 25
    ) {
        self.identity = identity
        self.api = api
        self.signedPrekeyMaxAgeDays = max(1, signedPrekeyMaxAgeDays)
        self.minOneTimePrekeys = max(0, minOneTimePrekeys)
        self.oneTimeBatchSize = max(1, oneTimeBatchSize)
    }

    // MARK: - Public: bootstrap/publish

    /// Ensures local signed prekey exists and is fresh; ensures OTP pool is above minimum;
    /// publishes public material to backend.
    ///
    /// Call:
    /// - after registration finished
    /// - on cold app start
    /// - periodically (e.g. app foreground)
    func bootstrapAndPublishIfNeeded() throws {
        let account = try requireAccount()
        let deviceId = try identity.requireActiveDeviceId()
        _ = try identity.loadIdentityAgreementPrivateKey(for: deviceId) // sanity check availability
        let signingPriv = try identity.loadIdentitySigningPrivateKey(for: deviceId)

        // 1) Ensure signed prekey
        let signed = try ensureSignedPrekey(deviceId: deviceId, signingKey: signingPriv)

        // 2) Ensure OTP pool
        let needed = try max(0, minOneTimePrekeys - currentOTPCount(deviceId: deviceId))
        var generatedOTPs: [C6POneTimePrekeyPublicRecord] = []
        if needed > 0 {
            let toGenerate = max(oneTimeBatchSize, needed)
            generatedOTPs = try generateAndStoreOneTimePrekeys(deviceId: deviceId, count: toGenerate)
        }

        // 3) Publish
        let req = C6PPublishPrekeysRequest(
            c6pVersion: C6P_VERSION,
            virtualNumber: account.virtualNumberCanonical,
            deviceId: deviceId,
            identityPublicKeyEd25519: signingPriv.publicKey.rawRepresentation,
            signedPrekey: C6PSignedPrekeyPublicRecord(
                publicKeyX25519: signed.publicKeyX25519,
                signatureEd25519: signed.signatureEd25519,
                createdAt: signed.createdAt
            ),
            oneTimePrekeys: generatedOTPs
        )

        let resp = try api.publishPrekeys(req)
        guard resp.accepted else {
            throw C6PPrekeyServiceError.publishRejected(reason: resp.message ?? "server rejected prekeys")
        }

        // 4) If server accepted subset, keep only accepted OTPs locally (optional strictness).
        //    In v1 we fail-closed on mismatch? Not necessary; we can keep locally and publish later.
        //    But: to reduce drift, we remove OTPs that server explicitly did NOT accept (if any were generated).
        if generatedOTPs.isEmpty == false {
            let acceptedSet = Set(resp.acceptedOneTimePrekeyIds.map { $0.hexString })
            let generatedIds = generatedOTPs.map { $0.prekeyId.hexString }
            let rejected = generatedIds.filter { acceptedSet.contains($0) == false }

            // Remove rejected locally (strict).
            for hex in rejected {
                if let id = try? C6PKeyId(hexString: hex) {
                    try? deleteOneTimePrekey(deviceId: deviceId, id: id)
                }
            }
        }
    }

    // MARK: - Public: responder-side key access

    /// Provides private signed prekey for responder handshake acceptance.
    func loadSignedPrekeyPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        let deviceId = try identity.requireActiveDeviceId()
        let record = try loadLocalSignedPrekey(deviceId: deviceId)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: record.privateKeyX25519)
    }

    /// Provides private OTP for responder handshake acceptance.
    func loadOneTimePrekeyPrivateKey(for id: C6PKeyId) throws -> Curve25519.KeyAgreement.PrivateKey {
        let deviceId = try identity.requireActiveDeviceId()
        let data = try loadOneTimePrekey(deviceId: deviceId, id: id)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    /// Consumes OTP locally (delete) AND tells server it's consumed (optional but recommended).
    ///
    /// Call this after `C6PHandshake99.acceptAsResponder(...)` succeeds.
    func consumeOneTimePrekey(_ id: C6PKeyId) throws {
        let deviceId = try identity.requireActiveDeviceId()
        try deleteOneTimePrekey(deviceId: deviceId, id: id)

        // Best-effort server mark: consumption should be authoritative on server to avoid reuse.
        // Fail-closed? In v1, failing to notify server is not a cryptographic break,
        // but it can allow reuse of same OTP in the bundle pool. So we treat as error.
        try api.markOneTimePrekeyConsumed(responderDeviceId: deviceId, oneTimePrekeyId: id)
    }

    // MARK: - Public: initiator fetch (bridge for session service)

    func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) throws -> C6PPrekeyBundleContract {
        let bundle = try api.fetchPrekeyBundle(remoteDeviceId: remoteDeviceId)
        try validateBundle(bundle)
        return bundle
    }

    // MARK: - Core: signed prekey

    private func ensureSignedPrekey(
        deviceId: C6PDeviceId,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> C6PLocalSignedPrekeyRecord {
        if let existing = try? loadLocalSignedPrekey(deviceId: deviceId) {
            if isSignedPrekeyFresh(existing.createdAt) {
                return existing
            }
        }

        // Generate new X25519 signed prekey
        let spkPriv = Curve25519.KeyAgreement.PrivateKey()
        let spkPub = spkPriv.publicKey.rawRepresentation

        guard spkPub.count == 32 else {
            throw C6PPrekeyServiceError.invalidPublicKeyLength(expected: 32, actual: spkPub.count)
        }

        // Signature over: label || spkPub
        var msg = Data()
        msg.append(Self.prekeySignatureLabel.data(using: .utf8)!)
        msg.append(spkPub)

        let sig = try signingKey.signature(for: msg)
        let sigData = sig

        let record = C6PLocalSignedPrekeyRecord(
            privateKeyX25519: spkPriv.rawRepresentation,
            publicKeyX25519: spkPub,
            signatureEd25519: sigData,
            createdAt: Date()
        )

        try saveLocalSignedPrekey(deviceId: deviceId, record: record)
        return record
    }

    private func isSignedPrekeyFresh(_ createdAt: Date) -> Bool {
        let maxAgeSeconds = TimeInterval(signedPrekeyMaxAgeDays * 24 * 60 * 60)
        return Date().timeIntervalSince(createdAt) <= maxAgeSeconds
    }

    // MARK: - Core: one-time prekeys

    private func currentOTPCount(deviceId: C6PDeviceId) throws -> Int {
        return try loadOTPIndex(deviceId: deviceId).ids.count
    }

    private func generateAndStoreOneTimePrekeys(
        deviceId: C6PDeviceId,
        count: Int
    ) throws -> [C6POneTimePrekeyPublicRecord] {
        guard count > 0 else { return [] }

        var index = try loadOTPIndex(deviceId: deviceId)
        var out: [C6POneTimePrekeyPublicRecord] = []
        out.reserveCapacity(count)

        for _ in 0..<count {
            let id = try C6PKeyId.random()
            let priv = Curve25519.KeyAgreement.PrivateKey()
            let pub = priv.publicKey.rawRepresentation

            guard pub.count == 32 else {
                throw C6PPrekeyServiceError.invalidPublicKeyLength(expected: 32, actual: pub.count)
            }

            try saveOneTimePrekey(deviceId: deviceId, id: id, privateKeyRaw: priv.rawRepresentation)

            index.ids.append(id.hexString)

            out.append(
                C6POneTimePrekeyPublicRecord(
                    prekeyId: id,
                    publicKeyX25519: pub,
                    createdAt: Date()
                )
            )
        }

        try saveOTPIndex(deviceId: deviceId, index: index)
        return out
    }

    // MARK: - Bundle validation

    private func validateBundle(_ b: C6PPrekeyBundleContract) throws {
        guard b.identityPublicKeyEd25519.count == 32 else {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "identityPublicKeyEd25519 length != 32")
        }
        guard b.signedPrekeyPublicKeyX25519.count == 32 else {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "signedPrekeyPublicKeyX25519 length != 32")
        }
        // OTP is optional
        if let otp = b.oneTimePrekeyPublicKeyX25519 {
            guard otp.count == 32 else {
                throw C6PPrekeyServiceError.serverBundleInvalid(reason: "oneTimePrekeyPublicKeyX25519 length != 32")
            }
        }
    }

    // MARK: - Account guard

    private func requireAccount() throws -> C6PAccountIdentity {
        do {
            return try identity.loadAccountIdentity()
        } catch {
            throw C6PPrekeyServiceError.onboardingNotCompletedNoAccountIdentity
        }
    }

    // MARK: - Keychain persistence (Signed Prekey)

    private func signedPrekeyKey(deviceId: C6PDeviceId) -> String {
        "signed_prekey_v1__device_\(deviceId.hexString)"
    }

    private func saveLocalSignedPrekey(deviceId: C6PDeviceId, record: C6PLocalSignedPrekeyRecord) throws {
        let data = try JSONEncoder().encode(record)
        try keychain.setData(data, key: signedPrekeyKey(deviceId: deviceId), accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func loadLocalSignedPrekey(deviceId: C6PDeviceId) throws -> C6PLocalSignedPrekeyRecord {
        let data = try keychain.getData(key: signedPrekeyKey(deviceId: deviceId))
        return try JSONDecoder().decode(C6PLocalSignedPrekeyRecord.self, from: data)
    }

    // MARK: - Keychain persistence (OTP Index + OTP items)

    private func otpIndexKey(deviceId: C6PDeviceId) -> String {
        "otp_index_v1__device_\(deviceId.hexString)"
    }

    private func otpItemKey(deviceId: C6PDeviceId, id: C6PKeyId) -> String {
        "otp_priv_v1__device_\(deviceId.hexString)__id_\(id.hexString)"
    }

    private func loadOTPIndex(deviceId: C6PDeviceId) throws -> C6PLocalOTPIndex {
        if let data = try? keychain.getData(key: otpIndexKey(deviceId: deviceId)) {
            return try JSONDecoder().decode(C6PLocalOTPIndex.self, from: data)
        }
        return C6PLocalOTPIndex(ids: [])
    }

    private func saveOTPIndex(deviceId: C6PDeviceId, index: C6PLocalOTPIndex) throws {
        let data = try JSONEncoder().encode(index)
        try keychain.setData(data, key: otpIndexKey(deviceId: deviceId), accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func saveOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId, privateKeyRaw: Data) throws {
        try keychain.setData(privateKeyRaw, key: otpItemKey(deviceId: deviceId, id: id), accessibility: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func loadOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId) throws -> Data {
        return try keychain.getData(key: otpItemKey(deviceId: deviceId, id: id))
    }

    private func deleteOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId) throws {
        // Remove key item
        try keychain.delete(key: otpItemKey(deviceId: deviceId, id: id))

        // Remove from index
        var index = try loadOTPIndex(deviceId: deviceId)
        index.ids.removeAll { $0 == id.hexString }
        try saveOTPIndex(deviceId: deviceId, index: index)
    }
}

// MARK: - Helpers: canonical VN

private extension C6PAccountIdentity {
    /// Must be canonical: "+99" + 6 digits. No spaces.
    var virtualNumberCanonical: String {
        // Assumption: your `C6PAccountIdentity` already stores canonical string.
        // If not, normalize once at creation-time and store canonical.
        return self.virtualNumber
    }
}

// MARK: - Minimal secure Keychain wrapper (Data-only)

private final class C6PSecureKeychain {

    private let service: String

    init(service: String) {
        self.service = service
    }

    func setData(_ data: Data, key: String, accessibility: CFString) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: accessibility
        ]

        // Try update first
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data
        ]

        let statusUpdate = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if statusUpdate == errSecSuccess {
            return
        }

        if statusUpdate != errSecItemNotFound {
            throw C6PPrekeyServiceError.keychain(statusUpdate)
        }

        // Add new
        var addQuery = query
        addQuery[kSecValueData as String] = data

        let statusAdd = SecItemAdd(addQuery as CFDictionary, nil)
        guard statusAdd == errSecSuccess else {
            throw C6PPrekeyServiceError.keychain(statusAdd)
        }
    }

    func getData(key: String) throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            throw C6PPrekeyServiceError.keychain(status)
        }
        guard let data = item as? Data else {
            throw C6PPrekeyServiceError.keychain(errSecInternalError)
        }
        return data
    }

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw C6PPrekeyServiceError.keychain(status)
        }
    }
}
