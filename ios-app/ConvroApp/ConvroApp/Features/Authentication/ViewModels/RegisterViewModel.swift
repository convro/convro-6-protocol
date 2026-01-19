import SwiftUI
import Combine

// MARK: - Register ViewModel
@MainActor
class RegisterViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var displayName: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var registrationSuccess: Bool = false
    @Published var assignedConvroNumber: String?

    // MARK: - Dependencies
    private let apiManager = APIManager.shared
    private let deviceIdentityManager = DeviceIdentityManager.shared
    private let c6pManager = C6PManager.shared
    private let webSocketManager = WebSocketManager.shared

    // MARK: - Validation
    var isValid: Bool {
        return !username.isEmpty &&
               username.count >= 3 &&
               !password.isEmpty &&
               password.count >= 8 &&
               password == confirmPassword &&
               !displayName.isEmpty
    }

    var passwordsMatch: Bool {
        return password == confirmPassword
    }

    // MARK: - Actions

    /// Register new user with device identity and prekeys
    func register() async {
        guard isValid else {
            errorMessage = "Please fill all fields correctly"
            return
        }

        guard passwordsMatch else {
            errorMessage = "Passwords do not match"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Step 1: Generate device identity (cryptographic keys)
            print("🔑 Generating device identity...")
            try await deviceIdentityManager.generateIdentity()

            guard let identity = deviceIdentityManager.deviceIdentity else {
                throw RegistrationError.identityGenerationFailed
            }

            // Step 2: Generate signed prekey and one-time prekeys
            print("🔐 Generating prekeys...")
            let spk = try c6pManager.generateSignedPrekey()
            let otps = try (0..<10).map { _ in try c6pManager.generateOneTimePrekey() }

            // Step 3: Register with server
            print("📡 Registering with server...")
            let response = try await apiManager.register(
                username: username,
                password: password,
                displayName: displayName,
                deviceIdentity: identity,
                signedPrekey: spk,
                oneTimePrekeys: otps
            )

            // Step 4: Connect WebSocket
            await webSocketManager.connect(accessToken: response.accessToken)

            // Success
            assignedConvroNumber = response.convroNumber
            registrationSuccess = true

            print("✅ Registration successful!")
            print("   Convro Number: \(response.convroNumber)")
            print("   Fingerprint: \(identity.fingerprint)")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Registration failed: \(error)")
        }
    }

    /// Clear error message
    func clearError() {
        errorMessage = nil
    }

    /// Validate field in real-time
    func validateUsername() -> String? {
        guard !username.isEmpty else { return nil }
        guard username.count >= 3 else {
            return "Username must be at least 3 characters"
        }
        return nil
    }

    func validatePassword() -> String? {
        guard !password.isEmpty else { return nil }
        guard password.count >= 8 else {
            return "Password must be at least 8 characters"
        }
        return nil
    }

    func validateConfirmPassword() -> String? {
        guard !confirmPassword.isEmpty else { return nil }
        guard password == confirmPassword else {
            return "Passwords do not match"
        }
        return nil
    }
}

// MARK: - Registration Error
enum RegistrationError: LocalizedError {
    case identityGenerationFailed
    case invalidInput
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .identityGenerationFailed:
            return "Failed to generate device identity"
        case .invalidInput:
            return "Please fill all fields correctly"
        case .serverError(let message):
            return message
        }
    }
}
