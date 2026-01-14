import SwiftUI

// MARK: - Login View
struct LoginView: View {
    @StateObject private var viewModel = LoginViewModel()
    let onSuccess: () -> Void
    let onShowRegister: () -> Void

    var body: some View {
        VStack(spacing: 24) {
                // Logo
                Image(systemName: "message.fill")
                    .resizable()
                    .frame(width: 80, height: 80)
                    .foregroundColor(.convroBlue)

                Text("Convro")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                // Input Fields
                VStack(spacing: 16) {
                    TextField("Username", text: $viewModel.username)
                        .textFieldStyle(.roundedBorder)
                        .autocapitalization(.none)

                    SecureField("Password", text: $viewModel.password)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(.horizontal)

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
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.convroBlue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .padding(.horizontal)
                .disabled(viewModel.isLoading)

                // Register Link
                Button {
                    onShowRegister()
                } label: {
                    Text("Don't have an account? Register")
                        .font(.footnote)
                }

                Spacer()
            }
            .padding()
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
