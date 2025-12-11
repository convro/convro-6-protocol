import Foundation
import CryptoKit

// MARK: - Role & Direction

/// Perspective of this device in the session.
enum C6PRole: String, Codable {
    case initiator = "INITIATOR"
    case responder = "RESPONDER"
}

/// Direction of traffic from POV tego urządzenia.
enum C6PDirection: String, Codable {
    case sending   = "SENDING"
    case receiving = "RECEIVING"
}

// MARK: - Root Key

/// 32-bajtowy klucz źródłowy dla danej sesji.
/// Powstaje z początkowego X25519 shared secret + kontekstu handshake.
struct C6PRootKey: Hashable, Codable, CustomStringConvertible {

    /// 32-bajtowy materiał klucza.
    let keyMaterial: Data

    /// Identyfikator sesji (4 bajty).
    let sessionId: C6PSessionId

    /// Device ID inicjatora (nadawcy handshaku).
    let initiatorDeviceId: C6PDeviceId

    /// Device ID respondenta (odbiorcy handshaku).
    let responderDeviceId: C6PDeviceId

    /// Algorytm DH użyty w tej sesji (np. X25519).
    let dhAlgorithmId: String

    /// Algorytm KDF użyty w tej sesji (HKDF-SHA256).
    let kdfAlgorithmId: String

    // MARK: - Init

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId,
        dhAlgorithmId: String = C6PAlgorithmId.dhX25519,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) {
        precondition(keyMaterial.count == 32, "Root key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.initiatorDeviceId = initiatorDeviceId
        self.responderDeviceId = responderDeviceId
        self.dhAlgorithmId = dhAlgorithmId
        self.kdfAlgorithmId = kdfAlgorithmId
    }

    // MARK: - Description

    var description: String {
        "C6PRootKey(sessionId=\(sessionId.hexString), dh=\(dhAlgorithmId), kdf=\(kdfAlgorithmId))"
    }
}

// MARK: - Chain Key

/// 32-bajtowy klucz łańcuchowy (per kierunek, per urządzenie).
/// Z niego derivujemy message keys oraz kolejny chain key (ratchet wewnątrz sesji).
struct C6PChainKey: Hashable, Codable, CustomStringConvertible {

    /// 32-bajtowy materiał klucza.
    let keyMaterial: Data

    /// Powiązana sesja.
    let sessionId: C6PSessionId

    /// To urządzenie.
    let selfDeviceId: C6PDeviceId

    /// Zdalne urządzenie.
    let remoteDeviceId: C6PDeviceId

    /// Rola tego urządzenia w sesji (initiator / responder).
    let role: C6PRole

    /// Kierunek z punktu widzenia selfDeviceId (sending / receiving).
    let direction: C6PDirection

    /// Algorytm KDF użyty do ratcheta.
    let kdfAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        selfDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId,
        role: C6PRole,
        direction: C6PDirection,
        kdfAlgorithmId: String = C6PAlgorithmId.kdfHKDFSHA256
    ) {
        precondition(keyMaterial.count == 32, "Chain key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.selfDeviceId = selfDeviceId
        self.remoteDeviceId = remoteDeviceId
        self.role = role
        self.direction = direction
        self.kdfAlgorithmId = kdfAlgorithmId
    }

    var description: String {
        "C6PChainKey(sessionId=\(sessionId.hexString), role=\(role.rawValue), dir=\(direction.rawValue))"
    }

    /// Tworzy SymmetricKey for CryptoKit (ChaCha20-Poly1305).
    var symmetricKey: SymmetricKey {
        SymmetricKey(data: keyMaterial)
    }
}

// MARK: - Message Key

/// Klucz wiadomości (per-message AEAD key, 32-bajtowy).
/// Nonce i AAD będą budowane w innych modułach na bazie sesji, direction i countera.
struct C6PMessageKey: Hashable, Codable, CustomStringConvertible {

    let keyMaterial: Data

    /// Sesja, do której należy wiadomość.
    let sessionId: C6PSessionId

    /// Kierunek z perspektywy tego urządzenia.
    let direction: C6PDirection

    /// Counter wiadomości (monotoniczny).
    let counter: C6PMessageCounter

    /// Typ wiadomości (DM / group / channel / control).
    let messageType: C6PMessageType

    /// AEAD algorithm dla tego klucza.
    let aeadAlgorithmId: String

    init(
        keyMaterial: Data,
        sessionId: C6PSessionId,
        direction: C6PDirection,
        counter: C6PMessageCounter,
        messageType: C6PMessageType,
        aeadAlgorithmId: String = C6PAlgorithmId.aeadChaCha20
    ) {
        precondition(keyMaterial.count == 32, "Message key must be 32 bytes")
        self.keyMaterial = keyMaterial
        self.sessionId = sessionId
        self.direction = direction
        self.counter = counter
        self.messageType = messageType
        self.aeadAlgorithmId = aeadAlgorithmId
    }

    /// SymmetricKey dla ChaCha20-Poly1305.
    var symmetricKey: SymmetricKey {
        SymmetricKey(data: keyMaterial)
    }

    var description: String {
        "C6PMessageKey(sessionId=\(sessionId.hexString), dir=\(direction.rawValue), counter=\(counter.value))"
    }
}

// MARK: - Key Schedule

/// Centralny punkt: tworzenie root / chain / message keys przy użyciu HKDF-SHA256.
enum C6PKeySchedule {

    // Stałe labelki, które idą w `info` HKDF (domain separation).
    private static let rootLabel  = "C6P_ROOT_KEY_V1"
    private static let chainLabel = "C6P_CHAIN_KEY_V1"
    private static let nextChainLabel = "C6P_CHAIN_RATCHET_V1"
    private static let messageLabel = "C6P_MESSAGE_KEY_V1"

    // MARK: Initial Root Key

    /// Wyprowadza początkowy root key z:
    /// - X25519 shared secret,
    /// - soli (z hashu transcriptu handshaku),
    /// - sessionId + urządzeń.
    ///
    /// To jest PUNKT STARTOWY całej sesji.
    static func deriveInitialRootKey(
        sharedSecret: Data,
        salt: Data,
        sessionId: C6PSessionId,
        initiatorDeviceId: C6PDeviceId,
        responderDeviceId: C6PDeviceId
    ) -> C6PRootKey {

        var info = Data()
        info.append(rootLabel.data(using: .utf8)!)
        info.append(C6P_VERSION) // 1 byte
        info.append(C6PAlgorithmId.dhX25519.data(using: .utf8)!)
        info.append(C6PAlgorithmId.kdfHKDFSHA256.data(using: .utf8)!)
        info.append(sessionId.data)
        info.append(initiatorDeviceId.data)
        info.append(responderDeviceId.data)

        let rootBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: sharedSecret,
            salt: salt,
            info: info,
            outputByteCount: 32
        )

        return C6PRootKey(
            keyMaterial: rootBytes,
            sessionId: sessionId,
            initiatorDeviceId: initiatorDeviceId,
            responderDeviceId: responderDeviceId
        )
    }

    // MARK: Chain Keys (per side, per direction)

    /// Wyprowadza chain key dla KONKRETNEJ kombinacji:
    /// - rootKey,
    /// - selfDeviceId,
    /// - remoteDeviceId,
    /// - rola (initiator / responder),
    /// - kierunek (sending / receiving).
    ///
    /// Handshake/Session layer wywoła to DWUKROTNIE z odpowiednimi parametrami,
    /// aby mieć osobny chain key: SEND i RECV.
    static func deriveChainKey(
        rootKey: C6PRootKey,
        selfDeviceId: C6PDeviceId,
        remoteDeviceId: C6PDeviceId,
        role: C6PRole,
        direction: C6PDirection
    ) -> C6PChainKey {

        var info = Data()
        info.append(chainLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(rootKey.kdfAlgorithmId.data(using: .utf8)!)
        info.append(rootKey.sessionId.data)
        info.append(selfDeviceId.data)
        info.append(remoteDeviceId.data)

        // Role & direction jako ASCII, żeby zakodować kontekst.
        info.append(role.rawValue.data(using: .utf8)!)
        info.append(direction.rawValue.data(using: .utf8)!)

        let chainBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: rootKey.keyMaterial,
            salt: Data(), // dodatkowe "salt" niepotrzebne – rootKey już jest wynikową entropią.
            info: info,
            outputByteCount: 32
        )

        return C6PChainKey(
            keyMaterial: chainBytes,
            sessionId: rootKey.sessionId,
            selfDeviceId: selfDeviceId,
            remoteDeviceId: remoteDeviceId,
            role: role,
            direction: direction
        )
    }

    /// Ratchet chain key do przodu:
    /// CK_{i+1} = HKDF( CK_i, info = label || sessionId || role || direction )
    ///
    /// Dzięki temu każdy „skok” łańcucha ma własny KDF step.
    static func ratchetChainKeyForward(_ chainKey: C6PChainKey) -> C6PChainKey {

        var info = Data()
        info.append(nextChainLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(chainKey.kdfAlgorithmId.data(using: .utf8)!)
        info.append(chainKey.sessionId.data)
        info.append(chainKey.selfDeviceId.data)
        info.append(chainKey.remoteDeviceId.data)
        info.append(chainKey.role.rawValue.data(using: .utf8)!)
        info.append(chainKey.direction.rawValue.data(using: .utf8)!)

        let nextBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return C6PChainKey(
            keyMaterial: nextBytes,
            sessionId: chainKey.sessionId,
            selfDeviceId: chainKey.selfDeviceId,
            remoteDeviceId: chainKey.remoteDeviceId,
            role: chainKey.role,
            direction: chainKey.direction,
            kdfAlgorithmId: chainKey.kdfAlgorithmId
        )
    }

    // MARK: Message Keys

    /// Wyprowadza klucz wiadomości:
    ///
    /// MK = HKDF( CK, info = label || version || algId || sessionId || dir || msgType || counter )
    ///
    /// Nonce i AAD do ChaCha20-Poly1305 będą budowane w innych modułach
    /// (NonceSequencer + AEAD wrapper), ale muszą skorzystać z tych samych
    /// parametrów sesji / countera.
    static func deriveMessageKey(
        from chainKey: C6PChainKey,
        counter: C6PMessageCounter,
        messageType: C6PMessageType
    ) -> C6PMessageKey {

        var info = Data()
        info.append(messageLabel.data(using: .utf8)!)
        info.append(C6P_VERSION)
        info.append(C6PAlgorithmId.aeadChaCha20.data(using: .utf8)!)
        info.append(chainKey.sessionId.data)

        // role + direction jako kontekst:
        info.append(chainKey.role.rawValue.data(using: .utf8)!)
        info.append(chainKey.direction.rawValue.data(using: .utf8)!)

        // message type (1 bajt)
        info.append(messageType.rawValue)

        // counter (8 bajtów big-endian)
        info.append(counter.data)

        let mkBytes = C6PHKDF.deriveKey(
            inputKeyMaterial: chainKey.keyMaterial,
            salt: Data(),
            info: info,
            outputByteCount: 32
        )

        return C6PMessageKey(
            keyMaterial: mkBytes,
            sessionId: chainKey.sessionId,
            direction: chainKey.direction,
            counter: counter,
            messageType: messageType
        )
    }
}
