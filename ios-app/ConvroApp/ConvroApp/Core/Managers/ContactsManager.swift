import Foundation

// MARK: - Contacts Manager
/// Contact list management (wrapper for APIManager contacts endpoints)
@MainActor
class ContactsManager: ObservableObject {
    // MARK: - Singleton
    static let shared = ContactsManager()

    // MARK: - Properties
    @Published var contacts: [ContactResponse] = []
    @Published var isLoading: Bool = false

    private init() {
        Task {
            try? await loadContacts()
        }
    }

    // MARK: - Operations

    /// Load all contacts from server
    func loadContacts() async throws {
        isLoading = true
        defer { isLoading = false }

        contacts = try await APIManager.shared.listContacts()
    }

    /// Add new contact by Convro Number
    func addContact(convroNumber: String, displayName: String?) async throws -> ContactResponse {
        let contact = try await APIManager.shared.addContact(convroNumber: convroNumber, displayName: displayName)

        // Add to local list
        contacts.append(contact)

        return contact
    }

    /// Verify contact's fingerprint (after manual verification)
    func verifyContact(contactId: UUID, verified: Bool = true) async throws {
        try await APIManager.shared.verifyContact(contactId: contactId, verified: verified)

        // Update local state
        if let index = contacts.firstIndex(where: { $0.contactId == contactId }) {
            var updatedContact = contacts[index]
            contacts[index] = ContactResponse(
                contactId: updatedContact.contactId,
                convroNumber: updatedContact.convroNumber,
                displayName: updatedContact.displayName,
                identityPubEd25519: updatedContact.identityPubEd25519,
                fingerprint: updatedContact.fingerprint,
                verified: verified,
                createdAt: updatedContact.createdAt
            )
        }
    }

    /// Delete contact
    func deleteContact(contactId: UUID) async throws {
        try await APIManager.shared.deleteContact(contactId: contactId)

        // Remove from local list
        contacts.removeAll { $0.contactId == contactId }
    }

    /// Find contact by Convro Number (local search)
    func findContact(byConvroNumber number: String) -> ContactResponse? {
        return contacts.first { $0.convroNumber == number }
    }

    /// Get contact by ID (local)
    func getContact(byId id: UUID) -> ContactResponse? {
        return contacts.first { $0.contactId == id }
    }

    /// Refresh contacts from server
    func refresh() async throws {
        try await loadContacts()
    }
}
