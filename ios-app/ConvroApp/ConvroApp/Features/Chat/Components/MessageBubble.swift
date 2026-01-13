import SwiftUI

struct MessageBubble: View {
    let message: Message
    private let currentUserNumber = "+99 123 456" // TODO: Get from UserDefaults

    private var isSentByMe: Bool {
        message.fromConvroNumber == currentUserNumber
    }

    var body: some View {
        HStack {
            if isSentByMe { Spacer() }

            VStack(alignment: isSentByMe ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.decryptedContent ?? "[Encrypted]")
                    .padding(12)
                    .background(isSentByMe ? Color.sentMessageBackground : Color.receivedMessageBackground)
                    .foregroundColor(isSentByMe ? .white : .primary)
                    .cornerRadius(16)

                // Timestamp
                Text(message.createdAt.timeAgo())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if !isSentByMe { Spacer() }
        }
    }
}
