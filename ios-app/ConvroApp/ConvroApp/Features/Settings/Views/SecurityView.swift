import SwiftUI

struct SecurityView: View {
    @State private var biometricsEnabled = true

    var body: some View {
        Form {
            Section("Authentication") {
                Toggle("Face ID / Touch ID", isOn: $biometricsEnabled)
            }

            Section("Encryption") {
                Text("End-to-end encryption: Active")
                    .foregroundColor(Color("ConvroGreen"))
            }
        }
        .navigationTitle("Security")
    }
}
