import SwiftUI

@MainActor
class AddContactViewModel: ObservableObject {
    @Published var convroNumber: String = ""
    @Published var displayName: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var addSuccess: Bool = false
    @Published var addedContact: ContactResponse?

    private let contactsManager = ContactsManager.shared

    /// Add contact by Convro Number
    func addContact() async {
        guard !convroNumber.isEmpty else {
            errorMessage = "Please enter Convro Number"
            return
        }

        // Validate Convro Number format (6 digits)
        guard convroNumber.count == 6, Int(convroNumber) != nil else {
            errorMessage = "Convro Number must be 6 digits"
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let contact = try await contactsManager.addContact(
                convroNumber: convroNumber,
                displayName: displayName.isEmpty ? nil : displayName
            )

            addedContact = contact
            addSuccess = true

            print("✅ Contact added: \(contact.displayName ?? contact.convroNumber)")
            print("   Fingerprint: \(contact.fingerprint)")

        } catch {
            errorMessage = error.localizedDescription
            print("❌ Add contact failed: \(error)")
        }
    }

    /// Validate Convro Number
    func validateConvroNumber() -> String? {
        guard !convroNumber.isEmpty else { return nil }
        guard convroNumber.count == 6 else {
            return "Must be 6 digits"
        }
        guard Int(convroNumber) != nil else {
            return "Must be numbers only"
        }
        return nil
    }

    /// Clear error
    func clearError() {
        errorMessage = nil
    }

    /// Reset form
    func reset() {
        convroNumber = ""
        displayName = ""
        errorMessage = nil
        addSuccess = false
        addedContact = nil
    }
}
