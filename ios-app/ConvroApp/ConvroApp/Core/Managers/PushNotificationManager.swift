import Foundation
import UserNotifications

// MARK: - Push Notification Manager
/// Handles APNs registration and notification handling
@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    // MARK: - Singleton
    static let shared = PushNotificationManager()

    // MARK: - Properties
    @Published var notificationPermission: UNAuthorizationStatus = .notDetermined
    private var deviceToken: Data?

    private override init() {
        super.init()
    }

    // MARK: - Permission
    func requestPermission() async throws {
        let center = UNUserNotificationCenter.current()
        let options: UNAuthorizationOptions = [.alert, .sound, .badge]
        let granted = try await center.requestAuthorization(options: options)

        if granted {
            await registerForRemoteNotifications()
        }
    }

    // MARK: - Registration
    private func registerForRemoteNotifications() async {
        // Register for remote notifications on main thread
        // Note: Actual UIApplication.shared.registerForRemoteNotifications()
        // must be called from AppDelegate or similar
        print("📱 Ready to register for remote notifications")
    }

    func didRegisterForRemoteNotifications(deviceToken: Data) {
        self.deviceToken = deviceToken

        // Send token to server for push notifications
        Task {
            do {
                let tokenHex = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
                try await APIManager.shared.registerPushToken(deviceToken: tokenHex)
                print("✅ Push token registered with server")
            } catch {
                print("❌ Failed to register push token: \(error)")
            }
        }
    }

    func didFailToRegisterForRemoteNotifications(error: Error) {
        print("Failed to register for push: \(error)")
    }

    // MARK: - Handle Notification
    func handleNotification(_ notification: UNNotification) async {
        let userInfo = notification.request.content.userInfo

        // Process notification type
        if let type = userInfo["type"] as? String {
            switch type {
            case "new_message":
                await handleNewMessageNotification(userInfo)

            case "handshake_offer":
                await handleHandshakeOfferNotification(userInfo)

            case "handshake_accept":
                await handleHandshakeAcceptNotification(userInfo)

            default:
                print("⚠️ Unknown notification type: \(type)")
            }
        }
    }

    // MARK: - Notification Handlers

    private func handleNewMessageNotification(_ userInfo: [AnyHashable: Any]) async {
        // Fetch new messages from server
        do {
            let messages = try await APIManager.shared.fetchInbox()
            print("📨 Fetched \(messages.count) new messages from push notification")

            // Notify MessageSyncManager or relevant view models
            // This will trigger UI updates via Combine publishers
            NotificationCenter.default.post(
                name: NSNotification.Name("NewMessagesAvailable"),
                object: nil,
                userInfo: ["messages": messages]
            )
        } catch {
            print("❌ Failed to fetch messages: \(error)")
        }
    }

    private func handleHandshakeOfferNotification(_ userInfo: [AnyHashable: Any]) async {
        print("🤝 Handshake offer received via push notification")

        // Fetch inbox to get the offer
        do {
            let messages = try await APIManager.shared.fetchInbox()
            print("📨 Fetched inbox for handshake offer")

            NotificationCenter.default.post(
                name: NSNotification.Name("HandshakeOfferReceived"),
                object: nil,
                userInfo: ["messages": messages]
            )
        } catch {
            print("❌ Failed to fetch handshake offer: \(error)")
        }
    }

    private func handleHandshakeAcceptNotification(_ userInfo: [AnyHashable: Any]) async {
        print("✅ Handshake accept received via push notification")

        // Fetch inbox to get the accept
        do {
            let messages = try await APIManager.shared.fetchInbox()
            print("📨 Fetched inbox for handshake accept")

            NotificationCenter.default.post(
                name: NSNotification.Name("HandshakeAcceptReceived"),
                object: nil,
                userInfo: ["messages": messages]
            )
        } catch {
            print("❌ Failed to fetch handshake accept: \(error)")
        }
    }
}
