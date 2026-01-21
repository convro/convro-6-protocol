import SwiftUI

struct PermissionsView: View {
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("Permissions").font(.largeTitle).fontWeight(.bold)

            VStack(spacing: 16) {
                PermissionRow(icon: "bell.fill", title: "Notifications", description: "Receive new messages")
                PermissionRow(icon: "faceid", title: "Biometrics", description: "Secure app unlock")
            }

            Button("Grant Permissions") { onContinue() }
                .frame(maxWidth: .infinity)
                .padding()
                .background(ColorColor("ConvroBlue"))
                .foregroundColor(.white)
                .cornerRadius(12)
                .padding(.horizontal)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack {
            Image(systemName: icon).frame(width: 40)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(description).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .padding(.horizontal)
    }
}
