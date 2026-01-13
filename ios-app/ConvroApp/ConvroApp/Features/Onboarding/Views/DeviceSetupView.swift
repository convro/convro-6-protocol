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
            // TODO: Generate device identity
        }
    }
}
