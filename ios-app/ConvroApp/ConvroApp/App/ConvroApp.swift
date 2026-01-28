import SwiftUI

@main
struct ConvroApp: App {
    // MARK: - Properties
    @StateObject private var appCoordinator = AppCoordinator()

    // MARK: - Initialization
    init() {
        configureAppearance()
    }

    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appCoordinator)
        }
    }

    // MARK: - Configuration
    private func configureAppearance() {
        // Configure global appearance
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Root View
struct RootView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator

    var body: some View {
        ZStack {
            // Main content based on app state
            switch appCoordinator.appState {
            case .splash:
                SplashView()

            case .onboarding:
                OnboardingFlowView()

            case .authentication:
                AuthenticationFlowView()

            case .main:
                MainAppView()
            }

            // Loading overlay
            if appCoordinator.isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(.white)
            }
        }
        .alert("Error", isPresented: .constant(appCoordinator.errorMessage != nil)) {
            Button("OK") {
                appCoordinator.clearError()
            }
        } message: {
            if let error = appCoordinator.errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - Splash View
struct SplashView: View {
    var body: some View {
        ZStack {
            Color.blue.ignoresSafeArea()
            VStack(spacing: 20) {
                Image(systemName: "message.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                Text("Convro")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
        }
    }
}

// MARK: - Onboarding Flow View
struct OnboardingFlowView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()

                switch viewModel.currentStep {
                case .welcome:
                    WelcomeView(onContinue: {
                        viewModel.nextStep()
                    })

                case .permissions:
                    PermissionsView(onContinue: {
                        viewModel.nextStep()
                    })

                case .deviceSetup:
                    DeviceSetupView(onComplete: {
                        appCoordinator.completeOnboarding()
                    })
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
    }
}

// MARK: - Authentication Flow View
struct AuthenticationFlowView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var showRegister = false

    var body: some View {
        NavigationView {
            if showRegister {
                RegisterView(
                    onSuccess: {
                        appCoordinator.userDidAuthenticate()
                    },
                    onBackToLogin: {
                        showRegister = false
                    }
                )
            } else {
                LoginView(
                    onSuccess: {
                        appCoordinator.userDidAuthenticate()
                    },
                    onShowRegister: {
                        showRegister = true
                    }
                )
            }
        }
    }
}

// MARK: - Main App View
struct MainAppView: View {
    @EnvironmentObject var appCoordinator: AppCoordinator
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            // Conversations Tab
            NavigationView {
                ConversationListView()
            }
            .tabItem {
                Label("Chats", systemImage: "message.fill")
            }
            .tag(0)

            // Contacts Tab
            NavigationView {
                ContactsListView()
            }
            .tabItem {
                Label("Contacts", systemImage: "person.2.fill")
            }
            .tag(1)

            // Settings Tab
            NavigationView {
                SettingsView(onLogout: {
                    appCoordinator.userDidLogout()
                })
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            .tag(2)
        }
    }
}
