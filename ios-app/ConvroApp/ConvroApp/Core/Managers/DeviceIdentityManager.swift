import Foundation
import C6PProtocol

// MARK: - Device Identity Manager
/// Manages device identity lifecycle (C6P cryptographic identity)
@MainActor
class DeviceIdentityManager: ObservableObject {
    // MARK: - Singleton
    static let shared = DeviceIdentityManager()

    // MARK: - Properties
    @Published var deviceIdentity: C6PProtocol.DeviceIdentity?
    @Published var isRegistered: Bool = false

    private init() {
        Task {
            await loadDeviceIdentity()
        }
    }

    // MARK: - Identity Operations

    /// Generate new device identity (cryptographic keys)
    func generateIdentity() async throws {
        // Generate identity using C6P FFI
        let identity = try C6PManager.shared.generateDeviceIdentity()
        self.deviceIdentity = identity

        // Auto-save to Keychain (already done by C6PManager)
        print("✅ Device identity generated: \(identity.fingerprint)")
    }

    /// Load device identity from Keychain
    func loadDeviceIdentity() async {
        do {
            self.deviceIdentity = try await KeychainManager.shared.loadDeviceIdentity()
            print("✅ Device identity loaded from Keychain")
        } catch {
            print("⚠️ No device identity found")
            self.deviceIdentity = nil
        }
    }

    /// Register device identity with Convro server
    func registerWithServer(username: String, password: String, displayName: String) async throws {
        guard let identity = deviceIdentity else {
            throw DeviceIdentityError.noIdentity
        }

        // Generate signed prekey and one-time prekeys for registration
        let spk = try C6PManager.shared.generateSignedPrekey()
        let otps = try (0..<10).map { _ in try C6PManager.shared.generateOneTimePrekey() }

        // Save SPK and OTPs to Keychain
        try await KeychainManager.shared.saveSignedPrekey(spk)
        try await KeychainManager.shared.saveOneTimePrekeys(otps)

        // Register with Convro server
        let response = try await APIManager.shared.register(
            username: username,
            password: password,
            displayName: displayName,
            deviceIdentity: identity,
            signedPrekey: spk,
            oneTimePrekeys: otps
        )

        // Mark as registered
        self.isRegistered = true

        print("✅ Device registered: \(response.user.convroNumber)")
        print("   Username: \(response.user.username)")
        print("   Display name: \(response.user.displayName)")
    }

    /// Generate and upload new signed prekey (rotation)
    func rotateSignedPrekey() async throws {
        guard deviceIdentity != nil else {
            throw DeviceIdentityError.noIdentity
        }

        let newSPK = try C6PManager.shared.generateSignedPrekey()

        // Save to Keychain
        try await KeychainManager.shared.saveSignedPrekey(newSPK)

        // Upload to server (with empty OTP array for rotation)
        try await APIManager.shared.uploadPrekeys(
            signedPrekey: newSPK,
            oneTimePrekeys: []
        )

        print("✅ Signed prekey rotated and uploaded")
    }

    /// Generate and upload new one-time prekeys (replenishment)
    func replenishOneTimePrekeys(count: Int = 10) async throws {
        guard deviceIdentity != nil else {
            throw DeviceIdentityError.noIdentity
        }

        let otps = try (0..<count).map { _ in try C6PManager.shared.generateOneTimePrekey() }

        // Save OTPs to Keychain before uploading
        try await KeychainManager.shared.saveOneTimePrekeys(otps)

        // Load current SPK from Keychain
        let currentSPK = try await KeychainManager.shared.loadSignedPrekey()

        // Upload OTPs with current SPK to server
        try await APIManager.shared.uploadPrekeys(
            signedPrekey: currentSPK,
            oneTimePrekeys: otps
        )

        print("✅ Generated and uploaded \(count) new one-time prekeys")
    }

    /// Delete device identity (logout/unregister)
    func deleteIdentity() async throws {
        guard deviceIdentity != nil else {
            return
        }

        // Delete from Keychain
        try await KeychainManager.shared.deleteDeviceIdentity()

        // Clear from memory
        self.deviceIdentity = nil
        self.isRegistered = false

        print("✅ Device identity deleted")
    }

    /// Get device fingerprint (for verification)
    func getFingerprint() -> String? {
        return deviceIdentity?.fingerprint
    }

    /// Get device ID (16 bytes, hex)
    func getDeviceId() -> String? {
        guard let identity = deviceIdentity else { return nil }
        return C6PManager.shared.bytesToHex(identity.deviceId)
    }
}

// MARK: - Errors
enum DeviceIdentityError: LocalizedError {
    case noIdentity

    var errorDescription: String? {
        switch self {
        case .noIdentity:
            return "No device identity. Generate one first."
        }
    }
}
