import SwiftUI

@MainActor
class AddContactViewModel: ObservableObject {
    @Published var convroNumber: String = ""
    @Published var displayName: String = ""
    @Published var isLoading: Bool = false

    func addContact() async throws {
        // TODO: Add contact via ContactsManager
    }
}
