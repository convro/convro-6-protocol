import Foundation

// MARK: - Contacts Manager
/// Contact list management
@MainActor
class ContactsManager: ObservableObject {
    // MARK: - Singleton
    static let shared = ContactsManager()

    // MARK: - Properties
    @Published var contacts: [Contact] = []
    @Published var isLoading: Bool = false

    private init() {}

    // MARK: - Operations
    func loadContacts() async throws {
        isLoading = true
        defer { isLoading = false }

        // TODO: Fetch from API
        contacts = try await APIManager.shared.listContacts()
    }

    func addContact(convroNumber: String, displayName: String) async throws -> Contact {
        // TODO: Call API
        let contact = try await APIManager.shared.addContact(convroNumber: convroNumber, displayName: displayName)
        contacts.append(contact)
        return contact
    }

    func verifyContact(_ contact: Contact) async throws {
        // TODO: Mark as verified after fingerprint check
        fatalError("Not implemented")
    }

    func deleteContact(_ contact: Contact) async throws {
        // TODO: Delete from API
        contacts.removeAll { $0.id == contact.id }
    }

    func searchContact(byConvroNumber number: String) async throws -> Contact? {
        // TODO: Call API search
        fatalError("Not implemented")
    }
}
