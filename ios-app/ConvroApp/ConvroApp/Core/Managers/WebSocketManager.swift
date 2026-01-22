import Foundation
import Combine

// MARK: - WebSocket Manager
/// Real-time messaging via WebSocket (presence, new messages, typing indicators)
@MainActor
class WebSocketManager: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = WebSocketManager()

    // MARK: - Properties
    @Published var connectionState: ConnectionState = .disconnected
    @Published var incomingMessages = PassthroughSubject<InboxMessage, Never>()
    @Published var typingIndicators = PassthroughSubject<TypingIndicator, Never>()
    @Published var presenceUpdates = PassthroughSubject<PresenceUpdate, Never>()

    private var client: WebSocketClient?
    private let url = URL(string: "wss://app.convro.eu/v1/stream")!

    private override init() {
        super.init()
    }

    // MARK: - Connection Management

    /// Connect to WebSocket with JWT token
    func connect(accessToken: String) {
        guard connectionState != .connected && connectionState != .connecting else {
            return
        }

        connectionState = .connecting

        client = WebSocketClient(url: url, authToken: accessToken)

        client?.onConnect = { [weak self] in
            Task { @MainActor in
                self?.connectionState = .connected
                print("✅ WebSocket Manager: Connected")
            }
        }

        client?.onDisconnect = { [weak self] error in
            Task { @MainActor in
                if let error = error {
                    self?.connectionState = .error(error.localizedDescription)
                } else {
                    self?.connectionState = .disconnected
                }
                print("⚠️ WebSocket Manager: Disconnected")
            }
        }

        client?.onMessage = { [weak self] data in
            Task { @MainActor in
                self?.handleIncomingData(data)
            }
        }

        client?.onError = { [weak self] error in
            Task { @MainActor in
                self?.connectionState = .error(error.localizedDescription)
                print("❌ WebSocket Manager: Error - \(error)")
            }
        }

        client?.connect()
    }

    /// Disconnect from WebSocket
    func disconnect() {
        client?.disconnect()
        client = nil
        connectionState = .disconnected
    }

    /// Reconnect after disconnect
    func reconnect(accessToken: String) {
        disconnect()
        connectionState = .reconnecting

        // Wait 2 seconds before reconnecting
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await connect(accessToken: accessToken)
        }
    }

    // MARK: - Message Handling

    /// Handle incoming WebSocket data
    private func handleIncomingData(_ data: Data) {
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            let message = try decoder.decode(WebSocketMessage.self, from: data)

            switch message.type {
            case "new_message":
                if let payload = message.payload {
                    let inboxMsg = try decoder.decode(InboxMessage.self, from: payload)
                    incomingMessages.send(inboxMsg)
                    print("📨 New message received: \(inboxMsg.messageId)")
                }

            case "typing":
                if let payload = message.payload {
                    let typing = try decoder.decode(TypingIndicator.self, from: payload)
                    typingIndicators.send(typing)
                }

            case "presence":
                if let payload = message.payload {
                    let presence = try decoder.decode(PresenceUpdate.self, from: payload)
                    presenceUpdates.send(presence)
                    print("👤 Presence update: \(presence.convroNumber) is \(presence.status)")
                }

            case "pong":
                // Heartbeat response
                break

            case "hello":
                // Server greeting - connection established
                print("👋 WebSocket hello received")

            case "authenticated":
                // Authentication successful
                print("✅ WebSocket authenticated")

            case "error":
                // Server error
                if let payload = message.payload,
                   let errorDict = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                   let errorMessage = errorDict["message"] as? String {
                    print("❌ WebSocket error: \(errorMessage)")
                }

            case "goodbye":
                // Server disconnect
                print("👋 WebSocket goodbye received")

            default:
                print("⚠️ Unknown WebSocket message type: \(message.type)")
            }

        } catch {
            print("❌ Failed to decode WebSocket message: \(error)")
        }
    }

    /// Send WebSocket message
    func sendMessage(_ message: WebSocketMessage) {
        do {
            try client?.sendJSON(message)
        } catch {
            print("❌ Failed to send WebSocket message: \(error)")
        }
    }

    /// Send typing indicator
    func sendTypingIndicator(conversationId: UUID, isTyping: Bool) {
        let message = WebSocketMessage(
            type: "typing",
            payload: try? JSONEncoder().encode(TypingIndicatorPayload(
                conversationId: conversationId,
                isTyping: isTyping
            ))
        )
        sendMessage(message)
    }

    /// Subscribe to conversation updates
    func subscribeToConversation(conversationId: UUID) {
        let message = WebSocketMessage(
            type: "subscribe",
            payload: try? JSONEncoder().encode(["conversation_id": conversationId.uuidString])
        )
        sendMessage(message)
    }
}

// MARK: - Connection State
enum ConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case reconnecting
    case error(String)

    static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.connected, .connected),
             (.reconnecting, .reconnecting):
            return true
        case (.error, .error):
            return true
        default:
            return false
        }
    }
}

// MARK: - WebSocket Message
struct WebSocketMessage: Codable {
    let type: String
    let payload: Data?

    init(type: String, payload: Data? = nil) {
        self.type = type
        self.payload = payload
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: Codable {
    let conversationId: UUID
    let participantConvroNumber: String
    let isTyping: Bool
}

private struct TypingIndicatorPayload: Codable {
    let conversationId: UUID
    let isTyping: Bool
}

// MARK: - Presence Update
struct PresenceUpdate: Codable {
    let convroNumber: String
    let status: String
    let timestamp: Date
}
