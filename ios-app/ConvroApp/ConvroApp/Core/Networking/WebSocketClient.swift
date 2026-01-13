import Foundation

// MARK: - WebSocket Client
class WebSocketClient: NSObject {
    // MARK: - Properties
    private var webSocketTask: URLSessionWebSocketTask?
    private let url: URL
    private var pingTimer: Timer?

    // Callbacks
    var onConnect: (() -> Void)?
    var onDisconnect: ((Error?) -> Void)?
    var onMessage: ((Data) -> Void)?
    var onError: ((Error) -> Void)?

    // MARK: - Initialization
    init(url: URL) {
        self.url = url
        super.init()
    }

    // MARK: - Connection
    func connect() {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        webSocketTask = session.webSocketTask(with: url)
        webSocketTask?.resume()
        receiveMessage()
        startPing()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        pingTimer?.invalidate()
        pingTimer = nil
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
        let data = try JSONEncoder().encode(value)
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
                    print("Ping error: \(error)")
                }
            }
        }
    }
}

// MARK: - URLSessionWebSocketDelegate
extension WebSocketClient: URLSessionWebSocketDelegate {
    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        onConnect?()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        onDisconnect?(nil)
    }
}
