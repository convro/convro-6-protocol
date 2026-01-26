import SwiftUI

// MARK: - Settings ViewModel
@MainActor
class SettingsViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var user: User?
    @Published var devices: [Device] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var logoutSuccess: Bool = false
    @Published var isBiometricEnabled: Bool = false

    // MARK: - Dependencies
    private let apiManager = APIManager.shared
    private let webSocketManager = WebSocketManager.shared
    private let keychainManager = KeychainManager.shared
    private let messageStorage = MessageStorage.shared

    // MARK: - Biometric Info
    var biometricType: String {
        switch BiometricAuth.biometricType() {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "Biometric"
        }
    }

    var canUseBiometrics: Bool {
        return BiometricAuth.canUseBiometrics()
    }

    // MARK: - Initialization
    init() {
        loadBiometricSetting()
    }

    // MARK: - User Profile

    /// Load user profile from server
    func loadUserProfile() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            user = try await apiManager.getUserProfile()
            print("✅ User profile loaded: \(user?.displayName ?? "Unknown")")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Load user profile failed: \(error)")
        }
    }

    /// Update user display name
    func updateDisplayName(_ newDisplayName: String) async {
        guard !newDisplayName.isEmpty else {
            errorMessage = "Display name cannot be empty"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            user = try await apiManager.updateUserProfile(displayName: newDisplayName)
            print("✅ Display name updated: \(newDisplayName)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Update display name failed: \(error)")
        }
    }

    // MARK: - Devices

    /// Load all devices for current user
    func loadDevices() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            devices = try await apiManager.listDevices()
            print("✅ Loaded \(devices.count) devices")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Load devices failed: \(error)")
        }
    }

    /// Remove device from account
    func removeDevice(_ device: Device) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await apiManager.deactivateDevice(deviceId: device.id)
            devices.removeAll { $0.id == device.id }
            print("✅ Device removed: \(device.deviceName)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Remove device failed: \(error)")
        }
    }

    // MARK: - Security

    /// Toggle biometric authentication
    func toggleBiometric(enabled: Bool) {
        guard canUseBiometrics else {
            errorMessage = "\(biometricType) is not available on this device"
            return
        }

        isBiometricEnabled = enabled
        saveBiometricSetting(enabled)
        print("✅ \(biometricType) \(enabled ? "enabled" : "disabled")")
    }

    /// Authenticate with biometrics
    func authenticateWithBiometrics() async -> Bool {
        guard canUseBiometrics else {
            errorMessage = "\(biometricType) is not available"
            return false
        }

        do {
            let success = try await BiometricAuth.authenticate(reason: "Authenticate to access settings")
            if success {
                print("✅ Biometric authentication successful")
            }
            return success
        } catch {
            errorMessage = "Biometric authentication failed"
            print("❌ Biometric authentication failed: \(error)")
            return false
        }
    }

    // MARK: - Biometric Settings Persistence

    private func loadBiometricSetting() {
        isBiometricEnabled = UserDefaults.standard.bool(forKey: "biometric_enabled")
    }

    private func saveBiometricSetting(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "biometric_enabled")
    }

    // MARK: - Logout

    /// Logout user and clear all data
    func logout() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Step 1: Disconnect WebSocket
            webSocketManager.disconnect()

            // Step 2: Logout from server
            try await apiManager.logout()

            // Step 3: Clear local data
            await clearLocalData()

            // Success
            logoutSuccess = true
            print("✅ Logout successful")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Logout failed: \(error)")
        }
    }

    /// Clear all local data on logout
    private func clearLocalData() async {
        // Clear message storage (conversations, messages)
        await messageStorage.clearCurrentUserData()

        // Clear biometric setting
        saveBiometricSetting(false)
        isBiometricEnabled = false

        // Clear user data
        user = nil
        devices = []

        print("🧹 Local data cleared")
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }
}
