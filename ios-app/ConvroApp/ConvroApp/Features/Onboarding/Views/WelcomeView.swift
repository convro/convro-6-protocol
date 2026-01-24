import SwiftUI

struct WelcomeView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: "lock.shield.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(Color("ConvroBlue"))

            Text("Welcome to Convro")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("End-to-end encrypted messaging with maximum privacy")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 16) {
                FeatureRow(icon: "lock.fill", title: "Privacy-First", description: "Server never sees sender identity")
                FeatureRow(icon: "shield.fill", title: "E2EE", description: "Military-grade encryption")
                FeatureRow(icon: "timer", title: "Sealed Sender", description: "64KB padding, timestamp obfuscation")
            }
            .padding()

            Button {
                onContinue()
            } label: {
                Text("Get Started")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color("ConvroBlue"))
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(Color("ConvroBlue"))
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
        }
    }
}
