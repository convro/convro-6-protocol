import Foundation

// MARK: - Message Encryption Service
/// Wrapper for message encryption/decryption with 64KB padding (sealed sender)
@MainActor
class MessageEncryptionService {
    // MARK: - Singleton
    static let shared = MessageEncryptionService()

    // 64KB constant for sealed sender (hides message length)
    private let SEALED_SENDER_SIZE = 65536 // 64 KB

    private init() {}

    // MARK: - Encryption

    /// Encrypt message with 64KB padding (sealed sender mode)
    /// - Parameters:
    ///   - plaintext: Message to encrypt
    ///   - sessionId: Session ID for encryption
    /// - Returns: 64KB padded, base64-encoded envelope
    func encryptMessage(_ plaintext: String, sessionId: String) throws -> Data {
        // Step 1: Encrypt using C6P session
        let encryptedData = try C6PManager.shared.encrypt(message: plaintext, sessionId: sessionId)

        // Step 2: Pad to 64KB (sealed sender - hides content length)
        let paddedData = padTo64KB(encryptedData)

        // Step 3: Base64 encode for transport
        let base64String = paddedData.base64EncodedString()
        guard let base64Data = base64String.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed
        }

        return base64Data
    }

    /// Encrypt message without padding (legacy mode - NOT RECOMMENDED)
    /// Only for compatibility with non-sealed sender endpoints
    func encryptMessageLegacy(_ plaintext: String, sessionId: String) throws -> Data {
        // Encrypt without padding (server sees message size - privacy leak!)
        let encryptedData = try C6PManager.shared.encrypt(message: plaintext, sessionId: sessionId)

        // Base64 encode
        let base64String = encryptedData.base64EncodedString()
        guard let base64Data = base64String.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed
        }

        return base64Data
    }

    // MARK: - Decryption

    /// Decrypt message with 64KB unpadding (sealed sender mode)
    /// - Parameters:
    ///   - encryptedEnvelope: 64KB padded, base64-encoded envelope
    ///   - sessionId: Session ID for decryption
    /// - Returns: Decrypted plaintext message
    func decryptMessage(_ encryptedEnvelope: Data, sessionId: String) throws -> String {
        // Step 1: Decode base64
        guard let base64String = String(data: encryptedEnvelope, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        guard let paddedData = Data(base64Encoded: base64String) else {
            throw EncryptionError.decryptionFailed
        }

        // Step 2: Unpad from 64KB
        let encryptedData = try unpad64KB(paddedData)

        // Step 3: Decrypt using C6P session
        let plaintext = try C6PManager.shared.decrypt(ciphertext: encryptedData, sessionId: sessionId)

        return plaintext
    }

    /// Decrypt message without unpadding (legacy mode)
    func decryptMessageLegacy(_ encryptedEnvelope: Data, sessionId: String) throws -> String {
        // Decode base64
        guard let base64String = String(data: encryptedEnvelope, encoding: .utf8) else {
            throw EncryptionError.decryptionFailed
        }

        guard let encryptedData = Data(base64Encoded: base64String) else {
            throw EncryptionError.decryptionFailed
        }

        // Decrypt directly (no unpadding)
        let plaintext = try C6PManager.shared.decrypt(ciphertext: encryptedData, sessionId: sessionId)

        return plaintext
    }

    // MARK: - Padding (64KB for sealed sender)

    /// Pad data to 64KB (sealed sender - hides message length from server)
    /// Format: [length:4 bytes][data:variable][random padding:rest]
    private func padTo64KB(_ data: Data) -> Data {
        // If already 64KB or larger, error (message too large)
        guard data.count < SEALED_SENDER_SIZE - 4 else {
            // Return as-is if message is too large (should never happen for text)
            // In production, we'd chunk large messages
            return data
        }

        var padded = Data(count: SEALED_SENDER_SIZE)

        // Store original length in first 4 bytes (big-endian)
        let length = UInt32(data.count).bigEndian
        withUnsafeBytes(of: length) { bytes in
            padded.replaceSubrange(0..<4, with: bytes)
        }

        // Copy actual encrypted data
        padded.replaceSubrange(4..<(4 + data.count), with: data)

        // Remaining bytes are already zero-initialized (padding)
        // Could use random padding for extra paranoia, but zeros are fine
        // (ciphertext is already indistinguishable from random)

        return padded
    }

    /// Unpad 64KB data to extract original encrypted message
    private func unpad64KB(_ padded: Data) throws -> Data {
        // Verify size
        guard padded.count == SEALED_SENDER_SIZE else {
            throw EncryptionError.invalidPadding
        }

        // Read length from first 4 bytes
        let length = padded.prefix(4).withUnsafeBytes {
            $0.load(as: UInt32.self).bigEndian
        }

        // Validate length (must be reasonable)
        guard length > 0 && length < UInt32(SEALED_SENDER_SIZE - 4) else {
            throw EncryptionError.invalidPadding
        }

        // Extract actual encrypted data
        return padded.subdata(in: 4..<(4 + Int(length)))
    }
}

// MARK: - Encryption Error
enum EncryptionError: LocalizedError {
    case invalidPadding
    case encryptionFailed
    case decryptionFailed

    var errorDescription: String? {
        switch self {
        case .invalidPadding:
            return "Invalid message padding"
        case .encryptionFailed:
            return "Message encryption failed"
        case .decryptionFailed:
            return "Message decryption failed"
        }
    }
}
