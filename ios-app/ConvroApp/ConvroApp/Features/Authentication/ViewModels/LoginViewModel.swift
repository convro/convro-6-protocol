import SwiftUI
import Combine

// MARK: - Login ViewModel
@MainActor
class LoginViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var isLoading: Bool = false
    @Published var error: Error?

    // MARK: - Dependencies
    private let apiManager = APIManager.shared

    // MARK: - Actions
    func login() async {
        guard !username.isEmpty && !password.isEmpty else {
            error = AuthError.invalidCredentials
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await apiManager.login(username: username, password: password)
            // TODO: Navigate to main app
        } catch {
            self.error = error
        }
    }
}
