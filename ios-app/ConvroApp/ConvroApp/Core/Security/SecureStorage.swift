import Foundation

// MARK: - Secure Storage
/// Additional secure storage utilities
class SecureStorage {
    // MARK: - Secure Random
    static func generateSecureRandom(bytes: Int) -> Data? {
        var data = Data(count: bytes)
        let result = data.withUnsafeMutableBytes {
            SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
        }
        return result == errSecSuccess ? data : nil
    }

    // MARK: - Wipe Memory
    static func wipeData(_ data: inout Data) {
        data.resetBytes(in: 0..<data.count)
        data.removeAll()
    }

    // MARK: - Secure Comparison
    static func constantTimeCompare(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }

        var result: UInt8 = 0
        for (a, b) in zip(lhs, rhs) {
            result |= a ^ b
        }
        return result == 0
    }
}
