# C6P Nonce Policy (v1)

**Status:** Production / normative  
**Scope:** Deterministic nonce derivation contract, injectivity requirements, replay/duplicate handling, skip-window rules (DM), and mandatory violation response.  
**Registry authority:** `docs/crypto/c6p-crypto-registry.md` (suite IDs, stream IDs, message types, fixed sizes)  
**Encoding authority:** `docs/crypto/c6p-encoding-and-canonicalization.md` (strict wire decoding; counter wire string → u64 → BE64)  
**AEAD/AAD authority:** `docs/crypto/c6p-aead-and-aad.md` (session_binding + canonical AAD layout)  
**Key schedule authority:** `docs/crypto/c6p-key-schedule.md` (per-message mk_material + suite_key + deterministic nonce derivation)

This document is **normative**. Implementations MUST follow it exactly. Any detected violation MUST trigger fail-closed behavior.

---

## 0. Design Principle (Normative)

C6P uses **deterministic nonces**. This is permitted because:

1. AEAD keys are **per-message** (derived per `(session, stream, counter, type, suite)`).
2. Nonce derivation is **context-bound** and treated as injective over the message uniqueness tuple.
3. Replays/duplicates are **explicitly detected** and rejected.

**Hard rule:** Under no circumstance may the same `(suite_key, nonce)` pair be reused. Implementations MUST make reuse impossible by construction and MUST detect any attempted replay.

---

## 1. Terms & Identifiers (Normative, registry-aligned)

### 1.1 Fixed-size identifiers (canonical bytes)
- `session_id`: **8 bytes** (wire: hex16)
- `initiator_device_id`: **16 bytes** (wire: hex32)
- `responder_device_id`: **16 bytes** (wire: hex32)

### 1.2 Session binding
`session_binding`: 32 bytes, computed as defined in AEAD/AAD:

`session_binding = SHA-256( "C6P_BIND_V1" || session_id(8) || initiator_device_id(16) || responder_device_id(16) )`

**Hard rule:** `session_binding` MUST be computed from canonical, locally trusted session state (not attacker-provided envelope fields).

### 1.3 Message context fields
- `C6P_VERSION`: u8, v1 = `0x01`
- `suite_id`: u8 (see §2)
- `message_type`: u8 (see §2)
- `stream_id`: u8 (see §2)
- `counter`: u64 canonical bytes `BE64(counter)` (wire: decimal string)

### 1.4 Key schedule artifacts
- `mk_material`: 32 bytes (per-message key material)
- `suite_key`: suite-sized AEAD key (32/32/16)
- `nonce`: suite-sized nonce (12/24/16)

**Hard rule:** Any size mismatch MUST be rejected before deriving keys/nonces or attempting AEAD.

---

## 2. Registry Bindings (Normative)

### 2.1 Suite IDs (wire-stable)
- `0x01` = ChaCha20-Poly1305 (`key=32`, `nonce=12`, `tag=16`) **REQUIRED**
- `0x02` = XChaCha20-Poly1305 (`key=32`, `nonce=24`, `tag=16`) OPTIONAL (v1)
- `0x03` = AEGIS-128L (`key=16`, `nonce=16`, `tag=16`) OPTIONAL (v1, gated)

**Hard rule:** Unknown `suite_id` MUST be rejected.

### 2.2 Stream IDs (wire-stable)
- `0x01` = `i2r` (initiator → responder)
- `0x02` = `r2i` (responder → initiator)

### 2.3 Message Types (wire-stable)
- `0x01` = `dm`
- `0x02` = `group`
- `0x03` = `channel`
- `0x10` = `control`

**Hard rule:** Unknown `stream_id` or `message_type` MUST be rejected.

---

## 3. Nonce Construction Contract (Normative)

### 3.1 Canonical inputs (must bind exactly)
Nonce derivation for a message MUST bind to:

- `C6P_VERSION` (u8)
- `suite_id` (u8)
- `message_type` (u8)
- `stream_id` (u8)
- `session_id` (8 bytes)
- `counter` (u64 BE64, 8 bytes)
- `session_binding` (32 bytes)
- `mk_material` (32 bytes)

### 3.2 Domain separation label (required)
Nonce derivation MUST use a dedicated domain label distinct from all other derivations:

- `NONCE_LABEL_V1 = "C6P_NONCE_V1"` (ASCII bytes)

**Hard rule:** This label MUST NOT be reused for message keys, chain keys, root keys, AAD, or key confirmation.

### 3.3 Derivation function (byte-exact; canonical)
Nonce bytes MUST be derived using HKDF-SHA256 expand with a strictly defined info block:

1) PRK:

`prk_nonce = HKDF-Extract( salt = session_binding, ikm = mk_material )`

2) Info:

`info = "C6P_NONCE_V1"`
`|| U8(C6P_VERSION)`
`|| U8(suite_id)`
`|| U8(message_type)`
`|| U8(stream_id)`
`|| session_id(8)`
`|| BE64(counter)`

3) Expand:

`nonce = HKDF-Expand( prk_nonce, info, L = nonce_len_for_suite(suite_id) )`

Where:
- `nonce_len_for_suite(0x01) = 12`
- `nonce_len_for_suite(0x02) = 24`
- `nonce_len_for_suite(0x03) = 16`

**Hard rule:** The nonce MUST be exactly the suite nonce length. Any other length MUST be treated as an internal invariant failure and MUST abort.

### 3.4 Consistency with AEAD/AAD (required)
The same `(suite_id, message_type, stream_id, session_id, counter)` tuple used for nonce derivation MUST be the tuple AAD binds (see AEAD/AAD doc). Implementations MUST not “relabel” or “reinterpret” these fields between layers.

---

## 4. Injectivity Requirement (Normative)

For a fixed session (fixed `session_binding` and `session_id`), nonce derivation MUST be injective (as a PRF binding) over:

`(suite_id, message_type, stream_id, counter)`

Operationally:
- Implementations MUST NOT permit two different accepted envelopes within the same session/stream to share the same `counter`.
- Implementations MUST NOT accept an envelope whose `(suite_id, message_type, stream_id)` differs from the expected session/channel context unless the protocol explicitly allows such multiplexing and the state machine accounts for it.

**Hard rule:** `counter` is the uniqueness anchor per `(session_id, stream_id)` for DM. Replays MUST be rejected even if ciphertext verifies.

---

## 5. Counter Uniqueness & Replay Handling (Normative)

### 5.1 Sender requirements (DM baseline)
For each `(session_id, stream_id)`:

- Sender MUST maintain `send_counter` starting at `0`.
- For each outgoing message:
  1. Use current `send_counter` as `counter`.
  2. Derive `mk_material`, `suite_key`, and `nonce` for that `(counter, suite_id, message_type, stream_id)`.
  3. Perform AEAD seal using canonical AAD (see AEAD/AAD doc).
  4. Persist ratchet + counter progression **crash-safely**.
  5. Increment `send_counter` by `1` only after successful persistence.

**Hard rule:** Sender MUST NOT reuse a counter after crash/restart. Counter persistence is mandatory.

### 5.2 Receiver requirements (DM baseline)
For each `(session_id, stream_id)` receiver MUST maintain:
- `recv_counter_expected` (u64)
- a bounded structure for out-of-order acceptance (skip-window) that prevents duplicate acceptance:
  - `consumed_counters` (or bitmap/range set)
  - `cached_keys` for skipped counters (bounded)

Receiver MUST reject:
- any `counter` already marked consumed
- any `counter` outside the allowed window (see §6)
- any message that violates session state machine invariants (e.g., wrong stream direction for role)

**Hard rule:** If AEAD open succeeds but the counter is detected as replay (already consumed), the message MUST still be rejected. Replay MUST NOT be accepted even if ciphertext verifies.

---

## 6. Skip-Window Policy (DM) (Normative)

C6P DM supports out-of-order delivery via a bounded skip-window.

### 6.1 Window size (normative default)
`SKIP_WINDOW_DM_V1 = 2048`

If deployments choose a different value, it MUST be explicitly declared in a deployment/config appendix and MUST be used consistently by both ends.

### 6.2 Handling out-of-order counters
On receive with `counter = c`:

- If `c == recv_counter_expected`:
  - derive keys for `c`
  - attempt AEAD open
  - on success:
    - mark `c` consumed
    - advance `recv_counter_expected = recv_counter_expected + 1`
    - opportunistically advance further if cached keys for subsequent counters are already consumed (optional)
  - on failure:
    - reject; do not advance; do not mark consumed

- If `c > recv_counter_expected` and `c <= recv_counter_expected + SKIP_WINDOW_DM_V1`:
  - derive/calculate and cache the necessary per-counter material to allow future opens
  - derive keys for `c`
  - attempt AEAD open
  - on success:
    - mark `c` consumed
    - keep `recv_counter_expected` unchanged unless contiguous progression is established
  - on failure:
    - reject; do not mark consumed

- If `c > recv_counter_expected + SKIP_WINDOW_DM_V1`:
  - reject (outside window)

### 6.3 Cache bounds and erasure
- Cached skipped keys MUST be bounded by the window.
- Cached material MUST be erased immediately after use.
- Implementations MUST NOT allow unbounded growth.

**Hard rule:** Skip-window is a controlled exception for ordering only; it must not weaken replay guarantees.

---

## 7. Failure & Violation Response (Normative)

Nonce safety is not “best effort.” Violations are treated as active attack indicators or severe state corruption.

### 7.1 Violation classes (non-exhaustive)
A nonce-policy violation includes:
- duplicate `counter` accepted/seen for `(session_id, stream_id)`
- counter regression by local sender (internal invariant failure)
- malformed sizes that prevent deterministic derivation
- internal mismatch: derived nonce length != suite nonce length
- `session_binding` mismatch to canonical session state
- unknown suite/type/stream values used in derivation attempt

### 7.2 Mandatory response (fail-closed)
On violation:
1. MUST reject the message.
2. MUST emit a structured security event (see `docs/crypto/c6p-error-codes.md` + observability docs).
3. MUST NOT advance ratchet/counters or mark any new counters consumed.
4. SHOULD mark the session as **tainted** until a clean re-handshake / session reset policy is applied.

**Hard rule:** The implementation MUST NOT “try to recover” by guessing counters or accepting duplicates. Recovery is explicit and controlled (session reset).

---

## 8. Logging & Privacy (Normative)

Nonce violations must be observable without leaking secrets.

Logs MUST be metadata-minimal:
- include: `session_id` (hex16), `stream_id`, `counter`, `suite_id`, `message_type`, and an error code
- MUST NOT include: plaintext, ciphertext, derived keys, derived nonces, `mk_material`, or raw device IDs (hash device IDs if needed)

**Hard rule:** Never log nonces or keys.

---

## 9. Interop Contract (Rust/Swift/Node) (Normative)

To prevent drift:
- Rust is the reference implementation for nonce derivation.
- Swift and Node implementations MUST be verified against deterministic vectors generated by Rust.

**Hard rule:** CI MUST fail if any nonce vector mismatches.

---

## 10. Test Vectors (Normative Requirement)

Vectors MUST exist at:

- `docs/crypto/test-vectors/nonce/`
  - `v1/nonce_vectors.json`

Each vector MUST include (canonical JSON fields recommended):

- `case_id`
- `session_id_hex` (hex16)
- `initiator_device_id_hex` (hex32)
- `responder_device_id_hex` (hex32)
- `session_binding_b64u` (32 bytes)
- `suite_id` (u8)
- `message_type` (u8)
- `stream_id` (u8)
- `counter` (decimal string)
- `mk_material_b64u` (32 bytes)
- `nonce_b64u` (suite nonce bytes)

Vectors MUST cover:
1. multiple suites (0x01, 0x02, 0x03)
2. multiple message types
3. both stream directions
4. boundary counters: 0, 1, 2, 2^32-1 (allowed), and an overflow case (> u64) (rejection)
5. skip-window scenarios: accept inside window, reject outside window
6. negative encodings: uppercase hex, base64 padding, whitespace contamination

---

## 11. Compliance Checklist (Fail-Closed)

- [ ] Nonce is derived via HKDF-SHA256 with label `"C6P_NONCE_V1"`.
- [ ] Nonce binds `suite_id`, `message_type`, `stream_id`, `session_id`, `counter`, `session_binding`, and `mk_material`.
- [ ] Nonce length matches suite exactly (12/24/16).
- [ ] Duplicate counters are rejected (even if AEAD verifies).
- [ ] Skip-window is bounded and enforced.
- [ ] No logging of keys/nonces/mk_material.
- [ ] CI validates nonce vectors against Rust reference outputs.

---
