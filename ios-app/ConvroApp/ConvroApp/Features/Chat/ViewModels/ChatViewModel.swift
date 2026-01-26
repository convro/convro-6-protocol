import SwiftUI
import Combine

// MARK: - Chat ViewModel
/// Complete messaging logic: encryption, WebSocket, caching, typing indicators
@MainActor
class ChatViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var messages: [Message] = []
    @Published var messageText: String = ""
    @Published var isLoading: Bool = false
    @Published var isSending: Bool = false
    @Published var errorMessage: String?
    @Published var isTyping: Bool = false
    @Published var participantTyping: Bool = false

    // MARK: - Properties
    let conversationId: UUID
    let participantConvroNumber: String
    let participantDisplayName: String?
    private var sessionId: String?

    // MARK: - Dependencies
    private let apiManager = APIManager.shared
    private let messageEncryption = MessageEncryptionService.shared
    private let webSocketManager = WebSocketManager.shared
    private let messageDatabase = MessageDatabase.shared

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?

    // MARK: - Initialization
    init(conversationId: UUID, participantConvroNumber: String, participantDisplayName: String?) {
        self.conversationId = conversationId
        self.participantConvroNumber = participantConvroNumber
        self.participantDisplayName = participantDisplayName

        setupWebSocketSubscriptions()
        Task {
            await loadMessages()
        }
    }

    // MARK: - Setup

    /// Subscribe to WebSocket for real-time updates
    private func setupWebSocketSubscriptions() {
        // Subscribe to incoming messages
        webSocketManager.incomingMessages
            .sink { [weak self] inboxMessage in
                Task { @MainActor in
                    await self?.handleIncomingMessage(inboxMessage)
                }
            }
            .store(in: &cancellables)

        // Subscribe to typing indicators
        webSocketManager.typingIndicators
            .filter { [weak self] indicator in
                indicator.conversationId == self?.conversationId
            }
            .sink { [weak self] indicator in
                self?.participantTyping = indicator.isTyping
            }
            .store(in: &cancellables)

        // Subscribe to this conversation
        webSocketManager.subscribeToConversation(conversationId: conversationId)
    }

    // MARK: - Load Messages

    /// Load messages from local cache and server
    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        // Load from local cache first (Core Data persistent storage)
        messages = await messageDatabase.fetchMessages(forConversation: conversationId.uuidString)
        
        // Note: Server-side pagination will be implemented when message history API is added.
        // Current architecture uses local Core Data as source of truth for message history.
        // New messages arrive via WebSocket real-time updates and /messages/inbox polling.
    }

    // MARK: - Send Message

    /// Send encrypted message with 64KB sealed sender padding
    func sendMessage() async {
        guard !messageText.trim.isEmpty else { return }

        // Get session ID for this conversation (or create new session via handshake)
        guard let sessionId = await getOrCreateSession() else {
            errorMessage = "Failed to establish secure session"
            return
        }

        let textToSend = messageText
        messageText = "" // Clear immediately for UX
        isSending = true
        defer { isSending = false }

        do {
            // Step 1: Encrypt message with 64KB padding (sealed sender)
            let encryptedEnvelope = try messageEncryption.encryptMessage(textToSend, sessionId: sessionId)

            // Step 2: Send to server
            let response = try await apiManager.sendMessage(
                toConvroNumber: participantConvroNumber,
                encryptedEnvelope: encryptedEnvelope
            )

            // Step 3: Create local message and add to UI
            var localMessage = Message(
                id: response.messageId,
                sessionId: Data(sessionId.utf8),
                fromConvroNumber: nil, // Sealed sender hides sender
                toConvroNumber: participantConvroNumber,
                messageType: .sealedSender,
                encryptedBlob: nil,
                encryptedEnvelope: encryptedEnvelope,
                createdAt: response.createdAt,
                deliveredAt: nil,
                deliveryStatus: .pending
            )
            localMessage.decryptedContent = textToSend // We know plaintext for sent messages

            messages.append(localMessage)

            // Step 4: Save to local database
            await messageDatabase.saveMessage(localMessage)

            print("✅ Message sent: \(response.messageId)")

        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            messageText = textToSend // Restore text on error
            print("❌ Send message failed: \(error)")
        }
    }

    // MARK: - Receive Messages

    /// Handle incoming message from WebSocket
    private func handleIncomingMessage(_ inboxMessage: InboxMessage) async {
        guard let sessionId = sessionId else {
            print("⚠️ No session ID, cannot decrypt message")
            return
        }

        do {
            // Step 1: Decrypt message (64KB sealed sender)
            guard let envelopeData = inboxMessage.encryptedEnvelope.data(using: .utf8) else {
                throw MessageError.invalidEnvelope
            }

            let plaintext = try messageEncryption.decryptMessage(envelopeData, sessionId: sessionId)

            // Step 2: Create message object
            var message = Message(
                id: inboxMessage.messageId,
                sessionId: Data(sessionId.utf8),
                fromConvroNumber: participantConvroNumber,
                toConvroNumber: "", // Unknown for received sealed sender messages
                messageType: .sealedSender,
                encryptedBlob: nil,
                encryptedEnvelope: Data(inboxMessage.encryptedEnvelope.utf8),
                createdAt: inboxMessage.createdAt,
                deliveredAt: Date(),
                deliveryStatus: .delivered
            )
            message.decryptedContent = plaintext

            // Step 3: Add to UI
            messages.append(message)

            // Step 4: Save to local database
            await messageDatabase.saveMessage(message)

            // Step 5: Mark as delivered on server
            try? await apiManager.markAsDelivered(messageId: inboxMessage.messageId)

            print("✅ Message received: \(inboxMessage.messageId)")

        } catch {
            print("❌ Failed to decrypt message: \(error)")
        }
    }

    // MARK: - Session Management

    /// Get existing session or initiate new handshake
    private func getOrCreateSession() async -> String? {
        // Check if session exists
        if let sessionId = sessionId {
            return sessionId
        }

        // Initiate handshake with participant
        do {
            // Ensure device identity is loaded
            guard DeviceIdentityManager.shared.deviceIdentity != nil else {
                errorMessage = "Device identity not loaded. Please restart the app."
                return nil
            }

            // Create Contact object for handshake
            let contact = Contact(
                id: UUID(),
                convroNumber: participantConvroNumber,
                displayName: participantDisplayName ?? "Unknown",
                userId: UUID(), // Placeholder
                isVerified: false,
                addedAt: Date(),
                verifiedAt: nil,
                identityPubEd25519: nil // Fetched with prekey bundle
            )

            // Initiate handshake via coordinator
            let handshakeCoordinator = HandshakeCoordinator()
            let newSessionId = try await handshakeCoordinator.initiateHandshake(withContact: contact)

            // Store session ID
            self.sessionId = newSessionId

            print("✅ Handshake initiated - session ID: \(newSessionId)")
            print("⏳ Waiting for accept from \(participantConvroNumber)...")

            return newSessionId

        } catch {
            print("❌ Failed to initiate handshake: \(error)")
            errorMessage = "Failed to establish secure session: \(error.localizedDescription)"
            return nil
        }
    }

    /// Set session ID (called after successful handshake)
    func setSession(sessionId: String) {
        self.sessionId = sessionId
    }

    // MARK: - Typing Indicators

    /// Send typing indicator to participant
    func setTyping(_ typing: Bool) {
        isTyping = typing

        // Send to WebSocket
        webSocketManager.sendTypingIndicator(conversationId: conversationId, isTyping: typing)

        // Auto-stop typing after 3 seconds of no input
        typingTimer?.invalidate()
        if typing {
            typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
                self?.setTyping(false)
            }
        }
    }

    /// Called when text field changes
    func onTextChanged() {
        if !messageText.isEmpty && !isTyping {
            setTyping(true)
        } else if messageText.isEmpty && isTyping {
            setTyping(false)
        }
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }
}

// MARK: - Message Error
enum MessageError: LocalizedError {
    case invalidEnvelope
    case encryptionFailed
    case decryptionFailed
    case sessionNotFound

    var errorDescription: String? {
        switch self {
        case .invalidEnvelope:
            return "Invalid message envelope"
        case .encryptionFailed:
            return "Failed to encrypt message"
        case .decryptionFailed:
            return "Failed to decrypt message"
        case .sessionNotFound:
            return "No secure session found"
        }
    }
}

// MARK: - String Extension
private extension String {
    var trim: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
