# C6P iOS Security Guidelines

Security best practices and guidelines for integrating the Convro 6 Protocol into iOS applications.

## Table of Contents

1. [Security Overview](#security-overview)
2. [Key Storage](#key-storage)
3. [Cryptographic Guarantees](#cryptographic-guarantees)
4. [Network Security](#network-security)
5. [Attack Mitigation](#attack-mitigation)
6. [Secure Coding Practices](#secure-coding-practices)
7. [Audit and Compliance](#audit-and-compliance)
8. [Incident Response](#incident-response)

---

## Security Overview

### Threat Model

C6P protects against the following threats:

✅ **Eavesdropping**: All messages encrypted end-to-end
✅ **Man-in-the-Middle (MITM)**: Authenticated key exchange with KC1/KC2
✅ **Replay Attacks**: Counter-based replay protection
✅ **Forward Secrecy**: Old keys cannot decrypt new messages
✅ **Key Compromise Impersonation**: Ephemeral keys prevent impersonation
✅ **Unauthorized Access**: iOS Keychain with device-bound protection

### Out of Scope

❌ **Endpoint Security**: C6P cannot protect against compromised devices
❌ **Social Engineering**: User verification of fingerprints required
❌ **Traffic Analysis**: Message metadata (size, timing) not hidden
❌ **Denial of Service**: Application-layer DoS not prevented

---

## Key Storage

### iOS Keychain Configuration

**CRITICAL**: All cryptographic keys MUST be stored in iOS Keychain with appropriate protection levels.

#### Device Identity (Long-Term Keys)

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "c6p_device_identity",
    kSecValueData as String: identityData,
    // CRITICAL: Use device-only, after-first-unlock protection
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    // Optional: Require biometric authentication for retrieval
    kSecAttrAccessControl as String: accessControl,  // See below
    // Prevent iCloud backup (device-specific identity)
    kSecAttrSynchronizable as String: false
]
```

**Protection Levels Explained:**

| Protection Level | Security | Availability | Use Case |
|-----------------|----------|--------------|----------|
| `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` | **Recommended** | After first unlock | Device identity, session keys |
| `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | Higher (locked screen = inaccessible) | Only when unlocked | Extremely sensitive keys |
| `kSecAttrAccessibleAlways` | **NEVER USE** | Always available | N/A - INSECURE |

**Why `AfterFirstUnlock`:**
- ✅ Survives device lock (background message processing)
- ✅ Device-bound (not synced to iCloud)
- ✅ Hardware-encrypted on modern devices (Secure Enclave)

#### Biometric Protection (Optional)

```swift
import LocalAuthentication

let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .biometryCurrentSet,  // Require Face ID / Touch ID
    nil
)!

let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "c6p_device_identity",
    kSecValueData as String: identityData,
    kSecAttrAccessControl as String: access,
    kSecUseAuthenticationContext as String: LAContext()
]
```

**Note**: Biometric protection requires user prompt on every access. Use only for:
- Revealing device identity to user (settings screen)
- Manual key export
- High-security actions

**Do NOT use for**:
- Session key retrieval (too frequent)
- Background message processing

### Session Keys

Session keys should use the same protection as device identity:

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: "c6p_session_\(sessionIdHex)",
    kSecValueData as String: sessionKeysData,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    kSecAttrSynchronizable as String: false  // Do NOT sync to iCloud
]
```

### Sensitive Data in Memory

When handling keys in Swift:

```swift
// ✅ GOOD: Use Data for sensitive bytes (can be zeroed)
var sensitiveData = Data(identity.identity_priv_ed25519)
defer {
    sensitiveData.resetBytes(in: 0..<sensitiveData.count)  // Zero on deallocation
}

// ❌ BAD: String for sensitive data (cannot be reliably zeroed)
let privateKeyString = String(decoding: identity.identity_priv_ed25519, as: UTF8.self)
```

**Memory Safety Practices:**

1. **Minimize lifetime**: Load keys only when needed, discard immediately
2. **Zero after use**: Use `defer { data.resetBytes(...) }` for sensitive `Data`
3. **Avoid copies**: Pass by reference (`inout`) when possible
4. **No logging**: Never log private keys or session keys
5. **No persistence**: Never write keys to UserDefaults, files, or databases

---

## Cryptographic Guarantees

### Algorithms Used

| Component | Algorithm | Key Size | Security Level |
|-----------|-----------|----------|----------------|
| Identity Signing | Ed25519 | 256-bit | 128-bit |
| Key Agreement (DH) | X25519 | 256-bit | 128-bit |
| AEAD | ChaCha20-Poly1305 | 256-bit key, 96-bit nonce | 128-bit |
| Key Derivation | HKDF-SHA256 | 256-bit | 128-bit |
| Hash | BLAKE3 | 256-bit | 128-bit |
| Key Confirmation | HMAC-SHA256 | 256-bit | 128-bit |

All algorithms provide **128-bit security level** (quantum-resistant: no, but post-quantum migration planned).

### Handshake Security (IslandAccord v1)

**3DH Handshake** (when no OTP available):
```
DH1: initiator_identity_dh × responder_identity_dh
DH2: initiator_ephemeral_dh × responder_identity_dh
DH3: initiator_ephemeral_dh × responder_spk_dh
```

**Security Properties:**
- ✅ Mutual authentication (both parties prove identity)
- ✅ Forward secrecy (ephemeral key destroyed after handshake)
- ✅ Key confirmation (KC1, KC2 prevent MITM)
- ✅ Transcript integrity (BLAKE3 hash covers all handshake messages)

**4DH Handshake** (when OTP available):
```
DH1-DH3: (same as 3DH)
DH4: initiator_ephemeral_dh × responder_otp_dh
```

**Additional Security:**
- ✅ Enhanced forward secrecy (OTP deleted after single use)
- ✅ Protection against key compromise impersonation (KCI)

### Message Encryption

Each message is encrypted with:

1. **Ratcheted Message Key**: Derived via HKDF from chain key, never reused
2. **Deterministic Nonce**: Derived from message key material + session binding
3. **AEAD**: ChaCha20-Poly1305 with Additional Authenticated Data (AAD)
4. **AAD Includes**: session_id, stream_id, counter, payload length

**Security Properties:**
- ✅ Confidentiality (ChaCha20 encryption)
- ✅ Authenticity (Poly1305 MAC)
- ✅ Forward secrecy (old chain keys deleted after ratchet)
- ✅ Replay protection (counter checked against skip-window)

### Constant-Time Operations

All security-critical operations use constant-time implementations:

```rust
// KC2 verification (c6p-ios/src/handshake.rs)
use subtle::ConstantTimeEq;
let kc2_valid: bool = accept_core.kc2.ct_eq(&expected_kc2).into();
```

**Prevents Timing Side-Channels:**
- ✅ KC2 comparison (32-byte HMAC)
- ✅ ChaCha20-Poly1305 (no data-dependent branches)
- ✅ Ed25519 signing/verification (constant-time scalar multiplication)
- ✅ X25519 DH (constant-time ladder)

---

## Network Security

### Transport Layer Security

**CRITICAL**: C6P provides end-to-end encryption but **does NOT** protect metadata (message size, timing, sender/receiver IP). Use TLS 1.3+ for transport.

```swift
// Configure URLSession with TLS 1.3+
let config = URLSessionConfiguration.default
config.tlsMinimumSupportedProtocolVersion = .TLSv13

let session = URLSession(configuration: config)
```

**TLS Configuration:**
- ✅ TLS 1.3 minimum (forbid TLS 1.2 and below)
- ✅ Certificate pinning (optional, for high-security apps)
- ✅ Perfect Forward Secrecy (ephemeral DH key exchange)

### Certificate Pinning (Optional)

For apps requiring maximum security:

```swift
class TLSDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Verify certificate chain
        let policies = [SecPolicyCreateSSL(true, challenge.protectionSpace.host as CFString)]
        SecTrustSetPolicies(serverTrust, policies as CFTypeRef)

        var result: SecTrustResultType = .invalid
        SecTrustEvaluate(serverTrust, &result)

        if result == .unspecified || result == .proceed {
            // Optionally: Pin to specific certificate or public key
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }
}
```

### Metadata Protection

C6P does **not** hide:
- Message size (ciphertext length ≈ plaintext length + 24 bytes overhead)
- Message timing (when messages sent)
- Sender/Receiver (visible to server)

**Mitigation Strategies:**
1. **Padding**: Add random padding to messages to hide true length
2. **Dummy Messages**: Send fake messages at regular intervals
3. **Batching**: Batch multiple messages together
4. **Tor/VPN**: Route traffic through Tor or VPN to hide IP addresses

**Example: Padding**

```swift
func padMessage(_ plaintext: [UInt8], to size: Int) -> [UInt8] {
    guard plaintext.count < size else { return plaintext }

    var padded = plaintext
    let paddingSize = size - plaintext.count

    // Add padding length (2 bytes)
    let paddingLen = UInt16(paddingSize).bigEndian
    padded.append(contentsOf: withUnsafeBytes(of: paddingLen) { Array($0) })

    // Add random padding
    padded.append(contentsOf: try! utils_random_bytes(length: UInt32(paddingSize - 2)))

    return padded
}

func unpadMessage(_ padded: [UInt8]) throws -> [UInt8] {
    guard padded.count >= 2 else { throw PaddingError.tooShort }

    let paddingLen = padded[(padded.count - 2)...].withUnsafeBytes { $0.load(as: UInt16.self).bigEndian }
    let messageLen = padded.count - Int(paddingLen)

    guard messageLen >= 0 else { throw PaddingError.invalid }

    return Array(padded[..<messageLen])
}
```

---

## Attack Mitigation

### Replay Attacks

**Built-in Protection**: C6P sessions maintain a skip-window to detect replayed messages.

```
Counter Window (size = 1000):
[====|====|====|====|XXXX]
     ^                  ^
  oldest            newest
  received          expected

X = already received (replay if seen again)
```

**Replay Detection:**
- ✅ Duplicate counter rejected immediately
- ✅ Counter gaps up to 1000 tolerated (out-of-order delivery)
- ✅ Counters older than window rejected

**Error Handling:**

```swift
do {
    let plaintext = try session.decrypt(message: encrypted)
    // Process message
} catch C6pError.ReplayDetected(let msg) {
    // CRITICAL: Log security event!
    logger.warning("Replay attack detected: \(msg)")

    // Alert user (optional)
    showSecurityAlert("Duplicate message detected. Possible attack.")

    // Report to server (for analytics)
    reportSecurityEvent(type: "replay", sessionId: sessionId)
}
```

### Man-in-the-Middle (MITM)

**Protection Mechanisms:**

1. **Key Confirmation (KC1, KC2)**: Both parties verify shared secret
2. **Transcript Hash**: Covers all handshake messages (prevents tampering)
3. **Signature Verification**: Offer signed by initiator, bundle signed by responder
4. **Fingerprint Verification**: Users verify fingerprints out-of-band (QR code, phone call)

**User Verification (Recommended):**

```swift
// Display fingerprints for verification
func verifyIdentity(with peer: String) {
    let myFingerprint = try! IdentityManager.getFormattedFingerprint()
    let peerFingerprint = fetchPeerFingerprint(for: peer)

    // Show UI for manual comparison
    presentVerificationScreen(
        myFingerprint: myFingerprint,
        peerFingerprint: peerFingerprint,
        onVerified: {
            markIdentityAsVerified(peer)
        }
    )
}
```

**Safety Numbers (Optional Enhancement):**

Generate a deterministic safety number from both fingerprints:

```swift
func generateSafetyNumber(my: String, peer: String) -> String {
    // Combine fingerprints (ordered lexicographically for determinism)
    let combined = [my, peer].sorted().joined()

    // Hash to produce compact verification code
    let hash = SHA256.hash(data: combined.data(using: .utf8)!)
    let bytes = [UInt8](hash)

    // Format as 6 groups of 5 digits (e.g., "12345 67890 12345 67890 12345 67890")
    return bytes.prefix(15)
        .map { String(format: "%02d", $0 % 100) }
        .enumerated()
        .map { $0.offset % 5 == 0 && $0.offset > 0 ? " \($0.element)" : $0.element }
        .joined()
}
```

### Key Compromise

**If Device Identity Compromised:**

1. **Immediate Actions**:
   - Revoke identity on server
   - Delete identity from Keychain
   - Generate new identity
   - Re-establish all sessions

2. **Impact**:
   - ❌ Past messages: **MAY** be decrypted if attacker stored ciphertexts
   - ✅ Future messages: Protected (new identity, new sessions)
   - ✅ Active sessions: Attacker cannot impersonate (no access to ephemeral keys)

**If Session Keys Compromised:**

1. **Immediate Actions**:
   - End session
   - Delete session keys
   - Start new handshake

2. **Impact**:
   - ❌ Messages in compromised session: Decryptable
   - ✅ Other sessions: Unaffected (independent keys)
   - ✅ Future sessions: Protected (new handshake)

**Forward Secrecy Guarantee:**

Even if long-term identity key is compromised:
- ✅ Past handshakes remain secure (ephemeral keys destroyed)
- ✅ Past sessions remain secure (chain keys derived from ephemeral DHs)

### Denial of Service (DoS)

**Application-Layer DoS:**

C6P does not protect against:
- ❌ Message flooding (rate limiting required at app layer)
- ❌ Handshake spam (server must rate-limit handshake requests)
- ❌ Invalid message attacks (repeated decryption failures)

**Mitigation Strategies:**

```swift
// Rate limiting (example)
class RateLimiter {
    private var messageTimestamps: [Date] = []
    private let maxMessagesPerMinute = 60

    func checkRateLimit() throws {
        let now = Date()
        let oneMinuteAgo = now.addingTimeInterval(-60)

        // Remove old timestamps
        messageTimestamps.removeAll { $0 < oneMinuteAgo }

        guard messageTimestamps.count < maxMessagesPerMinute else {
            throw RateLimitError.exceeded
        }

        messageTimestamps.append(now)
    }
}

// Use before decrypt
do {
    try rateLimiter.checkRateLimit()
    let plaintext = try session.decrypt(message: encrypted)
    // Process message
} catch RateLimitError.exceeded {
    logger.warning("Rate limit exceeded for session \(sessionIdHex)")
    throw MessageError.rateLimitExceeded
}
```

---

## Secure Coding Practices

### Never Log Sensitive Data

```swift
// ❌ INSECURE: Logging private keys
logger.debug("Identity: \(identity.identity_priv_ed25519)")

// ✅ SECURE: Log only public identifiers
logger.debug("Device ID: \(utils_bytes_to_hex(data: identity.device_id))")

// ❌ INSECURE: Logging session keys
logger.debug("Session keys: \(sessionKeys)")

// ✅ SECURE: Log only session ID
logger.debug("Session ID: \(utils_bytes_to_hex(data: sessionKeys.session_id))")
```

### Input Validation

**Always validate inputs before passing to C6P:**

```swift
func validateSessionId(_ sessionId: [UInt8]) throws {
    guard sessionId.count == 8 else {
        throw ValidationError.invalidSessionId
    }
}

func validateDeviceId(_ deviceId: [UInt8]) throws {
    guard deviceId.count == 16 else {
        throw ValidationError.invalidDeviceId
    }
}

// Use before C6P calls
let sessionId: [UInt8] = /* from network */
try validateSessionId(sessionId)
let keys = try KeychainManager.getSessionKeys(for: sessionId)
```

### Error Propagation

**Never swallow cryptographic errors:**

```swift
// ❌ INSECURE: Silently ignoring errors
func decrypt(_ encrypted: EncryptedMessage) -> String? {
    do {
        return try session.decrypt(message: encrypted)
    } catch {
        return nil  // DANGER: Caller doesn't know decryption failed!
    }
}

// ✅ SECURE: Propagate errors
func decrypt(_ encrypted: EncryptedMessage) throws -> String {
    return try session.decrypt(message: encrypted)
}
```

### Secure Defaults

```swift
// ✅ Secure by default
struct SecurityConfig {
    var keychainProtection = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    var tlsMinVersion = TLSv13
    var enableCertificatePinning = false  // Optional, but available
    var logSensitiveData = false  // Never enabled by default
    var requireBiometricForIdentity = false  // Optional
}
```

---

## Audit and Compliance

### Security Audit Checklist

- [ ] All keys stored in iOS Keychain (not UserDefaults, files, or databases)
- [ ] Keychain protection level: `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [ ] No sensitive data logged (private keys, session keys, plaintexts)
- [ ] TLS 1.3+ for all network communication
- [ ] User fingerprint verification flow implemented
- [ ] Replay attack handling (log security events)
- [ ] Rate limiting for messages and handshakes
- [ ] Session cleanup when conversations end
- [ ] No hardcoded keys or secrets
- [ ] Third-party dependencies audited (UniFFI, Rust crates)

### Compliance

**GDPR (EU):**
- ✅ End-to-end encryption protects user privacy
- ✅ Keys stored locally on device (not on server)
- ⚠️ Must implement data export (Keychain → user file)
- ⚠️ Must implement data deletion (clear Keychain on account deletion)

**HIPAA (US Healthcare):**
- ✅ End-to-end encryption satisfies encryption requirements
- ⚠️ Must document cryptographic algorithms and key management
- ⚠️ Must implement audit logging (message sent/received events)

**SOC 2:**
- ✅ Encryption at rest (iOS Keychain) and in transit (TLS 1.3)
- ✅ Access controls (device-bound keys, optional biometric)
- ⚠️ Must implement audit logging and monitoring

---

## Incident Response

### Suspected Key Compromise

**Immediate Actions:**

1. **Revoke Identity**:
```swift
func emergencyRevoke() async throws {
    // Notify server to revoke identity
    try await api.revokeIdentity()

    // Delete from Keychain
    try KeychainManager.deleteDeviceIdentity()

    // Delete all session keys
    try KeychainManager.deleteAllSessions()

    // Generate new identity
    let newIdentity = try IdentityManager.ensureDeviceIdentity()

    // Re-establish sessions
    await reestablishAllSessions()
}
```

2. **Alert User**:
```swift
func showSecurityIncidentAlert() {
    let alert = UIAlertController(
        title: "Security Incident",
        message: "Your encryption keys have been reset for security. You will need to verify your identity with your contacts again.",
        preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "OK", style: .default))
    present(alert, animated: true)
}
```

3. **Log Incident**:
```swift
logger.critical("Security incident: Emergency key revocation triggered")
analytics.track(event: "security_incident", properties: [
    "type": "key_revocation",
    "timestamp": Date(),
    "device_id": try? IdentityManager.getDeviceIdHex()
])
```

### Security Event Logging

**Log these events for security monitoring:**

```swift
enum SecurityEvent {
    case replayDetected(sessionId: String)
    case decryptionFailed(sessionId: String, reason: String)
    case handshakeFailed(reason: String)
    case rateLimitExceeded(sessionId: String)
    case invalidMessage(sessionId: String)
}

func logSecurityEvent(_ event: SecurityEvent) {
    switch event {
    case .replayDetected(let sessionId):
        logger.warning("Replay attack detected", metadata: [
            "session_id": sessionId,
            "timestamp": "\(Date())"
        ])
        // Alert security team
        sendSecurityAlert(event)

    case .decryptionFailed(let sessionId, let reason):
        logger.error("Decryption failed", metadata: [
            "session_id": sessionId,
            "reason": reason
        ])

    case .handshakeFailed(let reason):
        logger.error("Handshake failed", metadata: [
            "reason": reason
        ])

    case .rateLimitExceeded(let sessionId):
        logger.warning("Rate limit exceeded", metadata: [
            "session_id": sessionId
        ])

    case .invalidMessage(let sessionId):
        logger.warning("Invalid message received", metadata: [
            "session_id": sessionId
        ])
    }
}
```

---

## Conclusion

Security is a **shared responsibility** between C6P (cryptographic core) and your application (key management, transport security, user experience).

**C6P Provides:**
✅ Strong end-to-end encryption
✅ Authenticated key exchange
✅ Forward secrecy
✅ Replay protection
✅ Constant-time operations

**Your Application Must:**
✅ Store keys securely (iOS Keychain)
✅ Use secure transport (TLS 1.3+)
✅ Validate user fingerprints
✅ Handle security events
✅ Implement rate limiting
✅ Never log sensitive data

Follow these guidelines to build a **production-grade, security-critical application** with C6P.

---

**Document Version**: 1.0
**Last Updated**: 2026-01-11
**Status**: Production Ready
**Security Contact**: security@convro.eu
