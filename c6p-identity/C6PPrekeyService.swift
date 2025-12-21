//
//  C6PPrekeyService.swift
//  C6P-Protocol
//
//  Production service for managing device prekeys (signed prekey + one-time prekeys)
//  for handshake99.
//
//  Responsibilities:
//  - Generate & store signed prekey (X25519) + Ed25519 signature (identity key).
//  - Generate/store OTP prekeys (X25519) with stable key IDs.
//  - Publish public prekey material to backend.
//  - Provide private keys for responder-side handshake acceptance.
//  - Consume OTP locally + notify server.
//
//  Security posture: fail-closed, auditable.
//
//  IMPORTANT:
//  - Wire contracts are defined ONLY in `C6PPrekeyContracts.swift` (single source of truth).
//

import Foundation
import CryptoKit
import Security

// MARK: - Errors

public enum C6PPrekeyServiceError: Error, CustomStringConvertible {
    case onboardingNotCompletedNoAccountIdentity
    case noActiveDeviceId
    case deviceIdentityMissing

    case signedPrekeyMissing
    case oneTimePrekeyMissing(C6PKeyId)

    case invalidPublicKeyLength(expected: Int, actual: Int)

    case publishRejected(reason: String)
    case serverBundleInvalid(reason: String)

    case keychainError(status: OSStatus, operation: String)
    case notFound(String)
    case decodeFailed(String)
    case encodeFailed(String)

    public var description: String {
        switch self {
        case .onboardingNotCompletedNoAccountIdentity:
            return "C6PPrekeyServiceError.onboardingNotCompletedNoAccountIdentity"
        case .noActiveDeviceId:
            return "C6PPrekeyServiceError.noActiveDeviceId"
        case .deviceIdentityMissing:
            return "C6PPrekeyServiceError.deviceIdentityMissing"

        case .signedPrekeyMissing:
            return "C6PPrekeyServiceError.signedPrekeyMissing"
        case .oneTimePrekeyMissing(let id):
            return "C6PPrekeyServiceError.oneTimePrekeyMissing(\(id.hexString))"

        case .invalidPublicKeyLength(let e, let a):
            return "C6PPrekeyServiceError.invalidPublicKeyLength(expected=\(e), actual=\(a))"

        case .publishRejected(let reason):
            return "C6PPrekeyServiceError.publishRejected(reason=\(reason))"
        case .serverBundleInvalid(let reason):
            return "C6PPrekeyServiceError.serverBundleInvalid(reason=\(reason))"

        case .keychainError(let status, let op):
            return "C6PPrekeyServiceError.keychainError(status=\(status), operation=\(op))"
        case .notFound(let key):
            return "C6PPrekeyServiceError.notFound(\(key))"
        case .decodeFailed(let what):
            return "C6PPrekeyServiceError.decodeFailed(\(what))"
        case .encodeFailed(let what):
            return "C6PPrekeyServiceError.encodeFailed(\(what))"
        }
    }
}

// MARK: - API Client Contract (async)

public protocol C6PPrekeyAPIClient {
    func publishPrekeys(_ request: C6PPublishPrekeysRequest) async throws -> C6PPublishPrekeysResponse
    func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) async throws -> C6PPrekeyBundleContract
    func consumeOneTimePrekey(_ request: C6PConsumeOneTimePrekeyRequest) async throws -> C6PConsumeOneTimePrekeyResponse
}

// MARK: - Local persistent records (Keychain)

private struct C6PLocalSignedPrekeyRecord: Codable, Hashable {
    let privateKeyX25519B64u: String
    let publicKeyX25519B64u: String
    let signatureEd25519B64u: String
    let createdAt: Date
}

private struct C6PLocalOTPIndex: Codable, Hashable {
    var ids: [String] // hex strings
}

// MARK: - Prekey Service

public final class C6PPrekeyService {

    // Domain separation label (must match handshake99 verification)
    private static let prekeySignatureLabel = "C6P_PREKEY_V1"

    // Dependencies
    private let identityStore: C6PIdentityKeychainStore
    private let api: C6PPrekeyAPIClient

    // Keychain namespace for prekeys
    private let keychain = C6PSecureKeychain(service: "pl.convro.c6p.prekeys")

    // Policy knobs (v1 defaults)
    private let signedPrekeyMaxAgeDays: Int
    private let minOneTimePrekeys: Int
    private let oneTimeBatchSize: Int

    public init(
        identityStore: C6PIdentityKeychainStore,
        api: C6PPrekeyAPIClient,
        signedPrekeyMaxAgeDays: Int = 7,
        minOneTimePrekeys: Int = 50,
        oneTimeBatchSize: Int = 25
    ) {
        self.identityStore = identityStore
        self.api = api
        self.signedPrekeyMaxAgeDays = max(1, signedPrekeyMaxAgeDays)
        self.minOneTimePrekeys = max(0, minOneTimePrekeys)
        self.oneTimeBatchSize = max(1, oneTimeBatchSize)
    }

    // MARK: - Bootstrap / publish

    public func bootstrapAndPublishIfNeeded(c6pVersion: UInt8 = C6P_VERSION) async throws {
        let account = try requireAccount()
        let deviceId = try requireActiveDeviceId()
        let deviceIdentity = try identityStore.loadDeviceIdentity(deviceId: deviceId)

        // VN must be canonical at this layer
        let vn = try C6PVirtualNumber(canonical: account.virtualNumber)

        // 1) Ensure signed prekey (fresh)
        let signed = try ensureSignedPrekey(
            deviceId: deviceId,
            signingKey: deviceIdentity.ed25519PrivateKey
        )

        // 2) Ensure OTP pool
        let current = try currentOTPCount(deviceId: deviceId)
        let needed = max(0, minOneTimePrekeys - current)

        var newlyGeneratedOTPs: [C6POneTimePrekeyPublicRecord] = []
        if needed > 0 {
            let toGenerate = max(oneTimeBatchSize, needed)
            newlyGeneratedOTPs = try generateAndStoreOneTimePrekeys(deviceId: deviceId, count: toGenerate)
        }

        // 3) Build publish request using canonical contracts
        let idPub = deviceIdentity.ed25519PrivateKey.publicKey.rawRepresentation

        let spkPub = try C6PEncoding.base64URLDecode(signed.publicKeyX25519B64u)
        let spkSig = try C6PEncoding.base64URLDecode(signed.signatureEd25519B64u)

        let signedRecord = C6PSignedPrekeyPublicRecord(
            publicKeyX25519: C6PBase64UrlData(spkPub),
            signatureEd25519: C6PBase64UrlData(spkSig),
            createdAt: signed.createdAt
        )

        let req = try C6PPublishPrekeysRequest(
            c6pVersion: c6pVersion,
            virtualNumber: vn,
            deviceId: deviceId,
            identityPublicKeyEd25519: idPub,
            signedPrekey: signedRecord,
            oneTimePrekeys: newlyGeneratedOTPs
        )

        let resp = try await api.publishPrekeys(req)
        guard resp.accepted else {
            throw C6PPrekeyServiceError.publishRejected(reason: resp.message ?? "server rejected prekeys")
        }

        // Optional strict drift cleanup: remove OTPs server explicitly rejected
        if !newlyGeneratedOTPs.isEmpty {
            let accepted = Set(resp.acceptedOneTimePrekeyIds.map { $0.hexString })
            for otp in newlyGeneratedOTPs {
                if accepted.contains(otp.prekeyId.hexString) == false {
                    try? deleteOneTimePrekey(deviceId: deviceId, id: otp.prekeyId)
                }
            }
        }
    }

    // MARK: - Responder-side key access

    public func loadSignedPrekeyPrivateKey() throws -> Curve25519.KeyAgreement.PrivateKey {
        let deviceId = try requireActiveDeviceId()
        let record = try loadLocalSignedPrekey(deviceId: deviceId)
        let privRaw = try C6PEncoding.base64URLDecode(record.privateKeyX25519B64u)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: privRaw)
    }

    public func loadOneTimePrekeyPrivateKey(for id: C6PKeyId) throws -> Curve25519.KeyAgreement.PrivateKey {
        let deviceId = try requireActiveDeviceId()
        let raw = try loadOneTimePrekey(deviceId: deviceId, id: id)
        return try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
    }

    /// Fail-closed consumption:
    /// - first notify server (authoritative pool)
    /// - only then delete locally (so we can retry if network fails)
    public func consumeOneTimePrekey(_ id: C6PKeyId) async throws {
        let deviceId = try requireActiveDeviceId()
        let req = try C6PConsumeOneTimePrekeyRequest(
            c6pVersion: C6P_VERSION,
            responderDeviceId: deviceId,
            oneTimePrekeyId: id
        )
        let resp = try await api.consumeOneTimePrekey(req)
        guard resp.consumed else {
            throw C6PPrekeyServiceError.publishRejected(reason: resp.message ?? "server refused OTP consume")
        }
        try deleteOneTimePrekey(deviceId: deviceId, id: id)
    }

    // MARK: - Initiator fetch (bundle)

    public func fetchPrekeyBundle(remoteDeviceId: C6PDeviceId) async throws -> C6PPrekeyBundleContract {
        let bundle = try await api.fetchPrekeyBundle(remoteDeviceId: remoteDeviceId)
        try validateBundle(bundle)
        return bundle
    }

    // MARK: - Signed prekey core

    private func ensureSignedPrekey(
        deviceId: C6PDeviceId,
        signingKey: Curve25519.Signing.PrivateKey
    ) throws -> C6PLocalSignedPrekeyRecord {
        if let existing = try? loadLocalSignedPrekey(deviceId: deviceId) {
            if isSignedPrekeyFresh(existing.createdAt) { return existing }
        }

        let spkPriv = Curve25519.KeyAgreement.PrivateKey()
        let spkPub = spkPriv.publicKey.rawRepresentation
        guard spkPub.count == 32 else {
            throw C6PPrekeyServiceError.invalidPublicKeyLength(expected: 32, actual: spkPub.count)
        }

        // signature over: label || spkPub
        var msg = Data()
        msg.append(Self.prekeySignatureLabel.data(using: .utf8)!)
        msg.append(spkPub)

        let sig = signingKey.signature(for: msg)

        let record = C6PLocalSignedPrekeyRecord(
            privateKeyX25519B64u: C6PEncoding.base64URLEncode(spkPriv.rawRepresentation),
            publicKeyX25519B64u: C6PEncoding.base64URLEncode(spkPub),
            signatureEd25519B64u: C6PEncoding.base64URLEncode(sig),
            createdAt: Date()
        )

        try saveLocalSignedPrekey(deviceId: deviceId, record: record)
        return record
    }

    private func isSignedPrekeyFresh(_ createdAt: Date) -> Bool {
        let maxAgeSeconds = TimeInterval(signedPrekeyMaxAgeDays * 24 * 60 * 60)
        return Date().timeIntervalSince(createdAt) <= maxAgeSeconds
    }

    // MARK: - OTP core

    private func currentOTPCount(deviceId: C6PDeviceId) throws -> Int {
        try loadOTPIndex(deviceId: deviceId).ids.count
    }

    private func generateAndStoreOneTimePrekeys(deviceId: C6PDeviceId, count: Int) throws -> [C6POneTimePrekeyPublicRecord] {
        guard count > 0 else { return [] }

        var index = try loadOTPIndex(deviceId: deviceId)
        index.ids.reserveCapacity(index.ids.count + count)

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
                    publicKeyX25519: C6PBase64UrlData(pub),
                    createdAt: Date()
                )
            )
        }

        try saveOTPIndex(deviceId: deviceId, index: index)
        return out
    }

    // MARK: - Bundle validation

    private func validateBundle(_ b: C6PPrekeyBundleContract) throws {
        do {
            try b.validate()
        } catch {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "\(error)")
        }

        // hard checks (fail-closed)
        guard b.identityPublicKeyEd25519.data.count == 32 else {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "identityPublicKeyEd25519 length != 32")
        }
        guard b.signedPrekeyPublicKeyX25519.data.count == 32 else {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "signedPrekeyPublicKeyX25519 length != 32")
        }
        // signature should be 64 bytes for Ed25519
        if b.signedPrekeySignature.data.count != 64 {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "signedPrekeySignature length != 64")
        }
        if let otpPub = b.oneTimePrekeyPublicKeyX25519?.data, otpPub.count != 32 {
            throw C6PPrekeyServiceError.serverBundleInvalid(reason: "oneTimePrekeyPublicKeyX25519 length != 32")
        }
    }

    // MARK: - Identity guards

    private func requireAccount() throws -> C6PAccountIdentity {
        do {
            return try identityStore.loadAccountIdentity()
        } catch {
            throw C6PPrekeyServiceError.onboardingNotCompletedNoAccountIdentity
        }
    }

    private func requireActiveDeviceId() throws -> C6PDeviceId {
        do {
            return try identityStore.loadActiveDeviceId()
        } catch {
            throw C6PPrekeyServiceError.noActiveDeviceId
        }
    }

    // MARK: - Keychain persistence keys

    private func signedPrekeyKey(deviceId: C6PDeviceId) -> String {
        "signed_prekey_v1__device_\(deviceId.hexString)"
    }

    private func otpIndexKey(deviceId: C6PDeviceId) -> String {
        "otp_index_v1__device_\(deviceId.hexString)"
    }

    private func otpItemKey(deviceId: C6PDeviceId, id: C6PKeyId) -> String {
        "otp_priv_v1__device_\(deviceId.hexString)__id_\(id.hexString)"
    }

    // MARK: - Signed prekey persistence

    private func saveLocalSignedPrekey(deviceId: C6PDeviceId, record: C6PLocalSignedPrekeyRecord) throws {
        let enc = C6PJSON.makeEncoder()
        guard let data = try? enc.encode(record) else {
            throw C6PPrekeyServiceError.encodeFailed("signedPrekeyRecord")
        }
        try keychain.upsertData(data, key: signedPrekeyKey(deviceId: deviceId), accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func loadLocalSignedPrekey(deviceId: C6PDeviceId) throws -> C6PLocalSignedPrekeyRecord {
        let data = try keychain.getData(key: signedPrekeyKey(deviceId: deviceId))
        let dec = C6PJSON.makeDecoder()
        guard let obj = try? dec.decode(C6PLocalSignedPrekeyRecord.self, from: data) else {
            throw C6PPrekeyServiceError.decodeFailed("signedPrekeyRecord")
        }
        return obj
    }

    // MARK: - OTP persistence

    private func loadOTPIndex(deviceId: C6PDeviceId) throws -> C6PLocalOTPIndex {
        if let data = try? keychain.getData(key: otpIndexKey(deviceId: deviceId)) {
            let dec = C6PJSON.makeDecoder()
            if let idx = try? dec.decode(C6PLocalOTPIndex.self, from: data) {
                return idx
            }
            throw C6PPrekeyServiceError.decodeFailed("otpIndex")
        }
        return C6PLocalOTPIndex(ids: [])
    }

    private func saveOTPIndex(deviceId: C6PDeviceId, index: C6PLocalOTPIndex) throws {
        let enc = C6PJSON.makeEncoder()
        guard let data = try? enc.encode(index) else {
            throw C6PPrekeyServiceError.encodeFailed("otpIndex")
        }
        try keychain.upsertData(data, key: otpIndexKey(deviceId: deviceId), accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func saveOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId, privateKeyRaw: Data) throws {
        try keychain.upsertData(privateKeyRaw, key: otpItemKey(deviceId: deviceId, id: id), accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
    }

    private func loadOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId) throws -> Data {
        do {
            return try keychain.getData(key: otpItemKey(deviceId: deviceId, id: id))
        } catch C6PPrekeyServiceError.notFound {
            throw C6PPrekeyServiceError.oneTimePrekeyMissing(id)
        }
    }

    private func deleteOneTimePrekey(deviceId: C6PDeviceId, id: C6PKeyId) throws {
        try keychain.delete(key: otpItemKey(deviceId: deviceId, id: id))

        var index = try loadOTPIndex(deviceId: deviceId)
        index.ids.removeAll { $0 == id.hexString }
        try saveOTPIndex(deviceId: deviceId, index: index)
    }
}

// MARK: - Minimal secure Keychain wrapper (Data-only, robust)

private final class C6PSecureKeychain {
    private let service: String

    init(service: String) { self.service = service }

    private func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    func upsertData(_ data: Data, key: String, accessible: CFString) throws {
        // update
        let q = baseQuery(key: key)
        let attrs: [String: Any] = [kSecValueData as String: data]

        let sUpdate = SecItemUpdate(q as CFDictionary, attrs as CFDictionary)
        if sUpdate == errSecSuccess { return }

        if sUpdate != errSecItemNotFound {
            throw C6PPrekeyServiceError.keychainError(status: sUpdate, operation: "SecItemUpdate(\(key))")
        }

        // add
        var addQ = q
        addQ[kSecValueData as String] = data
        addQ[kSecAttrAccessible as String] = accessible

        let sAdd = SecItemAdd(addQ as CFDictionary, nil)
        guard sAdd == errSecSuccess else {
            throw C6PPrekeyServiceError.keychainError(status: sAdd, operation: "SecItemAdd(\(key))")
        }
    }

    func getData(key: String) throws -> Data {
        var q = baseQuery(key: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)

        if status == errSecItemNotFound {
            throw C6PPrekeyServiceError.notFound(key)
        }
        guard status == errSecSuccess else {
            throw C6PPrekeyServiceError.keychainError(status: status, operation: "SecItemCopyMatching(\(key))")
        }
        guard let data = result as? Data else {
            throw C6PPrekeyServiceError.keychainError(status: errSecInternalError, operation: "InvalidResult(\(key))")
        }
        return data
    }

    func delete(key: String) throws {
        let q = baseQuery(key: key)
        let status = SecItemDelete(q as CFDictionary)
        if status == errSecItemNotFound { return }
        guard status == errSecSuccess else {
            throw C6PPrekeyServiceError.keychainError(status: status, operation: "SecItemDelete(\(key))")
        }
    }
}

