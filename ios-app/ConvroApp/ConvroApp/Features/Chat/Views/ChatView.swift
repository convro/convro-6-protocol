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
            // Custom Header
            HStack(spacing: 12) {
                // Avatar
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .frame(width: 40, height: 40)
                    .foregroundColor(.gray)

                // Name and number
                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.participantDisplayName ?? "Unknown")
                        .font(.headline)
                        .lineLimit(1)

                    Text(viewModel.participantConvroNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .overlay(
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundColor(Color(.systemGray4)),
                alignment: .bottom
            )

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
        .navigationTitle("") // Hide default title
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(false) // Keep back arrow, hide label
        .toolbar(.hidden, for: .tabBar) // Hide tab bar in chat view
        .task {
            await viewModel.loadMessages()
        }
    }
}
