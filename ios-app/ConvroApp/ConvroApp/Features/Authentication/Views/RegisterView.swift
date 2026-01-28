import SwiftUI

// MARK: - Register View
struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    let onSuccess: () -> Void
    let onBackToLogin: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    Spacer().frame(height: 20)

                    // Header
                    VStack(spacing: 8) {
                        Text("Create Account")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)

                        Text("Set up your private identity")
                            .font(.subheadline)
                            .foregroundColor(Color.white.opacity(0.4))
                    }

                    // Input Fields
                    VStack(spacing: 14) {
                        TextField("Username", text: $viewModel.username)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .cornerRadius(14)
                            .foregroundColor(.white)

                        TextField("Display Name", text: $viewModel.displayName)
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .cornerRadius(14)
                            .foregroundColor(.white)

                        SecureField("Password", text: $viewModel.password)
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .cornerRadius(14)
                            .foregroundColor(.white)

                        SecureField("Confirm Password", text: $viewModel.confirmPassword)
                            .padding()
                            .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                            .cornerRadius(14)
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 28)

                    // Create Account Button
                    Button {
                        Task {
                            await viewModel.register()
                            if viewModel.registrationSuccess {
                                onSuccess()
                            }
                        }
                    } label: {
                        Text("Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(!viewModel.isValid || viewModel.isLoading ? Color("ConvroBlue").opacity(0.3) : Color("ConvroBlue"))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.horizontal, 28)
                    .disabled(!viewModel.isValid || viewModel.isLoading)

                    // Back to Login
                    Button {
                        onBackToLogin()
                    } label: {
                        HStack(spacing: 4) {
                            Text("Already have an account?")
                                .foregroundColor(Color.white.opacity(0.4))
                            Text("Sign in")
                                .foregroundColor(Color("ConvroBlue"))
                                .fontWeight(.semibold)
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .navigationBarHidden(true)
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
