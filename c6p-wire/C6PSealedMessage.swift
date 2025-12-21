import Foundation

enum C6PSealedMessageError: Error {
    case invalidAuthTagLength(expected: Int, actual: Int)
    case emptyCiphertext
}

struct C6PSealedMessage: Codable, Hashable {
    let ciphertext: Data
    let authTag: Data

    init(ciphertext: Data, authTag: Data) throws {
        if ciphertext.isEmpty { throw C6PSealedMessageError.emptyCiphertext }
        if authTag.count != 16 {
            throw C6PSealedMessageError.invalidAuthTagLength(expected: 16, actual: authTag.count)
        }
        self.ciphertext = ciphertext
        self.authTag = authTag
    }

    private enum CodingKeys: String, CodingKey {
        case ciphertext
        case authTag
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let ciphertext = try c.decode(Data.self, forKey: .ciphertext)
        let authTag = try c.decode(Data.self, forKey: .authTag)
        try self.init(ciphertext: ciphertext, authTag: authTag) // ✅ zawsze waliduje
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ciphertext, forKey: .ciphertext)
        try c.encode(authTag, forKey: .authTag)
    }
}
