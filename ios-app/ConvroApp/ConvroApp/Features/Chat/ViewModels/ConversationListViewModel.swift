import SwiftUI
import Combine

@MainActor
class ConversationListViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiManager = APIManager.shared
    private let webSocketManager = WebSocketManager.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupWebSocketSubscription()
        Task {
            await loadConversations()
        }
    }

    /// Setup WebSocket to update conversations on new messages
    private func setupWebSocketSubscription() {
        webSocketManager.incomingMessages
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshConversations()
                }
            }
            .store(in: &cancellables)
    }

    /// Load conversations from server
    func loadConversations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let responses = try await apiManager.fetchConversations()
            conversations = responses.map { $0.toConversation() }
            print("✅ Loaded \(conversations.count) conversations")
        } catch {
            errorMessage = error.localizedDescription
            print("❌ Load conversations failed: \(error)")
        }
    }

    /// Refresh conversations (pull-to-refresh)
    func refreshConversations() async {
        await loadConversations()
    }

    /// Clear error
    func clearError() {
        errorMessage = nil
    }
}
