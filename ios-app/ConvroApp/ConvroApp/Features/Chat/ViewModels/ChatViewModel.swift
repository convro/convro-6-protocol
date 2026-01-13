import SwiftUI
import Combine

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    @Published var isLoading: Bool = false

    let conversation: Conversation

    init(conversation: Conversation) {
        self.conversation = conversation
    }

    func loadMessages() async {
        // TODO: Load messages for conversation
    }

    func sendMessage() async {
        guard !messageText.isEmpty else { return }
        // TODO: Encrypt and send message
        messageText = ""
    }
}
