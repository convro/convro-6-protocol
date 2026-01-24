import SwiftUI

struct ContactRow: View {
    let contact: ContactResponse

    var body: some View {
        HStack {
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundColor(.gray)

            VStack(alignment: .leading) {
                Text(contact.displayName ?? contact.convroNumber).fontWeight(.semibold)
                Text(contact.convroNumber).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            if contact.verified {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(Color("ConvroGreen"))
            }
        }
    }
}
