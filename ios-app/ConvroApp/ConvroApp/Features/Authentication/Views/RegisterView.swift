import SwiftUI

// MARK: - Register View (Step-by-step)
struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    let onSuccess: () -> Void
    let onBackToLogin: () -> Void

    @State private var step = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                // Top bar: back + step indicator
                HStack {
                    Button {
                        if step > 1 {
                            step -= 1
                        } else {
                            onBackToLogin()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(.white)
                    }

                    Spacer()

                    Text("Step \(step) of 3")
                        .font(.subheadline)
                        .foregroundColor(Color.white.opacity(0.4))

                    Spacer()

                    // Balance the back button
                    Color.clear.frame(width: 24, height: 24)
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer()

                // Step content
                switch step {
                case 1:
                    stepView(
                        title: "Choose a username",
                        subtitle: "This is how others find you on Convro.",
                        content: {
                            TextField("Username", text: $viewModel.username)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding()
                                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                                .cornerRadius(14)
                                .foregroundColor(.white)
                        },
                        buttonText: "Next",
                        isEnabled: viewModel.username.count >= 3,
                        action: { step = 2 }
                    )

                case 2:
                    stepView(
                        title: "What should we call you?",
                        subtitle: "Your display name is visible to contacts.",
                        content: {
                            TextField("Display Name", text: $viewModel.displayName)
                                .padding()
                                .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                                .cornerRadius(14)
                                .foregroundColor(.white)
                        },
                        buttonText: "Next",
                        isEnabled: !viewModel.displayName.isEmpty,
                        action: { step = 3 }
                    )

                case 3:
                    stepView(
                        title: "Create a password",
                        subtitle: "At least 8 characters. Make it strong.",
                        content: {
                            VStack(spacing: 14) {
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
                        },
                        buttonText: "Create Account",
                        isEnabled: viewModel.password.count >= 8 && viewModel.password == viewModel.confirmPassword,
                        action: {
                            Task {
                                await viewModel.register()
                            }
                        }
                    )

                default:
                    EmptyView()
                }

                Spacer()
                Spacer()
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

    // MARK: - Step View Builder
    @ViewBuilder
    private func stepView<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        buttonText: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }

            content()
                .padding(.horizontal, 28)

            Button(action: action) {
                Text(buttonText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isEnabled ? Color("ConvroBlue") : Color("ConvroBlue").opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 28)
            .disabled(!isEnabled)
        }
    }
}
