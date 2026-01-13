import SwiftUI
import Combine

// MARK: - App State
enum AppState {
    case splash
    case onboarding
    case authentication
    case main
}

// MARK: - App Coordinator
@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var appState: AppState = .splash
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init() {
        // TODO: Check authentication state
        // TODO: Check onboarding status
        // TODO: Initialize core services
    }

    // MARK: - State Management
    func start() {
        // TODO: Determine initial state
    }

    func showOnboarding() {
        appState = .onboarding
    }

    func showAuthentication() {
        appState = .authentication
    }

    func showMainApp() {
        appState = .main
    }

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
    }
}
