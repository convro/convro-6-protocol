import SwiftUI
import Combine

@MainActor
class ConversationListViewModel: ObservableObject {
    @Published var conversations: [Conversation] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let apiManager = APIManager.shared
    private let webSocketManager = WebSocketManager.shared
    private let messageStorage = MessageStorage.shared
    private var cancellables = Set<AnyCancellable>()
    private var pollingTimer: Timer?

    init() {
        setupWebSocketSubscription()
        setupGlobalInboxPolling()
        Task {
            await loadConversations()
        }
    }

    deinit {
        pollingTimer?.invalidate()
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

    /// Setup global inbox polling (runs even when no chat is open)
    private func setupGlobalInboxPolling() {
        // Poll every 5 seconds for new messages
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.pollGlobalInbox()
            }
        }

        // Fire immediately on startup
        Task { @MainActor in
            await pollGlobalInbox()
        }
    }

    /// Poll inbox globally and handle new messages
    private func pollGlobalInbox() async {
        do {
            let inboxMessages = try await apiManager.fetchInbox()

            if !inboxMessages.isEmpty {
                print("📬 Global inbox polling: received \(inboxMessages.count) new messages")

                // Process each message
                for inboxMessage in inboxMessages {
                    print("📩 New message in global inbox: \(inboxMessage.messageId), type: \(inboxMessage.messageType)")

                    // If handshake_offer received, we need to create conversation
                    if inboxMessage.messageType == "handshake_offer" {
                        await handleIncomingHandshakeOffer(inboxMessage)
                    }
                }

                // Refresh conversations from backend (might include new conversations)
                await syncWithBackend()

                // Also reload local storage in case we created new conversations
                await loadConversations()
            }

        } catch {
            // Silent fail - polling is background operation
            print("⚠️ Global inbox polling failed: \(error.localizedDescription)")
        }
    }

    /// Handle incoming handshake offer (create conversation for recipient)
    private func handleIncomingHandshakeOffer(_ inboxMessage: InboxMessage) async {
        print("🤝 NEW CONVERSATION: Received handshake offer!")

        // Simple approach: Create conversation from ALL contacts
        // The one who sent the handshake will have messages in their chat
        // This ensures recipient sees the conversation immediately!

        do {
            // Fetch contacts
            let contacts = try await apiManager.fetchContacts()

            print("📋 Creating conversations for \(contacts.count) contacts (one of them sent handshake)")

            // Create conversation for each contact
            // The correct one will show handshake offer when opened
            for contact in contacts {
                // Check if conversation already exists
                let existingConversations = await messageStorage.fetchAllConversations()
                if existingConversations.contains(where: { $0.participantConvroNumber == contact.convroNumber }) {
                    print("⏭️ Conversation already exists for \(contact.displayName ?? contact.convroNumber)")
                    continue
                }

                let conversation = StoredConversation(
                    id: UUID().uuidString,
                    participantConvroNumber: contact.convroNumber,
                    participantDisplayName: contact.displayName,
                    lastMessageText: "🤝 New message",
                    lastActivityAt: inboxMessage.createdAt,
                    unreadCount: 1,
                    sessionId: nil
                )

                await messageStorage.saveConversation(conversation)
                print("💾 Created conversation for contact: \(contact.displayName ?? contact.convroNumber)")
            }

        } catch {
            print("❌ Failed to create conversations: \(error)")
        }
    }

    /// Load conversations from local storage
    func loadConversations() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Load from local storage first (instant)
        let storedConversations = await messageStorage.fetchAllConversations()
        conversations = storedConversations.map { $0.toConversation() }
        print("✅ Loaded \(conversations.count) conversations from storage")

        // Optionally sync with backend in background
        await syncWithBackend()
    }

    /// Sync conversations with backend (background)
    private func syncWithBackend() async {
        do {
            let responses = try await apiManager.fetchConversations()

            // Merge backend conversations with local ones
            for response in responses {
                let conversation = response.toConversation()

                // Check if we already have this conversation locally
                if !conversations.contains(where: { $0.id == conversation.id }) {
                    // New conversation from backend - add it
                    let stored = StoredConversation.from(conversation: conversation)
                    await messageStorage.saveConversation(stored)
                }
            }

            // Reload from storage to get merged data
            let storedConversations = await messageStorage.fetchAllConversations()
            conversations = storedConversations.map { $0.toConversation() }

            print("✅ Synced \(responses.count) conversations from backend")
        } catch {
            print("⚠️ Backend sync failed (offline?): \(error)")
            // Don't show error - local conversations still work
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
