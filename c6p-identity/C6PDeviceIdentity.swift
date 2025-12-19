//
//  C6PDeviceIdentity.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Device identity package (long-term keys) for Convro.
//
//  v1 goals:
//  - each device has long-term identity keys:
//      * Ed25519 signing (attestation, signatures)
//      * X25519 agreement (future-proofing / identity ECDH uses)
//  - expose a PUBLIC representation safe for backend/storage
//  - allow optional binding to account virtual number (+99 VN) at the app layer
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PDeviceIdentityError: Error, CustomStringConvertible {
    case invalidPublicKeyLength(expected: Int, actual: Int)

    var description: String {
        switch self {
        case .invalidPublicKeyLength(let expected, let actual):
            return "C6PDeviceIdentityError.invalidPublicKeyLength(expected=\(expected), actual=\(actual))"
        }
    }
}

// MARK: - Public Device Identity (safe to send/store server-side)

/// Public identity of a device (safe for backend).
///
/// This is what backend can store and return:
/// - deviceId
/// - Ed25519 public key (identity signing)
/// - X25519 public key (identity agreement)
///
/// Note: backend still MUST NOT infer message content; this is identity metadata only.
struct C6PPublicDeviceIdentity: Hashable, Codable, CustomStringConvertible {

    let deviceId: C6PDeviceId

    /// Ed25519 public key (32 bytes)
    let identityPublicKeyEd25519: Data

    /// X25519 public key (32 bytes)
    let identityPublicKeyX25519: Data

    /// Optional fingerprint helper for UI verification.
    /// (Not used in protocol logic, purely for user-facing checks.)
    var fingerprint: String {
        C6PFingerprint.fingerprint(forPublicKey: identityPublicKeyEd25519)
    }

    init(
        deviceId: C6PDeviceId,
        identityPublicKeyEd25519: Data,
        identityPublicKeyX25519: Data
    ) throws {
        guard identityPublicKeyEd25519.count == 32 else {
            throw C6PDeviceIdentityError.invalidPublicKeyLength(expected: 32, actual: identityPublicKeyEd25519.count)
        }
        guard identityPublicKeyX25519.count == 32 else {
            throw C6PDeviceIdentityError.invalidPublicKeyLength(expected: 32, actual: identityPublicKeyX25519.count)
        }
        self.deviceId = deviceId
        self.identityPublicKeyEd25519 = identityPublicKeyEd25519
        self.identityPublicKeyX25519 = identityPublicKeyX25519
    }

    var description: String {
        "C6PPublicDeviceIdentity(deviceId=\(deviceId.hexString), fp=\(fingerprint))"
    }
}

// MARK: - Private Device Identity (client-side only)

/// Full device identity (private keys included).
///
/// Must be stored securely (Keychain / Secure Enclave where appropriate).
/// Never sent to backend.
struct C6PDeviceIdentity: Hashable {

    let deviceId: C6PDeviceId

    /// Long-term Ed25519 signing keypair
    let ed25519PrivateKey: Curve25519.Signing.PrivateKey

    /// Long-term X25519 agreement keypair
    let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey

    // MARK: - Derived public identity

    var publicIdentity: C6PPublicDeviceIdentity {
        // rawRepresentation sizes are fixed for these key types (32 bytes public)
        // If CryptoKit changes, the initializer in publicIdentity will catch it.
        return try! C6PPublicDeviceIdentity(
            deviceId: deviceId,
            identityPublicKeyEd25519: ed25519PrivateKey.publicKey.rawRepresentation,
            identityPublicKeyX25519: x25519PrivateKey.publicKey.rawRepresentation
        )
    }

    // MARK: - Init

    init(
        deviceId: C6PDeviceId,
        ed25519PrivateKey: Curve25519.Signing.PrivateKey,
        x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) {
        self.deviceId = deviceId
        self.ed25519PrivateKey = ed25519PrivateKey
        self.x25519PrivateKey = x25519PrivateKey
    }

    /// Generates a fresh device identity (client-side).
    /// `deviceId` must come from backend registration flow OR be generated locally
    /// and later accepted by backend (policy decision).
    static func generate(deviceId: C6PDeviceId) -> C6PDeviceIdentity {
        C6PDeviceIdentity(
            deviceId: deviceId,
            ed25519PrivateKey: Curve25519.Signing.PrivateKey(),
            x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey()
        )
    }

    // MARK: - Sign helpers

    /// Signs arbitrary data with the device Ed25519 identity key.
    /// Used for attestation / verifiable events in protocol extensions.
    func sign(_ data: Data) -> Data {
        ed25519PrivateKey.signature(for: data)
    }

    /// Verifies a signature using this device's public Ed25519 key.
    func verify(signature: Data, for data: Data) -> Bool {
        ed25519PrivateKey.publicKey.isValidSignature(signature, for: data)
    }
}
