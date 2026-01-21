import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    let onLogout: () -> Void

    var body: some View {
        List {
            Section("Profile") {
                if let user = viewModel.user {
                    Text(user.displayName).font(.headline)
                    Text(user.convroNumber).font(.subheadline).foregroundColor(.secondary)
                } else {
                    Text("Loading...").foregroundColor(.secondary)
                }
            }

            Section("Security") {
                if viewModel.canUseBiometrics {
                    Toggle("\(viewModel.biometricType)", isOn: $viewModel.isBiometricEnabled)
                        .onChange(of: viewModel.isBiometricEnabled) { newValue in
                            viewModel.toggleBiometric(enabled: newValue)
                        }
                }
            }

            Section("Account") {
                NavigationLink("Devices") {
                    DevicesListView(viewModel: viewModel)
                }
                NavigationLink("Privacy") { Text("Privacy Settings") }
                NavigationLink("Security") { Text("Security Settings") }
            }

            Section {
                Button("Logout", role: .destructive) {
                    Task {
                        await viewModel.logout()
                        if viewModel.logoutSuccess {
                            onLogout()
                        }
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task {
            await viewModel.loadUserProfile()
        }
        .loadingOverlay(isLoading: viewModel.isLoading)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.clearError()
            }
        } message: {
            if let error = viewModel.errorMessage {
                Text(error)
            }
        }
    }
}

// MARK: - Devices List View
struct DevicesListView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            ForEach(viewModel.devices) { device in
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.deviceName).font(.headline)
                    Text("\(device.platform) • Last seen: \(device.lastSeen.formatted())")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .swipeActions {
                    Button("Remove", role: .destructive) {
                        Task {
                            await viewModel.removeDevice(device)
                        }
                    }
                }
            }
        }
        .navigationTitle("Devices")
        .task {
            await viewModel.loadDevices()
        }
    }
}
