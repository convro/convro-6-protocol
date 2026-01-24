import SwiftUI

struct ContactDetailView: View {
    let contact: ContactResponse
    @StateObject private var viewModel = ContactsListViewModel()
    @State private var showVerificationAlert = false

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                // Contact Avatar
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 100, height: 100)
                    .foregroundColor(contact.verified ? Color("ConvroGreen") : .gray)

                // Contact Info
                VStack(spacing: 8) {
                    Text(contact.displayName ?? "Unknown")
                        .font(.title)
                        .fontWeight(.bold)

                    Text(contact.convroNumber)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)

                    if contact.verified {
                        HStack {
                            Image(systemName: "checkmark.shield.fill")
                                .foregroundColor(Color("ConvroGreen"))
                            Text("Verified")
                                .foregroundColor(Color("ConvroGreen"))
                                .fontWeight(.medium)
                        }
                        .padding(.top, 4)
                    }
                }

                // Fingerprint Section
                VStack(spacing: 16) {
                    Divider()

                    FingerprintView(fingerprint: contact.fingerprint)

                    if !contact.verified {
                        Button {
                            showVerificationAlert = true
                        } label: {
                            Text("Mark as Verified")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color("ConvroGreen"))
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }

                    Divider()
                }

                // Contact Metadata
                VStack(alignment: .leading, spacing: 12) {
                    InfoRow(label: "Added", value: contact.createdAt.formatted())
                    InfoRow(label: "Identity Key", value: String(contact.identityPubEd25519.prefix(16)) + "...")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer()
            }
            .padding(.vertical)
        }
        .navigationTitle("Contact Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Verify Contact", isPresented: $showVerificationAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Verify") {
                Task {
                    await viewModel.verifyContact(contact)
                }
            }
        } message: {
            Text("Have you verified this fingerprint out-of-band with \(contact.displayName ?? "this contact")?")
        }
    }
}

// MARK: - Info Row
struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
