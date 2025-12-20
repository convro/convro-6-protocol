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
//      * X25519 agreement (future-proofing)
//  - expose a PUBLIC representation safe for backend/storage
//  - private keys never leave the device
//

import Foundation
import CryptoKit

// MARK: - Errors

public enum C6PDeviceIdentityError: Error, CustomStringConvertible {
    case invalidPublicKeyLength(expected: Int, actual: Int)

    public var description: String {
        switch self {
        case .invalidPublicKeyLength(let expected, let actual):
            return "C6PDeviceIdentityError.invalidPublicKeyLength(expected=\(expected), actual=\(actual))"
        }
    }
}

// MARK: - Public Device Identity (safe for server)

public struct C6PPublicDeviceIdentity: Hashable, Codable, CustomStringConvertible {

    public let deviceId: C6PDeviceId

    /// Ed25519 public key (32 bytes)
    public let identityPublicKeyEd25519: Data

    /// X25519 public key (32 bytes)
    public let identityPublicKeyX25519: Data

    /// UI-only fingerprint (NOT used in protocol logic).
    /// Stable short form: first 12 hex chars of SHA256(ed25519Pub).
    public var fingerprintShort: String {
        let digest = SHA256.hash(data: identityPublicKeyEd25519)
        return digest.compactMap { String(format: "%02x", $0) }.joined().prefix(12).lowercased()
    }

    public init(
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

    public var description: String {
        "C6PPublicDeviceIdentity(deviceId=\(deviceId.hexString), fp=\(fingerprintShort))"
    }
}

// MARK: - Private Device Identity (client-side only)

public struct C6PDeviceIdentity: Hashable {

    public let deviceId: C6PDeviceId

    /// Long-term Ed25519 signing keypair
    public let ed25519PrivateKey: Curve25519.Signing.PrivateKey

    /// Long-term X25519 agreement keypair
    public let x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey

    public init(
        deviceId: C6PDeviceId,
        ed25519PrivateKey: Curve25519.Signing.PrivateKey,
        x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey
    ) {
        self.deviceId = deviceId
        self.ed25519PrivateKey = ed25519PrivateKey
        self.x25519PrivateKey = x25519PrivateKey
    }

    /// Safe conversion to public identity.
    public func makePublicIdentity() throws -> C6PPublicDeviceIdentity {
        try C6PPublicDeviceIdentity(
            deviceId: deviceId,
            identityPublicKeyEd25519: ed25519PrivateKey.publicKey.rawRepresentation,
            identityPublicKeyX25519: x25519PrivateKey.publicKey.rawRepresentation
        )
    }

    /// Generates a fresh device identity (client-side).
    public static func generate(deviceId: C6PDeviceId) -> C6PDeviceIdentity {
        C6PDeviceIdentity(
            deviceId: deviceId,
            ed25519PrivateKey: Curve25519.Signing.PrivateKey(),
            x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey()
        )
    }

    // MARK: - Sign helpers

    /// Signs arbitrary data with the device Ed25519 identity key.
    public func sign(_ data: Data) -> Data {
        ed25519PrivateKey.signature(for: data)
    }

    /// Verifies a signature using this device's public Ed25519 key.
    public func verify(signature: Data, for data: Data) -> Bool {
        ed25519PrivateKey.publicKey.isValidSignature(signature, for: data)
    }
}

