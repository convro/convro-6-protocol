import SwiftUI

@MainActor
class ContactsListViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var isLoading: Bool = false

    func loadContacts() async {
        // TODO: Load from ContactsManager
    }
}
