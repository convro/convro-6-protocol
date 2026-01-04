# C6P Sessions Overview (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Session model, DM ratchet architecture, message types, and session lifecycle
**Applies to:** All C6P v1 implementations

---

## 0. Design Principles (Non-Negotiable)

1. **Per-message keys**: Every message has unique encryption key and nonce
2. **Forward secrecy**: Compromise of current state does not reveal past messages
3. **Bounded out-of-order**: Skip-window allows reordering without weakening replay protection
4. **Crash-safe state**: Counter and ratchet state persist atomically
5. **Fail-closed**: Any validation or decryption failure aborts operation

---

## 1. Session Model (Normative)

### 1.1 Session Definition

A **C6P session** represents a secure messaging channel between two devices.

**Components:**
- **Session ID** (8 bytes): Unique identifier for this session
- **Initiator Device** (16 bytes): Device that created the session
- **Responder Device** (16 bytes): Device that accepted the session
- **Root Key** (32 bytes): Master secret derived from handshake
- **Directional Streams**: Two independent ratchet chains (i2r, r2i)

### 1.2 Session Types (v1)

- **DM (Direct Message)**: 1-to-1 session between two devices
- **Group** (future): Multi-party session
- **Channel** (future): Broadcast-style session

**v1 scope:** DM only

---

## 2. DM Ratchet Architecture (Normative)

### 2.1 Directional Streams

Each DM session has two independent streams:

- **`i2r` (stream_id=0x01)**: Initiator → Responder
- **`r2i` (stream_id=0x02)**: Responder → Initiator

**Hard rule:** Streams are unidirectional; each has independent chain key and counter.

### 2.2 Per-Stream State

For each stream, maintain:
- **Chain Key** (`CK`): Current chain state (32 bytes)
- **Send Counter** (`send_counter`): Monotonic message counter (u64)
- **Receive Expected** (`recv_expected`): Next expected counter for in-order messages (u64)
- **Consumed Set**: Bitmap/set of received counters (for replay detection)

### 2.3 Ratchet Step (Per-Message)

**On send:**
1. Derive per-message material: `(mk_material, suite_key, nonce)` from `CK` + `counter`
2. Advance chain: `CK_next = derive_next_chain_key(CK, counter)`
3. Encrypt message with `suite_key` + `nonce` + AAD
4. Persist: `send_counter++`, `CK_next`
5. Send envelope

**On receive:**
1. Validate: counter not replayed, within skip-window
2. Derive per-message material from stored/derived `CK` for that `counter`
3. AEAD open with canonical AAD
4. On success: mark counter consumed, advance `recv_expected` (if in-order), persist state
5. On failure: reject, do not advance state

---

## 3. Session Lifecycle (Normative)

### 3.1 States

- **PENDING_HANDSHAKE**: Offer sent, waiting for accept
- **ACTIVE**: Handshake complete (KC verified), ready for messaging
- **SUSPENDED**: Paused (e.g., user archived conversation)
- **EXPIRED**: TTL exceeded without activity
- **TERMINATED**: Explicitly closed by user or policy

### 3.2 State Transitions

```
PENDING_HANDSHAKE ──→ ACTIVE (after KC verification)
ACTIVE ──→ SUSPENDED (user action)
ACTIVE ──→ EXPIRED (inactivity TTL)
ACTIVE ──→ TERMINATED (explicit close)
SUSPENDED ──→ ACTIVE (user resumes)
```

**Hard rule:** Once `TERMINATED`, session MUST NOT be reactivated (create new session instead).

---

## 4. Message Types (Registry-Bound)

### 4.1 DM Message Type

- **Type ID**: `0x01` (`dm`)
- **Scope**: 1-to-1 direct messaging
- **Ratchet**: Symmetric double-ratchet (per-stream chain keys)

### 4.2 Future Types (Placeholders)

- **Group** (`0x02`): Multi-party group messaging
- **Channel** (`0x03`): Broadcast channels
- **Control** (`0x10`): Control messages (typing indicators, read receipts)

**v1 limitation:** Only `dm` is normative and implemented.

---

## 5. Session Storage Contract (Normative Pointers)

Detailed storage requirements are in:
- `docs/Sessions/session-storage-contract.md`

Summary (MUST):
- Atomic persistence (counter + chain key + consumed set)
- Crash-safe (no partial updates)
- Versioned schema (`state_version=1`)
- Encrypted at rest (master key in Keychain/KeyStore)

---

## 6. Concurrency & Ordering (Normative Pointers)

Detailed rules are in:
- `docs/Sessions/concurrency-and-ordering.md`

Summary (MUST):
- Out-of-order messages accepted within skip-window (2048)
- Replay detection via consumed counter set
- Concurrent sends from same device MUST serialize counter increments

---

## 7. Error Codes (Normative Pointers)

Session-related errors are in:
- `docs/Sessions/sessions-error-codes.md`

Examples:
- `C6P.SESSION.NOT_FOUND`
- `C6P.SESSION.EXPIRED`
- `C6P.RATCHET.REPLAY_DETECTED`
- `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`

---

## 8. Observability (Normative Pointers)

Telemetry and metrics are in:
- `docs/Sessions/sessions-observability.md`

Summary (MUST):
- Emit events for: session creation, message send/receive, errors
- Metrics: message counts, latencies, error rates
- No secret leakage in logs

---

## 9. Security Properties (Normative)

### 9.1 Forward Secrecy

- Per-message keys derived from chain key
- Chain key updated after each message
- Compromise of current state does not reveal past message keys

### 9.2 Replay Resistance

- Counter uniqueness enforced per (session, stream)
- Duplicate counters rejected even if AEAD verifies
- Consumed set prevents replay within skip-window

### 9.3 Downgrade Resistance

- Suite ID bound to session at handshake
- AAD binds version, suite, stream, counter
- Protocol version changes require new session

---

## 10. Compliance Checklist (Fail-Closed)

- [ ] Per-message keys derived deterministically
- [ ] Counters monotonic and crash-safe
- [ ] Replay detection enforced (consumed set)
- [ ] Skip-window bounded (2048 for DM)
- [ ] Session state persisted atomically
- [ ] No secret leakage in logs or errors

---
