# C6P Replay Defense & Skip-Window (DM v1)

**Status:** Production / normative  
**Scope:** Replay prevention, out-of-order acceptance, skip-window semantics, bounded key caching, crash safety, and DoS controls for DM streams.  
**Depends on:**
- `docs/crypto/c6p-key-schedule.md` (chain evolution + per-counter key derivation)
- `docs/crypto/c6p-nonce-policy.md` (deterministic nonce contract)
- `docs/crypto/c6p-aead-and-aad.md` (AAD binding and AEAD open rules)
**Aligned with:** `docs/handshake/island-accord-state-machine.md` (session authority + invariant enforcement)

This document defines **exactly** how C6P v1 handles:
- out-of-order messages (network realities),
- duplicates/replays (active attacker realities),
- bounded storage and CPU (DoS realities),
- crash recovery (mobile realities),
without ever weakening cryptographic safety or accepting “minimum viable” behavior.

---

## 0. Security Objectives (Normative)

1. **Never accept replays** (same counter twice for a given `(session_id, stream_id)`).
2. **Allow bounded out-of-order delivery** within an explicit window.
3. **Never reuse `(key, nonce)`**; deterministic nonces remain safe under strict counter uniqueness enforcement.
4. **Be DoS-resistant**: bound CPU, memory, and storage per message and per session.
5. **Crash-safe correctness**: counters and caches remain consistent across restarts.
6. **Fail-closed**: any ambiguity or state corruption results in rejection and session tainting.

---

## 1. Definitions (Normative)

For each DM session, there are exactly two unidirectional streams:

- `stream_id = I2R` (initiator → responder)
- `stream_id = R2I` (responder → initiator)

Each stream has its own ratchet/chain and counter domain.

### 1.1 Counters
- `counter`: u64, BE64 in AAD
- **Uniqueness anchor:** For a fixed `(session_id, stream_id)`, each `counter` MUST be consumed at most once.

### 1.2 Expected counter
- `recv_expected`: the smallest not-yet-consumed counter, for that stream.
- Baseline delivery means the next valid message is `counter == recv_expected`.

### 1.3 Skip-window
C6P v1 defines a normative window:

- `SKIP_WINDOW_DM_V1 = 2048`

Meaning:
- out-of-order messages may be accepted if `counter <= recv_expected + SKIP_WINDOW_DM_V1`
- anything beyond that MUST be rejected

---

## 2. Normative Acceptance Rules (DM v1)

Given an incoming DM envelope with `(session_id, stream_id, counter, suite_id, message_type, sealed)`:

### 2.1 Structural checks (must happen first)
Implementation MUST reject if:
- unknown `suite_id`, `stream_id`, `message_type`
- malformed `sealed` (too short for tag, etc.)
- session is not in an active/accepted state per IslandAccord invariants
- envelope device/session binding does not match canonical session state

### 2.2 Replay check (must happen before AEAD acceptance)
Implementation MUST reject if:
- `counter` is already marked consumed for that `(session_id, stream_id)`

**Hard rule:** Replay rejection is unconditional (even if AEAD would verify).

### 2.3 Window bounds
Implementation MUST reject if:
- `counter < recv_expected - 0` (i.e., counter below expected and not known-unconsumed; in practice this is replay/old)
- `counter > recv_expected + SKIP_WINDOW_DM_V1`

This prevents “huge counter jump” DoS.

### 2.4 Decrypt attempt and commit ordering
For any candidate message:
1. derive keys for this `counter` under the ratchet rules (bounded; see §5)
2. compute nonce deterministically (see `c6p-nonce-policy.md`)
3. build AAD and call AEAD open (see `c6p-aead-and-aad.md`)
4. on AEAD success:
   - mark `counter` as consumed
   - deliver plaintext
   - advance `recv_expected` if possible (see §4.3)
5. on AEAD failure:
   - do NOT mark consumed
   - do NOT advance ratchet
   - emit security event

**Hard rule:** “Mark-consumed” MUST happen only after AEAD open succeeds.

---

## 3. State Per Stream (Normative)

For each `(session_id, stream_id)` the receiver maintains:

1. `recv_expected: u64`
2. `consumed_map`: a bounded data structure tracking which counters in `[recv_expected, recv_expected + window]` have been consumed out-of-order
3. `skipped_key_cache`: optional cache mapping counter → derived message key material (bounded)
4. `chain_state`: chain key + any ratchet sub-state required by `c6p-key-schedule.md`
5. `tainted: bool` (session-level or stream-level flag)

---

## 4. Data Structures (Production-grade, Normative)

### 4.1 Consumed bitmap (required)
Use a fixed-size bitmap of length `SKIP_WINDOW_DM_V1 + 1` (2049 bits) representing counters in:

- index `i = counter - recv_expected`
- valid range: `0..SKIP_WINDOW_DM_V1`

Where:
- bit=1 means “consumed”
- bit=0 means “not yet consumed”

This is:
- tiny in memory (~257 bytes)
- O(1) replay check for in-window counters
- deterministic and auditable

### 4.2 Optional: Skipped key cache (recommended)
A bounded map:
- key: `counter`
- value: `DerivedMsgKey` (exactly the per-message AEAD key material, never a chain key)

Cache size MUST be bounded:
- `max_skipped_keys = SKIP_WINDOW_DM_V1`

### 4.3 Advancing `recv_expected` (tight loop)
After consuming any counter, receiver MUST attempt to advance:

While bitmap bit 0 is set (meaning current expected counter is consumed):
- clear bit 0
- shift bitmap left by 1 (or logically slide window)
- increment `recv_expected`

This continues until the next expected counter is not yet consumed.

**Hard rule:** This “advance loop” MUST be correct and atomic relative to other receives on that stream.

---

## 5. Key Derivation Strategy (Normative)

### 5.1 Bounded derivation per message
To decrypt a message at `counter = c` where `c >= recv_expected`:
- receiver may need to derive intermediate message keys from `recv_expected` up to `c`

This is permitted only if:
- `c - recv_expected <= SKIP_WINDOW_DM_V1`

**Hard CPU bound:** The maximum number of derivation steps per received message is:
- `DERIVE_STEPS_MAX = SKIP_WINDOW_DM_V1 + 1` (2049)

If an implementation would exceed this due to internal inconsistency, it MUST reject and taint.

### 5.2 Derivation policy
Two compliant policies exist; choose one and enforce consistently:

**Policy A — Derive-and-cache (recommended):**
- derive message keys sequentially for `recv_expected..c`
- store derived keys for any counters that are skipped (not equal to `c`) into `skipped_key_cache`
- immediately use key for `c` to attempt AEAD open

**Policy B — Derive-on-demand with chain snapshots:**
- maintain periodic chain checkpoints (e.g., every 64 steps) to reduce recomputation
- still MUST remain within CPU and memory bounds
- more complex; use only if you have rigorous tests

**Hard rule:** Never cache chain keys long-term as “skipped” material. Cache only per-message derived keys.

### 5.3 Cache eviction (mandatory)
`skipped_key_cache` MUST evict entries when:
- `counter < recv_expected` (no longer in window)
- window slides past them
- cache size would exceed `max_skipped_keys`

Eviction MUST include secure zeroization (see §8).

---

## 6. DoS Controls (Normative)

Attackers (or malicious servers) can attempt:
- massive counter jumps,
- flood of random ciphertext at valid counters,
- repeated near-window edge messages to maximize derivation work.

C6P v1 MUST implement:

### 6.1 Strict window bound
Reject any message where:
- `counter > recv_expected + SKIP_WINDOW_DM_V1`

### 6.2 Rate limits per session (recommended, production-grade)
Maintain per-session counters:
- `failed_decrypts_last_60s`
- `replay_rejects_last_60s`
- `invalid_envelope_last_60s`

If thresholds are exceeded, implementation SHOULD:
- temporarily deprioritize that session (local scheduling)
- emit security telemetry event
- optionally taint session if pattern indicates active attack

### 6.3 Derivation work cap (mandatory)
If handling one message would require more than `DERIVE_STEPS_MAX` steps, reject.

### 6.4 Memory cap (mandatory)
Total memory allocated for a single session’s skipped caches MUST be bounded:
- `max_skipped_keys = 2048`
- `max_bytes_per_key_entry` MUST be fixed by suite (store only what’s needed)

---

## 7. Crash Safety & Persistence (Production-grade, Normative)

This is where many protocols quietly fail. C6P does not.

### 7.1 What MUST be persisted
For each active DM session and stream, persist atomically:
- `recv_expected`
- `consumed_bitmap` (current window state)
- `chain_state` (as defined by key schedule)
- `skipped_key_cache` (if enabled)

### 7.2 Atomicity model
Persistence MUST be crash-safe:
- Use a transactional store or write-ahead-log (WAL) semantics.
- A “commit” MUST either fully apply or not apply at all.

**Hard rule:** After restart, the receiver MUST NOT accept a message that would have been rejected pre-crash, and MUST NOT reject a message that would have been accepted pre-crash (within the same session state).

### 7.3 Encryption-at-rest (mandatory on client devices)
Any persisted material that can derive message keys (chain state, skipped keys) MUST be encrypted at rest with device-local secure storage (e.g., Keychain on iOS, OS keystore on desktop).

**Hard rule:** Never persist `mk_material` logs, nonces, or plaintexts.

### 7.4 Recovery procedure
On startup:
1. load session + stream state
2. validate invariants (bitmap size, bounds, chain consistency)
3. if any corruption detected:
   - mark session tainted
   - require session reset / re-handshake per policy
   - emit security event

---

## 8. Secure Erasure (Normative)

When keys are no longer needed, implementation MUST:
- overwrite key bytes in memory if language allows (Rust: `zeroize`)
- drop/clear caches deterministically
- delete persisted entries securely (best-effort on modern filesystems; encryption-at-rest is primary)

**Hard rule:** Eviction without erasure is not acceptable.

---

## 9. Concurrency Model (Normative)

Per stream, message processing MUST be serialized or protected by a lock.

Why:
- `recv_expected` and bitmap sliding are order-sensitive
- accepting two messages concurrently can cause double-consume or missed-advance bugs

**Hard rule:** For `(session_id, stream_id)`, there MUST be exactly one state-mutating decrypt pipeline at a time.

---

## 10. Session Tainting & Reset Policy (Normative)

Certain conditions require marking the session as tainted:
- repeated replay attempts
- inconsistent state on disk
- chain derivation invariants failing
- counter anomalies that suggest state rollback

### 10.1 Taint behavior
When tainted:
- receiver SHOULD reject further messages for that session
- receiver SHOULD trigger a controlled re-handshake / new session establishment
- receiver MUST emit a security event

### 10.2 Reset semantics
A reset results in:
- new IslandAccord session (new `session_id`)
- fresh root + chain keys
- old session state is archived or securely erased

---

## 11. Observability & Error Codes (Normative)

All rejects MUST map to stable error codes (see `docs/crypto/c6p-error-codes.md`) and produce structured events without leaking sensitive data.

Recommended event fields:
- `session_id`
- `stream_id`
- `counter`
- `reason_code`
- `window_expected`
- `window_limit` (= expected + window)
- `tainted` boolean

**Hard rule:** Do not log ciphertext, keys, nonces, mk_material, or raw device identifiers.

---

## 12. Compliance Checklist (Fail-Closed)

- [ ] Replay detection is enforced before AEAD acceptance.
- [ ] Window bound enforced exactly: `counter <= recv_expected + 2048`.
- [ ] Bitmap is used and slides correctly when advancing expected.
- [ ] Skipped key cache (if enabled) is bounded and zeroized on eviction.
- [ ] Derivation steps per message are bounded (≤ 2049).
- [ ] Stream processing is serialized (no concurrent state mutation).
- [ ] State persistence is atomic and encrypted at rest.
- [ ] Corruption triggers taint + reset policy.
- [ ] Logs are metadata-minimal and never include key/nonce material.

---

## Appendix A — Required Test Coverage

This repo MUST include tests validating:

1. **Replay rejection:** same `(session, stream, counter)` delivered twice → second rejected.
2. **Out-of-order accept:** deliver `expected+10` then later missing ones → all accepted within window.
3. **Window reject:** deliver `expected+2049` → rejected.
4. **Bitmap slide correctness:** consume counters out of order and ensure `recv_expected` advances to first gap.
5. **Crash recovery:** simulate crash after accepting message, confirm no double-accept or state rollback.
6. **DoS cap:** huge counter jump results in immediate reject without heavy derivation.
7. **Concurrency safety:** parallel receives cannot double-consume or corrupt bitmap.

All tests MUST run against the Rust reference implementation and MUST have deterministic vectors where applicable.

