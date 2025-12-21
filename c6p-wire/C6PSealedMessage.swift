//
//  C6PSealedMessage.swift
//  C6P-Protocol
//
//  Sealed payload container used inside C6PEnvelope.
//  Codable Data -> base64 in JSON by default.
//

import Foundation

enum C6PSealedMessageError: Error {
    case invalidAuthTagLength(expected: Int, actual: Int)
    case emptyCiphertext
}

struct C6PSealedMessage: Codable, Hashable {

    /// Ciphertext bytes (no tag).
    let ciphertext: Data

    /// AEAD tag (ChaCha20-Poly1305 => 16 bytes).
    let authTag: Data

    init(ciphertext: Data, authTag: Data) throws {
        if ciphertext.isEmpty { throw C6PSealedMessageError.emptyCiphertext }
        if authTag.count != 16 {
            throw C6PSealedMessageError.invalidAuthTagLength(expected: 16, actual: authTag.count)
        }
        self.ciphertext = ciphertext
        self.authTag = authTag
    }
}
