import SwiftUI

struct FingerprintView: View {
    let fingerprint: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Identity Fingerprint")
                .font(.headline)

            Text(fingerprint)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

            Text("Verify this fingerprint out-of-band with your contact")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
