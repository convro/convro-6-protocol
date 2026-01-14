import SwiftUI
import Combine

// MARK: - Login ViewModel
@MainActor
class LoginViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var loginSuccess: Bool = false

    // MARK: - Dependencies
    private let apiManager = APIManager.shared
    private let webSocketManager = WebSocketManager.shared

    // MARK: - Actions

    /// Login user and connect to WebSocket
    func login() async {
        guard !username.isEmpty && !password.isEmpty else {
            errorMessage = "Please enter username and password"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await apiManager.login(username: username, password: password)

            // Connect WebSocket for real-time updates
            await webSocketManager.connect(accessToken: response.accessToken)

            // Success
            loginSuccess = true
            print("✅ Login successful: \(response.user.displayName)")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Login failed: \(error)")
        }
    }

    /// Clear error message
    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Auth Error
enum AuthError: LocalizedError {
    case invalidCredentials
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid username or password"
        case .networkError:
            return "Network connection failed"
        case .serverError(let message):
            return message
        }
    }
}
