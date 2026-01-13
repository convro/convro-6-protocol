import SwiftUI

struct ContactsListView: View {
    @StateObject private var viewModel = ContactsListViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.contacts) { contact in
                ContactRow(contact: contact)
            }
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { /* TODO: Add contact */ } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .task {
            await viewModel.loadContacts()
        }
    }
}
