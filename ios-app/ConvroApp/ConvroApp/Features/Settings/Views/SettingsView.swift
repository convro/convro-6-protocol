import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()

    var body: some View {
        NavigationView {
            List {
                Section("Profile") {
                    if let user = viewModel.user {
                        Text(user.displayName).font(.headline)
                        Text(user.convroNumber).font(.subheadline).foregroundColor(.secondary)
                    }
                }

                Section("Account") {
                    NavigationLink("Devices") { Text("Devices") }
                    NavigationLink("Privacy") { Text("Privacy") }
                    NavigationLink("Security") { Text("Security") }
                }

                Section {
                    Button("Logout", role: .destructive) {
                        Task { await viewModel.logout() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
        .task {
            await viewModel.loadUserProfile()
        }
    }
}
