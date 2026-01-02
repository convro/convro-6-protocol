# C6P AEAD & AAD (v1)

**Status:** Production / normative  
**Scope:** AEAD suites, suite-key mapping, deterministic nonce contract, canonical AAD, envelope binding, misuse resistance, fail-closed rules.  
**Depends on:**  
- `docs/handshake/island-accord-crypto.md` (canonical session context + device-pair authority)  
- `docs/crypto/c6p-key-schedule.md` (mk_material derivation + per-message suite key + per-message nonce derivation)  
- `docs/crypto/c6p-crypto-registry.md` (algorithm IDs, suite IDs, labels)  

**Applies to:** DM envelopes (v1), and any encrypted payload type in C6P v1 (group/channel/control as they ship).

This document is written to be **Signal-grade** in clarity: strict invariants, explicit byte layouts, and fail-closed behavior.

---

## 0. Goals (Normative)

1. **Misuse resistance via binding:** integrity MUST cover *protocol + session + device-pair + stream + type + counter + suite*.  
2. **Deterministic nonce safety:** deterministic nonces are safe only if `(key, nonce)` reuse is cryptographically impossible and state rollback is fail-closed.  
3. **Suite agility:** one canonical AAD format across suites; only suite-key length and nonce length vary by suite.  
4. **Auditability:** every byte is specified; no implicit behavior; no “optional” fields in v1.

---

## 1. AEAD Suites (Normative)

C6P v1 supports these suites:

| suite_id | Name | Suite key bytes | Nonce bytes | Tag bytes | Production policy |
|---:|---|---:|---:|---:|---|
| 0x01 | ChaCha20-Poly1305 | 32 | 12 | 16 | **MUST** (baseline) |
| 0x03 | XChaCha20-Poly1305 | 32 | 24 | 16 | MAY |
| 0x02 | AEGIS-128L | 16 | 16 | 16 | MAY (only if audited/approved) |

**Rule:** Unknown `suite_id` MUST be rejected (fail-closed).  
**Rule:** Tag length MUST be exactly **16 bytes** for all supported suites in v1.

---

## 2. Plaintext / Ciphertext Boundary (Normative)

C6P encrypts an arbitrary byte payload `P` using a per-message suite key and deterministic nonce.

- The crypto layer treats `P` as bytes (UTF-8 text is an application concern).
- Envelope metadata is **not encrypted**, but is authenticated via AAD.

**Rule:** Any serialization (JSON/protobuf/etc.) MUST happen above this layer.

---

## 3. Key & Nonce Contract (Normative)

### 3.1 Per-message material
For each message, the Key Schedule provides:
- `mk_material` (32 bytes) — unique per `(session, stream, counter, message_type, suite_id)`  
- `suite_key` — mapped from `mk_material` with suite-specific output length  
- `nonce` — deterministic with suite-specific length

All details of derivation belong to `c6p-key-schedule.md`, but this document imposes the following **hard contract**:

**Hard rule:** For a given `(session_id, initiator_device_id, responder_device_id, stream_id, counter, message_type, suite_id)` the derived `(suite_key, nonce)` MUST be identical across implementations and languages.

### 3.2 Suite-key mapping requirement (no implementation-defined behavior)
If a suite uses fewer than 32 key bytes (e.g., AEGIS-128L = 16B), the mapping from `mk_material` MUST be defined by Key Schedule using explicit KDF labels and output sizes (NOT “truncate by convention”).

**Hard rule:** `suite_key_len(suite_id)` MUST be:
- 32 for 0x01, 0x03
- 16 for 0x02

### 3.3 Deterministic nonce requirement
Nonce MUST be derived deterministically from the same context that AAD binds, with explicit domain separation (labels) defined in Key Schedule.

**Hard rule:** `nonce_len(suite_id)` MUST be:
- 12 for 0x01
- 24 for 0x03
- 16 for 0x02

---

## 4. Counter Uniqueness, Ordering, and Replay (Normative)

For a fixed tuple `(session_id, stream_id, message_type, suite_id)`:

- `counter` MUST be unique.
- Baseline DM: `counter` MUST be strictly increasing by 1.
- If a skip-window exists, out-of-order counters MAY be accepted only if:
  - they are within the configured window,
  - each counter is accepted at most once (replay rejected),
  - derived keys may be cached only within window bounds.

**Hard rule:** Any detected replay or counter rollback MUST fail closed.

---

## 5. Canonical AAD (Additional Authenticated Data) (Normative)

AAD MUST bind ciphertext to:
- protocol version
- message type + suite
- canonical session device-pair (initiator/responder)
- session id
- stream id
- counter
- flags (reserved for explicit future opt-ins)

### 5.1 Canonical session context (IslandAccord binding)
AAD uses the **canonical device-pair** from the session context:
- `initiator_device_id` = deviceId of the session initiator (IslandAccord)
- `responder_device_id` = deviceId of the session responder (IslandAccord)

**Rule:** Implementations MUST NOT treat these fields as `(local, peer)`; they MUST be `(initiator, responder)` even on the responder device.

### 5.2 Types and sizes
- `C6P_VERSION` = `0x01` (UInt8)
- `message_type` = UInt8 (DM=0x01, GROUP=0x02, CHANNEL=0x03, CONTROL=0x10)
- `stream_id` = UInt8 (I2R=0x01, R2I=0x02)
- `suite_id` = UInt8
- `aad_flags` = UInt8 (v1 MUST be 0)
- `session_id` = 4 bytes (UInt32 big-endian)
- `initiator_device_id` = 8 bytes (UInt64 big-endian)
- `responder_device_id` = 8 bytes (UInt64 big-endian)
- `counter` = 8 bytes (UInt64 big-endian)

### 5.3 AAD v1 layout (byte-exact)
AAD is the concatenation:

- `"C6P_AAD_V1"` (ASCII bytes, **10 bytes**)
- `U8(C6P_VERSION)` (1)
- `U8(message_type)` (1)
- `U8(stream_id)` (1)
- `U8(suite_id)` (1)
- `U8(aad_flags)` (1) — MUST be `0x00` in v1
- `session_id` (4, BE)
- `initiator_device_id` (8, BE)
- `responder_device_id` (8, BE)
- `counter` (8, BE)

**Total length (v1):** `10 + (1+1+1+1+1) + 4 + 8 + 8 + 8 = 43 bytes`.

### 5.4 Why both device IDs are included
AAD binds the message to the session’s canonical device pair to prevent:
- cross-session replay/splicing between different device pairs,
- server-side routing mixups from bugs,
- envelope relabeling across sessions that share `session_id` by coincidence (defense-in-depth).

### 5.5 Flags policy
- v1: `aad_flags MUST be 0x00`
- future: flags require explicit opt-in; MUST NOT silently change semantics of existing messages.

---

## 6. Envelope Binding Rules (Normative)

A DM envelope contains wire-visible fields (example):
- `session_id_hex` (8 hex chars = 4 bytes)
- `stream_id` (u8)
- `counter` (u64)
- `message_type` (u8)
- `suite_id` (u8)
- `sealed` (ciphertext || tag)

**Rule:** The envelope fields used to build AAD MUST exactly match the values actually present in the envelope.
On decrypt, any mismatch MUST be rejected (fail-closed).

---

## 7. Sealed Payload Format (Normative)

### 7.1 `sealed` bytes
`sealed` MUST be:

`sealed = ciphertext || tag`

Where:
- `len(ciphertext) == len(plaintext)`
- `len(tag) == 16` bytes (all v1 suites)

**Rule:** Implementations MUST reject malformed sealed sizes (e.g., `sealed.len < 16`).

### 7.2 JSON transport encoding
If `sealed` is transported in JSON:
- it MUST be base64url without padding,
- decoding MUST be strict.

---

## 8. Encrypt (Seal) Algorithm (Normative)

Inputs:
- `plaintext` bytes
- canonical session context: `(session_id, initiator_device_id, responder_device_id)`
- envelope context: `(message_type, stream_id, suite_id, counter)`
- `suite_key` + `nonce` derived from Key Schedule for this exact context

Steps:
1. Construct `AAD` exactly per §5.
2. Compute `(ciphertext, tag) = AEAD_Seal(key=suite_key, nonce=nonce, aad=AAD, plaintext=plaintext)`.
3. Output envelope fields + `sealed = ciphertext || tag`.

**Rule:** Any AEAD failure MUST abort and MUST NOT output partial/corrupt data.

---

## 9. Decrypt (Open) Algorithm (Normative)

Inputs:
- envelope fields + `sealed`
- session state providing canonical device-pair and counter policy
- `suite_key` + `nonce` derived for `(session, stream, counter, type, suite)`

Steps:
1. Validate envelope structural constraints:
   - known `suite_id`, `message_type`, `stream_id`
   - `sealed.len >= 16`
2. Rebuild `AAD` per §5 using envelope fields and the session’s canonical device IDs.
3. Compute `plaintext = AEAD_Open(key=suite_key, nonce=nonce, aad=AAD, sealed=sealed)`.
4. If open fails → reject, do NOT advance counters/ratchet.
5. On success → advance counters/ratchet exactly per ratchet rules (or skip-window rules).

---

## 10. Misuse Resistance & Downgrade Notes (Audit-Facing)

### 10.1 Deterministic nonces are safe here because:
- suite_key is per-message (derived from ratchet + counter),
- nonce is derived deterministically with domain separation and is unique under the schedule,
- AAD binds the full context (device-pair + stream + counter + suite + type).

### 10.2 Counter rollback / state rollback
Because deterministic nonce safety depends on uniqueness, implementations MUST:
- persist state atomically (ratchet + counters),
- treat detected rollback as `STATE_CORRUPT` and force session reset/re-handshake.

### 10.3 Downgrade resistance (suite)
Because `suite_id` is included in:
- Key Schedule derivations (suite_key + nonce),
- AAD binding,
an attacker cannot mutate suite without triggering authentication failure.

---

## 11. Compliance Checklist (Fail-Closed)

- [ ] AAD MUST be **43 bytes** exactly for v1.
- [ ] `"C6P_AAD_V1"` MUST be 10 ASCII bytes.
- [ ] `aad_flags MUST be 0x00` in v1.
- [ ] Reject unknown `suite_id` / `stream_id` / `message_type`.
- [ ] Reject `sealed.len < 16`; require tag length 16.
- [ ] Do not advance session state on AEAD failure.
- [ ] AAD device IDs MUST match the session’s canonical (initiator,responder) device pair (IslandAccord).
- [ ] Nonce MUST come from Key Schedule; never randomize.
- [ ] Ensure counter uniqueness; reject replays; rollback = fail closed.

---

## Appendix A — Required Test Vectors

This repo MUST include deterministic vectors covering:
1) AAD byte layout given fixed IDs/counter (aad_hex).
2) suite_key + nonce derived for fixed inputs.
3) AEAD seal/open round-trip for each supported suite.

Vector format (JSON):
- `session_id_hex`, `initiator_device_hex`, `responder_device_hex`
- `stream_id`, `message_type`, `suite_id`, `counter`
- `mk_material_b64u`
- `suite_key_b64u`
- `nonce_b64u`
- `aad_hex`
- `plaintext_hex`
- `sealed_b64u`

Vectors are generated by the Rust reference implementation and verified by Swift clients.
