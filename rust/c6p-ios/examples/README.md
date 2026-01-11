# C6P Swift Examples

Ready-to-use Swift code for integrating C6P into your iOS app.

## Files

### KeychainManager.swift

Production-ready Keychain manager for secure key storage.

**Features:**
- ✅ Device identity storage
- ✅ Session keys storage (per session_id)
- ✅ Secure protection level (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`)
- ✅ No iCloud sync (device-bound keys)
- ✅ Binary serialization format

**Usage:**

```swift
// Store device identity
let identity = try identity_generate_identity()
try KeychainManager.storeDeviceIdentity(identity)

// Retrieve device identity
let identity = try KeychainManager.getDeviceIdentity()

// Store session keys
try KeychainManager.storeSessionKeys(sessionKeys, for: sessionId)

// Retrieve session keys
let keys = try KeychainManager.getSessionKeys(for: sessionId)
```

### C6PManager.swift

High-level manager that orchestrates all C6P operations.

**Features:**
- ✅ Thread-safe (Swift actor)
- ✅ Session management (memory cache + Keychain storage)
- ✅ Simple API for handshake and messaging
- ✅ Automatic identity generation on first run

**Usage:**

```swift
// Initialize
let c6p = try await C6PManager()

// Get device ID and fingerprint
let deviceId = try await c6p.getDeviceIdHex()
let fingerprint = try await c6p.getFormattedFingerprint()

// Start handshake (initiator)
let offerBytes = try await c6p.startHandshake(with: peerDeviceId)
// Send offerBytes to peer...

// Accept handshake (responder)
let acceptBytes = try await c6p.acceptHandshake(offerBytes: offerBytes)
// Send acceptBytes back...

// Send encrypted message
let encrypted = try await c6p.sendMessage("Hello!", sessionId: sessionId)
// Send encrypted over network...

// Receive encrypted message
let plaintext = try await c6p.receiveMessage(encrypted, sessionId: sessionId)

// End session
try await c6p.endSession(sessionId: sessionId)
```

## Integration Steps

1. **Add to Xcode Project**:
   - Copy `KeychainManager.swift` and `C6PManager.swift` to your project
   - Ensure `c6p_ios.xcframework` and `c6p_ios.swift` are already added

2. **Customize for Your App**:
   - In `C6PManager.swift`, implement the `TODO` sections:
     - `fetchPrekeyBundle()` - fetch from your server
     - `getCurrentSPK()` / `getNextOTP()` - manage prekeys
     - Store peer device IDs and metadata

3. **Network Integration**:
   - Add methods to send/receive offer, accept, and encrypted messages
   - Use TLS 1.3+ for transport security

4. **Error Handling**:
   - Handle `C6pError.ReplayDetected` (security event)
   - Handle `KeychainError.itemNotFound` (expired session)
   - Log errors appropriately (without logging sensitive data)

## Example App

See `../docs/SWIFT_INTEGRATION.md` for a complete integration example with:
- Network layer implementation
- UI for fingerprint verification
- Rate limiting
- Security event logging

## Security Notes

**CRITICAL**:
- ✅ Keys stored in Keychain with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- ✅ No iCloud sync (`kSecAttrSynchronizable: false`)
- ✅ Binary format (not JSON) for serialization
- ⚠️ Never log private keys or session keys
- ⚠️ Use TLS 1.3+ for network transport
- ⚠️ Implement fingerprint verification in your UI

## License

Apache 2.0 / MIT (same as C6P)
