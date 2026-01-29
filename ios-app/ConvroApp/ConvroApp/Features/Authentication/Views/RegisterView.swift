import SwiftUI

// MARK: - Register View (Step-by-step)
struct RegisterView: View {
    @StateObject private var viewModel = RegisterViewModel()
    let onSuccess: () -> Void
    let onBackToLogin: () -> Void

    @State private var step = 1
    private let totalSteps = 3

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Top bar: back button
                HStack {
                    Button {
                        if step > 1 {
                            withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                        } else {
                            onBackToLogin()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.body.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)

                // Progress bar
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 3)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color("ConvroBlue"))
                            .frame(width: geo.size.width * CGFloat(step) / CGFloat(totalSteps), height: 3)
                            .animation(.easeInOut(duration: 0.3), value: step)
                    }
                }
                .frame(height: 3)
                .padding(.horizontal, 28)
                .padding(.top, 4)

                Spacer()

                // Step content
                Group {
                    switch step {
                    case 1:
                        registrationStep(
                            icon: "at",
                            title: "Choose a username",
                            subtitle: "This is how others find you on Convro.",
                            content: {
                                StyledTextField(
                                    icon: "person",
                                    placeholder: "Username",
                                    text: $viewModel.username,
                                    autocapitalize: false
                                )
                            },
                            buttonText: "Continue",
                            isEnabled: viewModel.username.count >= 3,
                            action: { withAnimation(.easeInOut(duration: 0.2)) { step = 2 } }
                        )

                    case 2:
                        registrationStep(
                            icon: "hand.wave",
                            title: "What should we call you?",
                            subtitle: "Your display name is visible to your contacts.",
                            content: {
                                StyledTextField(
                                    icon: "textformat",
                                    placeholder: "Display Name",
                                    text: $viewModel.displayName
                                )
                            },
                            buttonText: "Continue",
                            isEnabled: !viewModel.displayName.isEmpty,
                            action: { withAnimation(.easeInOut(duration: 0.2)) { step = 3 } }
                        )

                    case 3:
                        registrationStep(
                            icon: "lock.shield",
                            title: "Secure your account",
                            subtitle: "At least 8 characters. Make it count.",
                            content: {
                                VStack(spacing: 12) {
                                    StyledSecureField(
                                        icon: "lock",
                                        placeholder: "Password",
                                        text: $viewModel.password
                                    )
                                    StyledSecureField(
                                        icon: "lock.rotation",
                                        placeholder: "Confirm Password",
                                        text: $viewModel.confirmPassword
                                    )

                                    // Inline validation
                                    if !viewModel.confirmPassword.isEmpty && viewModel.password != viewModel.confirmPassword {
                                        HStack(spacing: 6) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.caption)
                                            Text("Passwords don't match")
                                                .font(.caption)
                                        }
                                        .foregroundColor(Color("ConvroRed"))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 4)
                                    }
                                }
                            },
                            buttonText: "Create Account",
                            isEnabled: viewModel.password.count >= 8 && viewModel.password == viewModel.confirmPassword,
                            action: {
                                Task { await viewModel.register() }
                            }
                        )

                    default:
                        EmptyView()
                    }
                }

                Spacer()
                Spacer()
            }
        }
        .navigationBarHidden(true)
        .loadingOverlay(isLoading: viewModel.isLoading)
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
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

    // MARK: - Step Builder
    @ViewBuilder
    private func registrationStep<Content: View>(
        icon: String,
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content,
        buttonText: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        VStack(spacing: 24) {
            // Icon
            Image(systemName: icon)
                .font(.system(size: 32, weight: .light))
                .foregroundColor(Color("ConvroBlue"))
                .padding(.bottom, 4)

            // Title + subtitle
            VStack(spacing: 6) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
            }

            // Input
            content()

            // Button
            Button(action: action) {
                Text(buttonText)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isEnabled ? Color("ConvroBlue") : Color("ConvroBlue").opacity(0.3))
                    .foregroundColor(.white)
                    .cornerRadius(16)
            }
            .disabled(!isEnabled)
        }
        .padding(.horizontal, 28)
    }
}

// MARK: - Styled Text Field
private struct StyledTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var autocapitalize: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(Color.white.opacity(0.3))
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .autocapitalization(autocapitalize ? .words : .none)
                .disableAutocorrection(true)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .cornerRadius(14)
    }
}

// MARK: - Styled Secure Field
private struct StyledSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(Color.white.opacity(0.3))
                .frame(width: 20)

            SecureField(placeholder, text: $text)
                .foregroundColor(.white)
        }
        .padding()
        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
        .cornerRadius(14)
    }
}
