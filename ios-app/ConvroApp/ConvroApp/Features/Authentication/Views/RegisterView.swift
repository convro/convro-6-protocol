import SwiftUI

// MARK: - Register View
struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    let onSuccess: () -> Void
    let onBackToLogin: () -> Void

    var body: some View {
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
                            if viewModel.registrationSuccess {
                                onSuccess()
                            }
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
                        onBackToLogin()
                    }
                }
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
            .sheet(isPresented: $viewModel.registrationSuccess) {
                if let convroNumber = viewModel.assignedConvroNumber {
                    ConvroNumberDisplayView(
                        convroNumber: convroNumber,
                        onContinue: onSuccess
                    )
                }
            }
    }
}

// MARK: - String Identifiable Extension
extension String: Identifiable {
    public var id: String { self }
}
