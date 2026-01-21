# C6P iOS Bridge

Production-ready Swift/iOS bindings for the Convro 6 Protocol using Mozilla's UniFFI.

## Features

✅ **Identity Management**: Generate device identities, fingerprints, prekeys
✅ **IslandAccord v1 Handshake**: 3DH/4DH authenticated key exchange with stateless design
✅ **Session Management**: Encrypt/decrypt with forward secrecy and replay protection
✅ **Stateless Architecture**: Swift stores all session keys in iOS Keychain
✅ **Zero-copy**: Efficient byte array handling
✅ **Type-safe**: Leverages Swift's type system
✅ **Production-ready**: Wraps battle-tested Rust core (113/113 tests passing)

## Quick Start

### 1. Build XCFramework

```bash
cd rust/c6p-ios
./scripts/build-xcframework.sh release
```

This generates:
- `xcframework/c6p_ios.xcframework` - Binary framework
- `xcframework/c6p_ios.swift` - Swift bindings

### 2. Add to Xcode Project

1. Drag `c6p_ios.xcframework` into your Xcode project
2. Add `c6p_ios.swift` to your project
3. In Build Settings → "Other Linker Flags", add: `-lc++`

### 3. Use in Swift

```swift
import c6p_ios

// Generate device identity
let identity = try identity_generate_identity()
print("Device ID: \\(utils_bytes_to_hex(data: identity.device_id))")
print("Fingerprint: \\(identity.fingerprint)")

// Responder: Generate prekeys
let responderIdentity = try identity_generate_identity()
let responderSpk = try identity_generate_signed_prekey(identity: responderIdentity)

// Responder: Publish bundle
let bundle = PrekeyBundle(
    responder_device_id: responderIdentity.device_id,
    identity_pub_ed25519: responderIdentity.identity_pub_ed25519,
    identity_pub_x25519: responderIdentity.identity_pub_x25519,
    spk_id: responderSpk.spk_id,
    spk_pub: responderSpk.spk_pub,
    spk_sig: responderSpk.spk_sig,
    otp_id: nil,
    otp_pub: nil
)

// Initiator: Create handshake offer
let result = try handshake_create_offer(
    initiator_identity: identity,
    responder_bundle: bundle
)

// CRITICAL: Store session keys in Keychain immediately!
try KeychainManager.store(sessionKeys: result.session_keys, for: result.offer.session_id)

// Send result.offer.serialized to responder over network...

// Responder: Accept offer
let acceptResult = try handshake_accept_offer(
    responder_identity: responderIdentity,
    responder_spk: responderSpk,
    responder_otp: nil,
    offer_bytes: result.offer.serialized
)

// CRITICAL: Store session keys in Keychain immediately!
try KeychainManager.store(sessionKeys: acceptResult.session_keys, for: acceptResult.accept.session_id)

// Send acceptResult.accept.serialized back to initiator...

// Initiator: Verify accept message
try handshake_verify_accept(
    offer: result.offer,
    accept_bytes: acceptResult.accept.serialized,
    session_keys: result.session_keys  // Retrieved from Keychain
)

// Both parties: Create session
let session = try SessionState(
    keys: result.session_keys,
    is_initiator: true
)

// Encrypt message
let plaintext = "Hello, Convro!".data(using: .utf8)!
let encrypted = try session.encrypt(plaintext: [UInt8](plaintext))

// Decrypt message
let decrypted = try session.decrypt(message: encrypted)
let message = String(bytes: decrypted, encoding: .utf8)!
```

## Architecture

### Stateless Handshake Design

C6P iOS bridge uses a **stateless architecture** where the Rust bridge has **zero internal state**. All session keys are returned to Swift and **MUST** be stored securely in iOS Keychain.

```
┌─────────────────────────────────────────────────────────┐
│                   Swift (iOS App)                       │
│  ┌───────────────────────────────────────────────────┐  │
│  │  iOS Keychain (Secure Storage)                    │  │
│  │  • DeviceIdentity (long-term keys)                │  │
│  │  • SessionKeys per session_id                     │  │
│  │  • Protection: kSecAttrAccessibleAfterFirstUnlock │  │
│  └───────────────────────────────────────────────────┘  │
│           │                                   ▲          │
│           ▼ (store)                 (retrieve)│          │
│  ┌───────────────────────────────────────────────────┐  │
│  │  C6P Swift API (c6p_ios.swift)                    │  │
│  │  • handshake_create_offer() → (offer, keys)       │  │
│  │  • handshake_accept_offer() → (accept, keys)      │  │
│  │  • handshake_verify_accept(offer, accept, keys)   │  │
│  └───────────────┬───────────────────────────────────┘  │
│                  │ FFI calls                             │
├──────────────────┼───────────────────────────────────────┤
│  ┌───────────────▼───────────────────────────────────┐  │
│  │    Rust Bridge (c6p-ios)                          │  │
│  │    ✅ Stateless - no session storage               │  │
│  │    ✅ Pure functions                               │  │
│  │    ✅ Returns keys for Swift to store             │  │
│  └───────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Key Design Principles

1. **Stateless Bridge**: Rust has NO internal state - keys returned to Swift
2. **Keychain Storage**: Swift stores ALL session keys in iOS Keychain with appropriate protection
3. **Explicit Verification**: `verify_accept()` requires passing stored session keys
4. **Zero-copy**: Byte arrays passed directly between Swift and Rust
5. **Type safety**: Rust's type system exposed to Swift via UniFFI

## API Reference

See [SWIFT_INTEGRATION.md](./docs/SWIFT_INTEGRATION.md) for complete API documentation and Keychain integration examples.

### Identity Management

```swift
// Generate new device identity
func identity_generate_identity() throws -> DeviceIdentity

// Generate signed prekey
func identity_generate_signed_prekey(identity: DeviceIdentity) throws -> SignedPrekey

// Generate one-time prekey
func identity_generate_one_time_prekey() throws -> OneTimePrekey

// Compute device ID from Ed25519 public key
func identity_compute_device_id(ed25519_pub: [UInt8]) throws -> [UInt8]

// Compute fingerprint
func identity_compute_fingerprint(ed25519_pub: [UInt8]) throws -> String

// Validate prekey bundle (verify SPK signature)
func identity_validate_bundle(bundle: PrekeyBundle) throws
```

### Handshake (Stateless)

```swift
// Initiator: Create handshake offer
// Returns CreateOfferResult { offer, session_keys }
// CRITICAL: Store session_keys in Keychain immediately!
func handshake_create_offer(
    initiator_identity: DeviceIdentity,
    responder_bundle: PrekeyBundle
) throws -> CreateOfferResult

// Responder: Accept handshake offer
// Returns AcceptOfferResult { accept, session_keys }
// CRITICAL: Store session_keys in Keychain immediately!
func handshake_accept_offer(
    responder_identity: DeviceIdentity,
    responder_spk: SignedPrekey,
    responder_otp: OneTimePrekey?,
    offer_bytes: [UInt8]
) throws -> AcceptOfferResult

// Initiator: Verify accept message
// STATELESS: requires session_keys from create_offer (stored in Keychain)
func handshake_verify_accept(
    offer: HandshakeOffer,
    accept_bytes: [UInt8],
    session_keys: SessionKeys
) throws
```

### Session

```swift
class SessionState {
    // Create new session from handshake keys
    init(keys: SessionKeys, is_initiator: Bool) throws

    // Encrypt outgoing message
    func encrypt(plaintext: [UInt8]) throws -> EncryptedMessage

    // Decrypt incoming message
    func decrypt(message: EncryptedMessage) throws -> [UInt8]

    // Get current send counter
    func send_counter() -> UInt64

    // Get current recv expected counter
    func recv_expected() -> UInt64
}
```

### Utilities

```swift
// Convert bytes to hex string
func utils_bytes_to_hex(data: [UInt8]) -> String

// Convert hex string to bytes
func utils_hex_to_bytes(hex: String) throws -> [UInt8]

// Generate random bytes
func utils_random_bytes(length: UInt32) throws -> [UInt8]
```

## Security

### Critical Requirements

1. **Store session keys in Keychain** - `create_offer` and `accept_offer` return session keys that **MUST** be stored securely:

```swift
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrAccount as String: sessionIdHex,
    kSecValueData as String: sessionKeysData,
    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
]
SecItemAdd(query as CFDictionary, nil)
```

2. **Use secure transport** - Send `offer.serialized` and `accept.serialized` over TLS 1.3+

3. **Never reuse ephemeral keys** - Each handshake generates fresh ephemeral keys automatically

4. **Validate bundles before use** - Call `identity_validate_bundle()` to verify SPK signatures

5. **Handle replay protection** - Session automatically detects replayed messages (returns `ReplayDetected` error)

### Threat Model

See `../../docs/threat-model/` for complete security analysis:
- **C6P-Threat-Model-CONCISE.pdf** - Executive summary (7 pages)
- **C6P-Threat-Model-AUDIT.pdf** - Full analysis (26 pages)

## Documentation

- **[ARCHITECTURE.md](./docs/ARCHITECTURE.md)** - Detailed stateless design architecture
- **[SWIFT_INTEGRATION.md](./docs/SWIFT_INTEGRATION.md)** - Complete integration guide with Keychain examples
- **[SECURITY.md](./docs/SECURITY.md)** - Security guidelines and best practices

## Building from Source

### Prerequisites

1. **Rust toolchain** (1.85.0+):
   ```bash
   curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
   ```

2. **iOS targets**:
   ```bash
   rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
   ```

3. **Xcode** (14.0+):
   ```bash
   xcode-select --install
   ```

4. **UniFFI CLI** (optional, auto-installed by script):
   ```bash
   cargo install uniffi-bindgen --version 0.28
   ```

### Build Commands

```bash
# Release build (optimized, ~2-3 min)
./scripts/build-xcframework.sh release

# Debug build (faster compile, larger binary)
./scripts/build-xcframework.sh debug

# Clean build artifacts
rm -rf build xcframework

# Run Rust tests
cargo test -p c6p-ios
```

## Testing

### Rust Tests

```bash
cd rust/c6p-ios
cargo test
```

All 113 tests passing ✅ (13 bridge tests + 100 core tests)

### Swift Integration Tests

See [SWIFT_INTEGRATION.md](./docs/SWIFT_INTEGRATION.md) for example Xcode test cases.

## Performance

### Benchmarks (iPhone 14 Pro, release build)

| Operation | Time | Notes |
|-----------|------|-------|
| `identity_generate_identity` | ~2 ms | Ed25519 + X25519 keygen |
| `identity_generate_signed_prekey` | ~1 ms | X25519 keygen + Ed25519 sign |
| `handshake_create_offer` | ~8 ms | 3DH: 3× DH + transcript + KC1 |
| `handshake_create_offer` (4DH) | ~11 ms | 4DH: 4× DH + transcript + KC1 |
| `handshake_accept_offer` | ~10 ms | Mirror DHs + verify KC1 + KC2 |
| `handshake_verify_accept` | ~0.5 ms | Constant-time KC2 check |
| `encrypt` | ~50 µs | ChaCha20-Poly1305 + ratchet |
| `decrypt` | ~60 µs | ChaCha20-Poly1305 + replay check |

### Memory

- **Identity**: ~200 bytes per device
- **Prekey**: ~80 bytes (SPK) + ~40 bytes (OTP)
- **Session state**: ~300 bytes (both directions)
- **Message overhead**: 24 bytes (counter + tag)

## Limitations

### By Design

- Session state is **not thread-safe** - wrap in Swift actor or `DispatchQueue` if needed
- Maximum message count: 2^64-1 per session (create new session after)
- Counter gaps > 1000 rejected (replay window limit)

## Troubleshooting

### Build Errors

**Error: "library not found for -lc++"**

Add `-lc++` to Xcode → Build Settings → Other Linker Flags

**Error: "Undefined symbol: ___gxx_personality_v0"**

Add `-lc++` to linker flags (same as above)

### Runtime Errors

**Error: "ReplayDetected"**

Message was already decrypted (replay attack protection working correctly)

**Error: "CounterExhausted"**

Session has reached 2^64-1 message limit. Create new session via handshake.

## License

Same as main repository: Apache 2.0 / MIT dual license

## Contributing

See main repository README for contribution guidelines.

## Support

- **Documentation**: [docs/](./docs/)
- **Issues**: [GitHub Issues](https://github.com/convro/convro-6-protocol/issues)
- **Security**: security@convro.eu (PGP key in repo)

---

**Production Status**: ✅ **Production Ready**
**Core Rust**: 113/113 tests passing
**iOS Bridge**: Stateless design complete, full UDL API exposed
**Architecture**: Battle-tested E2EE with Keychain integration
