# C6P Key Schedule (v1)

**Status:** Production / normative  
**Scope:** Root derivation, stream chain derivation, per-message derivation (message-key material + next chain), deterministic nonce derivation, key confirmation derivation, and reserved rekey/export hooks.  
**Registry authority:** `docs/crypto/c6p-crypto-registry.md` (suite IDs, stream IDs, message types, fixed sizes)  
**Encoding authority:** `docs/crypto/c6p-encoding-and-canonicalization.md` (wire parsing/strictness; counter wire string → u64 → BE64)  
**AEAD/AAD binding:** `docs/crypto/c6p-aead-and-aad.md` (session_binding + canonical AAD)  
**Handshake input:** `docs/handshake/island-accord-wire.md` + `docs/handshake/island-accord-crypto.md` (IKM inputs, transcript construction, signature/KC flow)

This document is designed to be audit-friendly: every derivation is explicit, domain-separated, deterministic, and bound to canonical context.

> **Hard rule (normative):** This key schedule MUST be identical across Rust/Swift/Node reference tooling.  
> Any deviation in labels, byte layout, or context binding MUST be treated as an implementation bug and MUST fail CI via vectors.

---

## 0. Goals (Normative)

1. **Deterministic, reproducible derivations** across implementations.
2. **Hard domain separation** between: root, chains, per-message keys, nonces, key confirmation, rekey, and export hooks.
3. **Context binding:** keys/nonces MUST be bound to session + stream + message type + suite + counter.
4. **Fail-closed:** unknown suite/stream/type MUST abort; length mismatches MUST abort.

---

## 1. Inputs & Canonical Types (Normative, registry-aligned)

### 1.1 Fixed-size identifiers (canonical bytes)
- `session_id`: **8 bytes** (decoded from wire `hex16`)
- `initiator_device_id`: **16 bytes** (decoded from wire `hex32`)
- `responder_device_id`: **16 bytes** (decoded from wire `hex32`)

### 1.2 Context enums (canonical bytes)
- `stream_id`: `u8` ∈ `{0x01 i2r, 0x02 r2i}`
- `message_type`: `u8` ∈ `{0x01 dm, 0x02 group, 0x03 channel, 0x10 control}`
- `suite_id`: `u8` ∈ `{0x01 ChaCha20-Poly1305, 0x02 XChaCha20-Poly1305, 0x03 AEGIS-128L}`

### 1.3 Counter
- `counter`: `u64`
- canonical bytes: `BE64(counter)` (8 bytes)
- wire (JSON): decimal string (see Encoding doc), parsed to u64, then `BE64`

### 1.4 Cryptographic building blocks
- `SHA-256`
- `HKDF-SHA256` (RFC 5869)
- `HMAC-SHA256`

### 1.5 Fixed-length outputs (canonical bytes)
- `root_key`: 32 bytes
- `chain_key`: 32 bytes
- `mk_material` (message key material): 32 bytes
- `kc_key`: 32 bytes
- `nonce`: suite-defined length (12/24/16)
- `suite_key`: suite-defined length (32/32/16)

---

## 2. Canonical Serialization Helpers (Normative)

### 2.1 `U8(x)`
One byte: `x & 0xff`.

### 2.2 `BE64(x)`
8-byte big-endian encoding of uint64.

### 2.3 `CTX(session_id, initiator_device_id, responder_device_id)`
Canonical session context bytes:

`CTX = session_id(8) || initiator_device_id(16) || responder_device_id(16)`

Total `CTX` length: `8 + 16 + 16 = 40 bytes`.

### 2.4 `STREAM_CTX(stream_id, message_type, suite_id)`
Canonical per-stream context bytes:

`STREAM_CTX = U8(stream_id) || U8(message_type) || U8(suite_id)`

Total `STREAM_CTX` length: `3 bytes`.

---

## 3. Domain Separation Labels (Normative)

All derivations MUST use these exact ASCII labels (case-sensitive, exact bytes):

- `C6P_ROOT_V1`
- `C6P_CHAIN_V1`
- `C6P_MSG_V1`
- `C6P_NONCE_V1`
- `C6P_KC_V1`
- `C6P_REKEY_V1` (reserved)
- `C6P_EXPORT_V1` (reserved)

Labels MUST be encoded as ASCII/UTF-8 bytes with identical results (only ASCII characters used).

---

## 4. IslandAccord v1 → Initial Root Derivation (Normative)

### 4.1 Handshake shared secret input (IKM)
IslandAccord v1 produces:
- `DH1`, `DH2`, `DH3` (each 32 bytes, X25519)
- optional `DH4` (32 bytes, X25519 with OTP) if OTP is reserved/used

`IKM = DH1 || DH2 || DH3 || [DH4]`

IKM length:
- 96 bytes (no OTP)
- 128 bytes (with OTP)

### 4.2 Transcript hash
IslandAccord defines canonical transcript bytes `T` (handshake docs). Compute:

`transcript_hash = SHA256(T)` (32 bytes)

### 4.3 Root salt (session + transcript bound)
`C6P_VERSION` (v1) is `0x01`.

`salt_root = SHA256( "C6P_ROOT_V1" || CTX || transcript_hash )`

### 4.4 Root extraction + expansion
`prk_root = HKDF-Extract( salt = salt_root, ikm = IKM )`

`root_key = HKDF-Expand( prk_root, info = "C6P_ROOT_V1" || U8(0x01), L = 32 )`

Output:
- `root_key` (32 bytes)

### 4.5 Key confirmation key (from root PRK)
Key confirmation uses a distinct derivation:

`kc_key = HKDF-Expand( prk_root, info = "C6P_KC_V1" || U8(0x01) || transcript_hash, L = 32 )`

**Invariant:** `kc_key` MUST NOT equal `root_key` (domain separation guarantees this).

---

## 5. Stream Chain Derivation (Normative)

C6P v1 maintains two directional chains (per session):

- `i2r` (`stream_id=0x01`)
- `r2i` (`stream_id=0x02`)

### 5.1 Chain salt
`salt_chain = SHA256( "C6P_CHAIN_V1" || CTX || transcript_hash )`

### 5.2 Chain PRK
`prk_chain = HKDF-Extract( salt = salt_chain, ikm = root_key )`

### 5.3 Initial chain keys (per stream, per suite, per message type)
For each `stream_id ∈ {0x01, 0x02}`:

`chain_key_stream = HKDF-Expand(`
- `prk_chain,`
- `info = "C6P_CHAIN_V1" || U8(0x01) || U8(stream_id) || U8(suite_id) || U8(message_type),`
- `L = 32`
`)`

Outputs:
- `CK_i2r` (32)
- `CK_r2i` (32)

**Role mapping (normative):**
- Initiator: `send = CK_i2r`, `recv = CK_r2i`
- Responder: `send = CK_r2i`, `recv = CK_i2r`

---

## 6. Per-Message Derivation & Ratchet Step (Normative)

For each message in a given `(session, stream)` at counter `c`:
- input: current `chain_key` (32), `counter` (u64), `STREAM_CTX`
- output: `mk_material` (32) and `next_chain_key` (32)

### 6.1 Per-message salt
`salt_msg = SHA256( "C6P_MSG_V1" || CTX || transcript_hash || STREAM_CTX || BE64(counter) )`

### 6.2 Per-message PRK
`prk_msg = HKDF-Extract( salt = salt_msg, ikm = chain_key )`

### 6.3 Message key material
`mk_material = HKDF-Expand( prk_msg, info = "C6P_MSG_V1" || U8(0x01) || STREAM_CTX, L = 32 )`

### 6.4 Next chain key
`next_chain_key = HKDF-Expand( prk_msg, info = "C6P_CHAIN_V1" || U8(0x01) || STREAM_CTX || BE64(counter), L = 32 )`

**Hard rule:** Both sides MUST compute identical outputs for the same `(CTX, transcript_hash, STREAM_CTX, counter)`.

**Hard rule:** On decrypt failure (AEAD open fails), receiver MUST NOT advance chain/counter state.

---

## 7. Suite Key Mapping (Normative, registry-aligned)

`mk_material` is always 32 bytes. Each suite maps it into AEAD key bytes:

### 7.1 ChaCha20-Poly1305 (`suite_id = 0x01`)
- `suite_key = mk_material[0..32]` (32 bytes)

### 7.2 XChaCha20-Poly1305 (`suite_id = 0x02`)
- `suite_key = mk_material[0..32]` (32 bytes)

### 7.3 AEGIS-128L (`suite_id = 0x03`)
AEGIS uses a 16-byte key. Derive it deterministically to avoid truncation ambiguity:

`aegis_prk = HKDF-Extract( salt = "C6P_AEAD_AEGIS_128L_V1", ikm = mk_material )`

`aegis_key = HKDF-Expand( aegis_prk, info = "C6P_AEAD_AEGIS_128L_V1" || U8(0x01), L = 16 )`

- `suite_key = aegis_key` (16 bytes)

**Hard rule:** Unknown `suite_id` MUST abort.

---

## 8. Deterministic Nonce Derivation (Normative)

Nonce derivation MUST be deterministic and MUST bind:
- protocol version
- suite_id
- message_type
- stream_id
- session_id
- counter
- session device-pair binding

### 8.1 Canonical session binding (source-of-truth)
Compute `session_binding` exactly as in `docs/crypto/c6p-aead-and-aad.md`:

`session_binding = SHA-256( "C6P_BIND_V1" || session_id(8) || initiator_device_id(16) || responder_device_id(16) )`

Output: 32 bytes.

**Hard rule:** `session_binding` MUST be computed from locally trusted session state, not attacker-provided envelope fields.

### 8.2 Nonce PRK
Nonce derivation uses `session_binding` as HKDF salt and `mk_material` as IKM:

`prk_nonce = HKDF-Extract( salt = session_binding, ikm = mk_material )`

### 8.3 Nonce info block (byte-exact)
`nonce_info = "C6P_NONCE_V1"`
`|| U8(0x01)`
`|| U8(suite_id)`
`|| U8(message_type)`
`|| U8(stream_id)`
`|| session_id(8)`
`|| BE64(counter)`

### 8.4 Nonce length per suite
- `suite_id=0x01` ChaCha20-Poly1305: `nonce_len = 12`
- `suite_id=0x02` XChaCha20-Poly1305: `nonce_len = 24`
- `suite_id=0x03` AEGIS-128L: `nonce_len = 16`

### 8.5 Nonce output
`nonce = HKDF-Expand( prk_nonce, info = nonce_info, L = nonce_len )`

**Hard invariants (normative):**
- same `(session, stream, counter, suite, type)` MUST yield identical nonce across implementations
- nonce MUST NOT be randomized or altered
- derived nonce length MUST equal suite nonce length; otherwise abort as internal invariant failure

---

## 9. Key Confirmation (IslandAccord v1) (Normative)

Key confirmation provides explicit assurance that both parties derived the same root.

### 9.1 Confirmation payload (canonical)
`kc_payload = SHA256( "C6P_KC_V1" || U8(0x01) || CTX || transcript_hash || U8(suite_id) )`

### 9.2 Confirmation tag
`kc_tag = HMAC-SHA256( key = kc_key, data = kc_payload )`

Output: 32 bytes.

### 9.3 Directional confirmation (recommended, normative if used)
To prevent reflection/replay, define directional tags:

- `kc_tag_initiator = HMAC( kc_key, kc_payload || "INIT" )`
- `kc_tag_responder = HMAC( kc_key, kc_payload || "RESP" )`

Where `"INIT"` and `"RESP"` are ASCII bytes (exact).

**State machine rule (normative):** session MUST NOT transition to `ACTIVE` until the expected directional KC tag is verified.

---

## 10. Rekey Hooks (Reserved) (Normative for format)

C6P v1 reserves a deterministic rekey mechanism even if not used immediately.

### 10.1 Rekey event identifiers
- `rekey_epoch`: `u64`
- `reason_code`: `u8`
- `rekey_context_hash`: 32 bytes (hash of structured reason/context)

### 10.2 Rekey derivation
`salt_rekey = SHA256( "C6P_REKEY_V1" || CTX || transcript_hash || BE64(rekey_epoch) )`

`prk_rekey = HKDF-Extract( salt = salt_rekey, ikm = root_key )`

`new_root_key = HKDF-Expand(`
- `prk_rekey,`
- `info = "C6P_REKEY_V1" || U8(0x01) || BE64(rekey_epoch) || U8(reason_code) || rekey_context_hash,`
- `L = 32`
`)`

After rekey, stream chain derivations restart from `new_root_key` using §5.

---

## 11. Export Keys (Reserved) (Normative for format)

Export keys allow app-level features without leaking message keys.

`export_prk = HKDF-Extract( salt = "C6P_EXPORT_V1" || CTX, ikm = root_key )`

`export_key = HKDF-Expand( export_prk, info = "C6P_EXPORT_V1" || U8(0x01) || purpose_label || context_hash, L = N )`

**Hard rule:** Export keys MUST NOT be used to encrypt DM content.

---

## 12. Security Properties (Audit-facing)

This schedule provides:

- **Domain separation** across root/chain/msg/nonce/KC/rekey/export.
- **Session binding**: nonce derivation is salted by `session_binding`, preventing cross-session confusion.
- **Context binding**: suite/type/stream/counter and session_id are included in nonce info and message salts.
- **Server splicing resistance**: transcript_hash and CTX bind root/chain/msg derivations to the handshake/session identities.
- **Deterministic nonces** safe by design: per-message keys + counter uniqueness + replay rejection.

---

## 13. Implementation Checklist (Fail-Closed)

Implementations MUST:

- [ ] Validate all input lengths before any crypto.
- [ ] Reject unknown `suite_id`, `stream_id`, `message_type`.
- [ ] Parse wire IDs strictly (hex lowercase fixed-length; base64url no padding).
- [ ] Parse counter from wire decimal string to u64 with bounds-check; canonical `BE64`.
- [ ] Use exact labels and byte layouts (no JSON-in-crypto).
- [ ] Enforce monotonic counters per stream (unless skip-window is specified and implemented).
- [ ] Never advance chain/counter on AEAD failure.
- [ ] Zeroize `IKM`, PRKs, and intermediate buffers where feasible.

---



### A.1 Root + KC

