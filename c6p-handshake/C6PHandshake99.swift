//
//  Handshake99.swift
//  C6P-Protocol
//
//  Production implementation of C6P prekey-based handshake ("handshake99").
//
//  v1 goals:
//  - Minimal and auditable X3DH-style session bootstrap
//  - Server cannot compute session secrets
//  - Client can pin/override remote identity key to detect server substitution
//  - Deterministic transcript -> salt for HKDF
//
//  Crypto:
//  - Ed25519 (Curve25519.Signing) identity + signed-prekey signature
//  - X25519 (Curve25519.KeyAgreement) ECDH
//  - HKDF-SHA256 root/chain keys (via C6PKeySchedule)
//
//  NOTE:
//  - This module only bootstraps RootKey + ChainKeys.
//  - Message-level secrecy and integrity are enforced later by AEAD + ratcheting.
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PHandshakeError: Error, CustomStringConvertible {

    // Bundle / offer validation
    case invalidProtocolVersion(expected: UInt8, actual: UInt8)

    case invalidIdentityPublicKeyLength(actual: Int)
    case invalidSignedPrekeyPublicKeyLength(actual: Int)
    case invalidOneTimePrekeyPublicKeyLength(actual: Int)
    case invalidEphemeralPublicKeyLength(actual: Int)
    case invalidSignedPrekeySignatureLength(actual: Int)

    case invalidBundleOneTimePrekeyInconsistency // id without pub or pub without id
    case identityOverrideMismatch                // pinned identity mismatch
    case signatureVerificationFailed             // signed prekey signature invalid
    case signedPrekeyMismatchToOffer             // offer claims a signed prekey not equal to responder actual
    case missingOneTimePrekey                    // responder lacks referenced OTP

    case inconsistentDeviceIds                   // offer not intended for this device

    // Crypto failures
    case keyAgreementFailed
    case internalInvariantFailed(String)

    var description: String {
        switch self {
        case .invalidProtocolVersion(let expected, let actual):
            return "C6PHandshakeError.invalidProtocolVersion(expected=\(expected), actual=\(actual)) – unsupported handshake99 version"

        case .invalidIdentityPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidIdentityPublicKeyLength(actual=\(actual)) – Ed25519 public key must be 32 bytes"
        case .invalidSignedPrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual=\(actual)) – X25519 signed prekey must be 32 bytes"
        case .invalidOneTimePrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual=\(actual)) – X25519 one-time prekey must be 32 bytes"
        case .invalidEphemeralPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidEphemeralPublicKeyLength(actual=\(actual)) – X25519 ephemeral public key must be 32 bytes"
        case .invalidSignedPrekeySignatureLength(let actual):
            return "C6PHandshakeError.invalidSignedPrekeySignatureLength(actual=\(actual)) – Ed25519 signature must be 64 bytes"

        case .invalidBundleOneTimePrekeyInconsistency:
            return "C6PHandshakeError.invalidBundleOneTimePrekeyInconsistency – OTP id/pub must be both present or both nil"
        case .identityOverrideMismatch:
            return "C6PHandshakeError.identityOverrideMismatch – provided pinned identity key does not match bundle"
        case .signatureVerificationFailed:
            return "C6PHandshakeError.signatureVerificationFailed – signed prekey signature invalid for given identity key"
        case .signedPrekeyMismatchToOffer:
            return "C6PHandshakeError.signedPrekeyMismatchToOffer – offer references a signed prekey not matching responder signed prekey"
        case .missingOneTimePrekey:
            return "C6PHandshakeError.missingOneTimePrekey – offer references a one-time prekey that is not available locally"

        case .inconsistentDeviceIds:
            return "C6PHandshakeError.inconsistentDeviceIds – handshake offer has device IDs inconsistent with local expectations"

        case .keyAgreementFailed:
            return "C6PHandshakeError.keyAgreementFailed – X25519 shared secret could not be derived"
        case .internalInvariantFailed(let msg):
            return "C6PHandshakeError.internalInvariantFailed(\(msg))"
        }
    }
}

// MARK: - Constants

/// handshake99 version (NOT the same as global C6P_VERSION).
private let C6P_HANDSHAKE99_VERSION: UInt8 = 1

/// Domain separation label for signed-prekey signature.
private let C6P_PREKEY_SIGNATURE_LABEL = "C6P_PREKEY_V1"

/// Domain separation label for handshake transcript salt.
private let C6P_HANDSHAKE99_LABEL = "C6P_HANDSHAKE99_V1"

// MARK: - Prekey bundle (wire / server response)

/// Public prekey bundle returned by backend to initiator.
struct C6PPrekeyBundle: Codable, Hashable {

    let responderDeviceId: C6PDeviceId

    let identityPublicKeyEd25519: Data                // 32 bytes
    let signedPrekeyPublicKeyX25519: Data             // 32 bytes
    let signedPrekeySignature: Data                   // 64 bytes (Ed25519)

    let oneTimePrekeyId: C6PKeyId?                    // optional
    let oneTimePrekeyPublicKeyX25519: Data?           // optional (32 bytes)

    init(
        responderDeviceId: C6PDeviceId,
        identityPublicKeyEd25519: Data,
        signedPrekeyPublicKeyX25519: Data,
        signedPrekeySignature: Data,
        oneTimePrekeyId: C6PKeyId?,
        oneTimePrekeyPublicKeyX25519: Data?
    ) {
        self.responderDeviceId = responderDeviceId
        self.identityPublicKeyEd25519 = identityPublicKeyEd25519
        self.signedPrekeyPublicKeyX25519 = signedPrekeyPublicKeyX25519
        self.signedPrekeySignature = signedPrekeySignature
        self.oneTimePrekeyId = oneTimePrekeyId
        self.oneTimePrekeyPublicKeyX25519 = oneTimePrekeyPublicKeyX25519
    }
}

// MARK: - Handshake offer (wire-level)

/// First handshake message sent by initiator to responder via backend.
struct C6PHandshake99Offer: Codable, Hashable {

    let version: UInt8

    let initiatorDeviceId: C6PDeviceId
    let responderDeviceId: C6PDeviceId

    let sessionId: C6PSessionId

    let ephemeralPublicKeyX25519: Data                // 32 bytes

    /// Signed-prekey public key that initiator used (to bind transcript + allow responder checks).
    let usedSignedPrekeyPublicKeyX25519: Data         // 32 bytes

    /// Optional consumed OTP id.
    let usedOneTimePrekeyId: C6PKeyId?

    init(
        version: UInt8 = C6P_HANDSHAKE99_VERSION,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        sessionId: C6PSessionId,
        ephemeralPublicKeyX25519: Data,
        usedSignedPrekeyPublicKeyX25519: Data,
        usedOneTimePrekeyId: C6PKeyId?
    ) {
        self.version = version
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.sessionId = sessionId
        self.ephemeralPublicKeyX25519 = ephemeralPublicKeyX25519
        self.usedSignedPrekeyPublicKeyX25519 = usedSignedPrekeyPublicKeyX25519
        self.usedOneTimePrekeyId = usedOneTimePrekeyId
    }
}

// MARK: - Results

struct C6PHandshake99InitiatorResult {
    let sessionId: C6PSessionId
    let rootKey: C6PRootKey
    let sendChainKey: C6PChainKey
    let recvChainKey: C6PChainKey
    var sendCounter: C6PMessageCounter
    var recvCounter: C6PMessageCounter

    let offer: C6PHandshake99Offer

    /// Returned only for callers that want to explicitly drop references after sending offer.
    let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey
}

struct C6PHandshake99ResponderResult {
    let sessionId: C6PSessionId
    let rootKey: C6PRootKey
    let sendChainKey: C6PChainKey
    let recvChainKey: C6PChainKey
    var sendCounter: C6PMessageCounter
    var recvCounter: C6PMessageCounter
    let consumedOneTimePrekeyId: C6PKeyId?
}

// MARK: - Handshake99

enum C6PHandshake99 {

    // MARK: Initiator

    static func startAsInitiator(
        localDeviceId: C6PDeviceId,
        prekeyBundle: C6PPrekeyBundle,
        identityPublicKeyOverride: Data? = nil
    ) throws -> C6PHandshake99InitiatorResult {

        // 0) OTP consistency in bundle
        let hasOtpId = (prekeyBundle.oneTimePrekeyId != nil)
        let hasOtpPub = (prekeyBundle.oneTimePrekeyPublicKeyX25519 != nil)
        guard hasOtpId == hasOtpPub else {
            throw C6PHandshakeError.invalidBundleOneTimePrekeyInconsistency
        }

        // 1) Validate lengths
        guard prekeyBundle.identityPublicKeyEd25519.count == 32 else {
            throw C6PHandshakeError.invalidIdentityPublicKeyLength(actual: prekeyBundle.identityPublicKeyEd25519.count)
        }
        guard prekeyBundle.signedPrekeyPublicKeyX25519.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: prekeyBundle.signedPrekeyPublicKeyX25519.count)
        }
        guard prekeyBundle.signedPrekeySignature.count == 64 else {
            throw C6PHandshakeError.invalidSignedPrekeySignatureLength(actual: prekeyBundle.signedPrekeySignature.count)
        }
        if let otpPub = prekeyBundle.oneTimePrekeyPublicKeyX25519 {
            guard otpPub.count == 32 else {
                throw C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual: otpPub.count)
            }
        }

        // 2) Pin/override check (server substitution defense)
        if let pinned = identityPublicKeyOverride, pinned != prekeyBundle.identityPublicKeyEd25519 {
            throw C6PHandshakeError.identityOverrideMismatch
        }

        // 3) Build public keys
        let identityPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: prekeyBundle.identityPublicKeyEd25519)
        let signedPrekeyPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: prekeyBundle.signedPrekeyPublicKeyX25519)

        let oneTimePrekeyPub: Curve25519.KeyAgreement.PublicKey? = try {
            if let raw = prekeyBundle.oneTimePrekeyPublicKeyX25519 {
                return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
            }
            return nil
        }()

        // 4) Verify signed-prekey signature:
        //    Sig over: label || signedPrekeyPublicKeyX25519
        var signedMessage = Data()
        signedMessage.append(C6P_PREKEY_SIGNATURE_LABEL.data(using: .utf8)!)
        signedMessage.append(prekeyBundle.signedPrekeyPublicKeyX25519)

        guard identityPubKey.isValidSignature(prekeyBundle.signedPrekeySignature, for: signedMessage) else {
            throw C6PHandshakeError.signatureVerificationFailed
        }

        // 5) Generate initiator ephemeral keypair
        let ephemeralPriv = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPubRaw = ephemeralPriv.publicKey.rawRepresentation

        // 6) Compute IKM = DH1 || DH2(optional)
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
            signedPrekeyPublicKeyX25519: prekeyBundle.signedPrekeyPublicKeyX25519,
            oneTimePrekeyPublicKeyX25519: prekeyBundle.oneTimePrekeyPublicKeyX25519
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

        // 11) Offer to send via backend
        let offer = C6PHandshake99Offer(
            version: C6P_HANDSHAKE99_VERSION,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            sessionId: sessionId,
            ephemeralPublicKeyX25519: ephemeralPubRaw,
            usedSignedPrekeyPublicKeyX25519: prekeyBundle.signedPrekeyPublicKeyX25519,
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
            ephemeralPrivateKey: ephemeralPriv
        )
    }

    // MARK: Responder

    static func acceptAsResponder(
        offer: C6PHandshake99Offer,
        localDeviceId: C6PDeviceId,
        signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        oneTimePrekeys: [C6PKeyId: Curve25519.KeyAgreement.PrivateKey]
    ) throws -> C6PHandshake99ResponderResult {

        // 1) Version check
        guard offer.version == C6P_HANDSHAKE99_VERSION else {
            throw C6PHandshakeError.invalidProtocolVersion(
                expected: C6P_HANDSHAKE99_VERSION,
                actual: offer.version
            )
        }

        // 2) Device id check (offer must target this responder device)
        guard offer.responderDeviceId == localDeviceId else {
            throw C6PHandshakeError.inconsistentDeviceIds
        }

        // 3) Validate lengths
        guard offer.ephemeralPublicKeyX25519.count == 32 else {
            throw C6PHandshakeError.invalidEphemeralPublicKeyLength(actual: offer.ephemeralPublicKeyX25519.count)
        }
        guard offer.usedSignedPrekeyPublicKeyX25519.count == 32 else {
            throw C6PHandshakeError.invalidSignedPrekeyPublicKeyLength(actual: offer.usedSignedPrekeyPublicKeyX25519.count)
        }

        // 4) Ensure offer's signed-prekey matches responder's actual signed-prekey.
        //    This prevents a malicious server from splicing an offer that references a different signed-prekey.
        let actualSignedPrekeyPubRaw = signedPrekeyPrivateKey.publicKey.rawRepresentation
        guard actualSignedPrekeyPubRaw == offer.usedSignedPrekeyPublicKeyX25519 else {
            throw C6PHandshakeError.signedPrekeyMismatchToOffer
        }

        // 5) Build initiator ephemeral public key
        let ephPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: offer.ephemeralPublicKeyX25519)

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

        // 7) Transcript salt must match initiator's computation (deterministic)
        let salt = handshakeSalt(
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId,
            ephemeralPublicKeyX25519: offer.ephemeralPublicKeyX25519,
            signedPrekeyPublicKeyX25519: offer.usedSignedPrekeyPublicKeyX25519,
            oneTimePrekeyPublicKeyX25519: otpPubRaw
        )

        // 8) RootKey (initiator/responder device IDs must match offer)
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId
        )

        // 9) Chain keys from responder POV
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
    ///
    /// IMPORTANT:
    /// - Must be identical for initiator and responder.
    /// - Includes an explicit "otp_present" byte to avoid any ambiguity.
    private static func handshakeSalt(
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        ephemeralPublicKeyX25519: Data,
        signedPrekeyPublicKeyX25519: Data,
        oneTimePrekeyPublicKeyX25519: Data?
    ) -> Data {

        // fixed-size fields -> stable transcript layout
        var transcript = Data()
        transcript.append(C6P_HANDSHAKE99_LABEL.data(using: .utf8)!)
        transcript.append(C6P_VERSION)                 // global protocol version
        transcript.append(C6P_HANDSHAKE99_VERSION)     // handshake99 version

        transcript.append(sessionId.data)              // 4 bytes
        transcript.append(initiatorDeviceId.data)      // 8 bytes
        transcript.append(responderDeviceId.data)      // 8 bytes

        transcript.append(ephemeralPublicKeyX25519)    // 32 bytes
        transcript.append(signedPrekeyPublicKeyX25519) // 32 bytes

        // explicit presence byte
        if let otp = oneTimePrekeyPublicKeyX25519 {
            transcript.append(0x01)
            transcript.append(otp)                     // 32 bytes
        } else {
            transcript.append(0x00)
        }

        let hash = SHA256.hash(data: transcript)
        return Data(hash)
    }
}

