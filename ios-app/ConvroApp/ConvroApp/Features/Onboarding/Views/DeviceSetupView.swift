import SwiftUI

struct DeviceSetupView: View {
    var onComplete: () -> Void
    @State private var isReady = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Illustration
                Image("IMG_4159-ntf-2")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(.horizontal, 40)
                .offset(y: -20)

                // Text + Button
                VStack(spacing: 16) {
                    Text("Your secure identity")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("We're generating your encryption keys.\nThis stays on your device — always.")
                        .font(.body)
                        .foregroundColor(Color.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)

                    if isReady {
                        Button {
                            onComplete()
                        } label: {
                            Text("Continue")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color("ConvroBlue"))
                                .foregroundColor(.white)
                                .cornerRadius(16)
                        }
                        .padding(.top, 8)
                    } else {
                        ProgressView()
                            .tint(Color("ConvroBlue"))
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 28)
                .offset(y: -60)

                Spacer()
            }
            .padding(.top, 40)
        }
        .navigationBarHidden(true)
        .task {
            do {
                try await DeviceIdentityManager.shared.generateIdentity()
                print("✅ Device identity generated in onboarding")
                isReady = true
            } catch {
                print("❌ Failed to generate device identity: \(error)")
                isReady = true // Allow continue even on error
            }
        }
    }
}
