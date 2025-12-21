//
//  C6PHandshake99.swift
//  C6P-Protocol
//
//  Canonical production implementation of C6P prekey-based handshake ("handshake99").
//
//  CANON v1 (single source of truth):
//  1) Initiator fetches bundle from backend (server atomically reserves/consumes OTP if present).
//  2) Initiator computes secrets locally and sends C6PHandshake99OfferContract via backend.
//  3) Responder computes secrets locally using:
//       - current SignedPrekey private key
//       - OneTimePrekey private key if offer references OTP id
//  4) Server never computes session secrets.
//
//  Crypto:
//  - Ed25519 identity + signature verification of SPK
//  - X25519 ECDH
//  - HKDF-SHA256 root/chain keys (via C6PKeySchedule)
//
//  NOTE:
//  - Wire contracts: C6PPrekeyBundleContract (from C6PPrekeyContracts.swift)
//                    C6PHandshake99OfferContract (from C6PHandshakeContracts.swift)
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

/// Domain separation label for signed-prekey signature (Ed25519).
private let C6P_PREKEY_SIGNATURE_LABEL = "C6P_PREKEY_V1"

/// Domain separation label for handshake transcript salt.
private let C6P_HANDSHAKE99_LABEL = "C6P_HANDSHAKE99_V1"

// MARK: - Results

public struct C6PHandshake99InitiatorResult {
    public let sessionId: C6PSessionId
    public let rootKey: C6PRootKey
    public let sendChainKey: C6PChainKey
    public let recvChainKey: C6PChainKey
    public var sendCounter: C6PMessageCounter
    public var recvCounter: C6PMessageCounter

    public let offer: C6PHandshake99OfferContract

    /// Returned only for callers that want to explicitly drop references after sending offer.
    public let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey

    /// CANON metadata
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

    /// Start handshake99 as initiator using backend-provided prekey bundle (canonical contract).
    ///
    /// - Parameters:
    ///   - localDeviceId: initiator device id
    ///   - prekeyBundle: responder bundle from backend (C6PPrekeyBundleContract)
    ///   - identityPublicKeyOverride: optional pinned remote identity key (raw 32B Ed25519 pub)
    public static func startAsInitiator(
        localDeviceId: C6PDeviceId,
        prekeyBundle: C6PPrekeyBundleContract,
        identityPublicKeyOverride: Data? = nil
    ) throws -> C6PHandshake99InitiatorResult {

        // 0) OTP consistency in bundle (contract-level already checks, but we fail-closed)
        let hasOtpId = (prekeyBundle.oneTimePrekeyId != nil)
        let hasOtpPub = (prekeyBundle.oneTimePrekeyPublicKeyX25519 != nil)
        guard hasOtpId == hasOtpPub else {
            throw C6PHandshakeError.invalidBundleOneTimePrekeyInconsistency
        }

        // 1) Validate lengths
        let idPubRaw = prekeyBundle.identityPublicKeyEd25519.data
        guard idPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidIdentityPublicKeyLength(actual: idPubRaw.count)
        }

        let spkPubRaw = prekeyBundle.signedPrekeyPublicKeyX25519.data
        guard spkPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: spkPubRaw.count)
        }

        let spkSigRaw = prekeyBundle.signedPrekeySignature.data
        guard spkSigRaw.count == 64 else {
            throw C6PHandshakeError.invalidSignedPrekeySignatureLength(actual: spkSigRaw.count)
        }

        if let otpPub = prekeyBundle.oneTimePrekeyPublicKeyX25519?.data {
            guard otpPub.count == 32 else {
                throw C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual: otpPub.count)
            }
        }

        // 2) Pin/override check (server substitution defense when pinned)
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

        // 4) Verify signed-prekey signature:
        //    Sig over: label || signedPrekeyPublicKeyX25519
        var signedMessage = Data()
        signedMessage.append(contentsOf: Array(C6P_PREKEY_SIGNATURE_LABEL.utf8))
        signedMessage.append(spkPubRaw)

        guard identityPubKey.isValidSignature(spkSigRaw, for: signedMessage) else {
            throw C6PHandshakeError.signatureVerificationFailed
        }

        // 5) Generate initiator ephemeral keypair
        let ephemeralPriv = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPubRaw = ephemeralPriv.publicKey.rawRepresentation
        guard ephemeralPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidEphemeralPublicKeyLength(actual: ephemeralPubRaw.count)
        }

        // 6) IKM = DH1 || DH2(optional)
        var ikm = Data()
        do {
            let dh1 = try ephemeralPriv.sharedSecretFromKeyAgreement(with: signedPrekeyPub)
            ikm.append(sharedSecretToData(dh1))
        } catch {
            throw C6PHandshakeError.keyAgreementFailed
        }

        if let otpPub = oneTimePrekeyPub {
            do {
                let dh2 = try ephemeralPriv.sharedSecretFromKeyAgreement(with: otpPub)
                ikm.append(sharedSecretToData(dh2))
            } catch {
                throw C6PHandshakeError.keyAgreementFailed
            }
        }

        // 7) sessionId chosen by initiator
        let sessionId = try C6PSessionId.random()

        // 8) Deterministic transcript -> salt
        let salt = handshakeSalt(
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            ephemeralPublicKeyX25519: ephemeralPubRaw,
            signedPrekeyPublicKeyX25519: spkPubRaw,
            oneTimePrekeyPublicKeyX25519: prekeyBundle.oneTimePrekeyPublicKeyX25519?.data
        )

        // 9) Derive RootKey
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId
        )

        // 10) Derive chain keys (initiator POV)
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

        // 11) Offer to send via backend (canonical contract)
        let offer = try C6PHandshake99OfferContract(
            version: C6P_HANDSHAKE99_VERSION,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            sessionId: sessionId,
            ephemeralPublicKeyX25519: ephemeralPubRaw,
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
            ephemeralPrivateKey: ephemeralPriv,
            usedOneTimePrekeyId: prekeyBundle.oneTimePrekeyId
        )
    }

    // MARK: Responder

    /// Accept handshake99 as responder.
    ///
    /// Responder computes:
    /// IKM = DH(SPK_priv, eph_pub) || DH(OTP_priv, eph_pub)?
    ///
    /// IMPORTANT:
    /// - Server reserves OTP at bundle fetch (initiator).
    /// - Responder must delete referenced OTP private key locally after successful accept.
    public static func acceptAsResponder(
        offer: C6PHandshake99OfferContract,
        localDeviceId: C6PDeviceId,
        signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        oneTimePrekeys: [C6PKeyId: Curve25519.KeyAgreement.PrivateKey]
    ) throws -> C6PHandshake99ResponderResult {

        // 1) Version check
        guard offer.version == C6P_HANDSHAKE99_VERSION else {
            throw C6PHandshakeError.invalidProtocolVersion(expected: C6P_HANDSHAKE99_VERSION, actual: offer.version)
        }

        // 2) Device id check (offer must target this responder device)
        guard offer.responderDeviceId == localDeviceId else {
            throw C6PHandshakeError.inconsistentDeviceIds
        }

        // 3) Validate lengths
        let ephPubRaw = offer.ephemeralPublicKeyX25519.data
        guard ephPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidEphemeralPublicKeyLength(actual: ephPubRaw.count)
        }

        let offerSpkPubRaw = offer.usedSignedPrekeyPublicKeyX25519.data
        guard offerSpkPubRaw.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: offerSpkPubRaw.count)
        }

        // 4) Ensure offer's signed-prekey matches responder's current signed-prekey.
        let actualSignedPrekeyPubRaw = signedPrekeyPrivateKey.publicKey.rawRepresentation
        guard actualSignedPrekeyPubRaw == offerSpkPubRaw else {
            throw C6PHandshakeError.signedPrekeyMismatchToOffer
        }

        // 5) Build initiator ephemeral public key
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephPubRaw)

        // 6) IKM = DH1 || DH2(optional)
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

        // 7) Transcript salt (must match initiator)
        let salt = handshakeSalt(
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId,
            ephemeralPublicKeyX25519: ephPubRaw,
            signedPrekeyPublicKeyX25519: offerSpkPubRaw,
            oneTimePrekeyPublicKeyX25519: otpPubRaw
        )

        // 8) RootKey
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId
        )

        // 9) Chain keys (responder POV)
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

    /// Deterministic transcript salt for HKDF (SHA256 over transcript).
    private static func handshakeSalt(
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        ephemeralPublicKeyX25519: Data,
        signedPrekeyPublicKeyX25519: Data,
        oneTimePrekeyPublicKeyX25519: Data?
    ) -> Data {

        var transcript = Data()
        transcript.append(contentsOf: Array(C6P_HANDSHAKE99_LABEL.utf8))
        transcript.append(contentsOf: [C6P_VERSION])              // global protocol version
        transcript.append(contentsOf: [C6P_HANDSHAKE99_VERSION])  // handshake99 version

        transcript.append(sessionId.data)
        transcript.append(initiatorDeviceId.data)
        transcript.append(responderDeviceId.data)

        transcript.append(ephemeralPublicKeyX25519)
        transcript.append(signedPrekeyPublicKeyX25519)

        if let otp = oneTimePrekeyPublicKeyX25519 {
            transcript.append(contentsOf: [0x01])
            transcript.append(otp)
        } else {
            transcript.append(contentsOf: [0x00])
        }

        let hash = SHA256.hash(data: transcript)
        return Data(hash)
    }
}
