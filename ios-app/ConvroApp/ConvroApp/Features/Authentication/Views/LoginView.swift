import SwiftUI

// MARK: - Login View
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    let onSuccess: () -> Void
    let onShowRegister: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Logo
                Image("L-Logo-7-5")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 20))

                Text("Sign in to Convro")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                // Input Fields
                VStack(spacing: 14) {
                    TextField("Username", text: $viewModel.username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .padding()
                        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .cornerRadius(14)
                        .foregroundColor(.white)

                    SecureField("Password", text: $viewModel.password)
                        .padding()
                        .background(Color(red: 0.1, green: 0.1, blue: 0.1))
                        .cornerRadius(14)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 28)

                // Login Button
                Button {
                    Task {
                        await viewModel.login()
                        if viewModel.loginSuccess {
                            onSuccess()
                        }
                    }
                } label: {
                    Text("Login")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color("ConvroBlue"))
                        .foregroundColor(.white)
                        .cornerRadius(16)
                }
                .padding(.horizontal, 28)
                .disabled(viewModel.isLoading)

                // Register Link
                Button {
                    onShowRegister()
                } label: {
                    HStack(spacing: 4) {
                        Text("Don't have an account?")
                            .foregroundColor(Color.white.opacity(0.4))
                        Text("Register")
                            .foregroundColor(Color("ConvroBlue"))
                            .fontWeight(.semibold)
                    }
                    .font(.subheadline)
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
    }
}
