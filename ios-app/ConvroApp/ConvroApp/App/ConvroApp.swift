import SwiftUI

@main
struct ConvroApp: App {
    // MARK: - Properties
    @StateObject private var appCoordinator = AppCoordinator()

    // MARK: - Initialization
    init() {
        // TODO: Configure appearance
        // TODO: Initialize core managers
    }

    // MARK: - Body
    var body: some Scene {
        WindowGroup {
            // TODO: Root view based on app state
            ContentView()
                .environmentObject(appCoordinator)
        }
    }
}

// MARK: - Content View (Temporary)
struct ContentView: View {
    var body: some View {
        Text("Convro")
            .font(.largeTitle)
    }
}
