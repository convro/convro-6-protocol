# C6P AEAD & AAD (v1)

Status: **PRODUCTION — NORMATIVE**  
Scope: DM / Group / Channel message encryption; wire envelopes; deterministic nonce; AAD binding.  
Depends on:
- `docs/handshake/island-accord-crypto.md`
- `docs/crypto/c6p-key-schedule.md`
- `docs/crypto/c6p-crypto-registry.md`
- `docs/crypto/c6p-error-codes.md`

This document specifies:
1) AEAD suites and their canonical parameters  
2) Canonical AAD (Additional Authenticated Data) layout  
3) Deterministic nonce derivation (no nonce transmitted)  
4) Required failure behavior and security invariants

---

## 0. Non-negotiable Security Properties

### 0.1 Integrity and Binding
All ciphertexts MUST be authenticated with AEAD where AAD binds:
- protocol version
- suite id
- message type
- session id
- stream id
- message counter

If any AAD-bound field differs at decrypt time, authentication MUST fail closed.

### 0.2 Deterministic Nonce Safety
Nonce is deterministic (not transmitted). Therefore:
- nonce MUST be a deterministic function of (sessionId, streamId, counter, messageType[, suiteId])
- receiver MUST compute the same nonce from public envelope fields
- state MUST prevent counter rollback; otherwise nonce reuse becomes possible

### 0.3 Fail-Closed
Any decode, validation, or auth failure MUST stop processing and return canonical error codes.

### 0.4 No Secret Leakage
Implementations MUST NOT log:
- plaintext
- keys (root/chain/message)
- raw nonce bytes
- raw AAD bytes
- transcript bytes

Allowed to log:
- `errorCode`, `stage`, `module`
- `sessionId` (public), `deviceId` (public), `streamId`, `counter`
- lengths (expected/actual)

---

## 1. AEAD Suites (v1)

C6P v1 defines suite identifiers (wire-stable):

- `0x01` — **ChaCha20-Poly1305** (IETF, 96-bit nonce, 128-bit tag) — **MUST**
- `0x03` — **XChaCha20-Poly1305** (192-bit nonce, 128-bit tag) — **MAY**
- `0x02` — **AEGIS-128L** — **MAY** (optional; gated behind “supported suites” policy)

**Production baseline**: implementations MUST support suite `0x01`.  
Other suites MAY be offered but MUST NOT weaken security or introduce downgrade ambiguity.

### 1.1 Key length
All suites use a 32-byte message key `MK` (derived by Key Schedule).
- `MK` is never reused across distinct messages.

### 1.2 Tag handling
The authentication tag MUST be verified by the AEAD implementation.
Any tag mismatch MUST produce:
- `C6P.AEAD.AUTH_FAILED` (severity: SECURITY)

---

## 2. Wire Envelope vs Encryption Inputs

C6P wire envelope (DM example) includes:
- `version` (implicit in protocol; stored in AAD)
- `suite_id` (UInt8)
- `message_type` (UInt8)
- `session_id` (4 bytes, hex on JSON)
- `stream_id` (UInt8)
- `counter` (UInt64)
- `sealed` (ciphertext+tag only; nonce is not transmitted)

**Critical**: The nonce is not stored in the envelope; it is derived deterministically.

---

## 3. Canonical AAD Layout

AAD is a byte array constructed exactly as follows:

### 3.1 AAD v1 layout (DM / Group / Channel)

All integers are **big-endian**.

| Field | Size | Notes |
|------|------|------|
| `C6P_VERSION` | 1 | `0x01` |
| `suite_id` | 1 | AEAD suite identifier |
| `message_type` | 1 | DM=0x01, GROUP=0x02, CHANNEL=0x03, CONTROL=0x10 |
| `session_id` | 4 | raw bytes (UInt32 BE), not hex string |
| `stream_id` | 1 | i2r=0x01, r2i=0x02 |
| `counter` | 8 | UInt64 BE |
| `flags` | 1 | v1: MUST be `0x00` unless specified |
| `reserved` | 2 | MUST be `0x0000` in v1 (future-proofing) |

Total: **19 bytes**.

### 3.2 AAD construction rules
- Any deviation from layout MUST raise `C6P.AAD.INVALID_LAYOUT`.
- Unknown `suite_id` MUST raise `C6P.AEAD.UNSUPPORTED_SUITE`.
- Unknown `message_type` MUST raise `C6P.WIRE.MESSAGE_TYPE_INVALID`.
- Unknown `stream_id` MUST raise `C6P.WIRE.STREAM_ID_INVALID`.

---

## 4. Deterministic Nonce Derivation

### 4.1 Goal
Derive nonce without transmitting it, while guaranteeing:
- uniqueness per (message key, nonce)
- deterministic recomputation by receiver
- domain separation across message types and streams

### 4.2 Nonce derivation (v1)

We define a nonce derivation function:

`nonce = Trunc_N( SHA256( "C6P_NONCE_V1" || aad_bytes ) )`

Where:
- `"C6P_NONCE_V1"` is ASCII bytes
- `aad_bytes` is the canonical AAD from §3
- `Trunc_N` truncates to suite nonce length:
  - ChaCha20-Poly1305: **12 bytes**
  - XChaCha20-Poly1305: **24 bytes**
  - AEGIS-128L: **16 bytes** (if used)

**Rationale**:
- ties nonce to the same fields already integrity-bound
- prevents cross-stream reuse
- prevents cross-message-type reuse
- auditable and deterministic

### 4.3 Nonce safety requirements
Implementations MUST:
- persist send state atomically (sendCounter + chain state)
- reject counter rollback as `C6P.RATCHET.STATE_CORRUPT` (or force session reset)
- detect replays on receiver side (see ratchet spec; `C6P.RATCHET.REPLAY_DETECTED`)

---

## 5. Seal / Open Algorithms (Normative)

### 5.1 Encrypt (Seal)
Inputs:
- `MK` (32 bytes)
- `AAD` (19 bytes)
- `nonce` derived from AAD (§4)
- plaintext bytes

Output:
- `sealed = ciphertext || tag` (nonce NOT included)

Rules:
- If suite unsupported => `C6P.AEAD.UNSUPPORTED_SUITE`
- Any internal AEAD failure => `C6P.AEAD.SEAL_FAILED`

### 5.2 Decrypt (Open)
Inputs:
- `MK` (32 bytes)
- `AAD` (reconstructed from envelope)
- `nonce` derived from AAD (§4)
- `sealed = ciphertext || tag`

Rules:
- If auth fails => `C6P.AEAD.AUTH_FAILED` (SECURITY)
- If decode fails => `C6P.WIRE.INVALID_ENVELOPE` / `C6P.ENC.*`
- If AAD mismatch => treated as auth failure (do not leak details)

---

## 6. Error Codes (Binding)

Implementations MUST map failures to canonical codes:

- decode/format: `C6P.ENC.*`, `C6P.WIRE.*`
- AAD layout: `C6P.AAD.INVALID_LAYOUT`, `C6P.AAD.VERSION_MISMATCH`
- suite: `C6P.AEAD.UNSUPPORTED_SUITE`
- nonce: `C6P.AEAD.NONCE_INVALID`
- auth failure: `C6P.AEAD.AUTH_FAILED`
- state issues: `C6P.RATCHET.STATE_CORRUPT`, `C6P.RATCHET.REPLAY_DETECTED`

Reference: `docs/crypto/c6p-error-codes.md`

---

## 7. Interop Test Vectors (Required)

Each suite MUST provide deterministic test vectors:
- fixed session_id, stream_id, counter, message_type, suite_id
- fixed plaintext
- expected AAD bytes (hex)
- expected nonce (hex)
- expected sealed (hex or b64url)

Minimum required vectors:
- DM i2r counter=0,1
- DM r2i counter=0,1
- Group example (if implemented)
- CONTROL message (if implemented)

All vectors MUST be identical across Rust core and clients.

---

## 8. Auditor Notes (Why this is “signal-grade”)

- Nonce is derived from canonical AAD => deterministic, domain-separated, and auditable.
- AAD binds all routing-critical envelope fields => prevents splicing / confusion.
- Fail-closed + strict error mapping => safe triage and low leakage.
- Suite agility exists but baseline is one MUST suite for simplicity.

