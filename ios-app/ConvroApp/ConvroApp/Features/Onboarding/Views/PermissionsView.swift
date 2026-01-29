import SwiftUI
import UserNotifications
import LocalAuthentication

struct PermissionsView: View {
    var onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Illustration
                Image("IMG_4158-ntf-2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 40)
                .offset(y: -20)

                // Text + Button
                VStack(spacing: 16) {
                    Text("Stay in the loop")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Enable notifications and biometrics\nto keep your messages secure and instant.")
                        .font(.body)
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    Button {
                        requestPermissions()
                    } label: {
                        Text("Enable Permissions")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color("ConvroBlue"))
                            .foregroundColor(.white)
                            .cornerRadius(16)
                    }
                    .padding(.top, 8)
                }
                .padding(.horizontal, 28)
                .offset(y: -60)

                Spacer()
            }
            .padding(.top, 40)
        }
        .navigationBarHidden(true)
    }

    private func requestPermissions() {
        // Request push notifications
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            // Request biometrics (triggers Face ID / Touch ID prompt)
            let context = LAContext()
            var error: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
                context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "Enable biometric unlock for Convro") { _, _ in
                    DispatchQueue.main.async {
                        onContinue()
                    }
                }
            } else {
                // No biometrics available, just continue
                DispatchQueue.main.async {
                    onContinue()
                }
            }
        }
    }
}
