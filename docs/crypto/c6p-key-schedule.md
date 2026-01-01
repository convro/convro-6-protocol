# C6P Key Schedule (v1)

**Status:** Production / normative  
**Scope:** Root derivation, chain derivation, message key derivation, deterministic nonces, key confirmation derivation, and rekey hooks.  
**Applies to:** **IslandAccord v1**, DM ratchet, group/channel messaging (future), and all v1 AEAD suites.

This document is designed to be audit-friendly: every derivation is explicit, domain-separated, and deterministic.

---

## 0. Goals

1. **Deterministic, reproducible derivations** across implementations (Rust/Swift/Node reference tooling).
2. **Hard domain separation** between: handshake root, per-stream chains, per-message keys, nonces, key-confirmation, and future rekey events.
3. **Wire-binding**: keys and nonces are bound to session/stream/counter/suite/message-type via AAD and/or KDF info.
4. **Fail-closed**: unknown suite or unsupported parameters must abort.

---

## 1. Inputs & Canonical Types (Normative)

### 1.1 Session binding
- `session_id` (8 bytes, big-endian / raw bytes)
- `initiator_device_id` (8 bytes)
- `responder_device_id` (8 bytes)
- `stream_id` (1 byte) ∈ {`0x01` i2r, `0x02` r2i}
- `message_type` (1 byte) ∈ {dm, group, channel, control}
- `suite_id` (1 byte)

### 1.2 Cryptographic building blocks
- `SHA-256`
- `HKDF-SHA256` (RFC 5869)
- `HMAC-SHA256`

### 1.3 Fixed-length outputs
- `root_key` = 32 bytes
- `chain_key` = 32 bytes
- `message_key_material` = 32 bytes (then mapped to suite key length if needed)
- `kc_key` = 32 bytes
- `nonce_bytes` = suite-defined (12/16/24)

---

## 2. Canonical Serialization Helpers (Normative)

### 2.1 `U8(x)`
One byte: `x & 0xff`.

### 2.2 `BE64(x)`
8-byte big-endian encoding of uint64.

### 2.3 `CTX(session_id, initiator_device_id, responder_device_id)`
Canonical session context bytes:


CTX = session_id(8)
|| initiator_device_id(8)
|| responder_device_id(8)


### 2.4 `STREAM_CTX(stream_id, message_type, suite_id)`


STREAM_CTX = U8(stream_id) || U8(message_type) || U8(suite_id)


---

## 3. Domain Separation Labels (Normative)

All derivations MUST use these exact ASCII labels:

- `C6P_ROOT_V1`
- `C6P_CHAIN_V1`
- `C6P_MSG_V1`
- `C6P_NONCE_V1`
- `C6P_KC_V1`
- `C6P_REKEY_V1` (reserved)
- `C6P_EXPORT_V1` (reserved for app-level export keys)

Labels MUST be encoded as UTF-8 bytes and concatenated exactly.

---

## 4. IslandAccord v1 → Initial Root Derivation (Normative)

### 4.1 IslandAccord shared secret input (IKM)
IslandAccord v1 produces:

- `DH1`, `DH2`, `DH3` (each 32 bytes, X25519)
- optional `DH4` (32 bytes, X25519 with OTP)

The handshake produces `IKM` by concatenation:



IKM = DH1 || DH2 || DH3 || [DH4]


**Note:** IKM length is 96 bytes without OTP, 128 bytes with OTP.

### 4.2 Transcript hash
IslandAccord defines a canonical transcript `T` (see handshake docs) and:



transcript_hash = SHA256(T) // 32 bytes


### 4.3 Root salt
C6P v1 binds root derivation to transcript and session context:



salt_root = SHA256(
"C6P_ROOT_V1" ||
CTX ||
transcript_hash ||
STREAM_CTX? // NOT included at root stage
)


**Important:** `STREAM_CTX` is NOT part of root. Streams are derived later.

### 4.4 Root extraction + expansion
Root key is HKDF output:



prk = HKDF-Extract(salt = salt_root, ikm = IKM)

root_key = HKDF-Expand(
prk,
info = "C6P_ROOT_V1" || U8(C6P_VERSION),
L = 32
)


Outputs:
- `root_key` (32 bytes)

### 4.5 Key confirmation key (from root)
Key confirmation uses a separate derived key:



kc_key = HKDF-Expand(
prk = HKDF-Extract(salt = salt_root, ikm = IKM),
info = "C6P_KC_V1" || U8(C6P_VERSION) || transcript_hash,
L = 32
)


**Invariant:** `kc_key` MUST NOT equal `root_key` (domain separation guarantees).

---

## 5. Stream Chain Derivation (Normative)

C6P uses two streams:
- `i2r` (`0x01`)
- `r2i` (`0x02`)

The initial chain keys are derived from `root_key` with HKDF:

### 5.1 Chain salt


salt_chain = SHA256(
"C6P_CHAIN_V1" ||
CTX ||
transcript_hash
)


### 5.2 Chain PRK


prk_chain = HKDF-Extract(salt = salt_chain, ikm = root_key)


### 5.3 Chain keys for each stream
For each `stream_id ∈ {i2r, r2i}`:



chain_key_stream = HKDF-Expand(
prk_chain,
info = "C6P_CHAIN_V1" ||
U8(C6P_VERSION) ||
U8(stream_id) ||
U8(suite_id) ||
U8(message_type),
L = 32
)


Outputs:
- `CK_i2r` (32)
- `CK_r2i` (32)

**Note (role mapping):**
- Initiator: `send = CK_i2r`, `recv = CK_r2i`
- Responder: `send = CK_r2i`, `recv = CK_i2r`

---

## 6. Message Key Derivation & Ratchet Step (Normative)

For each outgoing/incoming message in a given stream:
- input: current `chain_key` (32), `counter` (uint64), stream context
- output: `message_key_material` (32), `next_chain_key` (32)

### 6.1 Ratchet salt (per message)


salt_msg = SHA256(
"C6P_MSG_V1" ||
CTX ||
transcript_hash ||
STREAM_CTX ||
BE64(counter)
)


### 6.2 Per-message PRK


prk_msg = HKDF-Extract(salt = salt_msg, ikm = chain_key)


### 6.3 Message key material (32 bytes)


mk_material = HKDF-Expand(
prk_msg,
info = "C6P_MSG_V1" || U8(C6P_VERSION) || STREAM_CTX,
L = 32
)


### 6.4 Next chain key (32 bytes)


next_chain_key = HKDF-Expand(
prk_msg,
info = "C6P_CHAIN_V1" || U8(C6P_VERSION) || STREAM_CTX || BE64(counter),
L = 32
)


**Strict rule:** both sides MUST apply identical derivation for the same `(session, stream, counter)`.

---

## 7. Suite Key Material Mapping (Normative)

`mk_material` is 32 bytes. Each suite maps it into AEAD key bytes:

### 7.1 ChaCha20-Poly1305 (`suite_id = 0x01`)
- AEAD key = first 32 bytes of `mk_material` (all 32)

### 7.2 XChaCha20-Poly1305 (`suite_id = 0x03`)
- AEAD key = first 32 bytes of `mk_material` (all 32)

### 7.3 AEGIS-128L (`suite_id = 0x02`)
AEGIS-128L uses a 16-byte key. Derive it **deterministically** from mk_material:



aegis_key = HKDF-Expand(
prk = HKDF-Extract(salt = "C6P_AEAD_AEGIS_128L_V1", ikm = mk_material),
info = "C6P_AEAD_AEGIS_128L_V1" || U8(C6P_VERSION),
L = 16
)


**Rationale:** avoid truncation ambiguity and preserve audit clarity.

---

## 8. Deterministic Nonce Derivation (Normative)

Nonces are derived from session binding + stream context + counter, domain-separated.

### 8.1 Nonce salt


salt_nonce = SHA256(
"C6P_NONCE_V1" ||
CTX ||
transcript_hash ||
STREAM_CTX
)


### 8.2 Nonce PRK


prk_nonce = HKDF-Extract(salt = salt_nonce, ikm = mk_material)


### 8.3 Nonce bytes
Nonce length depends on suite:

- ChaCha20-Poly1305: 12 bytes
- XChaCha20-Poly1305: 24 bytes
- AEGIS-128L: 16 bytes



nonce = HKDF-Expand(
prk_nonce,
info = "C6P_NONCE_V1" ||
U8(C6P_VERSION) ||
STREAM_CTX ||
BE64(counter),
L = nonce_len
)


**Hard invariants:**
- same `(session, stream, counter, suite, msg_type)` MUST yield identical nonce across implementations
- nonce MUST NOT be randomized or altered

---

## 9. Key Confirmation (IslandAccord v1) (Normative)

Key confirmation provides explicit assurance that both parties derived the same root.

### 9.1 Confirmation payload
Both sides compute:



kc_payload = SHA256(
"C6P_KC_V1" ||
U8(C6P_VERSION) ||
CTX ||
transcript_hash ||
U8(suite_id)
)


### 9.2 Confirmation tag


kc_tag = HMAC-SHA256(key = kc_key, data = kc_payload)


### 9.3 Directional confirmation (recommended)
To prevent reflection/replay, define directional tags:



kc_tag_initiator = HMAC(kc_key, kc_payload || "INIT")
kc_tag_responder = HMAC(kc_key, kc_payload || "RESP")


Where `"INIT"` and `"RESP"` are ASCII bytes.

**State machine rule:** a session MUST NOT transition to `ACTIVE` until the expected directional KC tag is verified.

---

## 10. Rekey Hooks (Reserved, Normative for format)

C6P v1 reserves a deterministic rekey mechanism even if not used immediately.

### 10.1 Rekey event info
A rekey event is identified by:
- `rekey_epoch` (uint64)
- `reason_code` (uint8) – policy-defined
- `rekey_context_hash` (32) – hashed structured reason/context

### 10.2 Rekey derivation


salt_rekey = SHA256("C6P_REKEY_V1" || CTX || transcript_hash || BE64(rekey_epoch))

prk_rekey = HKDF-Extract(salt = salt_rekey, ikm = root_key)

new_root_key = HKDF-Expand(
prk_rekey,
info = "C6P_REKEY_V1" || U8(C6P_VERSION) || BE64(rekey_epoch) || U8(reason_code) || rekey_context_hash,
L = 32
)


After rekey, chain derivations restart from the new root using §5.

---

## 11. Export Keys (Reserved)

C6P reserves exportable keys for application-level features (attachments, indexing, etc.) without leaking message keys.



export_key = HKDF-Expand(
prk = HKDF-Extract(salt = "C6P_EXPORT_V1" || CTX, ikm = root_key),
info = "C6P_EXPORT_V1" || U8(C6P_VERSION) || purpose_label || context_hash,
L = N
)


**Rule:** Export keys MUST NOT be used to encrypt DM content.

---

## 12. Security Properties (Auditor-Facing)

This key schedule provides:

- **Strong domain separation** across root/chain/msg/nonce/KC/rekey.
- **Deterministic nonces** safely, because they are injective over `(session, stream, counter, suite, type)` and bound to unique message keys.
- **Explicit authentication & confirmation** when combined with IslandAccord v1 signature + KC.
- **Resilience to server splicing**: transcript hash binds to key material + identities + IDs, and initiator signature authenticates it.

---

## 13. Implementation Checklist (Fail-Closed)

Implementations MUST:

- [ ] Validate all input lengths before any crypto.
- [ ] Reject unknown suite_id, stream_id, message_type.
- [ ] Use canonical base64url/hex parsing rules.
- [ ] Use exact labels and info layouts.
- [ ] Enforce monotonic counters per stream (unless skip-window is explicitly implemented and documented).
- [ ] Ensure nonce derivation uses the **same counter** as the message key derivation.
- [ ] Zeroize `IKM`, `prk`, and intermediate buffers where feasible.

---

## Appendix A — Pseudocode Summary (Normative)

### A.1 Root + KC


IKM = DH1||DH2||DH3||[DH4]
transcript_hash = SHA256(T)
salt_root = SHA256("C6P_ROOT_V1" || CTX || transcript_hash)
prk = HKDF-Extract(salt_root, IKM)
root_key = HKDF-Expand(prk, "C6P_ROOT_V1"||ver, 32)
kc_key = HKDF-Expand(prk, "C6P_KC_V1"||ver||transcript_hash, 32)


### A.2 Chain keys


salt_chain = SHA256("C6P_CHAIN_V1" || CTX || transcript_hash)
prk_chain = HKDF-Extract(salt_chain, root_key)
CK(stream) = HKDF-Expand(prk_chain, "C6P_CHAIN_V1"||ver||stream||suite||type, 32)


### A.3 Message step


salt_msg = SHA256("C6P_MSG_V1"||CTX||transcript_hash||STREAM_CTX||BE64(counter))
prk_msg = HKDF-Extract(salt_msg, chain_key)
mk_material = HKDF-Expand(prk_msg, "C6P_MSG_V1"||ver||STREAM_CTX, 32)
next_chain = HKDF-Expand(prk_msg, "C6P_CHAIN_V1"||ver||STREAM_CTX||BE64(counter), 32)
nonce = HKDF-Expand(HKDF-Extract(SHA256("C6P_NONCE_V1"||CTX||th||STREAM_CTX), mk_material),
"C6P_NONCE_V1"||ver||STREAM_CTX||BE64(counter),
nonce_len)
