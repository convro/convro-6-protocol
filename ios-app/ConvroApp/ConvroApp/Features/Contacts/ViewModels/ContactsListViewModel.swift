import SwiftUI

@MainActor
class ContactsListViewModel: ObservableObject {
    @Published var contacts: [ContactResponse] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let contactsManager = ContactsManager.shared

    init() {
        // ContactsManager auto-loads on init
        contacts = contactsManager.contacts
    }

    /// Load contacts from server
    func loadContacts() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await contactsManager.loadContacts()
            contacts = contactsManager.contacts
            print("✅ Loaded \(contacts.count) contacts")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Load contacts failed: \(error)")
        }
    }

    /// Delete contact
    func deleteContact(_ contact: ContactResponse) async {
        do {
            try await contactsManager.deleteContact(contactId: contact.contactId)
            contacts = contactsManager.contacts
            print("✅ Contact deleted: \(contact.displayName ?? contact.convroNumber)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Delete contact failed: \(error)")
        }
    }

    /// Verify contact fingerprint
    func verifyContact(_ contact: ContactResponse) async {
        do {
            try await contactsManager.verifyContact(contactId: contact.contactId, verified: true)
            contacts = contactsManager.contacts
            print("✅ Contact verified: \(contact.displayName ?? contact.convroNumber)")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Verify contact failed: \(error)")
        }
    }

    /// Clear error
    func clearError() {
        errorMessage = nil
    }
}
