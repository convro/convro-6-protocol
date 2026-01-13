import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var user: User?
    @Published var isLoading: Bool = false

    func loadUserProfile() async {
        // TODO: Load user profile
    }

    func logout() async {
        // TODO: Logout
    }
}
