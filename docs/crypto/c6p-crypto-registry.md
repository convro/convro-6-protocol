# C6P Crypto Registry (v1)

**Status:** Production / normative  
**Scope:** Cryptographic identifiers, suites, labels, lengths, canonical encodings, and negotiation rules.  
**Applies to:** C6P wire, C6P DM/group/channel envelopes, **IslandAccord v1** (handshake), and all v1 implementations (Rust core, Node backend, Swift bridge/client).  

This document is intentionally strict: it defines the **only allowed** crypto identifiers and parameters for C6P v1, plus the discipline by which future versions may extend them.

> **Authority rule (normative):** This registry is the **single source of truth** for all wire-stable identifiers, suite IDs, labels, and fixed-size types.  
> Any other document that conflicts with this registry MUST be updated to match it.

---

## 0. Goals

1. **One registry for everything crypto**: auditors can verify that every byte string and identifier used on wire is known, documented, and stable.
2. **Wire stability**: wire-facing IDs MUST never change once released.
3. **Fail-closed**: unknown suite/alg ID => reject.
4. **Compatibility discipline**: new versions can be added without silent weakening.

---

## 1. Terminology

- **Wire ID** – compact numeric identifier serialized on the wire (e.g., `suite_id=0x01`).
- **Algorithm ID** – canonical human-readable string constant (spec/audit-facing).
- **Label** – ASCII string used in transcript construction, signatures, and KDF info separation.
- **Suite** – bundle of primitives (KDF + AEAD + nonce length + AAD schema binding) under one wire ID.
- **Domain separation** – strict separation of derivations and signatures by label/info strings.

---

## 2. Canonical Encodings (Normative)

### 2.1 Base64url (no padding)
Binary fields transported in JSON MUST use **base64url without padding**.

- Alphabet: RFC 4648 URL-safe (`A–Z a–z 0–9 - _`)
- Encoder MUST NOT emit `=`
- Decoder MUST reject:
  - any `=`
  - any `+` or `/`
  - any whitespace
  - invalid characters / invalid decode

**Implementation note (non-normative):** A decoder MAY internally restore padding for decoding, but it MUST still reject any on-wire input that contains `=`.

### 2.2 Hex (lowercase, fixed-length)
All fixed-size identifiers transported as hex MUST be:
- lowercase only `[0-9a-f]`
- fixed-length for that type
- no `0x` prefix
- no whitespace

Unknown-length or “almost valid” encodings MUST be rejected.

### 2.3 Big-endian integer encoding (canonical bytes)
When an identifier is represented as bytes inside transcripts/KDF/AAD:
- integers MUST be big-endian (BE)
- counters MUST be `BE64(counter)`

---

## 3. Fixed-Length Types (Normative)

### 3.1 IDs (wire + canonical bytes)
| Type | Canonical bytes | Wire encoding | Wire length |
|------|------------------:|--------------|------------:|
| `C6PDeviceId` | 16 bytes | hex (lowercase) | 32 chars |
| `C6PSessionId` | 8 bytes | hex (lowercase) | 16 chars |
| `C6PKeyId` | 8 bytes | hex (lowercase) | 16 chars |

**Hard rule:** Any decoded length mismatch MUST be rejected before any cryptographic operation.

### 3.2 Core crypto objects
| Type | Length | Encoding | Notes |
|------|-------:|----------|------|
| `X25519 public key` | 32 | base64url | Raw Montgomery u-coordinate |
| `X25519 private key` | 32 | internal | Stored locally only |
| `Ed25519 public key` | 32 | base64url | Identity signing public key |
| `Ed25519 signature` | 64 | base64url | Deterministic (RFC 8032) |
| `TranscriptHash` | 32 | base64url | SHA-256 over canonical transcript |
| `RootKey` | 32 | base64url | HKDF output |
| `ChainKey` | 32 | base64url | Per-stream chain state |
| `MessageKeyMaterial` | 32 | base64url | Per-message material, mapped per suite |
| `KcKey` | 32 | base64url | Key confirmation key |

---

## 4. Cryptographic Primitives (Normative)

### 4.1 DH: X25519
- **Algorithm ID:** `C6P_DH_X25519_V1`
- Used in IslandAccord and session ratchet.
- MUST use a constant-time X25519 implementation.

### 4.2 Signatures: Ed25519
- **Algorithm ID:** `C6P_SIG_ED25519_V1`
- Used for identity signatures and IslandAccord v1 initiator authentication.

### 4.3 Hash: SHA-256
- **Algorithm ID:** `C6P_HASH_SHA256_V1`
- Used for transcript hashing, session binding, and commitments.

### 4.4 KDF: HKDF-SHA256
- **Algorithm ID:** `C6P_KDF_HKDFSHA256_V1`
- Used for root/chain/message/nonce/KC derivations with strict domain separation.

---

## 5. AEAD Suites (Wire-Level) (Normative)

### 5.1 Suite registry (wire-stable)
C6P v1 defines the following **wire-stable** suite IDs:

| Suite | `suite_id` | Algorithm ID | Key bytes | Nonce bytes | Tag bytes | Status |
|------|-----------:|--------------|----------:|------------:|----------:|--------|
| ChaCha20-Poly1305 | `0x01` | `C6P_AEAD_CHACHA20POLY1305_V1` | 32 | 12 | 16 | **REQUIRED** |
| XChaCha20-Poly1305 | `0x02` | `C6P_AEAD_XCHACHA20POLY1305_V1` | 32 | 24 | 16 | OPTIONAL (v1) |
| AEGIS-128L | `0x03` | `C6P_AEAD_AEGIS_128L_V1` | 16* | 16 | 16 | OPTIONAL (v1, gated) |

\* AEGIS key bytes are derived deterministically from `MessageKeyMaterial` as specified in the Key Schedule (no truncation ambiguity).

**Hard rule:** Unknown `suite_id` MUST be rejected.

**Production default:** `0x01` ChaCha20-Poly1305.

### 5.2 Deterministic nonce policy (normative pointer)
C6P uses deterministic nonces derived from canonical context.  
Nonce derivation MUST follow `docs/crypto/c6p-key-schedule.md` and `docs/crypto/c6p-nonce-policy.md` once aligned.

**Hard rule:** If a sender ever reuses the same `(session_id, stream_id, counter, suite_id, message_type)` with the same derived key schedule state, that is a fatal invariant breach.

### 5.3 AAD required (normative pointer)
All AEAD operations MUST include AAD and MUST bind:
- protocol version
- message type
- suite id
- session id
- stream id
- counter
- canonical session binding (device pair binding)

AAD construction is defined in `docs/crypto/c6p-aead-and-aad.md`.

---

## 6. IslandAccord v1 Registry Entries (Normative)

IslandAccord v1 is the **canonical** prekey-based authenticated handshake for C6P v1.

### 6.1 Handshake identifier & labels
- **Handshake name:** `IslandAccord`
- **Version:** `v1`
- **Handshake label:** `C6P_ISLAND_ACCORD_V1`
- **Prekey signature label:** `C6P_PREKEY_V1`
- **Initiator signature label:** `C6P_IA_SIG_V1`
- **Key confirmation label:** `C6P_KC_V1`

Labels are ASCII bytes, case-sensitive, exact.

### 6.2 DH set (auditor-grade)
IslandAccord v1 uses 3DH (+ optional OTP):

- `DH1 = X25519(IK_dh_initiator, SPK_responder)`
- `DH2 = X25519(EK_initiator, IK_dh_responder)`
- `DH3 = X25519(EK_initiator, SPK_responder)`
- `DH4 = X25519(EK_initiator, OTP_responder)` (optional; if OTP reserved)

`IK_dh` is X25519 identity DH key; `IK_sig` is Ed25519 identity signing key.

### 6.3 Initiator authentication (normative)
Initiator MUST sign the transcript commitment:

- `sig = Ed25519.Sign(IK_sig_initiator, SHA256(transcript_bytes))`

Responder MUST verify before accepting the handshake as valid.

### 6.4 Key confirmation (normative)
Key confirmation MUST be computed after deriving initial root:
- `kc_key` derived via HKDF with info label `C6P_KC_V1`
- KC tag derived via HMAC-SHA256 over a canonical payload (see Key Schedule)

State machine MUST NOT transition to `ACTIVE` until expected directional KC tag is verified.

---

## 7. Key Schedule Registry Hooks (Normative)

Key schedule MUST be domain-separated by these ASCII labels:

- `C6P_ROOT_V1`
- `C6P_CHAIN_V1`
- `C6P_MSG_V1`
- `C6P_NONCE_V1`
- `C6P_KC_V1`
- `C6P_REKEY_V1` (reserved)
- `C6P_EXPORT_V1` (reserved)

All derivations MUST use exact label bytes and the canonical layouts defined in `docs/crypto/c6p-key-schedule.md`.

---

## 8. Stream Registry (Wire-stable) (Normative)

Stream IDs are wire-stable and MUST be AAD/KDF-bound:

| Stream | `stream_id` | Meaning |
|------|------------:|---------|
| `i2r` | `0x01` | Initiator → Responder |
| `r2i` | `0x02` | Responder → Initiator |

Unknown `stream_id` MUST be rejected.

---

## 9. Message Types (Wire-stable) (Normative)

Message type IDs are wire-stable and MUST be AAD/KDF-bound:

| Type | `message_type` |
|------|---------------:|
| `dm` | `0x01` |
| `group` | `0x02` |
| `channel` | `0x03` |
| `control` | `0x10` |

Unknown `message_type` MUST be rejected.

---

## 10. Negotiation & Compatibility Rules (Normative)

### 10.1 Supported suite list exchange
Any capability exchange MUST:
- be authenticated (inside encrypted channel or signed during handshake),
- include `protocol_version`,
- include an ordered list of supported `suite_id`s.

### 10.2 Selection policy
- Preferred suite is first common element by sender policy order (unless compliance policy overrides).
- If no overlap exists:
  - **DM:** abort session creation / handshake completion.
  - **group/channel/control:** abort or require explicit server-mediated policy (out of scope here).

### 10.3 Unknown IDs
- Unknown `suite_id`, `stream_id`, `message_type`, algorithm IDs MUST cause fail-closed rejection.
- Unknown optional fields MAY be ignored only if the wire schema explicitly marks them optional and non-security-critical.

### 10.4 Deprecation
A suite can be deprecated only by:
1. marking it `DEPRECATED` here,
2. updating negotiation policy docs,
3. retaining decoder support for a defined sunset window (explicit).

No silent weakening is allowed.

---

## 11. Rust Implementation Notes (Non-normative)

Auditors will expect:
- constant-time primitives (battle-tested crates),
- zeroization for secret material,
- strict separation between wire parsing and crypto.

Suggested mapping:
- X25519: `x25519-dalek`
- Ed25519: `ed25519-dalek`
- HKDF/HMAC/SHA256: `hkdf`, `hmac`, `sha2`
- ChaCha20-Poly1305 / XChaCha20-Poly1305: `chacha20poly1305`
- AEGIS-128L: only behind a feature gate and only with a reputable implementation.

---

## 12. Versioning & Extension Process (Normative)

To introduce v2:
1. Introduce `C6P_VERSION = 0x02`.
2. Add new suite IDs without changing existing IDs.
3. Add new labels with version suffix.
4. Provide explicit migration guidance and compatibility matrix.

No backporting silent changes to v1 is allowed.

---

## 13. Security Invariants Checklist (Auditor-facing)

Implementations MUST enforce:

- [ ] Reject non-canonical base64url/hex encodings.
- [ ] Reject wrong-length keys/signatures/IDs.
- [ ] Reject unknown suite/stream/type IDs.
- [ ] AAD is always present and canonical.
- [ ] Nonce never repeats for same `(session, stream, counter, suite, type)`.
- [ ] Transcript hash is identical on both sides.
- [ ] Initiator signature verified before activation.
- [ ] Key confirmation verified before activation.
- [ ] OTP referenced in offer MUST be consumed exactly once if used.

---

## Appendix A — Registry Constants (Copy/Paste)

### A.1 Algorithm IDs
- `C6P_DH_X25519_V1`
- `C6P_SIG_ED25519_V1`
- `C6P_HASH_SHA256_V1`
- `C6P_KDF_HKDFSHA256_V1`
- `C6P_AEAD_CHACHA20POLY1305_V1`
- `C6P_AEAD_XCHACHA20POLY1305_V1`
- `C6P_AEAD_AEGIS_128L_V1`

### A.2 Labels
- `C6P_ISLAND_ACCORD_V1`
- `C6P_PREKEY_V1`
- `C6P_IA_SIG_V1`
- `C6P_KC_V1`
- `C6P_ROOT_V1`
- `C6P_CHAIN_V1`
- `C6P_MSG_V1`
- `C6P_NONCE_V1`
- `C6P_REKEY_V1`
- `C6P_EXPORT_V1`

### A.3 Wire IDs
- Suites: `0x01`, `0x02`, `0x03`
- Streams: `0x01`, `0x02`
- Message types: `0x01`, `0x02`, `0x03`, `0x10`
