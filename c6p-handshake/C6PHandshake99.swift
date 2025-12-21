//
//  C6PHandshake99.swift
//  C6P-Protocol
//
//  Canonical production implementation of C6P prekey-based handshake ("handshake99").
//
//  CANON v1:
//  1) Initiator fetches bundle from backend (server atomically reserves/consumes OTP if present).
//  2) Initiator computes secrets locally and sends Handshake Offer via backend.
//  3) Responder computes secrets locally using current SignedPrekey private key
//     and optional OneTimePrekey private key if offer references OTP id.
//  4) Server never computes session secrets.
//
//  Crypto:
//  - Ed25519 identity key verifies SignedPrekey signature (label || spk_pub).
//  - X25519 ECDH: DH(ephemeral, signedPrekey) || DH(ephemeral, oneTimePrekey)?
//  - HKDF-SHA256 root/chain keys via C6PKeySchedule.
//
//  Encoding:
//  - Wire structs use base64url (no padding) for all binary fields.
//

import Foundation
import CryptoKit

// MARK: - Errors

public enum C6PHandshakeError: Error, CustomStringConvertible {

    case invalidProtocolVersion(expected: UInt8, actual: UInt8)

    case invalidIdentityPublicKeyLength(actual: Int)
    case invalidSignedPrekeyPublicKeyLength(actual: Int)
    case invalidOneTimePrekeyPublicKeyLength(actual: Int)
    case invalidEphemeralPublicKeyLength(actual: Int)
    case invalidSignedPrekeySignatureLength(actual: Int)

    case invalidBundleOneTimePrekeyInconsistency
    case identityOverrideMismatch
    case signatureVerificationFailed
    case signedPrekeyMismatchToOffer
    case missingOneTimePrekey
    case inconsistentDeviceIds

    case keyAgreementFailed
    case internalInvariantFailed(String)

    public var description: String {
        switch self {
        case .invalidProtocolVersion(let expected, let actual):
            return "C6PHandshakeError.invalidProtocolVersion(expected=\(expected), actual=\(actual))"

        case .invalidIdentityPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidIdentityPublicKeyLength(actual=\(actual))"
        case .invalidSignedPrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual=\(actual))"
        case .invalidOneTimePrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual=\(actual))"
        case .invalidEphemeralPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidEphemeralPublicKeyLength(actual=\(actual))"
        case .invalidSignedPrekeySignatureLength(let actual):
            return "C6PHandshakeError.invalidSignedPrekeySignatureLength(actual=\(actual))"

        case .invalidBundleOneTimePrekeyInconsistency:
            return "C6PHandshakeError.invalidBundleOneTimePrekeyInconsistency"
        case .identityOverrideMismatch:
            return "C6PHandshakeError.identityOverrideMismatch"
        case .signatureVerificationFailed:
            return "C6PHandshakeError.signatureVerificationFailed"
        case .signedPrekeyMismatchToOffer:
            return "C6PHandshakeError.signedPrekeyMismatchToOffer"
        case .missingOneTimePrekey:
            return "C6PHandshakeError.missingOneTimePrekey"
        case .inconsistentDeviceIds:
            return "C6PHandshakeError.inconsistentDeviceIds"

        case .keyAgreementFailed:
            return "C6PHandshakeError.keyAgreementFailed"
        case .internalInvariantFailed(let msg):
            return "C6PHandshakeError.internalInvariantFailed(\(msg))"
        }
    }
}

// MARK: - Constants

private let C6P_HANDSHAKE99_VERSION: UInt8 = 1
private let C6P_PREKEY_SIGNATURE_LABEL = "C6P_PREKEY_V1"
private let C6P_HANDSHAKE99_LABEL = "C6P_HANDSHAKE99_V1"

// MARK: - Handshake offer (wire-level, base64url)

public struct C6PHandshake99Offer: Codable, Hashable {

    public let version: UInt8

    public let initiatorDeviceId: C6PDeviceId
    public let responderDeviceId: C6PDeviceId

    public let sessionId: C6PSessionId

    public let ephemeralPublicKeyX25519: C6PBase64UrlData          // 32 bytes
    public let usedSignedPrekeyPublicKeyX25519: C6PBase64UrlData   // 32 bytes

    public let usedOneTimePrekeyId: C6PKeyId?

    public init(
        version: UInt8 = C6P_HANDSHAKE99_VERSION,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        ephemeralPublicKeyX25519: Data,
        usedSignedPrekeyPublicKeyX25519: Data,
        usedOneTimePrekeyId: C6PKeyId?
    ) throws {
        self.version = version
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.sessionId = sessionId
        self.ephemeralPublicKeyX25519 = C6PBase64UrlData(ephemeralPublicKeyX25519)
        self.usedSignedPrekeyPublicKeyX25519 = C6PBase64UrlData(usedSignedPrekeyPublicKeyX25519)
        self.usedOneTimePrekeyId = usedOneTimePrekeyId
        try validate()
    }

    public func validate() throws {
        guard version == C6P_HANDSHAKE99_VERSION else {
            throw C6PHandshakeError.invalidProtocolVersion(expected: C6P_HANDSHAKE99_VERSION, actual: version)
        }
        guard ephemeralPublicKeyX25519.data.count == 32 else {
            throw C6PHandshakeError.invalidEphemeralPublicKeyLength(actual: ephemeralPublicKeyX25519.data.count)
        }
        guard usedSignedPrekeyPublicKeyX25519.data.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: usedSignedPrekeyPublicKeyX25519.data.count)
        }
    }
}

// MARK: - Results

public struct C6PHandshake99InitiatorResult {
    public let sessionId: C6PSessionId
    public let rootKey: C6PRootKey
    public let sendChainKey: C6PChainKey
    public let recvChainKey: C6PChainKey
    public var sendCounter: C6PMessageCounter
    public var recvCounter: C6PMessageCounter

    public let offer: C6PHandshake99Offer
    public let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey

    public let usedOneTimePrekeyId: C6PKeyId?
}

public struct C6PHandshake99ResponderResult {
    public let sessionId: C6PSessionId
    public let rootKey: C6PRootKey
    public let sendChainKey: C6PChainKey
    public let recvChainKey: C6PChainKey
    public var sendCounter: C6PMessageCounter
    public var recvCounter: C6PMessageCounter
    public let consumedOneTimePrekeyId: C6PKeyId?
}

// MARK: - Handshake99

public enum C6PHandshake99 {

    // MARK: Initiator

    public static func startAsInitiator(
        localDeviceId: C6PDeviceId,
        prekeyBundle: C6PPrekeyBundleContract,
        identityPublicKeyOverride: Data? = nil
    ) throws -> C6PHandshake99InitiatorResult {

        // 0) Contract validation (OTP consistency etc.)
        try prekeyBundle.validate()

        // 1) Length checks (fail-closed)
        let idPubRaw = prekeyBundle.identityPublicKeyEd25519.data
        let spkPubRaw = prekeyBundle.signedPrekeyPublicKeyX25519.data
        let spkSigRaw = prekeyBundle.signedPrekeySignature.data

        guard idPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidIdentityPublicKeyLength(actual: idPubRaw.count)
        }
        guard spkPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: spkPubRaw.count)
        }
        guard spkSigRaw.count == 64 else {
            throw C6PHandshakeError.invalidSignedPrekeySignatureLength(actual: spkSigRaw.count)
        }
        if let otpPub = prekeyBundle.oneTimePrekeyPublicKeyX25519?.data, otpPub.count != 32 {
            throw C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual: otpPub.count)
        }

        // 2) Pin/override check (TOFU/pinning handled above)
        if let pinned = identityPublicKeyOverride, pinned != idPubRaw {
            throw C6PHandshakeError.identityOverrideMismatch
        }

        // 3) Build public keys
        let identityPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: idPubRaw)
        let signedPrekeyPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: spkPubRaw)

        let oneTimePrekeyPub: Curve25519.KeyAgreement.PublicKey? = try {
            if let raw = prekeyBundle.oneTimePrekeyPublicKeyX25519?.data {
                return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
            }
            return nil
        }()

        // 4) Verify signed-prekey signature: Sig(label || spkPub)
        var signedMessage = Data()
        signedMessage.append(C6P_PREKEY_SIGNATURE_LABEL.data(using: .utf8)!)
        signedMessage.append(spkPubRaw)

        guard identityPubKey.isValidSignature(spkSigRaw, for: signedMessage) else {
            throw C6PHandshakeError.signatureVerificationFailed
        }

        // 5) Generate ephemeral
        let ephPriv = Curve25519.KeyAgreement.PrivateKey()
        let ephPubRaw = ephPriv.publicKey.rawRepresentation

        // 6) IKM = DH(ephemeral, SPK) || DH(ephemeral, OTP)?
        var ikm = Data()
        do {
            let dh1 = try ephPriv.sharedSecretFromKeyAgreement(with: signedPrekeyPub)
            ikm.append(sharedSecretToData(dh1))
        } catch {
            throw C6PHandshakeError.keyAgreementFailed
        }

        if let otpPub = oneTimePrekeyPub {
            do {
                let dh2 = try ephPriv.sharedSecretFromKeyAgreement(with: otpPub)
                ikm.append(sharedSecretToData(dh2))
            } catch {
                throw C6PHandshakeError.keyAgreementFailed
            }
        }

        // 7) sessionId by initiator
        let sessionId = try C6PSessionId.random()

        // 8) Transcript salt
        let salt = handshakeSalt(
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            ephemeralPublicKeyX25519: ephPubRaw,
            signedPrekeyPublicKeyX25519: spkPubRaw,
            oneTimePrekeyPublicKeyX25519: prekeyBundle.oneTimePrekeyPublicKeyX25519?.data
        )

        // 9) RootKey
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId
        )

        // 10) Chain keys (initiator POV)
        let sendCK = C6PKeySchedule.deriveChainKey(
            rootKey: rootKey,
            selfDeviceId: localDeviceId,
            remoteDeviceId: prekeyBundle.responderDeviceId,
            role: .initiator,
            direction: .sending
        )

        let recvCK = C6PKeySchedule.deriveChainKey(
            rootKey: rootKey,
            selfDeviceId: localDeviceId,
            remoteDeviceId: prekeyBundle.responderDeviceId,
            role: .initiator,
            direction: .receiving
        )

        // 11) Offer
        let offer = try C6PHandshake99Offer(
            version: C6P_HANDSHAKE99_VERSION,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            sessionId: sessionId,
            ephemeralPublicKeyX25519: ephPubRaw,
            usedSignedPrekeyPublicKeyX25519: spkPubRaw,
            usedOneTimePrekeyId: prekeyBundle.oneTimePrekeyId
        )

        return C6PHandshake99InitiatorResult(
            sessionId: sessionId,
            rootKey: rootKey,
            sendChainKey: sendCK,
            recvChainKey: recvCK,
            sendCounter: C6PMessageCounter(value: 0),
            recvCounter: C6PMessageCounter(value: 0),
            offer: offer,
            ephemeralPrivateKey: ephPriv,
            usedOneTimePrekeyId: prekeyBundle.oneTimePrekeyId
        )
    }

    // MARK: Responder

    public static func acceptAsResponder(
        offer: C6PHandshake99Offer,
        localDeviceId: C6PDeviceId,
        signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        oneTimePrekeys: [C6PKeyId: Curve25519.KeyAgreement.PrivateKey]
    ) throws -> C6PHandshake99ResponderResult {

        // 1) Validate offer
        try offer.validate()

        // 2) Device binding
        guard offer.responderDeviceId == localDeviceId else {
            throw C6PHandshakeError.inconsistentDeviceIds
        }

        // 3) Signed-prekey binding (prevents server splicing)
        let actualSPKPub = signedPrekeyPrivateKey.publicKey.rawRepresentation
        guard actualSPKPub == offer.usedSignedPrekeyPublicKeyX25519.data else {
            throw C6PHandshakeError.signedPrekeyMismatchToOffer
        }

        // 4) Initiator ephemeral pub
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: offer.ephemeralPublicKeyX25519.data)

        // 5) IKM = DH(SPK_priv, eph_pub) || DH(OTP_priv, eph_pub)?
        var ikm = Data()
        do {
            let dh1 = try signedPrekeyPrivateKey.sharedSecretFromKeyAgreement(with: ephPub)
            ikm.append(sharedSecretToData(dh1))
        } catch {
            throw C6PHandshakeError.keyAgreementFailed
        }

        var consumedOTP: C6PKeyId? = nil
        var otpPubRaw: Data? = nil

        if let otpId = offer.usedOneTimePrekeyId {
            guard let otpPriv = oneTimePrekeys[otpId] else {
                throw C6PHandshakeError.missingOneTimePrekey
            }
            do {
                let dh2 = try otpPriv.sharedSecretFromKeyAgreement(with: ephPub)
                ikm.append(sharedSecretToData(dh2))
            } catch {
                throw C6PHandshakeError.keyAgreementFailed
            }

            consumedOTP = otpId
            otpPubRaw = otpPriv.publicKey.rawRepresentation
        }

        // 6) Transcript salt (must match initiator)
        let salt = handshakeSalt(
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId,
            ephemeralPublicKeyX25519: offer.ephemeralPublicKeyX25519.data,
            signedPrekeyPublicKeyX25519: offer.usedSignedPrekeyPublicKeyX25519.data,
            oneTimePrekeyPublicKeyX25519: otpPubRaw
        )

        // 7) RootKey
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId
        )

        // 8) Chain keys (responder POV)
        let sendCK = C6PKeySchedule.deriveChainKey(
            rootKey: rootKey,
            selfDeviceId: localDeviceId,
            remoteDeviceId: offer.initiatorDeviceId,
            role: .responder,
            direction: .sending
        )

        let recvCK = C6PKeySchedule.deriveChainKey(
            rootKey: rootKey,
            selfDeviceId: localDeviceId,
            remoteDeviceId: offer.initiatorDeviceId,
            role: .responder,
            direction: .receiving
        )

        return C6PHandshake99ResponderResult(
            sessionId: offer.sessionId,
            rootKey: rootKey,
            sendChainKey: sendCK,
            recvChainKey: recvCK,
            sendCounter: C6PMessageCounter(value: 0),
            recvCounter: C6PMessageCounter(value: 0),
            consumedOneTimePrekeyId: consumedOTP
        )
    }

    // MARK: - Helpers

    private static func sharedSecretToData(_ secret: SharedSecret) -> Data {
        secret.withUnsafeBytes { Data($0) }
    }

    private static func handshakeSalt(
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        ephemeralPublicKeyX25519: Data,
        signedPrekeyPublicKeyX25519: Data,
        oneTimePrekeyPublicKeyX25519: Data?
    ) -> Data {

        var transcript = Data()
        transcript.append(C6P_HANDSHAKE99_LABEL.data(using: .utf8)!)
        transcript.append(C6P_VERSION)
        transcript.append(C6P_HANDSHAKE99_VERSION)

        transcript.append(sessionId.data)
        transcript.append(initiatorDeviceId.data)
        transcript.append(responderDeviceId.data)

        transcript.append(ephemeralPublicKeyX25519)
        transcript.append(signedPrekeyPublicKeyX25519)

        if let otp = oneTimePrekeyPublicKeyX25519 {
            transcript.append(0x01)
            transcript.append(otp)
        } else {
            transcript.append(0x00)
        }

        let hash = SHA256.hash(data: transcript)
        return Data(hash)
    }
}
