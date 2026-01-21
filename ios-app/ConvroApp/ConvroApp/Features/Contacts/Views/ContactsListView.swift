import SwiftUI

struct ContactsListView: View {
    @StateObject private var viewModel = ContactsListViewModel()
    @State private var showingAddContact = false

    var body: some View {
        List(viewModel.contacts) { contact in
            NavigationLink(destination: ContactDetailView(contact: contact)) {
                ContactRow(contact: contact)
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddContact) {
            NavigationView {
                AddContactView(onSuccess: {
                    showingAddContact = false
                    Task {
                        await viewModel.loadContacts()
                    }
                }, onCancel: {
                    showingAddContact = false
                })
            }
        }
        .task {
            await viewModel.loadContacts()
        }
    }
}
