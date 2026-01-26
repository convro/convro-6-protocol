import SwiftUI

struct MessageBubble: View {
    let message: Message

    private var isSentByMe: Bool {
        message.isFromMe
    }

    var body: some View {
        HStack {
            if isSentByMe { Spacer(minLength: 60) }

            VStack(alignment: isSentByMe ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.decryptedContent ?? "[Encrypted]")
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(isSentByMe ? Color("ConvroBlue") : Color(.systemGray5))
                    .foregroundColor(isSentByMe ? .white : .primary)
                    .cornerRadius(18)
                    .textSelection(.enabled)

                // Timestamp + status
                HStack(spacing: 4) {
                    Text(message.createdAt.timeAgo())
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Delivery status for sent messages
                    if isSentByMe {
                        Image(systemName: deliveryStatusIcon)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !isSentByMe { Spacer(minLength: 60) }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var deliveryStatusIcon: String {
        switch message.deliveryStatus {
        case .pending:
            return "clock.fill"
        case .delivered:
            return "checkmark"
        case .failed:
            return "exclamationmark.triangle.fill"
        case .read:
            return "checkmark.circle.fill"
        }
    }
}
