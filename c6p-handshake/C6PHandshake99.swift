//
//  Handshake99.swift
//  C6P-Protocol
//
//  Production implementation of C6P prekey-based handshake ("handshake99").
//  Uses:
//  - Ed25519 (Curve25519.Signing) for identity + prekey signatures
//  - X25519 (Curve25519.KeyAgreement) for shared secret
//  - HKDF / RootKey / ChainKeys from c6p-crypto
//

import Foundation
import CryptoKit

// MARK: - Errors

enum C6PHandshakeError: Error, CustomStringConvertible {
    case invalidIdentityPublicKeyLength(actual: Int)
    case invalidPrekeyPublicKeyLength(actual: Int)
    case invalidOneTimePrekeyPublicKeyLength(actual: Int)
    case invalidEphemeralPublicKeyLength(actual: Int)
    case signatureVerificationFailed
    case missingOneTimePrekey
    case keyAgreementFailed
    case inconsistentDeviceIds
    case invalidProtocolVersion(expected: UInt8, actual: UInt8)

    var description: String {
        switch self {
        case .invalidIdentityPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidIdentityPublicKeyLength(actual=\(actual)) – Ed25519 public key must be 32 bytes"
        case .invalidPrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidPrekeyPublicKeyLength(actual=\(actual)) – X25519 signed prekey must be 32 bytes"
        case .invalidOneTimePrekeyPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual=\(actual)) – X25519 one-time prekey must be 32 bytes"
        case .invalidEphemeralPublicKeyLength(let actual):
            return "C6PHandshakeError.invalidEphemeralPublicKeyLength(actual=\(actual)) – X25519 ephemeral public key must be 32 bytes"
        case .signatureVerificationFailed:
            return "C6PHandshakeError.signatureVerificationFailed – signed prekey not valid for given identity key"
        case .missingOneTimePrekey:
            return "C6PHandshakeError.missingOneTimePrekey – offer references a one-time prekey that is not available locally"
        case .keyAgreementFailed:
            return "C6PHandshakeError.keyAgreementFailed – X25519 shared secret could not be derived"
        case .inconsistentDeviceIds:
            return "C6PHandshakeError.inconsistentDeviceIds – handshake offer has device IDs inconsistent with local expectations"
        case .invalidProtocolVersion(let expected, let actual):
            return "C6PHandshakeError.invalidProtocolVersion(expected=\(expected), actual=\(actual)) – unsupported handshake99 version"
        }
    }
}

// MARK: - Constants

/// Bieżąca wersja handshake99 (nie mylić z globalnym C6P_VERSION).
private let C6P_HANDSHAKE99_VERSION: UInt8 = 1

/// Kontekst podpisu dla signed prekey (domain separation).
private let C6P_PREKEY_SIGNATURE_LABEL = "C6P_PREKEY_V1"

/// Kontekst HKDF dla handshake shared secret / salt.
private let C6P_HANDSHAKE99_LABEL = "C6P_HANDSHAKE99_V1"

// MARK: - Prekey bundle (z perspektywy serwera / sieci)

/// To, co serwer zwraca, gdy inicjator chce rozpocząć sesję z danym urządzeniem peer'a.
/// Wszystko jest PUBLIC – nie ma tu żadnych kluczy prywatnych.
///
/// identityPublicKeyEd25519:
///   - Ed25519 public key urządzenia respondenta (tożsamość).
///
/// signedPrekeyPublicKeyX25519:
///   - publiczny X25519 używany jako signed prekey (długotrwały / rotowany okresowo).
///
/// signedPrekeySignature:
///   - podpis Ed25519 nad (label || signedPrekeyPublicKeyX25519), gdzie label = "C6P_PREKEY_V1".
///
/// oneTimePrekeyId / oneTimePrekeyPublicKeyX25519:
///   - opcjonalny one-time prekey (X25519) + jego identyfikator.
///   - jeśli brak, handshake dalej działa, ale ma nieco słabszą PFS/PCS (jak w standardowym X3DH).
struct C6PPrekeyBundle: Codable, Hashable {

    let responderDeviceId: C6PDeviceId

    let identityPublicKeyEd25519: Data
    let signedPrekeyPublicKeyX25519: Data
    let signedPrekeySignature: Data

    let oneTimePrekeyId: C6PKeyId?
    let oneTimePrekeyPublicKeyX25519: Data?

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

/// To jest payload, który inicjator wysyła jako pierwszą wiadomość handshake99.
/// Serwer widzi ten obiekt, ale nie jest w stanie odtworzyć żadnych kluczy.
struct C6PHandshake99Offer: Codable, Hashable {

    /// Wersja handshake99 (aktualnie = 1).
    let version: UInt8

    /// Identyfikatory urządzeń: kto do kogo.
    let initiatorDeviceId: C6PDeviceId
    let responderDeviceId: C6PDeviceId

    /// Sesja C6P – inicjator losuje ją na starcie i komunikuje responderowi.
    let sessionId: C6PSessionId

    /// Publiczny ephemeral X25519 inicjatora.
    let ephemeralPublicKeyX25519: Data

    /// Informacje o użytym prekey bundle respondenta.
    let usedSignedPrekeyPublicKeyX25519: Data
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

// MARK: - Wynik handshake po stronie inicjatora / respondenta

/// Wynik handshake po stronie inicjatora.
struct C6PHandshake99InitiatorResult {

    /// Identyfikator sesji (wspólny dla obu stron).
    let sessionId: C6PSessionId

    /// Root key dla tej sesji.
    let rootKey: C6PRootKey

    /// Łańcuchy kluczy po stronie inicjatora.
    let sendChainKey: C6PChainKey
    let recvChainKey: C6PChainKey

    /// Stan liczników wiadomości (start od 0).
    var sendCounter: C6PMessageCounter
    var recvCounter: C6PMessageCounter

    /// Oferta handshake, którą trzeba wysłać do respondenta przez serwer.
    let offer: C6PHandshake99Offer

    /// Ephemeral private key inicjatora (jeśli chcesz go wyzerować po handshake).
    let ephemeralPrivateKey: Curve25519.KeyAgreement.PrivateKey
}

/// Wynik handshake po stronie respondenta.
struct C6PHandshake99ResponderResult {

    let sessionId: C6PSessionId

    let rootKey: C6PRootKey

    let sendChainKey: C6PChainKey
    let recvChainKey: C6PChainKey

    var sendCounter: C6PMessageCounter
    var recvCounter: C6PMessageCounter

    /// Identyfikator użytego one-time prekey (jeśli był wykorzystany).
    let consumedOneTimePrekeyId: C6PKeyId?
}

// MARK: - C6P Handshake99

/// Główny punkt wejścia do handshake99.
///
/// Wersja v1:
/// - Inicjator pobiera prekey bundle z serwera.
/// - Weryfikuje podpis signed prekey.
/// - Generuje ephemeral X25519.
/// - Wykonuje X25519 z signed prekey (+ opcjonalnie z one-time prekey).
/// - Wyprowadza root key via C6PKeySchedule.
/// - Tworzy chain keys SEND/RECV (role = INITIATOR).
/// - Wysyła C6PHandshake99Offer do respondenta.
///
/// Responder:
/// - Dostaje C6PHandshake99Offer.
/// - Na podstawie swojego signed prekey + optional one-time prekey
///   odtwarza shared secret (X25519).
/// - Wyprowadza identyczny root key.
/// - Wyprowadza chain keys SEND/RECV (role = RESPONDER).
enum C6PHandshake99 {

    // MARK: - Public API (Initiator)

    /// Rozpoczyna handshake po stronie inicjatora.
    ///
    /// - Parameters:
    ///   - localDeviceId: urządzenie inicjatora.
    ///   - prekeyBundle: publiczne dane urządzenia respondenta (z serwera).
    ///   - identityPublicKeyOverride: opcjonalny znany już publiczny klucz tożsamości
    ///     respondenta; jeśli podasz, prekeyBundle.identityPublicKeyEd25519
    ///     musi z nim się zgadzać (ochrona przed atakiem serwera).
    ///
    /// - Returns: `C6PHandshake99InitiatorResult` zawierający rootKey, chainKeys i ofertę handshake.
    static func startAsInitiator(
        localDeviceId: C6PDeviceId,
        prekeyBundle: C6PPrekeyBundle,
        identityPublicKeyOverride: Data? = nil
    ) throws -> C6PHandshake99InitiatorResult {

        // 1) Sprawdź spójność identity key.
        if let override = identityPublicKeyOverride, override != prekeyBundle.identityPublicKeyEd25519 {
            throw C6PHandshakeError.signatureVerificationFailed
        }

        // 2) Zweryfikuj długości kluczy publicznych.
        guard prekeyBundle.identityPublicKeyEd25519.count == 32 else {
            throw C6PHandshakeError.invalidIdentityPublicKeyLength(actual: prekeyBundle.identityPublicKeyEd25519.count)
        }
        guard prekeyBundle.signedPrekeyPublicKeyX25519.count == 32 else {
            throw C6PHandshakeError.invalidPrekeyPublicKeyLength(actual: prekeyBundle.signedPrekeyPublicKeyX25519.count)
        }
        if let oneTimeData = prekeyBundle.oneTimePrekeyPublicKeyX25519 {
            guard oneTimeData.count == 32 else {
                throw C6PHandshakeError.invalidOneTimePrekeyPublicKeyLength(actual: oneTimeData.count)
            }
        }

        // 3) Zbuduj CryptoKit public keys.
        let identityPubKey = try Curve25519.Signing.PublicKey(rawRepresentation: prekeyBundle.identityPublicKeyEd25519)
        let signedPrekeyPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: prekeyBundle.signedPrekeyPublicKeyX25519)

        let oneTimePrekeyPub: Curve25519.KeyAgreement.PublicKey? = try {
            if let raw = prekeyBundle.oneTimePrekeyPublicKeyX25519 {
                return try Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw)
            } else {
                return nil
            }
        }()

        // 4) Zweryfikuj podpis signed prekey (Ed25519).
        //    Signature over: "C6P_PREKEY_V1" || signedPrekeyPublicKeyX25519
        var signedMessage = Data()
        signedMessage.append(C6P_PREKEY_SIGNATURE_LABEL.data(using: .utf8)!)
        signedMessage.append(prekeyBundle.signedPrekeyPublicKeyX25519)

        guard identityPubKey.isValidSignature(prekeyBundle.signedPrekeySignature, for: signedMessage) else {
            throw C6PHandshakeError.signatureVerificationFailed
        }

        // 5) Wygeneruj ephemeral X25519 inicjatora.
        let ephemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPublicKeyData = ephemeralPrivateKey.publicKey.rawRepresentation

        // 6) Wykonaj ECDH z signed prekey + opcjonalnym one-time prekey.
        let dh1Shared = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: signedPrekeyPub)
        let dh1 = sharedSecretToData(dh1Shared)

        var ikm = Data()
        ikm.append(dh1)

        if let otpPub = oneTimePrekeyPub {
            let dh2Shared = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: otpPub)
            let dh2 = sharedSecretToData(dh2Shared)
            ikm.append(dh2)
        }

        // 7) Wylosuj sessionId.
        let sessionId = try C6PSessionId.random()

        // 8) Zbuduj transcript i policz salt = SHA256(transcript).
        let salt = handshakeSalt(
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            ephemeralPublicKeyX25519: ephemeralPublicKeyData,
            signedPrekeyPublicKeyX25519: prekeyBundle.signedPrekeyPublicKeyX25519,
            oneTimePrekeyPublicKeyX25519: prekeyBundle.oneTimePrekeyPublicKeyX25519
        )

        // 9) Wyprowadź root key via C6PKeySchedule.
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: sessionId,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId
        )

        // 10) Wyprowadź chain keys (SEND/RECV) z perspektywy inicjatora.
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

        let sendCounter = C6PMessageCounter(value: 0)
        let recvCounter = C6PMessageCounter(value: 0)

        // 11) Zbuduj ofertę handshake do wysłania przez serwer.
        let offer = C6PHandshake99Offer(
            version: C6P_HANDSHAKE99_VERSION,
            initiatorDeviceId: localDeviceId,
            responderDeviceId: prekeyBundle.responderDeviceId,
            sessionId: sessionId,
            ephemeralPublicKeyX25519: ephemeralPublicKeyData,
            usedSignedPrekeyPublicKeyX25519: prekeyBundle.signedPrekeyPublicKeyX25519,
            usedOneTimePrekeyId: prekeyBundle.oneTimePrekeyId
        )

        return C6PHandshake99InitiatorResult(
            sessionId: sessionId,
            rootKey: rootKey,
            sendChainKey: sendCK,
            recvChainKey: recvCK,
            sendCounter: sendCounter,
            recvCounter: recvCounter,
            offer: offer,
            ephemeralPrivateKey: ephemeralPrivateKey
        )
    }

    // MARK: - Public API (Responder)

    /// Akceptuje ofertę handshake po stronie respondenta.
    ///
    /// - Parameters:
    ///   - offer: `C6PHandshake99Offer` otrzymany z serwera.
    ///   - localDeviceId: device ID bieżącego urządzenia (respondenta).
    ///   - signedPrekeyPrivateKey: prywatny X25519 odpowiadający signed prekey'owi,
    ///     który był wysłany w prekey bundle.
    ///   - oneTimePrekeys: mapa: keyId -> prywatny X25519 one-time prekey.
    ///
    /// - Returns: `C6PHandshake99ResponderResult` z rootKey i chain keys.
    static func acceptAsResponder(
        offer: C6PHandshake99Offer,
        localDeviceId: C6PDeviceId,
        signedPrekeyPrivateKey: Curve25519.KeyAgreement.PrivateKey,
        oneTimePrekeys: [C6PKeyId: Curve25519.KeyAgreement.PrivateKey]
    ) throws -> C6PHandshake99ResponderResult {

        // 1) Sprawdź wersję handshake.
        guard offer.version == C6P_HANDSHAKE99_VERSION else {
            throw C6PHandshakeError.invalidProtocolVersion(
                expected: C6P_HANDSHAKE99_VERSION,
                actual: offer.version
            )
        }

        // 2) Sprawdź spójność device IDs.
        guard offer.responderDeviceId == localDeviceId else {
            throw C6PHandshakeError.inconsistentDeviceIds
        }

        // 3) Zbuduj ephemeral public key inicjatora.
        guard offer.ephemeralPublicKeyX25519.count == 32 else {
            throw C6PHandshakeError.invalidEphemeralPublicKeyLength(actual: offer.ephemeralPublicKeyX25519.count)
        }
        let ephemeralPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: offer.ephemeralPublicKeyX25519)

        // 4) Wykonaj ECDH z signed prekey.
        let dh1Shared = try signedPrekeyPrivateKey.sharedSecretFromKeyAgreement(with: ephemeralPub)
        let dh1 = sharedSecretToData(dh1Shared)

        var ikm = Data()
        ikm.append(dh1)

        // 5) Opcjonalnie: one-time prekey wg ID z offer.
        var consumedOTPId: C6PKeyId? = nil

        if let otpId = offer.usedOneTimePrekeyId {
            guard let otpPriv = oneTimePrekeys[otpId] else {
                throw C6PHandshakeError.missingOneTimePrekey
            }
            let dh2Shared = try otpPriv.sharedSecretFromKeyAgreement(with: ephemeralPub)
            let dh2 = sharedSecretToData(dh2Shared)
            ikm.append(dh2)
            consumedOTPId = otpId
        }

        // 6) Odtwórz salt z identycznego transcriptu.
        let salt = handshakeSalt(
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId,
            ephemeralPublicKeyX25519: offer.ephemeralPublicKeyX25519,
            signedPrekeyPublicKeyX25519: offer.usedSignedPrekeyPublicKeyX25519,
            oneTimePrekeyPublicKeyX25519: nil // nie potrzebujemy go po stronie respondenta do salt
        )

        // 7) Wyprowadź root key (uwaga na role: inicjator = offer.initiatorDeviceId).
        let rootKey = C6PKeySchedule.deriveInitialRootKey(
            sharedSecret: ikm,
            salt: salt,
            sessionId: offer.sessionId,
            initiatorDeviceId: offer.initiatorDeviceId,
            responderDeviceId: offer.responderDeviceId
        )

        // 8) Wyprowadź chain keys z perspektywy respondenta.
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

        let sendCounter = C6PMessageCounter(value: 0)
        let recvCounter = C6PMessageCounter(value: 0)

        return C6PHandshake99ResponderResult(
            sessionId: offer.sessionId,
            rootKey: rootKey,
            sendChainKey: sendCK,
            recvChainKey: recvCK,
            sendCounter: sendCounter,
            recvCounter: recvCounter,
            consumedOneTimePrekeyId: consumedOTPId
        )
    }

    // MARK: - Helpers

    /// Konwersja CryptoKit.SharedSecret -> Data.
    private static func sharedSecretToData(_ secret: SharedSecret) -> Data {
        secret.withUnsafeBytes { buffer in
            return Data(buffer)
        }
    }

    /// Deterministyczny salt dla HKDF w handshake99, bazujący na "transcripcie" handshaku.
    ///
    /// W obu rolach (inicjator / responder) musi zostać policzony identycznie.
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
        transcript.append(C6P_VERSION) // globalny C6P_VERSION
        transcript.append(C6P_HANDSHAKE99_VERSION) // handshake99 version

        transcript.append(sessionId.data)
        transcript.append(initiatorDeviceId.data)
        transcript.append(responderDeviceId.data)

        transcript.append(ephemeralPublicKeyX25519)
        transcript.append(signedPrekeyPublicKeyX25519)

        if let otp = oneTimePrekeyPublicKeyX25519 {
            transcript.append(otp)
        }

        let hash = SHA256.hash(data: transcript)
        return Data(hash)
    }
}
