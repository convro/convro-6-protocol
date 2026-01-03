# C6P Replay & Skip-Window (v1)

**Status:** Production / normative  
**Scope:** Replay rejection rules, consumed-counter tracking, out-of-order acceptance via bounded skip-window, cache semantics, crash-safety, and mandatory violation response for DM (v1).  
**Registry authority:** `docs/crypto/c6p-crypto-registry.md` (stream IDs, message types, suite IDs)  
**Encoding authority:** `docs/crypto/c6p-encoding-and-canonicalization.md` (strict parsing; `counter` wire string → `u64` → `BE64`; `session_id` hex16 → 8B)  
**AEAD/AAD authority:** `docs/crypto/c6p-aead-and-aad.md` (AAD binds session/type/stream/suite/counter + `session_binding`)  
**Key schedule authority:** `docs/crypto/c6p-key-schedule.md` (per-counter `mk_material`, `suite_key`, deterministic nonce; chain progression)  
**Nonce policy authority:** `docs/crypto/c6p-nonce-policy.md` (nonce derivation + violation response)

This document is **normative**. Implementations MUST follow it exactly. “Best effort” acceptance is forbidden.

---

## 0. Goals (Normative)

1. **Reject replays deterministically** for DM messages.
2. Support **bounded out-of-order delivery** without weakening replay guarantees.
3. Ensure **crash-safe monotonicity** for send counters and **idempotent receive behavior**.
4. Provide **audit-grade determinism** with explicit invariants and observable failure modes.

---

## 1. Model & Definitions (Normative)

### 1.1 Session and streams
For each DM session there are two directional streams (registry-defined):

- `stream_id = 0x01` (`i2r`) Initiator → Responder  
- `stream_id = 0x02` (`r2i`) Responder → Initiator  

Replay/ordering is tracked **per (session_id, stream_id)**.

### 1.2 Counter
- `counter` is `u64`.
- Canonical bytes: `BE64(counter)` (8 bytes).
- Wire transport: decimal string (strict, digits-only), per Encoding doc.

### 1.3 Envelope uniqueness tuple
A DM message is uniquely identified (for replay purposes) by:

`(session_id, stream_id, counter)`

**Hard rule:** A receiver MUST NOT accept two messages with the same tuple, even if AEAD verifies.

### 1.4 Consumed vs. seen
- **Consumed counter**: message authenticated and accepted (AEAD open succeeded, and state committed).
- **Seen (unauthenticated)**: observed but not accepted (failed validation, AEAD failure, outside window).

**Hard rule:** Only **consumed** counters affect replay state.

---

## 2. Normative Parameters

### 2.1 Skip-window size (DM v1)
`SKIP_WINDOW_DM_V1 = 2048`

This is the maximum allowed forward distance from `recv_expected` for out-of-order acceptance.

### 2.2 Minimum tracking requirement
Receiver MUST track, per `(session_id, stream_id)`:
- `recv_expected: u64` (next expected counter for in-order delivery)
- `consumed_set` (bounded structure for consumed counters in a sliding range)
- optional `cached_keys` / `cached_state` (bounded) if you pre-derive per-counter material for skipped counters

---

## 3. Baseline Rule Set (Normative)

### 3.1 In-order acceptance
Given an incoming DM envelope with `counter = c`:

- If `c == recv_expected`:
  - attempt AEAD open (after strict validation)
  - on success:
    - mark `c` consumed
    - advance `recv_expected = recv_expected + 1`
    - optionally fast-forward `recv_expected` over contiguous already-consumed counters (if tracked)
  - on failure:
    - reject
    - do not mark consumed
    - do not advance `recv_expected`

### 3.2 Out-of-order acceptance (within window)
- If `c > recv_expected` and `c <= recv_expected + SKIP_WINDOW_DM_V1`:
  - MAY accept out-of-order if:
    - strict validation passes
    - counter not consumed
    - AEAD open succeeds
  - on success:
    - mark `c` consumed
    - `recv_expected` MUST NOT jump forward unless contiguous counters are already consumed
  - on failure:
    - reject; do not mark consumed

### 3.3 Outside window rejection (too far ahead)
- If `c > recv_expected + SKIP_WINDOW_DM_V1`:
  - reject with `REPLAY_COUNTER_TOO_FAR`
  - do not mark consumed

### 3.4 Below-window rejection (too old) — **LOCKED**
If `c < recv_expected`:

- If `c` is already consumed: reject with `REPLAY_DUPLICATE_COUNTER`
- Else (not in consumed_set because it fell out of window or never tracked): reject with **`REPLAY_COUNTER_BELOW_WINDOW`**

**Hard rule:** Anything below `recv_expected` that is not already known-consumed is **always rejected**. No recovery attempts, no “maybe accept”.

### 3.5 Duplicate/replay rejection (consumed)
- If `c` is marked consumed:
  - reject with `REPLAY_DUPLICATE_COUNTER`
  - MUST NOT attempt to “re-open” or “re-commit”
  - MUST NOT advance any state

**Hard rule:** Replay MUST be rejected even if ciphertext verifies.

---

## 4. Strict Validation Order (Fail-Closed) (Normative)

Receiver MUST apply checks in this order:

1. **Wire/encoding validation (strict)**:
   - `session_id`: hex16 → 8 bytes
   - `counter`: decimal string → u64
   - `suite_id`, `stream_id`, `message_type`: known u8 registry values
   - `sealed`: base64url (no padding), decoded length ≥ 16
2. **Session context validation**:
   - session exists and is in a state that allows message processing
   - stream direction consistent with local role (initiator/responder mapping)
3. **Replay/window checks (pre-AEAD)**:
   - if `c < recv_expected`: reject (as §3.4)
   - if consumed: reject
   - if outside window (too far): reject
4. **Key/nonce derivation** for `(session, stream, counter, suite, type)` per Key Schedule + Nonce Policy
5. **AAD reconstruction** (envelope fields + canonical `session_binding`) per AEAD/AAD
6. **AEAD open**
7. **Atomic commit**:
   - mark `c` consumed
   - update ratchet/chain state for `c`
   - update `recv_expected` if appropriate
   - persist all relevant state atomically (see §6.1)

**Hard rule:** If AEAD open fails, nothing is committed.

---

## 5. Data Structures (Normative Requirements)

Implementations MAY choose internal representations, but MUST satisfy these properties.

### 5.1 Consumed counter tracking (bounded)
Receiver MUST maintain a bounded “consumed” representation that supports:

- efficient lookup `is_consumed(c)`
- marking `c` consumed for `c ∈ [recv_expected, recv_expected + SKIP_WINDOW_DM_V1]`
- window sliding when `recv_expected` advances (dropping old range)
- bounded memory (must not grow unbounded)

Recommended: bitmap window anchored at `recv_expected` (ring buffer of bits) + optional sparse overflow guard.

### 5.2 Key/state caching (optional, bounded)
If implementation pre-derives/caches per-counter material for skipped counters, it MUST:

- bound cache size to `SKIP_WINDOW_DM_V1`
- erase cached material immediately after use
- never cache plaintext/ciphertext
- never log keys/nonces/mk_material

**Hard rule:** Cache MUST NOT enable acceptance outside the window.

---

## 6. Storage Contract & Crash Safety (Normative)

### 6.1 Atomic persistence — **LOCKED**
Receiver MUST persist the following **atomically as one state record** per `(session_id, stream_id)`:

- `recv_expected`
- `consumed_set` (bitmap/range representation)
- any ratchet/chain state needed to derive keys for future counters
- any bounded cached state (optional; if present it must be consistent)

**Hard rule:** No partial writes. Either the whole update commits or none.

### 6.2 Versioning — **LOCKED**
The stored record MUST include:

- `state_version = 1` (u32 or u16; wire-independent, storage-internal)

Future changes MUST bump `state_version` and provide migration rules.

### 6.3 Idempotency across crashes
- If crash occurs **after** commit: message MUST be treated as already processed and replay rejected.
- If crash occurs **before** commit: message may be retried and accepted once (subject to normal validation).

---

## 7. Interaction with Ratchet/Chain State (Normative)

### 7.1 Commit semantics
On successful AEAD open for counter `c`:
- mark consumed for `c`
- commit ratchet/chain progression for `c` exactly once
- persist state atomically (see §6)

### 7.2 Out-of-order and derivation
Out-of-order acceptance is supported because derivations are deterministic per counter. Implementation may derive intermediate per-counter material up to the window.

**Hard rule:** Intermediate derivation MUST be bounded by the window and MUST not be persisted in a way that breaks determinism.

### 7.3 No advance on failure
On any failure (encoding, replay check, key derivation error, AEAD open fail):
- MUST NOT mark consumed
- MUST NOT advance `recv_expected`
- MUST NOT advance ratchet/chain state
- MUST NOT taint state by partial caching beyond policy

---

## 8. Sender-Side Requirements (Normative)

### 8.1 Monotonic send counter
Sender MUST maintain `send_counter` per `(session_id, stream_id)`:
- starts at 0
- increments by exactly 1 per successfully sealed+persisted outgoing message

### 8.2 Crash-safe persistence
Sender MUST persist updated send state before considering the message “sent”.

**Hard rule:** After crash/restart, sender MUST NOT reuse a previously used counter.

### 8.3 Retry semantics
If transport retries the same message:
- sender MUST resend the exact same envelope (same counter, same sealed)
- receiver accepts at most once; subsequent retries are replay

---

## 9. Taint Policy (Normative) — **LOCKED**

Replay/ordering violations are treated as strong attack/corruption signals.

### 9.1 What counts as a taintable violation
At minimum, these events increment `violation_count` for the session:

- `REPLAY_DUPLICATE_COUNTER`
- `REPLAY_COUNTER_TOO_FAR`
- `REPLAY_COUNTER_BELOW_WINDOW`

(Encoding errors may be logged but do not necessarily indicate session corruption; you may treat them separately.)

### 9.2 Threshold and response — **LOCKED**
- After **two (2)** taintable violations within the same session, the session MUST transition to `TAINTED`.

When `TAINTED`:
1. MUST reject all further DM payload messages for this session with `SESSION_TAINTED`.
2. MUST emit a structured security event `REPLAY_SESSION_TAINTED` (no secrets).
3. Recovery MUST be explicit: require a clean re-handshake/session reset policy (outside this doc’s scope, but MUST exist in Sessions state machine docs).

**Hard rule:** No silent auto-recovery.

---

## 10. Observability (Normative)

Implementations MUST emit structured events (no secrets) for:

- `REPLAY_DUPLICATE_COUNTER`
- `REPLAY_COUNTER_TOO_FAR`
- `REPLAY_COUNTER_BELOW_WINDOW`
- `SESSION_TAINTED` / `REPLAY_SESSION_TAINTED`
- `AEAD_OPEN_FAILED` (no ciphertext)
- strict parsing errors (`ENC_*`) per Encoding doc

Logs MUST include:
- `session_id` (hex16)
- `stream_id`
- `counter`
- `suite_id`
- `message_type`
- error code

Logs MUST NOT include:
- plaintext/ciphertext
- keys/nonces/mk_material
- raw device IDs (hash if needed)

---

## 11. Test Vectors & Conformance Tests (Normative)

Vectors MUST exist under your canonical plan:

- `docs/Sessions/test-vectors/v1/skip_window_vectors.json`
- `docs/Sessions/test-vectors/v1/replay_reject_vectors.json`

### 11.1 Required conformance cases (minimum)
1. **In-order accept**: 0,1,2,3
2. **Out-of-order accept inside window**:
   - receive 5 first (accept), later 3 (accept), 4 (accept), ensure `recv_expected` advances only when contiguous
3. **Too far ahead reject**:
   - `recv_expected=0`, receive `counter=SKIP_WINDOW+1` → `REPLAY_COUNTER_TOO_FAR`
4. **Below window reject (locked rule)**:
   - accept counters 0..10, window slides; later receive a counter `< recv_expected` not in consumed_set → `REPLAY_COUNTER_BELOW_WINDOW`
5. **Duplicate reject**:
   - accept counter 7; receive counter 7 again → `REPLAY_DUPLICATE_COUNTER`
6. **Taint after 2 violations (locked)**:
   - trigger two taintable violations → session becomes `TAINTED`, further messages rejected with `SESSION_TAINTED`
7. **AEAD fail does not consume**:
   - deliver malformed sealed for valid counter; ensure counter not marked consumed and can later accept correct message for that counter (if within window and policy allows resend exact counter)

**Hard rule:** CI MUST fail if any implementation disagrees with the reference behavior.

---

## 12. Compliance Checklist (Fail-Closed)

- [ ] Replay uniqueness enforced per `(session_id, stream_id, counter)`.
- [ ] Skip-window enforced with `SKIP_WINDOW_DM_V1 = 2048`.
- [ ] `counter < recv_expected` always rejected (`REPLAY_COUNTER_BELOW_WINDOW`) unless already consumed (then duplicate).
- [ ] Duplicate counters rejected even if AEAD verifies.
- [ ] Outside-window counters rejected before AEAD.
- [ ] No ratchet/counter advancement on any failure.
- [ ] Receiver state (`recv_expected`, `consumed_set`, ratchet) persisted atomically and versioned (`state_version=1`).
- [ ] Taint policy enforced: **2** taintable violations → `TAINTED` → reject until re-handshake/reset.
- [ ] Observability events emitted without leaking secrets.
- [ ] CI validates replay/skip-window vectors against the reference behavior.

---

