import SwiftUI

// MARK: - Convro Number Display View
struct ConvroNumberDisplayView: View {
    let convroNumber: String
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .resizable()
                .frame(width: 80, height: 80)
                .foregroundColor(.convroGreen)

            Text("Welcome to Convro!")
                .font(.title)
                .fontWeight(.bold)

            Text("Your Convro Number")
                .font(.headline)
                .foregroundColor(.secondary)

            Text(convroNumber)
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(.convroBlue)

            Text("Save this number. Your contacts will use it to reach you.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button {
                UIPasteboard.general.string = convroNumber
            } label: {
                Label("Copy Number", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.convroBlue.opacity(0.1))
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Button {
                onContinue()
            } label: {
                Text("Continue")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.convroBlue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)

            Spacer()
        }
        .padding()
    }
}
