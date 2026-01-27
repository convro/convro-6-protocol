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
    private let messageStorage = MessageStorage.shared

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    private var typingTimer: Timer?
    private var pollingTimer: Timer?

    // MARK: - Initialization
    init(conversationId: UUID, participantConvroNumber: String, participantDisplayName: String?) {
        self.conversationId = conversationId
        self.participantConvroNumber = participantConvroNumber
        self.participantDisplayName = participantDisplayName

        setupWebSocketSubscriptions()
        setupPolling()
        Task {
            await loadMessages()
        }
    }

    deinit {
        pollingTimer?.invalidate()
        typingTimer?.invalidate()
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

    /// Setup polling for new messages (fallback if WebSocket fails)
    private func setupPolling() {
        // Poll every 3 seconds for new messages
        pollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                await self.pollNewMessages()
            }
        }
    }

    // MARK: - Load Messages

    /// Load messages from local cache and server
    func loadMessages() async {
        isLoading = true
        defer { isLoading = false }

        // Load from local cache first (instant UI)
        messages = await messageStorage.fetchMessages(
            forConversation: conversationId.uuidString,
            participantConvroNumber: participantConvroNumber
        )

        // Fetch new messages from server in background
        await pollNewMessages()
    }

    /// Poll inbox for new messages
    private func pollNewMessages() async {
        do {
            let inboxMessages = try await apiManager.fetchInbox()

            print("📬 Inbox polling: received \(inboxMessages.count) messages")

            // Process each inbox message
            for inboxMessage in inboxMessages {
                print("📩 Processing message: \(inboxMessage.messageId), type: \(inboxMessage.messageType)")
                // Check if we already have this message
                if messages.contains(where: { $0.id == inboxMessage.messageId }) {
                    continue
                }

                // Handle based on message type
                switch inboxMessage.messageType {
                case "handshake_offer":
                    await handleHandshakeOffer(inboxMessage)
                case "handshake_accept":
                    // Ignore - we're responder, not initiator
                    print("⚠️ Received handshake_accept as responder (ignoring)")
                case "sealed_sender":
                    // Normal encrypted message
                    if sessionId != nil {
                        await handleIncomingMessage(inboxMessage)
                    } else {
                        print("⚠️ Received sealed_sender but no session yet")
                    }
                default:
                    print("⚠️ Unknown message type: \(inboxMessage.messageType)")
                }
            }

        } catch {
            print("⚠️ Polling failed: \(error)")
            print("⚠️ Polling error details: \(error.localizedDescription)")
            if let decodingError = error as? DecodingError {
                print("❌ JSON Decoding Error: \(decodingError)")
            }
            // Don't show error - polling is background operation
        }
    }

    /// Handle incoming handshake offer (responder flow)
    private func handleHandshakeOffer(_ inboxMessage: InboxMessage) async {
        print("🤝 Received handshake offer from participant")

        do {
            // Step 1: Decode base64 envelope
            guard let offerData = Data(base64Encoded: inboxMessage.encryptedEnvelope) else {
                print("❌ Failed to decode handshake offer")
                return
            }
            let offerBytes = [UInt8](offerData)

            // Step 2: Accept handshake offer
            let handshakeCoordinator = HandshakeCoordinator()
            let newSessionId = try await handshakeCoordinator.respondToHandshakeOffer(offerBytes: offerBytes)

            // Step 3: Store session ID
            self.sessionId = newSessionId
            print("✅ Handshake accepted - session ID: \(newSessionId)")

            // Step 4: Mark handshake message as delivered
            try? await apiManager.markAsDelivered(messageId: inboxMessage.messageId)

            // Step 5: Reload messages now that we have session
            await loadMessages()

        } catch {
            print("❌ Failed to accept handshake: \(error)")
            errorMessage = "Failed to establish secure session: \(error.localizedDescription)"
        }
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
            localMessage.isFromMe = true

            messages.append(localMessage)

            // Step 4: Save to local database
            await messageStorage.saveMessage(localMessage)
            // Step 5: Update conversation list
            await updateConversation(withMessage: localMessage)

            print("✅ Message sent: \(response.messageId)")

        } catch {
            errorMessage = "Failed to send message: \(error.localizedDescription)"
            messageText = textToSend // Restore text on error
            print("❌ Send message failed: \(error)")
        }
    }

    // MARK: - Receive Messages

    /// Handle incoming message from WebSocket or polling
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
            message.isFromMe = false // Received message

            // Step 3: Add to UI (only if not already present)
            if !messages.contains(where: { $0.id == message.id }) {
                messages.append(message)
                messages.sort { $0.createdAt < $1.createdAt }
            }

            // Step 4: Save to local database
            await messageStorage.saveMessage(message)
            // Step 5: Update conversation list
            await updateConversation(withMessage: message)

            // Step 6: Mark as delivered on server
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
            // Ensure device identity is loaded (wait for it)
            print("⏳ Waiting for device identity to load...")
            var retries = 0
            while C6PManager.shared.loadDeviceIdentity() == nil && retries < 10 {
                try await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                retries += 1
            }

            guard C6PManager.shared.loadDeviceIdentity() != nil else {
                errorMessage = "Device identity not loaded. Please restart the app."
                print("❌ Device identity still nil after waiting")
                return nil
            }

            print("✅ Device identity loaded, proceeding with handshake")

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

    // MARK: - Conversation Sync

    /// Update conversation after sending/receiving message
    private func updateConversation(withMessage message: Message) async {
        let conversation = StoredConversation(
            id: conversationId.uuidString,
            participantConvroNumber: participantConvroNumber,
            participantDisplayName: participantDisplayName,
            lastMessageText: message.decryptedContent,
            lastActivityAt: message.createdAt,
            unreadCount: 0, // Reset unread for active conversation
            sessionId: sessionId
        )

        await messageStorage.saveConversation(conversation)
        print("💾 Conversation updated: \(conversationId)")
    }
}

// MARK: - Message Error
enum MessageError: LocalizedError {
    case invalidEnvelope
    case encryptionFailed
    case decryptionFailed
