# C6P AEAD & AAD (v1)

**Status:** Production / normative  
**Scope:** AEAD suites, key/nonce usage rules, canonical AAD construction, envelope binding, and misuse resistance.  
**Depends on:** `docs/crypto/c6p-key-schedule.md` (derives per-message keys and deterministic nonces).  
**Aligned with:** `docs/handshake/*` (IslandAccord v1 session binding + device/session identifiers).  
**Applies to:** DM payload encryption for C6P v1 (and the exact same construction is reused by future group/channel/control envelopes without changing AAD semantics).

This document is **normative**: implementations MUST follow it exactly. Any deviation MUST be rejected (fail-closed).

---

## 0. Security Goals (Normative)

1. **Strong binding**: ciphertext authenticity MUST cover *protocol, version, suite, message type, session binding, stream direction, counter*.
2. **Deterministic nonce safety**: deterministic nonces are permitted ONLY because nonce derivation is injective over the full message context and message keys are per-counter.
3. **Misuse resistance**: envelope relabeling, splicing across sessions/streams, downgrade and replay MUST be detected and rejected.
4. **Audit-grade determinism**: AAD bytes are fully specified; no implicit fields; no “implementation-defined” behavior.

---

## 1. AEAD Suites (Normative)

C6P v1 supports these suites:

| suite_id | Name | Key bytes | Nonce bytes | Tag bytes |
|---:|---|---:|---:|---:|
| 0x01 | ChaCha20-Poly1305 | 32 | 12 | 16 |
| 0x02 | XChaCha20-Poly1305 | 32 | 24 | 16 |
| 0x03 | AEGIS-128L | 16 | 16 | 16 |

**Hard rule:** Unknown `suite_id` MUST be rejected.

**Hard rule:** All suites MUST output a 16-byte authentication tag and MUST be represented as `ciphertext || tag`.

---

## 2. What Is Encrypted (Normative)

The crypto layer encrypts a byte string `P` (plaintext). It does not know or care if `P` is UTF-8 text, protobuf, JSON, etc.

**Hard rule:** All higher-level serialization MUST occur above this layer.

Wire-visible envelope fields are NOT encrypted. They are authenticated via AAD binding.

---

## 3. Identifiers & Sizes (Normative)

C6P v1 uses fixed-size identifiers aligned to IslandAccord:

- `session_id` = 4 bytes (`hex8` on the wire)
- `device_id` = 16 bytes (`hex32` on the wire)
- `counter` = 8 bytes unsigned (BE64)
- `stream_id` = 1 byte (directional stream discriminator)
- `message_type` = 1 byte
- `suite_id` = 1 byte
- `aad_flags` = 1 byte (v1 MUST be zero)

**Hard rule:** Any size mismatch MUST be rejected before attempting AEAD.

---

## 4. Key & Nonce Rules (Normative)

### 4.1 Per-message keying
For each message `(session, stream, counter, type, suite)` the Key Schedule derives:

- `mk_material` (fixed canonical output size from key schedule)
- `suite_key` (exactly Key bytes for the suite_id)
- `nonce` (exactly Nonce bytes for the suite_id)

This derivation is defined in `docs/crypto/c6p-key-schedule.md` and MUST be used verbatim.

**Hard rule:** The AEAD key MUST be per-message (per-counter) — never a long-lived static AEAD key.

### 4.2 Deterministic nonce
Nonce MUST be deterministically derived from the Key Schedule. Implementations MUST NOT randomize or replace it.

**Hard rule:** Nonce uniqueness is guaranteed by design. If a receiver detects a reused `(stream_id, counter)` in the same session, it MUST reject as replay.

### 4.3 Counter policy
Baseline DM ratchet policy:

- Sender counters MUST increase by exactly 1 per message per stream.
- Receiver MUST reject duplicates and MUST apply the skip-window policy (if enabled) exactly as specified by the ratchet/state-machine docs.

**Hard rule:** A message MUST NOT be accepted if its `counter` is already consumed for that `(session_id, stream_id)`.

---

## 5. Canonical Session Binding (Normative)

To prevent cross-session splicing and to bind AEAD to the exact device pair, both peers compute:

`session_binding = SHA-256( "C6P_BIND_V1" || session_id || initiator_device_id || responder_device_id )`

Where:
- `"C6P_BIND_V1"` is ASCII bytes (exactly 11 bytes)
- `session_id` is 4 bytes
- `device_id` is 16 bytes each
- hash output is 32 bytes

**Hard rule:** `session_binding` MUST be computed from canonical, locally trusted session state (not attacker-provided envelope fields).

This does NOT add network metadata: it is computed locally but cryptographically binds the message to the correct session/device pair.

---

## 6. Canonical AAD Format (Normative)

AAD is “Additional Authenticated Data” passed into AEAD. AAD MUST be constructed exactly as follows.

### 6.1 Constants
- `C6P_VERSION` = `0x01`
- `aad_flags` for v1 MUST be `0x00`
- `aad_label` = ASCII `"C6P_AAD_V1"` (10 bytes)

### 6.2 Enumerations
- `message_type: u8` (values registered in `docs/crypto/c6p-crypto-registry.md`)
- `stream_id: u8` (direction discriminator; values registered in the registry)
- `suite_id: u8` (see §1)

### 6.3 AAD layout (byte-exact)
AAD is the concatenation:

`AAD =`
- `aad_label` (ASCII `"C6P_AAD_V1"`, 10)
- `U8(C6P_VERSION)` (1)
- `U8(message_type)` (1)
- `U8(stream_id)` (1)
- `U8(suite_id)` (1)
- `U8(aad_flags)` (1)  // MUST be 0x00 in v1
- `session_id` (4)
- `session_binding` (32)
- `counter` (8)  // BE64

Total length (v1): `10 + 1+1+1+1+1 + 4 + 32 + 8 = 59 bytes`.

**Hard rule:** AAD MUST be 59 bytes exactly in v1.

### 6.4 Why `session_binding` is in AAD
This prevents:
- server-side splicing between sessions
- stream relabeling across device pairs
- accidental acceptance of messages under the wrong session metadata

Because `session_binding` is derived from canonical session state, the attacker cannot “fix” the AAD without owning the session context.

---

## 7. Sealed Payload Format (Normative)

C6P uses a suite-agnostic sealed layout:

`sealed = ciphertext || tag`

Where:
- `ciphertext.len == plaintext.len`
- `tag.len == 16` for all supported suites

**Hard rule:** If `sealed.len < 16`, reject.

### 7.1 JSON transport encoding
When `sealed` is transported in JSON, it MUST be base64url **without padding**.

Decoding MUST be strict:
- reject padding
- reject non-canonical encodings
- reject invalid characters

---

## 8. Envelope Binding (Normative)

A DM envelope contains wire-visible fields, at minimum:
- `session_id` (hex8)
- `message_type` (u8)
- `stream_id` (u8)
- `suite_id` (u8)
- `counter` (u64)
- `sealed` (b64u)

**Hard rule:** During decryption, the AAD MUST be reconstructed from:
- envelope fields (`session_id`, `message_type`, `stream_id`, `suite_id`, `counter`)
- canonical session state (`session_binding` derived from known device IDs)

If any envelope field mismatches the decrypt context → reject.

---

## 9. Encrypt (Normative)

Inputs:
- `plaintext: bytes`
- `session_id: [4]`
- `message_type: u8`
- `stream_id: u8`
- `suite_id: u8`
- `counter: u64`
- canonical session state provides `initiator_device_id`, `responder_device_id`
- key schedule provides `suite_key`, `nonce` for this exact message context

Steps:
1. Compute `session_binding` (see §5).
2. Construct AAD exactly per §6.
3. AEAD seal:
   - `(ciphertext, tag) = AEAD_Seal(key=suite_key, nonce=nonce, aad=AAD, plaintext=plaintext)`
4. Output `sealed = ciphertext || tag`.

**Hard rule:** Any AEAD failure MUST abort; never emit partial output.

---

## 10. Decrypt (Normative)

Inputs:
- envelope fields + `sealed`
- canonical session state
- key schedule capable of deriving `suite_key`, `nonce` for the (stream, counter, suite, type)

Steps:
1. Structural validation (fail-closed):
   - suite_id known
   - message_type known
   - stream_id known
   - `sealed.len >= 16`
2. Compute `session_binding` from canonical session state (see §5).
3. Reconstruct AAD exactly per §6.
4. AEAD open:
   - `plaintext = AEAD_Open(key=suite_key, nonce=nonce, aad=AAD, sealed)`
5. If open fails:
   - reject
   - do NOT advance counters/ratchet state
6. On success:
   - apply ratchet/counter progression exactly as specified by the DM state machine
   - mark `(session_id, stream_id, counter)` as consumed to prevent replay

---

## 11. Mandatory Misuse Controls (Normative)

### 11.1 Replay & duplicate rejection
Receiver MUST maintain a consumed-counter set (or equivalent) consistent with its ratchet design.

**Hard rule:** Accepting the same `counter` twice in the same stream is forbidden.

### 11.2 Downgrade resistance
`suite_id` and `message_type` are bound in AAD. Any tampering MUST fail AEAD.

### 11.3 Context confusion
`session_binding` binds all messages to the exact device pair and session_id. Cross-session splicing MUST fail.

---

## 12. Test Vectors (Normative Requirement)

This repo MUST include deterministic test vectors for:
1. `session_binding` computation.
2. AAD byte layout (full 59 bytes hex output).
3. Key schedule output (`suite_key`, `nonce`) for fixed transcript inputs.
4. AEAD seal/open round-trip for each suite_id.

Vector directory (normative path):
- `docs/crypto/test-vectors/aead/`
- `docs/crypto/test-vectors/aad/`
- `docs/crypto/test-vectors/bind/`

Vector format MUST be canonical JSON with:
- `session_id_hex`
- `initiator_device_id_hex`
- `responder_device_id_hex`
- `message_type`
- `stream_id`
- `suite_id`
- `counter`
- `session_binding_hex`
- `aad_hex`
- `nonce_b64u`
- `suite_key_b64u`
- `plaintext_hex`
- `sealed_b64u`

---

## 13. Compliance Checklist (Fail-Closed)

- [ ] AAD is exactly 59 bytes (v1).
- [ ] `aad_flags` is exactly `0x00`.
- [ ] `session_binding` computed from canonical session state, never from attacker-provided fields.
- [ ] Reject unknown enums (`suite_id`, `message_type`, `stream_id`).
- [ ] Reject malformed sizes (`session_id`, `device_id`, `sealed`).
- [ ] Never advance ratchet/counters on AEAD failure.
- [ ] Enforce replay/duplicate rejection per stream.

