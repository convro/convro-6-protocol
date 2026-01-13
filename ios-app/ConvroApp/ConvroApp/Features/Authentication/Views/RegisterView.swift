import SwiftUI

// MARK: - Register View
struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    @EnvironmentObject private var coordinator: AppCoordinator
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Account Information") {
                    TextField("Username", text: $viewModel.username)
                        .autocapitalization(.none)

                    TextField("Display Name", text: $viewModel.displayName)
                }

                Section("Security") {
                    SecureField("Password", text: $viewModel.password)

                    SecureField("Confirm Password", text: $viewModel.confirmPassword)
                }

                Section {
                    Button {
                        Task {
                            await viewModel.register()
                        }
                    } label: {
                        Text("Create Account")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                    .disabled(!viewModel.isValid || viewModel.isLoading)
                }
            }
            .navigationTitle("Register")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .loadingOverlay(isLoading: viewModel.isLoading)
            .errorAlert($viewModel.error)
            .sheet(item: $viewModel.assignedConvroNumber) { convroNumber in
                ConvroNumberDisplayView(convroNumber: convroNumber)
            }
        }
    }
}

// MARK: - String Identifiable Extension
extension String: Identifiable {
    public var id: String { self }
}
