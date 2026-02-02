import SwiftUI

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Image(systemName: "person.circle.fill")
                .resizable()
                .frame(width: 50, height: 50)
                .foregroundColor(.gray)

            VStack(alignment: .leading, spacing: 4) {
                // Name + Time
                HStack {
                    Text(conversation.participant.displayName)
                        .fontWeight(.semibold)
                    Spacer()
                    if let lastMessage = conversation.lastMessage {
                        Text(lastMessage.timestamp.timeAgo())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Last message preview
                if let lastMessage = conversation.lastMessage {
                    Text(lastMessage.text)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                // Unread badge
                if conversation.unreadCount > 0 {
                    Text("\(conversation.unreadCount)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color("ConvroBlue"))
                        .cornerRadius(12)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
