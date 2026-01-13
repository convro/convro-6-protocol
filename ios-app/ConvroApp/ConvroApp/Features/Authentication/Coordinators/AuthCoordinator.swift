import SwiftUI

// MARK: - Auth Coordinator
@MainActor
class AuthCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var currentView: AuthView = .login

    // MARK: - Navigation
    func showLogin() {
        currentView = .login
    }

    func showRegister() {
        currentView = .register
    }

    func didCompleteAuth() {
        // TODO: Notify AppCoordinator to transition to main app
    }
}

// MARK: - Auth View
enum AuthView {
    case login
    case register
}

// MARK: - Auth Error
enum AuthError: Error {
    case invalidCredentials
    case invalidInput
    case networkError
}
