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
/// Manages app-wide navigation and state transitions
@MainActor
class AppCoordinator: ObservableObject {
    // MARK: - Published Properties
    @Published var appState: AppState = .splash
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Dependencies
    private let apiManager = APIManager.shared
    private let keychainManager = KeychainManager.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - UserDefaults Keys
    private let hasCompletedOnboardingKey = "has_completed_onboarding"

    // MARK: - Initialization
    init() {
        start()
    }

    // MARK: - State Management

    /// Determine initial app state based on onboarding and authentication status
    func start() {
        isLoading = true
        defer { isLoading = false }

        // Check onboarding status
        let hasCompletedOnboarding = UserDefaults.standard.bool(forKey: hasCompletedOnboardingKey)

        if !hasCompletedOnboarding {
            // Show onboarding for first-time users
            appState = .onboarding
            print("📱 App State: Onboarding (first launch)")
            return
        }

        // Check authentication status
        let isAuthenticated = checkAuthenticationStatus()

        if isAuthenticated {
            // User is logged in - show main app
            appState = .main
            print("📱 App State: Main (authenticated)")

            // Auto-connect WebSocket if we have token
            Task {
                await reconnectWebSocket()
            }
        } else {
            // User needs to login
            appState = .authentication
            print("📱 App State: Authentication (not logged in)")
        }
    }

    /// Check if user is authenticated by verifying stored tokens
    private func checkAuthenticationStatus() -> Bool {
        // Check if we have valid access token in Keychain
        do {
            let hasTokens = try keychainManager.hasValidTokens()
            return hasTokens
        } catch {
            print("⚠️ Failed to check auth status: \(error)")
            return false
        }
    }

    /// Reconnect WebSocket on app start if authenticated
    private func reconnectWebSocket() async {
        do {
            let accessToken = try keychainManager.getAccessToken()
            await WebSocketManager.shared.connect(accessToken: accessToken)
            print("✅ WebSocket reconnected on app start")
        } catch {
            print("⚠️ Failed to reconnect WebSocket: \(error)")
        }
    }

    // MARK: - Navigation Actions

    /// Complete onboarding and move to authentication
    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: hasCompletedOnboardingKey)
        appState = .authentication
        print("✅ Onboarding completed → Authentication")
    }

    /// Show onboarding (for testing or reset)
    func showOnboarding() {
        appState = .onboarding
        print("📱 Navigating to: Onboarding")
    }

    /// User authenticated successfully - show main app
    func userDidAuthenticate() {
        appState = .main
        print("✅ User authenticated → Main app")
    }

    /// Show authentication screen (used by logout)
    func showAuthentication() {
        appState = .authentication
        print("📱 Navigating to: Authentication")
    }

    /// Show main app
    func showMainApp() {
        appState = .main
        print("📱 Navigating to: Main app")
    }

    /// User logged out - clear data and show authentication
    func userDidLogout() {
        // Clear onboarding flag if needed (or keep it)
        // UserDefaults.standard.removeObject(forKey: hasCompletedOnboardingKey)

        appState = .authentication
        print("✅ User logged out → Authentication")
    }

    // MARK: - Error Handling

    func handleError(_ error: Error) {
        errorMessage = error.localizedDescription
        print("❌ App Error: \(error.localizedDescription)")
    }

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - KeychainManager Extension
extension KeychainManager {
    /// Check if we have valid authentication tokens
    func hasValidTokens() throws -> Bool {
        do {
            let _ = try getAccessToken()
            return true
        } catch {
            return false
        }
    }

    /// Get access token from Keychain
    func getAccessToken() throws -> String {
        guard let tokenData = try? retrieve(forKey: "access_token"),
              let token = String(data: tokenData, encoding: .utf8) else {
            throw KeychainError.itemNotFound
        }
        return token
    }
}
