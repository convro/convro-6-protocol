# C6P Crypto Error Codes (v1)

Status: **PRODUCTION — NORMATIVE**  
Applies to: **C6P v1**, **IslandAccord v1**, DM/Group ratchet, encoding/decoding, key schedule, AEAD/AAD.

This document defines the canonical error code registry for all crypto-critical paths in Convro/C6P.  
The goal is to provide **deterministic**, **auditable**, and **safe** failures across Rust core, Node backend, and clients.

---

## 0. Principles (Non-Negotiable)

### 0.1 Fail-Closed
If any validation, decoding, or invariant check fails, the operation **MUST** abort and return an error.

### 0.2 No Secret Leakage
Errors and logs **MUST NOT** include:
- private keys / shared secrets / root keys / chain keys / message keys
- plaintext
- raw nonces
- raw AAD bytes
- raw transcript bytes (except in test builds with explicit opt-in)

Allowed in logs:
- error code
- module + function
- field name
- expected length vs actual length
- public identifiers (deviceId, sessionId) if already known at that stage
- opaque correlation id / trace id
- peer user id only if already available to the caller context

### 0.3 Deterministic, Stable Codes
Error codes are **stable wire contracts** for internal observability and security triage.  
Once shipped, codes MUST NOT be repurposed.

### 0.4 Uniform Surfaces
All implementations (Rust/Node/Swift) MUST map internal errors to these codes.
If a platform-specific error occurs, it MUST be wrapped into the nearest canonical code.

---

## 1. Code Format

Canonical error code format:

- `C6P.<DOMAIN>.<NAME>`
- Domain is one of: `ENC`, `KEYS`, `KDF`, `AAD`, `AEAD`, `WIRE`, `RATCHET`, `HANDSHAKE`, `STORE`, `RNG`, `INVAR`

Examples:
- `C6P.ENC.INVALID_HEX`
- `C6P.AEAD.AUTH_FAILED`
- `C6P.RATCHET.COUNTER_MISMATCH`

---

## 2. Severity Levels

Each code includes severity:

- **INFO**: expected operational event; not security sensitive
- **WARN**: likely client misuse / desync; may be benign
- **ERROR**: operation failure requiring handling
- **SECURITY**: suspicious or potentially malicious input; should be monitored

---

## 3. Retry Policy (Canonical)

- **NO_RETRY**: deterministic failure; retry will not help
- **RETRY_SAFE**: retry may succeed without state changes (e.g., transient transport)
- **RETRY_AFTER_ROTATION**: retry only after key refresh / handshake
- **RETRY_AFTER_SYNC**: retry only after state resync (e.g., refetch session state)

---

## 4. Response Mapping

### 4.1 HTTP API
For crypto-related HTTP endpoints:
- Client-facing response SHOULD contain:
  - `ok: false`
  - `errorCode: <canonical code>`
  - `message: short human-safe text` (optional)
  - `retry: <policy>` (optional)

Backend MUST NOT return internal stack traces.

Suggested HTTP status mapping:
- 400: invalid input / decode / non-canonical
- 401/403: auth / access issues (non-crypto domain)
- 409: state conflict (e.g., ratchet desync requiring sync)
- 422: semantically invalid, but well-formed input (signature mismatch etc.)
- 500: internal invariant / unexpected failure

### 4.2 WebSocket / Push
For WS events:
- MUST include `errorCode`
- SHOULD include `sessionId` if known
- MUST NOT include secrets

### 4.3 Local (Client / Rust Core)
Expose:
- `errorCode`
- structured metadata: expectedLength, actualLength, fieldName, stage
- optional debug-only “cause” string gated behind compile flag

---

## 5. Logging Policy (NORMATIVE)

All crypto errors MUST emit a structured log record with:

- `code` (canonical)
- `severity`
- `module`
- `stage` (e.g., `decode`, `validate`, `kdf`, `open`)
- `sessionId` (if public at that stage)
- `deviceId` (if public at that stage)
- `peerDeviceId` (if present)
- `expectedLength`, `actualLength` (if relevant)
- `retryPolicy`
- `build` (prod/test)
- `traceId`

**Never log:** keys, plaintext, raw AAD, raw nonce, raw transcript.

---

## 6. Canonical Registry (v1)

### 6.1 Encoding / Canonicalization (`C6P.ENC.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.ENC.INVALID_HEX` | WARN | NO_RETRY | Hex decode fails | includes non-hex chars, odd length |
| `C6P.ENC.NON_CANONICAL_HEX` | WARN | NO_RETRY | Non-canonical hex input rejected | if you enforce strict lowercase input |
| `C6P.ENC.INVALID_B64URL` | WARN | NO_RETRY | base64url decode fails | invalid alphabet, padding present (if disallowed) |
| `C6P.ENC.INVALID_DECIMAL_U64` | WARN | NO_RETRY | decimal string → u64 parse fails | non-digit, negative, overflow |
| `C6P.ENC.LENGTH_MISMATCH` | WARN | NO_RETRY | decoded length != expected | include expected/actual |
| `C6P.ENC.MISSING_FIELD` | WARN | NO_RETRY | required field absent | reject early |
| `C6P.ENC.EXTRA_FIELD_DISALLOWED` | WARN | NO_RETRY | strict parser rejects unknown fields | only if endpoint is strict |

### 6.2 Randomness (`C6P.RNG.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.RNG.FAILURE` | ERROR | RETRY_SAFE | CSPRNG failure | OS entropy source failure |
| `C6P.RNG.INSUFFICIENT_ENTROPY` | ERROR | RETRY_SAFE | platform reports entropy issue | rare, but explicit |

### 6.3 Key Material & Validation (`C6P.KEYS.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.KEYS.INVALID_PUBLIC_KEY` | WARN | NO_RETRY | public key bytes invalid for curve | X25519/Ed25519 parse fails |
| `C6P.KEYS.INVALID_SIGNATURE` | SECURITY | NO_RETRY | signature verification fails | includes IslandAccord initiator signature, SPK signature |
| `C6P.KEYS.KEY_NOT_FOUND` | ERROR | RETRY_AFTER_SYNC | referenced key id missing | e.g., OTP id not found locally |
| `C6P.KEYS.KEY_ALREADY_CONSUMED` | WARN | RETRY_AFTER_SYNC | OTP referenced but already consumed | indicates race/desync/attack |
| `C6P.KEYS.KEY_STATE_INVALID` | ERROR | NO_RETRY | key store corruption detected | malformed stored bytes |
| `C6P.KEYS.PINNING_MISMATCH` | SECURITY | NO_RETRY | identity pin mismatch | TOFU/pinning violation |

### 6.4 KDF / Key Schedule (`C6P.KDF.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.KDF.INVALID_INFO` | ERROR | NO_RETRY | info string/layout invalid | programmer/config error |
| `C6P.KDF.DERIVATION_FAILED` | ERROR | NO_RETRY | HKDF fails unexpectedly | should not happen |
| `C6P.KDF.DOMAIN_SEPARATION_VIOLATION` | SECURITY | NO_RETRY | wrong label/version | prevents cross-protocol key reuse |
| `C6P.KDF.TRANSCRIPT_HASH_MISMATCH` | SECURITY | NO_RETRY | computed transcript != received | handshake tamper/desync |

### 6.5 AAD (`C6P.AAD.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.AAD.INVALID_LAYOUT` | ERROR | NO_RETRY | AAD construction violated spec | programmer error |
| `C6P.AAD.VERSION_MISMATCH` | WARN | NO_RETRY | version not supported | fail closed |
| `C6P.AAD.BINDING_MISMATCH` | SECURITY | NO_RETRY | AAD binds wrong session/device/stream | indicates forged envelope |

### 6.6 AEAD (`C6P.AEAD.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.AEAD.UNSUPPORTED_SUITE` | WARN | NO_RETRY | suite id unknown | negotiate/upgrade needed |
| `C6P.AEAD.NONCE_INVALID` | ERROR | NO_RETRY | nonce length/layout invalid | deterministic nonce rules violated |
| `C6P.AEAD.AUTH_FAILED` | SECURITY | NO_RETRY | authentication tag fails | wrong key/nonce/AAD, tamper likely |
| `C6P.AEAD.SEAL_FAILED` | ERROR | NO_RETRY | encryption failure | rare; treat as fatal |
| `C6P.AEAD.OPEN_FAILED` | SECURITY | NO_RETRY | decrypt failure (non-auth reason) | treat as auth failure unless proven otherwise |

### 6.7 Wire / Envelope (`C6P.WIRE.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.WIRE.INVALID_ENVELOPE` | WARN | NO_RETRY | malformed envelope fields | missing/invalid types |
| `C6P.WIRE.SESSION_ID_MISMATCH` | WARN | NO_RETRY | envelope sessionId != expected | drop |
| `C6P.WIRE.STREAM_ID_INVALID` | WARN | NO_RETRY | stream id invalid | drop |
| `C6P.WIRE.MESSAGE_TYPE_INVALID` | WARN | NO_RETRY | type invalid | drop |
| `C6P.WIRE.COUNTER_INVALID` | WARN | NO_RETRY | counter parse/format invalid | includes decimal string parse |

### 6.8 Ratchet / State (`C6P.RATCHET.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.RATCHET.COUNTER_MISMATCH` | WARN | RETRY_AFTER_SYNC | strict-order recv mismatch | in future: skip-window policy |
| `C6P.RATCHET.SKIP_WINDOW_EXCEEDED` | WARN | RETRY_AFTER_SYNC | message too far ahead | anti-DoS |
| `C6P.RATCHET.STATE_CORRUPT` | ERROR | NO_RETRY | stored chain state invalid | requires reset |
| `C6P.RATCHET.REPLAY_DETECTED` | SECURITY | NO_RETRY | repeated counter/nonce | drop + alert |
| `C6P.RATCHET.DH_RATCHET_REQUIRED` | WARN | RETRY_AFTER_ROTATION | state expects DH step | if your design adds DH ratchet later |

### 6.9 Handshake / IslandAccord (`C6P.HANDSHAKE.*`)

These MUST align with:
- `docs/handshake/island-accord-crypto.md`
- `docs/handshake/island-accord-wire.md`
- `docs/handshake/island-accord-state-machine.md`

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.HANDSHAKE.VERSION_UNSUPPORTED` | WARN | NO_RETRY | offer/accept version unknown | fail closed |
| `C6P.HANDSHAKE.SPK_SIGNATURE_INVALID` | SECURITY | NO_RETRY | SPK signature invalid | identity->SPK verification fails |
| `C6P.HANDSHAKE.INITIATOR_SIGNATURE_INVALID` | SECURITY | NO_RETRY | initiator signature invalid | “auditor candy” signature |
| `C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED` | SECURITY | NO_RETRY | key confirmation mismatch | prevents unknown-key-share |
| `C6P.HANDSHAKE.OTP_MISSING` | WARN | RETRY_AFTER_SYNC | offer references OTP not found | backend reservation race/attack |
| `C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH` | SECURITY | NO_RETRY | offer device ids inconsistent | prevents splicing |
| `C6P.HANDSHAKE.TRANSCRIPT_MISMATCH` | SECURITY | NO_RETRY | transcript differs | tamper/desync |
| `C6P.HANDSHAKE.STATE_VIOLATION` | WARN | NO_RETRY | state machine illegal transition | strict protocol |
| `C6P.HANDSHAKE.REPLAYED_OFFER` | SECURITY | NO_RETRY | same offer processed twice | drop + alert |

### 6.10 Storage / Persistence (`C6P.STORE.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.STORE.READ_FAILED` | ERROR | RETRY_SAFE | store unavailable transiently | e.g., IO/keychain |
| `C6P.STORE.WRITE_FAILED` | ERROR | RETRY_SAFE | failed to persist session | must not proceed partially |
| `C6P.STORE.ATOMICITY_VIOLATION` | ERROR | NO_RETRY | partial write detected | treat as corruption |
| `C6P.STORE.MIGRATION_REQUIRED` | WARN | RETRY_AFTER_SYNC | schema version mismatch | force upgrade/migrate |

### 6.11 Internal Invariants (`C6P.INVAR.*`)

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|------|
| `C6P.INVAR.UNREACHABLE` | ERROR | NO_RETRY | unreachable path hit | bug |
| `C6P.INVAR.ASSERTION_FAILED` | ERROR | NO_RETRY | invariant violated | bug, fail closed |
| `C6P.INVAR.CONFIG_INVALID` | ERROR | NO_RETRY | build-time config invalid | wrong suite/labels |

---

## 7. Required Structured Error Payload

All components SHOULD expose a structured error object:


{
  "ok": false,
  "errorCode": "C6P.AEAD.AUTH_FAILED",
  "severity": "SECURITY",
  "retry": "NO_RETRY",
  "stage": "open",
  "module": "dm/aead",
  "field": "sealed",
  "expectedLength": 32,
  "actualLength": 31,
  "sessionId": "a1b2c3d4",
  "deviceId": "0011223344556677",
  "traceId": "t-7c9e..."
}



Rules:

errorCode is REQUIRED.

traceId is REQUIRED for backend.

expectedLength/actualLength only when meaningful.

Never include secrets.

8. Monitoring & Security Triage (Auditor Notes)

Recommended high-signal alerts:

bursts of C6P.AEAD.AUTH_FAILED

C6P.HANDSHAKE.*_INVALID (signature, transcript, key confirmation)

C6P.RATCHET.REPLAY_DETECTED

repeated C6P.KEYS.KEY_ALREADY_CONSUMED (OTP abuse attempts)

Recommended dashboards:

errorCode frequency by endpoint / build / client version

per-peer failure rates (privacy-preserving aggregation)

ratchet desync incidence (counter mismatch / skip window exceeded)

9. Change Control

Adding a new code:

MUST add it to this registry

MUST document the mapping in the affected module’s README

MUST include tests that assert the mapping

Removing or repurposing a code: MUST NOT (requires version bump + migration plan).
