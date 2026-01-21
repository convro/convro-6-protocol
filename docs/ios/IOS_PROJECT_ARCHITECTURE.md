# iOS Project Architecture - Convro App

**Version:** 1.0
**Target:** iOS 15.0+
**Language:** Swift 5.9+
**UI Framework:** SwiftUI
**Architecture:** MVVM + Coordinator Pattern

---

## 1. Xcode Project Structure

```
ConvroApp/
├── ConvroApp.xcodeproj
├── ConvroApp/
│   ├── App/
│   │   ├── ConvroApp.swift              # App entry point (@main)
│   │   ├── AppDelegate.swift            # App lifecycle, push notifications
│   │   └── SceneDelegate.swift          # Scene lifecycle (if needed)
│   │
│   ├── Core/                             # ⭐ KLUCZOWE - Fundament aplikacji
│   │   ├── Managers/
│   │   │   ├── C6PManager.swift         # 🔥 Session management (główny manager C6P)
│   │   │   ├── KeychainManager.swift    # 🔥 Secure storage (identity, keys, sessions)
│   │   │   ├── DeviceIdentityManager.swift  # 🔥 Device identity lifecycle
│   │   │   ├── APIManager.swift         # 🔥 REST API client (auth, prekeys, contacts)
│   │   │   ├── WebSocketManager.swift   # 🔥 Realtime messaging (WebSocket)
│   │   │   ├── HandshakeCoordinator.swift   # 🔥 Handshake flow orchestration
│   │   │   ├── MessageEncryptionService.swift  # 🔥 Encrypt/decrypt wrapper
│   │   │   ├── ContactsManager.swift    # Contact list management
│   │   │   └── PushNotificationManager.swift  # APNs registration & handling
│   │   │
│   │   ├── Models/
│   │   │   ├── User.swift               # User model (convro_number, username, etc.)
│   │   │   ├── Contact.swift            # Contact model
│   │   │   ├── Message.swift            # Message model (encrypted + decrypted)
│   │   │   ├── Session.swift            # Session model (session_id, participants)
│   │   │   ├── DeviceIdentity.swift     # Device identity model
│   │   │   └── ConvroNumber.swift       # Convro Number (+99 XXX XXX)
│   │   │
│   │   ├── Networking/
│   │   │   ├── APIClient.swift          # Base HTTP client (URLSession wrapper)
│   │   │   ├── APIEndpoint.swift        # Endpoint definitions
│   │   │   ├── APIRequest.swift         # Request builder
│   │   │   ├── APIResponse.swift        # Response models
│   │   │   └── WebSocketClient.swift    # WebSocket client (Starscream)
│   │   │
│   │   ├── Persistence/
│   │   │   ├── CoreDataStack.swift      # Core Data setup (optional for local DB)
│   │   │   ├── MessageDatabase.swift    # Local message cache
│   │   │   └── SessionDatabase.swift    # Local session cache
│   │   │
│   │   ├── Security/
│   │   │   ├── KeychainWrapper.swift    # Low-level Keychain operations
│   │   │   ├── BiometricAuth.swift      # Face ID / Touch ID
│   │   │   └── SecureStorage.swift      # Additional secure storage utils
│   │   │
│   │   └── Extensions/
│   │       ├── Data+Hex.swift           # Data ↔ Hex conversions
│   │       ├── String+Validation.swift  # Input validation
│   │       └── View+Extensions.swift    # SwiftUI helpers
│   │
│   ├── Features/                         # Feature modules (MVVM per feature)
│   │   │
│   │   ├── Authentication/              # 🔐 Login / Register / Logout
│   │   │   ├── ViewModels/
│   │   │   │   ├── LoginViewModel.swift
│   │   │   │   └── RegisterViewModel.swift
│   │   │   ├── Views/
│   │   │   │   ├── LoginView.swift
│   │   │   │   ├── RegisterView.swift
│   │   │   │   └── ConvroNumberDisplayView.swift  # Show assigned number
│   │   │   └── Coordinators/
│   │   │       └── AuthCoordinator.swift
│   │   │
│   │   ├── Onboarding/                  # First-time setup
│   │   │   ├── ViewModels/
│   │   │   │   └── OnboardingViewModel.swift
│   │   │   └── Views/
│   │   │       ├── WelcomeView.swift
│   │   │       ├── PermissionsView.swift  # Notifications, biometrics
│   │   │       └── DeviceSetupView.swift  # Generate device identity
│   │   │
│   │   ├── Contacts/                    # 👥 Contact list & management
│   │   │   ├── ViewModels/
│   │   │   │   ├── ContactsListViewModel.swift
│   │   │   │   └── AddContactViewModel.swift
│   │   │   ├── Views/
│   │   │   │   ├── ContactsListView.swift
│   │   │   │   ├── AddContactView.swift  # Enter Convro Number
│   │   │   │   └── ContactDetailView.swift  # Fingerprint verification
│   │   │   └── Components/
│   │   │       ├── ContactRow.swift
│   │   │       └── FingerprintView.swift  # Display identity fingerprint
│   │   │
│   │   ├── Chat/                        # 💬 Main messaging feature
│   │   │   ├── ViewModels/
│   │   │   │   ├── ConversationListViewModel.swift
│   │   │   │   └── ChatViewModel.swift
│   │   │   ├── Views/
│   │   │   │   ├── ConversationListView.swift
│   │   │   │   ├── ChatView.swift
│   │   │   │   └── HandshakeProgressView.swift  # Show handshake steps
│   │   │   └── Components/
│   │   │       ├── MessageBubble.swift
│   │   │       ├── MessageInputBar.swift
│   │   │       ├── TypingIndicator.swift
│   │   │       └── EncryptionBadge.swift  # "E2EE Active" indicator
│   │   │
│   │   ├── Settings/                    # ⚙️ App settings
│   │   │   ├── ViewModels/
│   │   │   │   └── SettingsViewModel.swift
│   │   │   ├── Views/
│   │   │   │   ├── SettingsView.swift
│   │   │   │   ├── AccountView.swift     # Account info, Convro Number
│   │   │   │   ├── DevicesView.swift     # Multi-device management
│   │   │   │   ├── SecurityView.swift    # Biometrics, auto-lock
│   │   │   │   └── AboutView.swift
│   │   │   └── Components/
│   │   │       └── SettingsRow.swift
│   │   │
│   │   └── Profile/                     # User profile
│   │       ├── ViewModels/
│   │       │   └── ProfileViewModel.swift
│   │       └── Views/
│   │           └── ProfileView.swift
│   │
│   ├── UI/                              # 🎨 Reusable UI Components
│   │   ├── Components/
│   │   │   ├── TabBarRoot.swift         # 🔥 Main tab bar controller
│   │   │   ├── NavigationRoot.swift     # Custom navigation wrapper
│   │   │   ├── PrimaryButton.swift      # Branded button style
│   │   │   ├── SecondaryButton.swift
│   │   │   ├── TextFieldStyle.swift     # Custom text field
│   │   │   ├── LoadingView.swift        # Loading spinner
│   │   │   ├── ErrorView.swift          # Error display
│   │   │   └── EmptyStateView.swift     # Empty states
│   │   │
│   │   ├── Theme/
│   │   │   ├── Colors.swift             # Brand colors
│   │   │   ├── Typography.swift         # Font styles
│   │   │   ├── Spacing.swift            # Layout constants
│   │   │   └── AppTheme.swift           # Theme manager (light/dark)
│   │   │
│   │   └── Modifiers/
│   │       ├── CardModifier.swift       # Card-style container
│   │       └── ShimmerModifier.swift    # Loading shimmer effect
│   │
│   ├── Utilities/
│   │   ├── Logger.swift                 # Logging utility (OSLog wrapper)
│   │   ├── Validator.swift              # Input validation rules
│   │   ├── DateFormatter+Extensions.swift
│   │   └── HapticFeedback.swift         # Haptic feedback wrapper
│   │
│   ├── Resources/
│   │   ├── Assets.xcassets/
│   │   │   ├── AppIcon.appiconset/
│   │   │   ├── Colors/                  # Color assets
│   │   │   └── Images/                  # Image assets
│   │   ├── Localizable.strings          # Localization (EN, PL, etc.)
│   │   └── Info.plist
│   │
│   └── Supporting Files/
│       └── ConvroApp-Bridging-Header.h  # If needed for Obj-C interop
│
├── ConvroAppTests/
│   ├── Core/
│   │   ├── C6PManagerTests.swift
│   │   ├── KeychainManagerTests.swift
│   │   └── HandshakeCoordinatorTests.swift
│   ├── Features/
│   │   └── ChatViewModelTests.swift
│   └── Mocks/
│       ├── MockAPIManager.swift
│       └── MockC6PManager.swift
│
├── ConvroAppUITests/
│   └── E2EHandshakeTests.swift          # UI test for full handshake flow
│
└── Frameworks/
    └── C6PProtocol.xcframework           # C6P FFI framework (from SPM)
```

---

## 2. Core Architecture - KLUCZOWE KOMPONENTY

### 2.1 C6PManager (Actor) 🔥

**Odpowiedzialność:** Główny manager dla wszystkich operacji C6P

**Kluczowe metody:**
```swift
@available(iOS 13.0, *)
actor C6PManager {
    // Device Identity
    func generateDeviceIdentity() async throws -> DeviceIdentity
    func getDeviceIdentity() async throws -> DeviceIdentity

    // Prekeys
    func generateAndUploadPrekeys(count: Int) async throws
    func rotateSignedPrekey() async throws

    // Handshake
    func initiateHandshake(with convroNumber: String) async throws -> Session
    func acceptHandshake(offer: Data) async throws -> Session
    func getSession(sessionId: Data) async throws -> Session?

    // Messaging
    func encrypt(plaintext: String, sessionId: Data) async throws -> Data
    func decrypt(ciphertext: Data, sessionId: Data) async throws -> String

    // Session Management
    func listActiveSessions() async -> [Session]
    func closeSession(sessionId: Data) async throws
}
```

**Integracja:**
- Wywołuje funkcje FFI z `C6PProtocol.xcframework`
- Współpracuje z `KeychainManager` (secure storage)
- Współpracuje z `APIManager` (fetch prekey bundles)
- Thread-safe dzięki `actor`

---

### 2.2 KeychainManager 🔥

**Odpowiedzialność:** Bezpieczne przechowywanie kluczy i sesji

**Kluczowe metody:**
```swift
enum KeychainManager {
    // Device Identity
    static func storeDeviceIdentity(_ identity: DeviceIdentity) throws
    static func retrieveDeviceIdentity() throws -> DeviceIdentity?

    // Session Keys
    static func storeSessionKeys(_ keys: SessionKeys, sessionId: Data) throws
    static func retrieveSessionKeys(sessionId: Data) throws -> SessionKeys?
    static func deleteSessionKeys(sessionId: Data) throws

    // Prekeys
    static func storeSignedPrekey(_ spk: SignedPrekey) throws
    static func storeOneTimePrekeys(_ otps: [OneTimePrekey]) throws

    // Security
    static func requireBiometricAuth() -> Bool
    static func lockKeychain() throws
}
```

**Security Attributes:**
```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecAttrSynchronizable as String: false,  // NEVER sync to iCloud!
    kSecUseDataProtectionKeychain as String: true
]
```

---

### 2.3 HandshakeCoordinator 🔥

**Odpowiedzialność:** Orkiestracja pełnego procesu handshake

**Flow dla initiatora:**
```swift
class HandshakeCoordinator {
    func initiateHandshake(with contact: Contact) async throws -> Session {
        // 1. Fetch prekey bundle from server
        let bundle = try await apiManager.fetchPrekeyBundle(
            convroNumber: contact.convroNumber
        )

        // 2. Verify SPK signature
        guard verifySignature(bundle) else {
            throw HandshakeError.invalidSignature
        }

        // 3. Create offer (C6P FFI call)
        let identity = try await c6pManager.getDeviceIdentity()
        let offerResult = try handshake_create_offer(
            initiator_identity: identity,
            responder_bundle: bundle
        )

        // 4. Store session keys in Keychain
        try KeychainManager.storeSessionKeys(
            offerResult.session_keys,
            sessionId: offerResult.offer.session_id
        )

        // 5. Send offer to server
        try await apiManager.sendHandshakeOffer(
            offer: offerResult.offer,
            to: contact.convroNumber
        )

        // 6. Wait for accept (via WebSocket or polling)
        let accept = try await waitForAccept(sessionId: offerResult.offer.session_id)

        // 7. Verify KC2
        let verified = try handshake_verify_accept(
            accept: accept,
            expected_kc2: offerResult.kc2
        )

        guard verified else {
            throw HandshakeError.keyConfirmationFailed
        }

        // 8. Session ACTIVE!
        return Session(
            sessionId: offerResult.offer.session_id,
            contact: contact,
            status: .active
        )
    }
}
```

**Flow dla respondera:** (podobny, ale `handshake_accept_offer`)

---

### 2.4 APIManager 🔥

**Odpowiedzialność:** Komunikacja z serwerem (REST API)

**Kluczowe endpointy:**
```swift
class APIManager {
    // Authentication
    func register(username: String, password: String) async throws -> User
    func login(username: String, password: String) async throws -> AuthToken

    // Prekeys
    func uploadPrekeys(
        deviceIdentity: DeviceIdentity,
        signedPrekey: SignedPrekey,
        oneTimePrekeys: [OneTimePrekey]
    ) async throws

    func fetchPrekeyBundle(convroNumber: String) async throws -> PrekeyBundle

    // Handshake
    func sendHandshakeOffer(offer: HandshakeOffer, to: String) async throws
    func sendHandshakeAccept(accept: HandshakeAccept, to: String) async throws

    // Messages
    func sendEncryptedMessage(message: EncryptedMessage) async throws
    func fetchInbox() async throws -> [EncryptedMessage]

    // Contacts
    func searchUser(convroNumber: String) async throws -> User?
}
```

**Base URL:** `https://api.convro.app/v1`

---

### 2.5 WebSocketManager 🔥

**Odpowiedzialność:** Realtime messaging (WebSocket connection)

**Kluczowe funkcje:**
```swift
@MainActor
class WebSocketManager: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var incomingMessages: [EncryptedMessage] = []

    func connect(authToken: String) async throws
    func disconnect()
    func send(message: EncryptedMessage) async throws

    // Lifecycle
    func handleAppDidEnterBackground()
    func handleAppWillEnterForeground()

    // Heartbeat (keep-alive)
    private func startHeartbeat()
}
```

**WebSocket Protocol:**
```json
// Client → Server
{
  "type": "authenticate",
  "token": "jwt_token_here"
}

// Server → Client (new message)
{
  "type": "message",
  "message_id": "uuid",
  "from": "+99123456",
  "to": "+99654321",
  "encrypted_blob": "base64_encrypted_data",
  "created_at": "2026-01-12T10:30:00Z"
}

// Client → Server (ack)
{
  "type": "ack",
  "message_id": "uuid"
}
```

---

### 2.6 MessageEncryptionService 🔥

**Odpowiedzialność:** High-level wrapper dla encrypt/decrypt

```swift
class MessageEncryptionService {
    func send(
        plaintext: String,
        to contact: Contact,
        session: Session
    ) async throws -> Message {
        // 1. Encrypt with C6P
        let encryptedBlob = try await c6pManager.encrypt(
            plaintext: plaintext,
            sessionId: session.sessionId
        )

        // 2. Create message envelope
        let message = EncryptedMessage(
            messageId: UUID(),
            from: currentUser.convroNumber,
            to: contact.convroNumber,
            sessionId: session.sessionId,
            encryptedBlob: encryptedBlob,
            createdAt: Date()
        )

        // 3. Send via WebSocket (if online) or API (if offline)
        if webSocketManager.isConnected {
            try await webSocketManager.send(message: message)
        } else {
            try await apiManager.sendEncryptedMessage(message)
        }

        // 4. Save to local DB
        try await messageDatabase.insert(message)

        return message
    }

    func receive(encryptedMessage: EncryptedMessage) async throws -> Message {
        // 1. Decrypt with C6P
        let plaintext = try await c6pManager.decrypt(
            ciphertext: encryptedMessage.encryptedBlob,
            sessionId: encryptedMessage.sessionId
        )

        // 2. Create decrypted message
        let message = Message(
            id: encryptedMessage.messageId,
            content: plaintext,
            from: encryptedMessage.from,
            to: encryptedMessage.to,
            timestamp: encryptedMessage.createdAt,
            isEncrypted: true
        )

        // 3. Save to local DB
        try await messageDatabase.insert(message)

        // 4. Send ACK to server
        try await apiManager.markAsDelivered(messageId: message.id)

        return message
    }
}
```

---

### 2.7 DeviceIdentityManager 🔥

**Odpowiedzialność:** Zarządzanie device identity lifecycle

```swift
class DeviceIdentityManager {
    func setupDeviceIdentity() async throws {
        // Check if identity exists
        if let existing = try? KeychainManager.retrieveDeviceIdentity() {
            print("Device identity already exists: \(existing.deviceId.hex)")
            return
        }

        // Generate new identity
        let identity = try identity_generate_identity()

        // Store in Keychain
        try KeychainManager.storeDeviceIdentity(identity)

        // Register with server
        try await apiManager.registerDevice(identity: identity)

        // Generate and upload initial prekeys
        let spk = try identity_generate_signed_prekey(
            identity: identity,
            spk_id: 1
        )
        let otps = try (0..<25).map { id in
            try identity_generate_one_time_prekey(otp_id: UInt32(id))
        }

        try KeychainManager.storeSignedPrekey(spk)
        try KeychainManager.storeOneTimePrekeys(otps)

        try await apiManager.uploadPrekeys(
            deviceIdentity: identity,
            signedPrekey: spk,
            oneTimePrekeys: otps
        )
    }

    func rotatePrekeys() async throws {
        // Called weekly by background task
        let identity = try KeychainManager.retrieveDeviceIdentity()!

        // Generate new SPK
        let newSpkId = try await apiManager.getNextSpkId()
        let newSpk = try identity_generate_signed_prekey(
            identity: identity,
            spk_id: newSpkId
        )

        // Upload with migration window
        try await apiManager.uploadSignedPrekey(newSpk, migrateFrom: oldSpkId)
    }
}
```

---

## 3. Data Flow - Jak wszystko działa razem

### 3.1 User Registration Flow

```
User enters username/password
         ↓
RegisterViewModel.register()
         ↓
APIManager.register() → Server
         ↓
Server returns: User(id, convro_number)
         ↓
DeviceIdentityManager.setupDeviceIdentity()
         ↓
C6PManager.generateDeviceIdentity()
         ↓
KeychainManager.storeDeviceIdentity()
         ↓
APIManager.registerDevice()
         ↓
DeviceIdentityManager.generateInitialPrekeys()
         ↓
APIManager.uploadPrekeys()
         ↓
✅ User registered with Convro Number +99 XXX XXX
```

---

### 3.2 Handshake Flow (Alice initiates to Bob)

```
Alice taps "Start Chat" with Bob
         ↓
ChatViewModel.startConversation(contact: Bob)
         ↓
HandshakeCoordinator.initiateHandshake(with: Bob)
         ↓
APIManager.fetchPrekeyBundle(convroNumber: Bob.convroNumber)
         ↓
Server returns: PrekeyBundle(IK_pub, SPK, SPK_sig, OTP)
         ↓
C6PManager: handshake_create_offer(Alice.identity, Bob.bundle)
         ↓
KeychainManager.storeSessionKeys(session_keys, session_id)
         ↓
APIManager.sendHandshakeOffer(offer, to: Bob)
         ↓
Server relays offer → Bob (via WebSocket or push)
         ↓
Bob's app: HandshakeCoordinator.handleIncomingOffer(offer)
         ↓
C6PManager: handshake_accept_offer(Bob.identity, offer)
         ↓
KeychainManager.storeSessionKeys(session_keys, session_id)
         ↓
APIManager.sendHandshakeAccept(accept, to: Alice)
         ↓
Server relays accept → Alice
         ↓
Alice's app: HandshakeCoordinator.handleIncomingAccept(accept)
         ↓
C6PManager: handshake_verify_accept(accept, expected_kc2)
         ↓
✅ Session ACTIVE on both sides!
         ↓
ChatView displays "End-to-End Encrypted" badge
```

---

### 3.3 Sending Encrypted Message

```
User types message in ChatView
         ↓
ChatViewModel.sendMessage(text)
         ↓
MessageEncryptionService.send(plaintext, to: contact, session: session)
         ↓
C6PManager.encrypt(plaintext, sessionId)
         ↓
FFI: session_state.encrypt(plaintext) → EncryptedMessage
         ↓
WebSocketManager.send(encryptedMessage) OR APIManager.sendEncryptedMessage()
         ↓
Server relays to recipient
         ↓
Recipient's app: WebSocketManager receives message
         ↓
MessageEncryptionService.receive(encryptedMessage)
         ↓
C6PManager.decrypt(ciphertext, sessionId)
         ↓
FFI: session_state.decrypt(ciphertext) → plaintext
         ↓
MessageDatabase.insert(message)
         ↓
ChatViewModel updates @Published messages array
         ↓
✅ Message appears in ChatView with green "✓" checkmark
```

---

## 4. UI Components - Reusable Components

### 4.1 TabBarRoot.swift 🔥

**Główny tab bar aplikacji:**

```swift
struct TabBarRoot: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var contactsViewModel = ContactsViewModel()
    @StateObject private var settingsViewModel = SettingsViewModel()

    var body: some View {
        TabView {
            ConversationListView()
                .environmentObject(chatViewModel)
                .tabItem {
                    Label("Chats", systemImage: "message.fill")
                }

            ContactsListView()
                .environmentObject(contactsViewModel)
                .tabItem {
                    Label("Contacts", systemImage: "person.2.fill")
                }

            SettingsView()
                .environmentObject(settingsViewModel)
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .accentColor(.convroBlue)
    }
}
```

---

### 4.2 NavigationRoot.swift

**Custom navigation wrapper z branded style:**

```swift
struct NavigationRoot<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        NavigationView {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        HStack {
                            Image("ConvroLogo")
                                .resizable()
                                .frame(width: 24, height: 24)
                            Text(title)
                                .font(.headline)
                        }
                    }
                }
        }
        .navigationViewStyle(.stack)
    }
}
```

---

### 4.3 PrimaryButton.swift

**Branded button component:**

```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false

    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                } else {
                    Text(title)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(isDisabled ? Color.gray : Color.convroBlue)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isDisabled || isLoading)
    }
}
```

---

### 4.4 MessageBubble.swift

**Chat message bubble:**

```swift
struct MessageBubble: View {
    let message: Message
    let isFromCurrentUser: Bool

    var body: some View {
        HStack {
            if isFromCurrentUser { Spacer() }

            VStack(alignment: isFromCurrentUser ? .trailing : .leading, spacing: 4) {
                Text(message.content)
                    .padding(12)
                    .background(isFromCurrentUser ? Color.convroBlue : Color.gray.opacity(0.2))
                    .foregroundColor(isFromCurrentUser ? .white : .primary)
                    .cornerRadius(16)

                HStack(spacing: 4) {
                    if message.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    Text(message.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    if isFromCurrentUser {
                        Image(systemName: message.isDelivered ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption2)
                            .foregroundColor(message.isDelivered ? .green : .gray)
                    }
                }
            }

            if !isFromCurrentUser { Spacer() }
        }
    }
}
```

---

### 4.5 FingerprintView.swift

**Display identity fingerprint for verification:**

```swift
struct FingerprintView: View {
    let fingerprint: String  // Hex string

    var body: some View {
        VStack(spacing: 12) {
            Text("Identity Fingerprint")
                .font(.headline)

            // Display as blocks of 4 hex chars
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
                ForEach(fingerprintBlocks, id: \.self) { block in
                    Text(block)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
            }

            Button("Verify via QR Code") {
                // Show QR code scanner
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var fingerprintBlocks: [String] {
        // Split fingerprint into blocks of 4 chars
        stride(from: 0, to: fingerprint.count, by: 4).map {
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: $0)
            let end = fingerprint.index(start, offsetBy: min(4, fingerprint.count - $0))
            return String(fingerprint[start..<end])
        }
    }
}
```

---

### 4.6 EncryptionBadge.swift

**Show E2EE status in chat:**

```swift
struct EncryptionBadge: View {
    let session: Session?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: session?.isActive == true ? "lock.shield.fill" : "lock.open.fill")
                .font(.caption)

            Text(session?.isActive == true ? "End-to-End Encrypted" : "Not Encrypted")
                .font(.caption)
        }
        .foregroundColor(session?.isActive == true ? .green : .orange)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.green.opacity(0.1))
        .cornerRadius(8)
    }
}
```

---

### 4.7 HandshakeProgressView.swift

**Show handshake progress:**

```swift
struct HandshakeProgressView: View {
    @Binding var progress: HandshakeProgress

    var body: some View {
        VStack(spacing: 16) {
            ProgressView(value: progress.percentage)
                .progressViewStyle(.linear)

            VStack(alignment: .leading, spacing: 8) {
                StepRow(text: "Fetching prekey bundle", completed: progress.step >= 1)
                StepRow(text: "Creating handshake offer", completed: progress.step >= 2)
                StepRow(text: "Sending offer", completed: progress.step >= 3)
                StepRow(text: "Waiting for accept", completed: progress.step >= 4)
                StepRow(text: "Verifying key confirmation", completed: progress.step >= 5)
            }
        }
        .padding()
    }
}

struct StepRow: View {
    let text: String
    let completed: Bool

    var body: some View {
        HStack {
            Image(systemName: completed ? "checkmark.circle.fill" : "circle")
                .foregroundColor(completed ? .green : .gray)
            Text(text)
                .foregroundColor(completed ? .primary : .secondary)
        }
    }
}
```

---

### 4.8 LoadingView.swift

**Generic loading indicator:**

```swift
struct LoadingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
```

---

## 5. App Lifecycle

### 5.1 ConvroApp.swift (Entry Point)

```swift
@main
struct ConvroApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appCoordinator = AppCoordinator()

    var body: some Scene {
        WindowGroup {
            Group {
                if appCoordinator.isAuthenticated {
                    TabBarRoot()
                        .environmentObject(appCoordinator.c6pManager)
                        .environmentObject(appCoordinator.webSocketManager)
                } else {
                    LoginView()
                        .environmentObject(appCoordinator)
                }
            }
            .onAppear {
                Task {
                    await appCoordinator.initialize()
                }
            }
        }
    }
}
```

---

### 5.2 AppDelegate.swift (Push Notifications)

```swift
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // Register for push notifications
        UNUserNotificationCenter.current().delegate = self

        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            try? await PushNotificationManager.shared.registerToken(deviceToken)
        }
    }

    // Handle incoming push notification
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Silent push: new message available
        Task {
            await WebSocketManager.shared.connect()
        }

        completionHandler()
    }
}
```

---

## 6. Security Considerations

### 6.1 Keychain Best Practices

✅ **DO:**
- Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Set `kSecAttrSynchronizable = false` (NEVER sync to iCloud!)
- Use `kSecUseDataProtectionKeychain = true` (iOS 13+)
- Require biometric auth for sensitive operations

❌ **DON'T:**
- Store keys in UserDefaults or files
- Use `kSecAttrAccessibleAlways` (insecure)
- Allow iCloud sync for E2EE keys

---

### 6.2 Memory Management

- Use `zeroize` equivalent in Swift (overwrite Data before dealloc)
- Clear plaintext messages from memory after display
- Use `defer` blocks to ensure cleanup

```swift
func decrypt(ciphertext: Data) throws -> String {
    var plaintextData = Data()
    defer {
        // Zeroize plaintext data
        plaintextData.withUnsafeMutableBytes { ptr in
            memset(ptr.baseAddress, 0, ptr.count)
        }
    }

    plaintextData = try c6pManager.decrypt(ciphertext)
    return String(data: plaintextData, encoding: .utf8)!
}
```

---

### 6.3 App Transport Security (ATS)

**Info.plist:**
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.convro.app</key>
        <dict>
            <key>NSExceptionRequiresForwardSecrecy</key>
            <true/>
            <key>NSIncludesSubdomains</key>
            <true/>
            <key>NSExceptionMinimumTLSVersion</key>
            <string>TLSv1.3</string>
        </dict>
    </dict>
</dict>
```

---

## 7. Performance Optimizations

### 7.1 Actor-Based Concurrency

- Use `actor` for thread-safety (C6PManager, WebSocketManager)
- Use `@MainActor` for UI updates
- Avoid blocking main thread with FFI calls (wrap in `Task.detached`)

---

### 7.2 Message Pagination

```swift
class MessageDatabase {
    func fetchMessages(
        sessionId: Data,
        limit: Int = 50,
        offset: Int = 0
    ) async throws -> [Message] {
        // Fetch in batches to avoid loading 10,000 messages at once
    }
}
```

---

### 7.3 Prekey Rotation Background Task

```swift
// Register background task in AppDelegate
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "app.convro.prekey-rotation",
    using: nil
) { task in
    Task {
        try? await DeviceIdentityManager.shared.rotatePrekeys()
        task.setTaskCompleted(success: true)
    }
}
```

---

## 8. Testing Strategy

### 8.1 Unit Tests

- `C6PManagerTests`: Test handshake flows, encrypt/decrypt
- `KeychainManagerTests`: Test secure storage
- `HandshakeCoordinatorTests`: Test error handling

---

### 8.2 Integration Tests

- Full handshake between 2 simulators (XCTest)
- Message encryption roundtrip
- Session persistence across app restarts

---

### 8.3 UI Tests

- E2E test: Register → Add contact → Start chat → Send message → Receive message

---

## 9. Deployment Checklist

### 9.1 Pre-Release

- [ ] All unit tests passing
- [ ] Integration tests passing
- [ ] UI tests passing
- [ ] Code signing configured
- [ ] Push notifications tested (APNs sandbox)
- [ ] Keychain access groups configured
- [ ] App Transport Security (ATS) configured

### 9.2 App Store Submission

- [ ] Privacy manifest (`PrivacyInfo.xcprivacy`) created
- [ ] Export compliance (encryption) declared
- [ ] App Store Connect metadata
- [ ] Screenshots for all device sizes
- [ ] TestFlight beta testing completed

---

## 10. Następne kroki

Po zatwierdzeniu tej architektury:

1. **Utworzyć Xcode project** z tą strukturą katalogów
2. **Zaimplementować Core Managers** (C6PManager, KeychainManager, etc.)
3. **Zintegrować C6PProtocol.xcframework** (SPM dependency)
4. **Zbudować podstawowy UI** (TabBarRoot, LoginView)
5. **Przetestować handshake flow** (2 simulators)

---

**Czy ta architektura spełnia Twoje wymagania?** 🚀
