import SwiftUI

struct ContactDetailView: View {
    let contact: Contact

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)

            Text(contact.displayName).font(.title).fontWeight(.bold)
            Text(contact.convroNumber).foregroundColor(.secondary)

            // TODO: Show fingerprint, verification status
        }
        .navigationTitle("Contact Details")
    }
}
