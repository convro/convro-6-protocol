import SwiftUI

struct DeviceSetupView: View {
    var onComplete: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ProgressView("Generating device identity...")

            Text("Setting up encryption keys...")
                .foregroundColor(.secondary)

            Button("Complete Setup") { onComplete() }
        }
        .task {
            // Generate device identity (Ed25519 + X25519 keypairs)
            do {
                try await DeviceIdentityManager.shared.generateIdentity()
                print("✅ Device identity generated in onboarding")
                // Auto-saved to Keychain by DeviceIdentityManager
            } catch {
                print("❌ Failed to generate device identity: \(error)")
            }
        }
    }
}
