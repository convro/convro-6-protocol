import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(
            conversationId: UUID(uuidString: conversation.id) ?? UUID(),
            participantConvroNumber: conversation.participant.convroNumber,
            participantDisplayName: conversation.participant.displayName
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Messages List
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .background(Color.chatBackground)
            }

            // Input Bar
            HStack(spacing: 12) {
                TextField("Message", text: $viewModel.messageText)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(20)
                    .focused($isInputFocused)

                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 34, height: 34)
                        .foregroundColor(viewModel.messageText.isEmpty ? .gray : Color("ConvroBlue"))
                }
                .disabled(viewModel.messageText.isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.systemGray4)),
                alignment: .top
            )
        }
        .navigationTitle(viewModel.participantDisplayName ?? viewModel.participantConvroNumber)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar) // Hide tab bar in chat view
        .task {
            await viewModel.loadMessages()
        }
    }
}
