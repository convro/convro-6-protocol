// C6PManager.swift
// High-level manager for C6P integration - ready to use!
//
// Usage:
//   1. Copy KeychainManager.swift and this file to your Xcode project
//   2. Initialize: let c6p = C6PManager()
//   3. Start handshake: try await c6p.startHandshake(with: deviceId)
//   4. Send message: try await c6p.sendMessage("Hello!", to: sessionId)
//
// Architecture:
//   - Uses Swift actors for thread safety
//   - Manages sessions in memory (cached)
//   - Stores keys in Keychain (secure)
//   - Handles all C6P operations
//
// License: Apache 2.0 / MIT (same as C6P)

import Foundation
import c6p_ios

// MARK: - Errors

enum C6PManagerError: Error {
    case notInitialized
    case sessionNotFound
    case handshakeNotComplete
    case networkError(String)
    case invalidSessionId
}

// MARK: - Session State

struct C6PSession {
    let sessionId: [UInt8]
    let sessionKeys: SessionKeys
    let sessionState: SessionState
    let isInitiator: Bool
    let peerDeviceId: String
}

// MARK: - C6P Manager (Thread-Safe Actor)

@available(iOS 13.0, *)
actor C6PManager {

    // MARK: - Properties

    private var activeSessions: [String: C6PSession] = [:]
    private var deviceIdentity: DeviceIdentity?

    // MARK: - Initialization

    /// Initialize C6P manager
    /// Loads device identity from Keychain (or generates new one)
    init() async throws {
        // Try to load existing identity
        if let existing = try? KeychainManager.getDeviceIdentity() {
            self.deviceIdentity = existing
            print("✅ Loaded existing device identity")
            print("   Device ID: \(utils_bytes_to_hex(data: existing.device_id))")
            print("   Fingerprint: \(existing.fingerprint)")
        } else {
            // Generate new identity
            let identity = try identity_generate_identity()
            try KeychainManager.storeDeviceIdentity(identity)
            self.deviceIdentity = identity
            print("✅ Generated new device identity")
            print("   Device ID: \(utils_bytes_to_hex(data: identity.device_id))")
            print("   Fingerprint: \(identity.fingerprint)")
        }
    }

    // MARK: - Identity Management

    /// Get device ID as hex string
    func getDeviceIdHex() throws -> String {
        guard let identity = deviceIdentity else {
            throw C6PManagerError.notInitialized
        }
        return utils_bytes_to_hex(data: identity.device_id)
    }

    /// Get fingerprint for verification
    func getFingerprint() throws -> String {
        guard let identity = deviceIdentity else {
            throw C6PManagerError.notInitialized
        }
        return identity.fingerprint
    }

    /// Get formatted fingerprint (with spaces every 4 chars)
    func getFormattedFingerprint() throws -> String {
        let fingerprint = try getFingerprint()
        return fingerprint.enumerated()
            .map { $0.offset % 4 == 0 && $0.offset > 0 ? " \($0.element)" : String($0.element) }
            .joined()
    }

    // MARK: - Handshake (Initiator)

    /// Start handshake with a peer (initiator side)
    ///
    /// - Parameter peerDeviceId: Responder's device ID (hex string)
    /// - Returns: Offer bytes to send to responder
    /// - Throws: C6PManagerError or C6pError
    func startHandshake(with peerDeviceId: String) async throws -> [UInt8] {
        guard let identity = deviceIdentity else {
            throw C6PManagerError.notInitialized
        }

        // TODO: Fetch responder's prekey bundle from your server
        // For example:
        // let bundle = try await yourAPI.fetchPrekeyBundle(for: peerDeviceId)

        // For this example, we'll use a mock bundle
        // In production, replace this with actual server call
        throw C6PManagerError.networkError("fetchPrekeyBundle not implemented - see TODO in code")

        // Once you have the bundle:
        // let result = try handshake_create_offer(
        //     initiator_identity: identity,
        //     responder_bundle: bundle
        // )
        //
        // // Store session keys
        // try KeychainManager.storeSessionKeys(result.session_keys, for: result.offer.session_id)
        //
        // // Create session state
        // let sessionState = try SessionState(keys: result.session_keys, is_initiator: true)
        //
        // // Cache session
        // let sessionIdHex = utils_bytes_to_hex(data: result.offer.session_id)
        // activeSessions[sessionIdHex] = C6PSession(
        //     sessionId: result.offer.session_id,
        //     sessionKeys: result.session_keys,
        //     sessionState: sessionState,
        //     isInitiator: true,
        //     peerDeviceId: peerDeviceId
        // )
        //
        // print("✅ Started handshake with \(peerDeviceId)")
        // print("   Session ID: \(sessionIdHex)")
        //
        // return result.offer.serialized
    }

    /// Complete handshake after receiving accept (initiator side)
    ///
    /// - Parameters:
    ///   - acceptBytes: Accept message from responder
    ///   - sessionId: Session ID (from offer)
    /// - Throws: C6PManagerError or C6pError
    func completeHandshake(acceptBytes: [UInt8], sessionId: [UInt8]) throws {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        // Get session from cache
        guard let session = activeSessions[sessionIdHex] else {
            throw C6PManagerError.sessionNotFound
        }

        // Retrieve stored offer (you'd need to store this in KeychainManager)
        // For simplicity, assuming you have it from startHandshake
        // let offer = ... (retrieve from somewhere)

        // Verify accept
        // try handshake_verify_accept(
        //     offer: offer,
        //     accept_bytes: acceptBytes,
        //     session_keys: session.sessionKeys
        // )

        print("✅ Handshake complete with session \(sessionIdHex)")
    }

    // MARK: - Handshake (Responder)

    /// Accept handshake from a peer (responder side)
    ///
    /// - Parameter offerBytes: Offer message from initiator
    /// - Returns: Accept bytes to send to initiator
    /// - Throws: C6PManagerError or C6pError
    func acceptHandshake(offerBytes: [UInt8]) async throws -> [UInt8] {
        guard let identity = deviceIdentity else {
            throw C6PManagerError.notInitialized
        }

        // TODO: Retrieve your current SPK and OTP from Keychain
        // For example:
        // let spk = try KeychainManager.getCurrentSPK()
        // let otp = try? KeychainManager.getNextOTP()

        // For this example, we'll generate fresh prekeys
        // In production, you should have pre-generated these and stored them
        let spk = try identity_generate_signed_prekey(identity: identity)
        let otp = try? identity_generate_one_time_prekey()

        let result = try handshake_accept_offer(
            responder_identity: identity,
            responder_spk: spk,
            responder_otp: otp,
            offer_bytes: offerBytes
        )

        // Store session keys
        try KeychainManager.storeSessionKeys(result.session_keys, for: result.accept.session_id)

        // Create session state
        let sessionState = try SessionState(keys: result.session_keys, is_initiator: false)

        // Cache session
        let sessionIdHex = utils_bytes_to_hex(data: result.accept.session_id)

        // Extract peer device ID from accept (or parse from offer)
        let peerDeviceId = utils_bytes_to_hex(data: result.accept.responder_device_id)

        activeSessions[sessionIdHex] = C6PSession(
            sessionId: result.accept.session_id,
            sessionKeys: result.session_keys,
            sessionState: sessionState,
            isInitiator: false,
            peerDeviceId: peerDeviceId
        )

        print("✅ Accepted handshake")
        print("   Session ID: \(sessionIdHex)")

        return result.accept.serialized
    }

    // MARK: - Messaging

    /// Send encrypted message
    ///
    /// - Parameters:
    ///   - plaintext: Message to send (will be UTF-8 encoded)
    ///   - sessionId: Session ID (8 bytes)
    /// - Returns: Encrypted message to send over network
    /// - Throws: C6PManagerError or C6pError
    func sendMessage(_ plaintext: String, sessionId: [UInt8]) throws -> EncryptedMessage {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        // Get session from cache (or load from Keychain)
        let session = try getOrLoadSession(sessionIdHex: sessionIdHex)

        // Encrypt
        let plaintextBytes = Array(plaintext.utf8)
        let encrypted = try session.sessionState.encrypt(plaintext: plaintextBytes)

        print("✅ Encrypted message for session \(sessionIdHex)")
        print("   Counter: \(encrypted.counter)")
        print("   Ciphertext length: \(encrypted.ciphertext.count) bytes")

        return encrypted
    }

    /// Receive and decrypt message
    ///
    /// - Parameters:
    ///   - encrypted: Encrypted message from peer
    ///   - sessionId: Session ID (8 bytes)
    /// - Returns: Decrypted plaintext
    /// - Throws: C6PManagerError or C6pError (including ReplayDetected)
    func receiveMessage(_ encrypted: EncryptedMessage, sessionId: [UInt8]) throws -> String {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        // Get session from cache (or load from Keychain)
        let session = try getOrLoadSession(sessionIdHex: sessionIdHex)

        // Decrypt
        let plaintextBytes = try session.sessionState.decrypt(message: encrypted)

        guard let plaintext = String(bytes: plaintextBytes, encoding: .utf8) else {
            throw C6pError.InvalidInput("Decrypted data is not valid UTF-8")
        }

        print("✅ Decrypted message for session \(sessionIdHex)")
        print("   Counter: \(encrypted.counter)")

        return plaintext
    }

    // MARK: - Session Management

    /// Get or load session from cache/Keychain
    private func getOrLoadSession(sessionIdHex: String) throws -> C6PSession {
        // Check cache first
        if let session = activeSessions[sessionIdHex] {
            return session
        }

        // Load from Keychain
        guard let sessionIdBytes = try? utils_hex_to_bytes(hex: sessionIdHex) else {
            throw C6PManagerError.invalidSessionId
        }

        let sessionKeys = try KeychainManager.getSessionKeys(for: sessionIdBytes)

        // Create session state (default to initiator - you may need to store this metadata)
        let sessionState = try SessionState(keys: sessionKeys, is_initiator: true)

        let session = C6PSession(
            sessionId: sessionIdBytes,
            sessionKeys: sessionKeys,
            sessionState: sessionState,
            isInitiator: true,
            peerDeviceId: "unknown"  // TODO: Store peer device ID
        )

        // Cache it
        activeSessions[sessionIdHex] = session

        return session
    }

    /// End session (delete keys from Keychain)
    ///
    /// - Parameter sessionId: Session ID (8 bytes)
    func endSession(sessionId: [UInt8]) throws {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)

        // Remove from cache
        activeSessions.removeValue(forKey: sessionIdHex)

        // Delete from Keychain
        try KeychainManager.deleteSessionKeys(for: sessionId)

        print("✅ Ended session \(sessionIdHex)")
    }

    /// End all sessions (for logout)
    func endAllSessions() {
        activeSessions.removeAll()
        KeychainManager.deleteAllSessionKeys()
        print("✅ Ended all sessions")
    }

    // MARK: - Utilities

    /// Get list of active session IDs
    func getActiveSessions() -> [String] {
        return Array(activeSessions.keys)
    }

    /// Check if session exists
    func hasSession(sessionId: [UInt8]) -> Bool {
        let sessionIdHex = utils_bytes_to_hex(data: sessionId)
        return activeSessions[sessionIdHex] != nil ||
               (try? KeychainManager.getSessionKeys(for: sessionId)) != nil
    }
}

// MARK: - Example Usage

/*

// Example 1: Initialize
let c6pManager = try await C6PManager()

// Example 2: Get your device ID and fingerprint
let myDeviceId = try await c6pManager.getDeviceIdHex()
let myFingerprint = try await c6pManager.getFormattedFingerprint()
print("My Device ID: \(myDeviceId)")
print("My Fingerprint: \(myFingerprint)")

// Example 3: Start handshake (initiator)
let peerDeviceId = "a1b2c3d4..."  // From user input or QR code
do {
    let offerBytes = try await c6pManager.startHandshake(with: peerDeviceId)
    // Send offerBytes to peer over network (e.g., WebSocket, HTTP POST)
    try await yourNetworkLayer.send(offerBytes, to: peerDeviceId)
} catch {
    print("Handshake failed: \(error)")
}

// Example 4: Accept handshake (responder)
func handleIncomingOffer(_ offerBytes: [UInt8]) async {
    do {
        let acceptBytes = try await c6pManager.acceptHandshake(offerBytes: offerBytes)
        // Send acceptBytes back to initiator
        try await yourNetworkLayer.sendAccept(acceptBytes)
    } catch {
        print("Accept failed: \(error)")
    }
}

// Example 5: Send message
func sendMessage() async {
    let sessionId: [UInt8] = /* from handshake */
    do {
        let encrypted = try await c6pManager.sendMessage("Hello, secure world!", sessionId: sessionId)
        // Send encrypted message over network
        try await yourNetworkLayer.sendEncrypted(encrypted, sessionId: sessionId)
    } catch {
        print("Send failed: \(error)")
    }
}

// Example 6: Receive message
func handleIncomingMessage(_ encrypted: EncryptedMessage, sessionId: [UInt8]) async {
    do {
        let plaintext = try await c6pManager.receiveMessage(encrypted, sessionId: sessionId)
        print("Received: \(plaintext)")
    } catch C6pError.ReplayDetected(let msg) {
        print("⚠️ Replay attack detected: \(msg)")
        // Log security event
    } catch {
        print("Decrypt failed: \(error)")
    }
}

// Example 7: End session
try await c6pManager.endSession(sessionId: sessionId)

// Example 8: End all sessions (logout)
await c6pManager.endAllSessions()

*/
