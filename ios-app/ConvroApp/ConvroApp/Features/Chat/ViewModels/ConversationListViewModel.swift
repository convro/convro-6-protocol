import SwiftUI

@MainActor
class ConversationListViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false

    func loadConversations() async {
        isLoading = true
        defer { isLoading = false }
        // TODO: Load from API
    }
}
