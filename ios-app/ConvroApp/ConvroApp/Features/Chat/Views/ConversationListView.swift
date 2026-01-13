import SwiftUI

struct ConversationListView: View {
    @StateObject private var viewModel = ConversationListViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.conversations) { conversation in
                NavigationLink(destination: ChatView(conversation: conversation)) {
                    ConversationRow(conversation: conversation)
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { /* New message */ } label: {
                        Image(systemName: "square.and.pencil")
                    }
                }
            }
            .refreshable {
                await viewModel.loadConversations()
            }
        }
        .task {
            await viewModel.loadConversations()
        }
    }
}
