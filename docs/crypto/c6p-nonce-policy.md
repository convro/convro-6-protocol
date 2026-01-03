# C6P Nonce Policy (v1)

**Status:** Production / normative  
**Scope:** Deterministic nonce derivation contract, injectivity requirements, replay/duplicate handling, and violation response.  
**Depends on:** `docs/crypto/c6p-key-schedule.md` (message-key derivation + nonce derivation primitives).  
**Aligned with:** `docs/crypto/c6p-aead-and-aad.md` (AAD binds suite/type/stream/counter/session) and `docs/handshake/*` (IslandAccord session binding and canonical device/session identifiers).  
**Applies to:** DM encryption in C6P v1 and any future envelope types that reuse the same `(suite_id, stream_id, counter)` message key schedule.

This document is **normative**. Implementations MUST follow it exactly. Any detected violation MUST trigger fail-closed behavior.

---

## 0. Design Principle (Normative)

C6P uses **deterministic nonces**. This is permitted because:

1. AEAD keys are **per-message** (derived per `(session, stream, counter, type, suite)`).
2. Nonce derivation is **injective over the same message context** and is bound to the message key schedule.
3. Replays/duplicates are **explicitly detected** and rejected.

**Hard rule:** Under no circumstance may the same `(suite_key, nonce)` pair be reused. Implementations MUST make reuse impossible by construction and MUST detect any attempted replay.

---

## 1. Terms & Identifiers (Normative)

- `session_id`: 4 bytes (hex8 on wire)
- `initiator_device_id`: 16 bytes
- `responder_device_id`: 16 bytes
- `session_binding`: 32 bytes, computed as defined in `c6p-aead-and-aad.md` §5
- `message_type`: u8 (registry-defined)
- `stream_id`: u8 (registry-defined; directional)
- `suite_id`: u8 (AEAD suite)
- `counter`: u64 (BE64)
- `mk_material`: canonical per-message material derived by key schedule
- `suite_key`: suite-sized AEAD key derived from `mk_material`
- `nonce`: suite-sized nonce derived from `mk_material` and context (this document)

**Hard rule:** Any size mismatch MUST be rejected before deriving keys/nonces or attempting AEAD.

---

## 2. Nonce Construction Contract (Normative)

### 2.1 Canonical Inputs

Nonce derivation for a message MUST bind to this exact context:

- `C6P_VERSION` (u8, v1 = 0x01)
- `suite_id` (u8)
- `message_type` (u8)
- `stream_id` (u8)
- `counter` (u64 BE)
- `session_id` (4 bytes)
- `session_binding` (32 bytes)
- `mk_material` (canonical output from key schedule)

### 2.2 Domain Separation

Nonce derivation MUST use a dedicated domain label distinct from all other derivations:

- `NONCE_LABEL_V1 = "C6P_NONCE_V1"` (ASCII bytes)

**Hard rule:** This label MUST NOT be reused for message keys, chain keys, root keys, or AAD.

### 2.3 Derivation Function

Nonce bytes MUST be derived using HKDF-SHA256 expand with a strictly defined info block:

- `prk = HKDF-Extract(salt = session_binding, IKM = mk_material)`
- `info = NONCE_LABEL_V1 || U8(C6P_VERSION) || U8(suite_id) || U8(message_type) || U8(stream_id) || session_id || BE64(counter)`
- `nonce = HKDF-Expand(prk, info, L = nonce_len_for_suite(suite_id))`

Where `nonce_len_for_suite` is:
- ChaCha20-Poly1305: 12
- XChaCha20-Poly1305: 24
- AEGIS-128L: 16

**Hard rule:** The nonce MUST be exactly the suite nonce length. Any other length MUST be rejected as an internal invariant failure.

---

## 3. Injectivity Requirement (Normative)

For a fixed `session_binding`, the nonce derivation MUST be injective over:

`(suite_id, message_type, stream_id, counter)`

Meaning: if any of these fields differ, the derived nonce MUST differ (with overwhelming probability; HKDF-SHA256 is treated as a PRF for this purpose).

**Operational requirement:** Implementations MUST NOT permit two different envelopes within the same session and stream to share the same `(counter, suite_id, message_type)` tuple.

**Hard rule:** `counter` is the uniqueness anchor. If an attacker replays an envelope with the same counter, the receiver MUST detect it and reject before AEAD acceptance.

---

## 4. Counter Uniqueness & Replay Handling (Normative)

### 4.1 Sender requirements

For each `(session_id, stream_id)`:

- Sender MUST maintain `send_counter` starting at 0.
- For each outgoing message:
  - use current `send_counter`
  - derive `suite_key` and `nonce` for that counter
  - increment `send_counter` by 1 after successful seal and persistence

**Hard rule:** Sender MUST persist counter progression before considering the message “sent” (crash-safe monotonicity).

### 4.2 Receiver requirements

For each `(session_id, stream_id)` receiver MUST maintain:

- `recv_counter_expected` (baseline)
- `consumed_counters` set or equivalent structure (for skip-window mode)

Receiver MUST reject:
- any `counter` already in `consumed_counters`
- any `counter` below `recv_counter_expected - window` (if skip-window enabled)
- any `counter` that violates the DM state machine invariants

**Hard rule:** If AEAD open succeeds but the counter is detected as replay (already consumed), the message MUST be rejected anyway (replay MUST NOT be accepted even if ciphertext verifies).

---

## 5. Skip-Window Policy (Normative)

C6P DM supports a skip-window for out-of-order delivery.

### 5.1 Window size
The window size MUST be fixed and declared as a protocol parameter:

- `SKIP_WINDOW_DM_V1 = 2048` (default normative value for v1)

If deployments choose a different value, it MUST be explicitly stated in a config appendix and MUST be used consistently on both ends. (Auditors expect a fixed canonical default; this is it.)

### 5.2 Handling out-of-order counters
When receiving `counter = c`:

- If `c == recv_counter_expected`: accept (subject to AEAD success), then advance expected.
- If `c > recv_counter_expected` and `c <= recv_counter_expected + SKIP_WINDOW_DM_V1`:
  - derive message keys for all intermediate counters as required by the ratchet schedule
  - cache derived keys for missing counters (bounded by window)
  - accept `c` if AEAD succeeds
  - mark `c` consumed
  - do not mark missing counters consumed
- If `c > recv_counter_expected + SKIP_WINDOW_DM_V1`: reject

**Hard rule:** Cached skipped keys MUST be erased immediately once used, and MUST be bounded by window size. No unbounded caching.

---

## 6. Failure & Violation Response (Normative)

Nonce safety is not “best effort.” Violations are treated as active attack indicators or severe state corruption.

### 6.1 Violation classes
A nonce-policy violation includes (non-exhaustive):
- duplicate `counter` seen for `(session_id, stream_id)`
- counter regression by sender (local invariant failure)
- malformed envelope sizes that prevent deterministic derivation
- internal mismatch: derived nonce length != suite nonce length
- session_binding mismatch to canonical session state

### 6.2 Mandatory response
On violation:
1. MUST reject the message (fail-closed).
2. MUST emit a structured security event (see `docs/crypto/c6p-error-codes.md` and `docs/handshake/island-accord-observability.md`).
3. MUST NOT advance ratchet/counters.
4. SHOULD mark the session as **tainted** until a clean re-handshake / session reset policy is applied.

**Hard rule:** The implementation MUST NOT “try to recover” by guessing counters or accepting duplicates. Recovery is explicit and controlled (session reset).

---

## 7. Logging & Privacy (Normative)

Nonce violations must be observable to operators without leaking plaintext.

Logs MUST be metadata-minimal:
- include: `session_id`, `stream_id`, `counter`, `suite_id`, `message_type`, and an error code
- MUST NOT include: plaintext, ciphertext, derived keys, derived nonces, `mk_material`, or raw device IDs (use hashed identifiers if needed)

**Hard rule:** Never log nonces or keys.

---

## 8. Interop Contract (Rust/Swift) (Normative)

To prevent implementation drift across languages:

- Rust is the reference implementation for nonce derivation.
- Any non-Rust implementation MUST be verified against deterministic test vectors generated by Rust.

**Hard rule:** A build MUST fail CI if any vector mismatches.

---

## 9. Test Vectors (Normative Requirement)

This repo MUST include deterministic nonce-policy test vectors at:

- `docs/crypto/test-vectors/nonce/`

Each vector MUST include:
- `session_id_hex`
- `initiator_device_id_hex`
- `responder_device_id_hex`
- `session_binding_hex`
- `suite_id`
- `message_type`
- `stream_id`
- `counter`
- `mk_material_b64u`
- `nonce_b64u`

Vectors MUST cover:
1. multiple suites (0x01, 0x02, 0x03)
2. multiple message types
3. both stream directions
4. boundary counters: 0, 1, 2, 2^32-1 (if allowed), 2^64-1 (rejection policy if overflow)
5. skip-window scenario: accept inside window, reject outside window

---

## 10. Compliance Checklist (Fail-Closed)

- [ ] Nonce is derived via HKDF-SHA256 with `NONCE_LABEL_V1`.
- [ ] Nonce binds `suite_id`, `message_type`, `stream_id`, `counter`, `session_id`, `session_binding`, `mk_material`.
- [ ] Nonce length matches suite exactly (12/24/16).
- [ ] Duplicate counters are rejected (even if AEAD verifies).
- [ ] Skip-window is bounded and enforced.
- [ ] No logging of keys/nonces/mk_material.
- [ ] CI validates nonce vectors against Rust reference outputs.

