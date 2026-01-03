# C6P AEAD & AAD (v1)

**Status:** **PRODUCTION — NORMATIVE**  
**Scope:** AEAD suites, per-message key/nonce usage rules, canonical AAD construction, envelope binding, misuse resistance, and fail-closed behavior.  
**Applies to:** DM payload encryption in **C6P v1**. The same AAD semantics are reused by future group/channel/control envelopes **without changing AAD layout**.

**Registry authority (wire IDs / lengths):** `docs/crypto/c6p-crypto-registry.md`  
**Encoding authority (hex/base64url strictness, counter wire type):** `docs/crypto/c6p-encoding-and-canonicalization.md`  
**Key/nonce derivation authority:** `docs/crypto/c6p-key-schedule.md` and `docs/crypto/c6p-nonce-policy.md`  
**Replay/skip-window authority:** `docs/crypto/c6p-replay-and-skip-window.md`

This document is **normative**. Implementations MUST follow it exactly. Any deviation MUST be rejected (fail-closed).

---

## 0. Security Goals (Normative)

1. **Strong binding:** ciphertext authenticity MUST cover protocol version, message type, suite, session binding, stream direction, and counter.
2. **Misuse resistance:** envelope relabeling, splicing across sessions, downgrade, and replay MUST be detected and rejected.
3. **Audit-grade determinism:** AAD bytes are fully specified and fixed-length; no implicit fields.
4. **Fail-closed:** unknown IDs, malformed sizes, non-canonical encodings, or state invariant breaches MUST be rejected before acceptance.

---

## 1. AEAD Suites (Normative, registry-aligned)

C6P v1 supports these suites (wire-stable `suite_id` values):

| `suite_id` | Name | Key bytes | Nonce bytes | Tag bytes | Status |
|---:|---|---:|---:|---:|---|
| `0x01` | ChaCha20-Poly1305 | 32 | 12 | 16 | **REQUIRED (production default)** |
| `0x02` | XChaCha20-Poly1305 | 32 | 24 | 16 | OPTIONAL (v1) |
| `0x03` | AEGIS-128L | 16 | 16 | 16 | OPTIONAL (v1, gated) |

**Hard rules:**
- Unknown `suite_id` MUST be rejected.
- All suites MUST output a **16-byte authentication tag** and MUST be represented on wire as `sealed = ciphertext || tag`.
- The production default suite is **`0x01` ChaCha20-Poly1305**.

---

## 2. What Is Encrypted (Normative)

The crypto layer encrypts an arbitrary byte string `P` (plaintext). It does not interpret the content.

- Higher-level serialization (UTF-8, JSON, protobuf, etc.) MUST happen above this layer.
- Wire-visible envelope metadata is NOT encrypted, but MUST be authenticated via AAD binding.

---

## 3. Identifiers, Sizes, and Canonical Bytes (Normative)

All sizes and encodings in this section are authoritative for AEAD/AAD.

### 3.1 Fixed-size identifiers (registry-aligned)

- `session_id` = **8 bytes**  
  - wire encoding: **hex16** (lowercase)
- `device_id` = **16 bytes**  
  - wire encoding: **hex32** (lowercase)

**Hard rule:** Any decoded length mismatch MUST be rejected before any cryptographic operation.

### 3.2 Message context fields (wire-stable)

- `counter` = `u64` canonical bytes `BE64(counter)` (8 bytes)  
  - wire encoding: **decimal string** (parsed to `u64`, then `BE64`)
- `stream_id` = `u8` (1 byte)  
  - registry: `0x01` i2r, `0x02` r2i
- `message_type` = `u8` (1 byte)  
  - registry: `0x01 dm`, `0x02 group`, `0x03 channel`, `0x10 control`
- `suite_id` = `u8` (1 byte) per §1
- `aad_flags` = `u8` (1 byte), v1 MUST be `0x00`

**Hard rule:** Unknown or unsupported `stream_id` / `message_type` MUST be rejected.

---

## 4. Key & Nonce Rules (Normative)

### 4.1 Per-message keying (required)

For each message context:

`(session_id, initiator_device_id, responder_device_id, stream_id, message_type, suite_id, counter)`

the Key Schedule MUST derive:

- `mk_material` (32 bytes, canonical)
- `suite_key` (exactly `Key bytes` for the suite)
- `nonce` (exactly `Nonce bytes` for the suite)

Derivation is defined in:
- `docs/crypto/c6p-key-schedule.md` (message key material + suite mapping)
- `docs/crypto/c6p-nonce-policy.md` (nonce derivation contract)

**Hard rule:** The AEAD key MUST be **per-message (per-counter)** — never a long-lived static AEAD key.

### 4.2 Deterministic nonce (required)

Nonce MUST be deterministically derived for the exact same context.

**Hard rule:** Implementations MUST NOT randomize or replace the derived nonce.

### 4.3 Counter policy (required)

- Sender counters MUST be monotonic per `(session_id, stream_id)` and MUST advance exactly by 1 for each successfully sealed message.
- Receiver MUST reject duplicates and enforce replay/skip-window rules per:
  - `docs/crypto/c6p-replay-and-skip-window.md`

**Hard rule:** A message MUST NOT be accepted if `(session_id, stream_id, counter)` is already consumed (even if AEAD verifies).

---

## 5. Canonical Session Binding (Normative)

To prevent cross-session splicing and bind messages to the exact device pair, both peers compute:

`session_binding = SHA-256( "C6P_BIND_V1" || session_id || initiator_device_id || responder_device_id )`

Where:
- `"C6P_BIND_V1"` is ASCII bytes (exact bytes, case-sensitive)
- `session_id` is 8 bytes
- `initiator_device_id` is 16 bytes
- `responder_device_id` is 16 bytes
- output is 32 bytes

**Hard rules:**
- `session_binding` MUST be computed from **canonical, locally trusted session state** (handshake/session record), not from attacker-provided fields.
- Implementations MUST NOT accept a message if the locally computed `session_binding` does not correspond to the session context for which decryption is attempted.

**Interop note:** `session_binding` is a cross-document primitive and is referenced by nonce derivation and replay policy.

---

## 6. Canonical AAD Format (Normative)

AAD (“Additional Authenticated Data”) MUST be constructed exactly as follows.

### 6.1 Constants (v1)

- `C6P_VERSION` = `0x01`
- `aad_flags` = `0x00` (MUST be 0x00 in v1)
- `aad_label` = ASCII `"C6P_AAD_V1"` (**10 bytes**)

### 6.2 AAD layout (byte-exact)

AAD is the concatenation:

`AAD =`
1. `aad_label` (ASCII `"C6P_AAD_V1"`, 10)
2. `U8(C6P_VERSION)` (1)
3. `U8(message_type)` (1)
4. `U8(stream_id)` (1)
5. `U8(suite_id)` (1)
6. `U8(aad_flags)` (1)  // MUST be 0x00 in v1
7. `session_id` (8)
8. `session_binding` (32)
9. `BE64(counter)` (8)

Total length (v1):  
`10 + 5 + 8 + 32 + 8 = 63 bytes`

**Hard rules:**
- AAD MUST be **63 bytes exactly** in v1.
- If reconstruction yields any other length, that is an internal invariant failure and MUST abort.
- `aad_flags` MUST be exactly `0x00` in v1; any other value MUST be rejected.

### 6.3 Why `session_binding` is included

Including `session_binding` in AAD prevents:
- server-side splicing between sessions
- stream/type/suite relabeling across device pairs
- accidental acceptance under the wrong session metadata

Because `session_binding` is derived from canonical session state, an attacker cannot “fix” AAD without the correct session context.

---

## 7. Sealed Payload Format (Normative)

C6P uses a suite-agnostic sealed layout:

`sealed = ciphertext || tag`

Where:
- `ciphertext.len == plaintext.len`
- `tag.len == 16` (for all supported suites)

**Hard rule:** If `sealed.len < 16`, reject.

### 7.1 JSON transport encoding (required)

When `sealed` is transported in JSON, it MUST be **base64url without padding**.

Decoding MUST be strict:
- reject padding (`=`)
- reject non-url alphabet (`+` `/`)
- reject whitespace
- reject invalid decode

---

## 8. Envelope Binding (Normative)

A DM envelope contains wire-visible fields, at minimum:

- `session_id` (hex16)
- `message_type` (u8)
- `stream_id` (u8)
- `suite_id` (u8)
- `counter` (decimal string)
- `sealed` (base64url no padding)

**Hard rule:** During decryption, AAD MUST be reconstructed from:
- envelope fields: `session_id`, `message_type`, `stream_id`, `suite_id`, `counter`
- canonical session state: `session_binding` derived from stored `(session_id, initiator_device_id, responder_device_id)`

**Hard rule:** Implementations MUST validate (fail-closed) BEFORE any state advancement:
- `suite_id`, `stream_id`, `message_type` are known/supported
- `session_id` decodes to 8 bytes and matches the targeted session context
- `counter` parses to `u64` (no negative, no overflow)
- `sealed` decodes and has length ≥ 16

---

## 9. Encrypt (Normative)

**Inputs:**
- `plaintext: bytes`
- envelope fields: `session_id`, `message_type`, `stream_id`, `suite_id`, `counter`
- canonical session state: `initiator_device_id`, `responder_device_id`
- Key Schedule outputs: `suite_key`, `nonce` for the exact message context

**Steps:**
1. Compute `session_binding` (see §5).
2. Construct `AAD` exactly per §6.
3. AEAD seal:
   - `(ciphertext, tag) = AEAD_Seal(key=suite_key, nonce=nonce, aad=AAD, plaintext=plaintext)`
4. Output `sealed = ciphertext || tag`.

**Hard rules:**
- Any AEAD failure MUST abort; never emit partial output.
- Sender MUST persist counter progression (and any ratchet state) in a crash-safe way before treating the message as “sent”.

---

## 10. Decrypt (Normative)

**Inputs:**
- envelope fields + `sealed`
- canonical session state (including initiator/responder device IDs)
- Key Schedule capable of deriving `suite_key`, `nonce` for `(stream_id, counter, suite_id, message_type)`

**Steps:**
1. Structural validation (fail-closed):
   - known `suite_id`, `stream_id`, `message_type`
   - decoded `session_id` is 8 bytes and matches the targeted session
   - `sealed.len >= 16`
2. Compute `session_binding` from canonical session state (see §5).
3. Reconstruct `AAD` exactly per §6.
4. AEAD open:
   - `plaintext = AEAD_Open(key=suite_key, nonce=nonce, aad=AAD, sealed)`
5. If open fails:
   - reject
   - do NOT advance counters/ratchet state
6. On success:
   - apply ratchet/counter progression exactly as specified by replay/skip-window policy
   - mark `(session_id, stream_id, counter)` as consumed (replay defense)

---

## 11. Mandatory Misuse Controls (Normative)

### 11.1 Replay & duplicate rejection

Receiver MUST maintain consumed-counter state consistent with the ratchet/skip-window design.

**Hard rule:** Accepting the same `counter` twice for the same `(session_id, stream_id)` is forbidden, even if AEAD verifies.

### 11.2 Downgrade resistance

`suite_id` and `message_type` are bound in AAD. Any tampering MUST fail AEAD.

### 11.3 Context confusion / splicing resistance

`session_binding` binds messages to the exact `(session_id, initiator_device_id, responder_device_id)`. Cross-session splicing MUST fail.

---

## 12. Test Vectors (Normative Requirement)

This repo MUST include deterministic test vectors for:

1. `session_binding` computation.
2. AAD byte layout (full **63 bytes** hex output).
3. Key schedule outputs (`mk_material`, `suite_key`, `nonce`) for fixed inputs.
4. AEAD seal/open for each supported `suite_id`.
5. Negative vectors:
   - malformed ID lengths
   - uppercase hex / `0x` prefix
   - base64url padding
   - wrong enum IDs
   - replayed counters
   - AAD mismatch scenarios

### 12.1 Canonical vector fields (recommended JSON)

Each AEAD/AAD vector SHOULD include:

- `case_id`
- `session_id_hex` (hex16)
- `initiator_device_id_hex` (hex32)
- `responder_device_id_hex` (hex32)
- `message_type` (u8)
- `stream_id` (u8)
- `suite_id` (u8)
- `counter` (decimal string)
- `session_binding_hex` (32 bytes hex) *(or `session_binding_b64u`; choose one repo-wide and keep consistent)*
- `aad_hex` (63 bytes hex)
- `mk_material_b64u` (32 bytes)
- `suite_key_b64u` (suite key bytes)
- `nonce_b64u` (suite nonce bytes)
- `plaintext_hex`
- `sealed_b64u`

**Hard rule:** Vectors MUST be generated by the Rust reference implementation and validated by Swift and Node harnesses in CI.

---

## 13. Compliance Checklist (Fail-Closed)

- [ ] AAD is exactly **63 bytes** (v1).
- [ ] `aad_flags` is exactly `0x00`.
- [ ] `session_id` is 8 bytes (hex16 wire); `device_id` is 16 bytes (hex32 wire).
- [ ] Reject unknown enums (`suite_id`, `message_type`, `stream_id`).
- [ ] Reject malformed sizes (`session_id`, `sealed`).
- [ ] Never advance ratchet/counters on AEAD failure.
- [ ] Enforce replay/duplicate rejection per stream.
- [ ] `suite_id=0x01` (ChaCha20-Poly1305) is supported and is the production default.

---

