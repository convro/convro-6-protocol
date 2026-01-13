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
    @Published var error: Error?
    @Published var assignedConvroNumber: String?

    // MARK: - Dependencies
    private let apiManager = APIManager.shared

    // MARK: - Validation
    var isValid: Bool {
        return username.isValidUsername &&
               password.isValidPassword &&
               password == confirmPassword &&
               !displayName.isEmpty
    }

    // MARK: - Actions
    func register() async {
        guard isValid else {
            error = AuthError.invalidInput
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            let user = try await apiManager.register(
                username: username,
                password: password,
                displayName: displayName
            )
            assignedConvroNumber = user.convroNumber
            // TODO: Navigate to onboarding
        } catch {
            self.error = error
        }
    }
}
