# C6P Rust Implementation

Production-grade Rust implementation of the Convro 6 Protocol (C6P) v1.

**Status:** 🚧 **Active Development** (Core crypto complete, handshake/identity/sessions in progress)

---

## Workspace Structure

```
rust/
├── c6p-crypto/          ✅ Core cryptographic primitives (COMPLETE)
├── c6p-handshake/       🚧 IslandAccord v1 handshake (SKELETON)
├── c6p-identity/        🚧 Device IDs & fingerprints (SKELETON)
├── c6p-sessions/        🚧 Session ratcheting & replay protection (SKELETON)
└── c6p-test-vectors/    ✅ Test vector generator (CRYPTO COMPLETE)
```

---

## Quick Start

### Prerequisites

- Rust 1.75.0+ (MSRV)
- Cargo (comes with Rust)

### Build All Crates

```bash
cd rust
cargo build --workspace
```

### Run Tests

```bash
# Run all tests
cargo test --workspace

# Run specific crate tests
cargo test --package c6p-crypto
cargo test --package c6p-handshake
cargo test --package c6p-identity
cargo test --package c6p-sessions
```

### Generate Test Vectors

```bash
# Generate all crypto test vectors
cargo run --bin c6p-gen-vectors -- --output ../docs --module crypto --verbose

# Generate specific module vectors
cargo run --bin c6p-gen-vectors -- --output ../docs --module handshake --verbose
cargo run --bin c6p-gen-vectors -- --output ../docs --module identity --verbose
cargo run --bin c6p-gen-vectors -- --output ../docs --module sessions --verbose
```

---

## Crate Descriptions

### c6p-crypto (✅ COMPLETE)

**Status:** Production-ready, 8/8 tests passing

Core cryptographic primitives for C6P v1:
- Key schedule (root, chain, per-message derivation)
- Deterministic nonce derivation
- Session binding computation
- Key confirmation (KC) computation

**Normative specification:** `docs/crypto/c6p-key-schedule.md`

**Key features:**
- Zero unsafe code
- Zeroization of sensitive keys
- Fail-closed design
- HKDF-SHA256 for all KDFs
- Normative KDF labels (MUST NOT be changed)

**Test vectors:** `docs/crypto/test-vectors/v1/`

### c6p-handshake (🚧 SKELETON)

**Status:** Module structure complete, implementation pending

IslandAccord v1 authenticated prekey handshake:
- 3DH / 4DH key agreement
- SPK signature verification
- Offer construction & parsing
- Accept construction & parsing
- Key confirmation exchange

**Normative specification:** `docs/handshake/island-accord-*.md`

**Modules:**
- `types`: Core types (SPK, OTP, X25519/Ed25519 keys)
- `crypto`: DH operations, signature verification
- `bundle`: Prekey bundle validation
- `offer`: Offer construction (initiator → responder)
- `accept`: Accept construction (responder → initiator)
- `error`: Typed error handling

### c6p-identity (🚧 SKELETON)

**Status:** Module structure complete, implementation pending

Identity management for C6P:
- Device ID derivation from Ed25519 public keys
- Human-readable fingerprints (Base32)
- Identity proof construction

**Normative specification:** `docs/identity/c6p-identity-format.md`

**Modules:**
- `device_id`: SHA-256 derivation
- `fingerprint`: Base32-encoded fingerprints
- `error`: Typed error handling

### c6p-sessions (🚧 SKELETON)

**Status:** Module structure complete, implementation pending

Session management with symmetric ratcheting:
- Per-message ratcheting (chain key advancement)
- Replay protection (skip-window bitmap)
- Out-of-order message handling
- Session state persistence

**Normative specification:** `docs/sessions/c6p-sessions-*.md`

**Modules:**
- `ratchet`: Send/receive ratcheting
- `replay`: Skip-window replay detection
- `state`: Session state management
- `error`: Typed error handling

### c6p-test-vectors (✅ CRYPTO COMPLETE)

**Status:** Crypto vectors complete, handshake/identity/sessions pending

Deterministic test vector generator for cross-implementation validation.

**Generated vectors:**
- ✅ `key_schedule_vectors.json` (2 vectors)
- ✅ `nonce_vectors.json` (3 vectors)
- ✅ `aad_vectors.json` (4 vectors)
- ✅ `aead_vectors_chacha20poly1305.json` (3 vectors)
- ✅ `aead_vectors_xchacha20poly1305.json` (2 vectors)
- 🚧 `island_accord_offer_vectors.json` (pending)
- 🚧 `device_id_vectors.json` (pending)
- 🚧 `ratchet_send_vectors.json` (pending)

---

## Development

### Code Quality

```bash
# Format code
cargo fmt --all

# Lint code
cargo clippy --workspace --all-targets -- -D warnings

# Build documentation
cargo doc --workspace --no-deps --document-private-items --open
```

### Security

```bash
# Audit dependencies for security vulnerabilities
cargo install cargo-audit
cargo audit
```

### Coverage

```bash
# Generate code coverage report
cargo install cargo-llvm-cov
cargo llvm-cov --workspace --html
open target/llvm-cov/html/index.html
```

---

## CI/CD

GitHub Actions workflow runs on every push/PR:

**Jobs:**
1. **build-and-test**: Cross-platform builds (Linux, macOS, Windows)
2. **clippy**: Linting with Clippy
3. **rustfmt**: Code formatting check
4. **validate-vectors**: Test vector generation & validation
5. **security-audit**: Dependency security audit
6. **docs**: Documentation build
7. **coverage**: Code coverage report (PRs only)

**Status badge:** [![Rust CI/CD](../../actions/workflows/rust-ci.yml/badge.svg)](../../actions/workflows/rust-ci.yml)

---

## Architecture Principles

1. **No Unsafe Code:** All crates use `#![forbid(unsafe_code)]`
2. **Zeroization:** Sensitive keys are zeroized on drop
3. **Fail-Closed:** Unknown inputs cause panics (fail-closed design)
4. **Normative Labels:** KDF labels MUST match specification exactly
5. **Deterministic:** Test vectors use fixed seeds for reproducibility
6. **Type Safety:** Newtype pattern for all identifiers
7. **Error Handling:** Typed errors with `thiserror`
8. **Documentation:** Comprehensive doc comments with spec references

---

## Dependencies

All dependencies are workspace-managed in `rust/Cargo.toml`:

**Cryptographic:**
- `sha2`: SHA-256 hashing
- `hkdf`: HKDF-Extract/Expand (RFC 5869)
- `hmac`: HMAC-SHA256
- `chacha20poly1305`: AEAD encryption
- `x25519-dalek`: X25519 Diffie-Hellman
- `ed25519-dalek`: Ed25519 signatures

**Utilities:**
- `serde`, `serde_json`: Serialization
- `hex`, `base64`: Encoding
- `zeroize`: Secure memory clearing
- `thiserror`: Error handling
- `anyhow`: Error context
- `chrono`: Timestamps

---

## License

Apache 2.0 / MIT (dual license)

---

## Contributing

See root repository README for contribution guidelines.

---

## Specification

All implementations MUST match the normative specifications in `docs/`:
- `docs/crypto/`: Cryptographic primitives
- `docs/handshake/`: IslandAccord v1 handshake
- `docs/identity/`: Identity management
- `docs/sessions/`: Session management

**Critical:** Test vectors in `docs/*/test-vectors/v1/` are canonical. All implementations MUST pass these vectors bit-for-bit. CI MUST fail on any mismatch.
