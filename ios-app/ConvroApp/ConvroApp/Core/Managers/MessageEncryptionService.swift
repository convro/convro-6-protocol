import Foundation

// MARK: - Message Encryption Service
/// Wrapper for message encryption/decryption with padding
@MainActor
class MessageEncryptionService {
    // MARK: - Singleton
    static let shared = MessageEncryptionService()

    private init() {}

    // MARK: - Encryption
    func encryptMessage(_ plaintext: String, sessionId: String) throws -> Data {
        // TODO: Call C6PManager.encrypt()
        // TODO: Pad to 64KB (sealed sender)
        // TODO: Return base64 encoded envelope
        fatalError("Not implemented")
    }

    // MARK: - Decryption
    func decryptMessage(_ encryptedEnvelope: Data, sessionId: String) throws -> String {
        // TODO: Decode base64
        // TODO: Unpad envelope
        // TODO: Call C6PManager.decrypt()
        fatalError("Not implemented")
    }

    // MARK: - Padding (64KB for sealed sender)
    private func padTo64KB(_ data: Data) -> Data {
        let targetSize = 65536 // 64 KB
        guard data.count < targetSize else {
            return data
        }

        var padded = Data(count: targetSize)
        // Store length in first 4 bytes
        let length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: length) { bytes in
            padded.replaceSubrange(0..<4, with: bytes)
        }
        // Copy actual data
        padded.replaceSubrange(4..<(4 + data.count), with: data)
        return padded
    }

    private func unpad64KB(_ padded: Data) throws -> Data {
        guard padded.count == 65536 else {
            throw EncryptionError.invalidPadding
        }

        let length = padded.prefix(4).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        guard length > 0 && length < 65536 - 4 else {
            throw EncryptionError.invalidPadding
        }

        return padded.subdata(in: 4..<(4 + Int(length)))
    }
}

// MARK: - Encryption Error
enum EncryptionError: Error {
    case invalidPadding
    case encryptionFailed
    case decryptionFailed
}
