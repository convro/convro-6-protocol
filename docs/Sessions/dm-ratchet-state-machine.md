# DM Ratchet State Machine (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Per-stream ratchet state transitions, counter management, key derivation flow
**Applies to:** All C6P v1 DM sessions

---

## 0. Purpose

This document defines the **state machine** for the DM (Direct Message) symmetric ratchet used in C6P v1 sessions. It specifies:
- Per-stream state components
- State transitions on send/receive
- Counter advancement rules
- Chain key update protocol
- Error recovery and rollback semantics

---

## 1. State Components (Normative)

### 1.1 Per-Stream State

Each directional stream (`i2r` or `r2i`) maintains:

```rust
struct StreamState {
    stream_id: u8,              // 0x01 (i2r) or 0x02 (r2i)
    chain_key: [u8; 32],        // Current chain key (CK)
    send_counter: u64,          // Next counter to use for sending
    recv_expected: u64,         // Next expected in-order receive counter
    consumed: ConsumedSet,      // Set of received counters (for replay detection)
    state_version: u8,          // Always 1 for v1
}
```

### 1.2 Consumed Set

The `consumed` set tracks received message counters to prevent replay attacks:

- **Implementation**: Bitmap, hash set, or sorted array
- **Retention**: Keep counters within `recv_expected - SKIP_WINDOW` to `recv_expected + SKIP_WINDOW`
- **Skip window**: 2048 messages for DM (normative)
- **Pruning**: Remove counters below `recv_expected - SKIP_WINDOW` (no longer relevant)

---

## 2. Send State Machine (Normative)

### 2.1 Send Flow

**Preconditions:**
- Session is in `ACTIVE` state
- Stream state is initialized

**Steps:**

```
1. START
2. Load current state: (CK, send_counter)
3. Derive per-message material:
   - mk_material = HKDF-Expand(CK, "C6P_MESSAGE_KEY_V1" || counter, 80 bytes)
   - suite_key = mk_material[0..32]
   - nonce = derive_nonce(mk_material[32..64], counter, suite_id)
4. Construct AAD (63 bytes):
   - AAD = version || suite_id || session_binding || stream_id || counter || payload_type
5. Encrypt payload:
   - ciphertext = AEAD.Seal(suite_key, nonce, plaintext, AAD)
6. Advance chain key:
   - CK_next = HKDF-Expand(CK, "C6P_CHAIN_NEXT_V1" || counter, 32 bytes)
7. Persist atomically:
   - send_counter_next = send_counter + 1
   - CK = CK_next
8. Build wire envelope with counter, ciphertext, AAD components
9. DONE (send envelope)
```

**Failure modes:**
- **Encryption failure**: Abort, do not advance state
- **Persistence failure**: Abort, do not send envelope (fail-closed)

### 2.2 Counter Monotonicity

**Hard rule:** `send_counter` MUST be strictly increasing within a stream.

- **Concurrency**: If multiple threads send concurrently, serialize counter increments
- **Crash safety**: Persist counter before exposing envelope to network layer
- **No reuse**: Never reuse a counter (breaks AEAD security)

---

## 3. Receive State Machine (Normative)

### 3.1 Receive Flow

**Preconditions:**
- Session is in `ACTIVE` state
- Envelope passes wire-level validation (correct session_id, stream_id)

**Steps:**

```
1. START
2. Extract counter from envelope
3. Validate counter:
   a. NOT in consumed set (reject replay)
   b. Within skip-window: |counter - recv_expected| <= SKIP_WINDOW (2048)
   c. If counter < recv_expected - SKIP_WINDOW: reject (too old)
   d. If counter > recv_expected + SKIP_WINDOW: reject (too far ahead)
4. Derive CK for this counter:
   - If counter == recv_expected: use current CK
   - If counter > recv_expected: derive forward (see §3.2)
   - If counter < recv_expected: derive from cached/stored CK (skip-backward)
5. Derive per-message material (same as send):
   - mk_material = HKDF-Expand(CK_at_counter, "C6P_MESSAGE_KEY_V1" || counter, 80 bytes)
   - suite_key = mk_material[0..32]
   - nonce = derive_nonce(mk_material[32..64], counter, suite_id)
6. Reconstruct canonical AAD (63 bytes)
7. Decrypt:
   - plaintext = AEAD.Open(suite_key, nonce, ciphertext, AAD)
8. On success:
   a. Mark counter as consumed
   b. If counter == recv_expected: advance recv_expected to next unconsumed counter
   c. Prune old consumed entries (below recv_expected - SKIP_WINDOW)
   d. Persist state atomically
9. DONE (return plaintext)
```

**Failure modes:**
- **Counter replay**: Reject immediately, do not attempt decryption
- **Skip-window exceeded**: Reject, return `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`
- **AEAD open failure**: Reject, return `C6P.CRYPTO.DECRYPTION_FAILED`, do NOT advance state
- **Persistence failure**: Log error, reject message (fail-closed)

### 3.2 Skip-Forward Derivation

When `counter > recv_expected`, derive intermediate chain keys:

```
CK_at_counter = CK_current
for i in recv_expected..(counter + 1) {
    if i == counter {
        break
    }
    CK_at_counter = HKDF-Expand(CK_at_counter, "C6P_CHAIN_NEXT_V1" || i, 32 bytes)
}
```

**Optimization:** Cache intermediate `CK` values for recent counters to avoid re-derivation.

### 3.3 Advancing `recv_expected`

After successfully processing a message with `counter`:

```
if counter == recv_expected {
    recv_expected += 1
    while consumed.contains(recv_expected) {
        recv_expected += 1
    }
}
```

**Purpose:** `recv_expected` always points to the next missing in-order message.

---

## 4. State Persistence (Normative)

### 4.1 Atomicity Requirement

**Hard rule:** State updates MUST be atomic. Either:
- All of (`send_counter`, `CK`, `consumed`) persist together, OR
- None persist (rollback)

**Implementation strategies:**
- Write-ahead log (WAL)
- Transactional database (SQLite with `BEGIN IMMEDIATE`)
- Atomic file rename (write to temp, fsync, rename)

### 4.2 State Versioning

Include `state_version` field in persisted state:

```json
{
  "state_version": 1,
  "stream_id": 1,
  "chain_key": "base64url...",
  "send_counter": 42,
  "recv_expected": 38,
  "consumed": [35, 36, 39, 40, 41]
}
```

**Future-proofing:** If `state_version != 1`, reject load with `C6P.SESSION.INCOMPATIBLE_STATE_VERSION`.

---

## 5. Error Recovery (Normative)

### 5.1 Crash Recovery

**On app restart:**
1. Load persisted state for all active sessions
2. Verify integrity (check `state_version`, validate counter bounds)
3. Resume from last persisted counter

**Counter gaps:** Acceptable. The skip-window allows out-of-order messages to fill gaps.

### 5.2 Corrupted State

If state cannot be loaded (corrupted file, invalid format):
- Mark session as `CORRUPTED`
- Refuse to send/receive messages
- User MUST create new session (do not attempt auto-recovery)

### 5.3 Skip-Window Exhaustion

If a message arrives with `counter > recv_expected + SKIP_WINDOW`:
- Reject with `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`
- Log event for observability
- Do NOT advance state
- Sender should resend missing messages or renegotiate session

---

## 6. Concurrency Model (Normative)

### 6.1 Send Concurrency

**Rule:** At most one send operation per stream at a time.

**Enforcement:**
- Use mutex/lock around send state
- Serialize counter increments
- Concurrent sends to *different* streams are allowed (i2r vs r2i)

### 6.2 Receive Concurrency

**Rule:** Receives can process out-of-order concurrently IF:
- Counter validation is serialized (check consumed set atomically)
- State persistence is serialized

**Implementation:** Reader-writer lock with exclusive write for state updates.

---

## 7. State Machine Diagram

```
[SEND PATH]
  ┌───────────────┐
  │ Load CK + ctr │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Derive msg key│
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ AEAD Encrypt  │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Advance CK    │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Persist state │◄──── ATOMIC
  └───────┬───────┘
          │
          ▼
       [Send]

[RECEIVE PATH]
  ┌───────────────┐
  │ Validate ctr  │──► replay? ──► REJECT
  └───────┬───────┘
          │ OK
          ▼
  ┌───────────────┐
  │ Derive CK     │
  │ (skip if OOO) │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Derive msg key│
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ AEAD Decrypt  │──► fail? ──► REJECT
  └───────┬───────┘
          │ OK
          ▼
  ┌───────────────┐
  │ Mark consumed │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Advance recv  │
  │ if in-order   │
  └───────┬───────┘
          │
          ▼
  ┌───────────────┐
  │ Persist state │◄──── ATOMIC
  └───────┬───────┘
          │
          ▼
     [Plaintext]
```

---

## 8. Compliance Checklist

- [ ] Per-stream state includes: CK, send_counter, recv_expected, consumed
- [ ] Counters are strictly monotonic (no reuse)
- [ ] Replay detection enforced (consumed set)
- [ ] Skip-window bounded (2048 for DM)
- [ ] State persistence is atomic (all-or-nothing)
- [ ] AEAD failures abort without state change (fail-closed)
- [ ] Send concurrency serialized per stream
- [ ] Crash recovery loads last persisted state

---

## 9. Observability Hooks

Emit events at state transitions:
- `c6p.ratchet.send.start` (counter, stream_id)
- `c6p.ratchet.send.complete` (counter, latency_ms)
- `c6p.ratchet.receive.start` (counter, stream_id)
- `c6p.ratchet.receive.complete` (counter, latency_ms, out_of_order=bool)
- `c6p.ratchet.error` (error_code, counter, stream_id)

**Privacy:** Never log keys, nonces, or plaintext.

---

## 10. References

- Key derivation: `docs/crypto/c6p-key-schedule.md`
- Replay protection: `docs/crypto/c6p-replay-and-skip-window.md`
- Error codes: `docs/Sessions/sessions-error-codes.md`
- Storage contract: `docs/Sessions/session-storage-contract.md`
- Observability: `docs/Sessions/sessions-observability.md`

---
