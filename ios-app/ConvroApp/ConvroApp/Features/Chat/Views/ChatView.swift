import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var isInputFocused: Bool

    init(conversation: Conversation) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(conversation: conversation))
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
                    .textFieldStyle(.roundedBorder)
                    .focused($isInputFocused)

                Button {
                    Task {
                        await viewModel.sendMessage()
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .resizable()
                        .frame(width: 32, height: 32)
                        .foregroundColor(Color("ConvroBlue"))
                }
                .disabled(viewModel.messageText.isEmpty)
            }
            .padding()
            .background(Color.inputBackground)
        }
        .navigationTitle(viewModel.conversation.participant.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.loadMessages()
        }
    }
}
