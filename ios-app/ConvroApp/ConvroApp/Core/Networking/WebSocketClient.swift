import Foundation

// MARK: - WebSocket Client
class WebSocketClient: NSObject {
    // MARK: - Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private var pingTimer: Timer?
    private var authToken: String?

    // Callbacks
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onMessage: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Initialization
    init(url: URL, authToken: String? = nil) {
        self.url = url
        self.authToken = authToken
        super.init()
    }

    // MARK: - Connection
    func connect() {
        var request = URLRequest(url: url)

        // Add JWT token if available
        if let token = authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: request)
        webSocketTask?.resume()
        receiveMessage()
        startPing()

        print("🔌 WebSocket connecting to: \(url)")
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pingTimer?.invalidate()
        pingTimer = nil
        print("🔌 WebSocket disconnected")
    }

    // MARK: - Send
    func send(_ data: Data) {
        let message = URLSessionWebSocketTask.Message.data(data)
        webSocketTask?.send(message) { [weak self] error in
            if let error = error {
                self?.onError?(error)
            }
        }
    }

    func sendJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let data = try encoder.encode(value)
        send(data)
    }

    // MARK: - Receive
    private func receiveMessage() {
        webSocketTask?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .data(let data):
                    self?.onMessage?(data)
                case .string(let string):
                    if let data = string.data(using: .utf8) {
                        self?.onMessage?(data)
                    }
                @unknown default:
                    break
                }
                self?.receiveMessage() // Continue receiving
            case .failure(let error):
                self?.onError?(error)
            }
        }
    }

    // MARK: - Ping
    private func startPing() {
        pingTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.webSocketTask?.sendPing { error in
                if let error = error {
                    print("❌ Ping error: \(error)")
                }
            }
        }
    }

    // MARK: - Authentication
    func setAuthToken(_ token: String) {
        self.authToken = token
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        print("✅ WebSocket connected")
        onConnect?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        print("⚠️ WebSocket closed: \(closeCode)")
        onDisconnect?(nil)
    }
}
