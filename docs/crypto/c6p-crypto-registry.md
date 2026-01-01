# C6P Crypto Registry (v1)

**Status:** Production / normative  
**Scope:** Cryptographic identifiers, suites, labels, lengths, canonical encodings, negotiation rules.  
**Applies to:** C6P wire, C6P DM/group/channel envelopes, **IslandAccord v1** (handshake), and future protocol versions.

This document is intentionally strict: it defines the **only allowed** crypto identifiers and parameters for C6P v1, plus the rules by which new versions may extend them.

---

## 0. Goals

1. **One registry for everything crypto**: auditors can verify that every byte string and identifier used on wire is known, documented, and stable.
2. **Wire stability**: wire-facing IDs must never change once released.
3. **Fail-closed**: unknown suite/alg ID => reject (unless explicitly allowed by a documented compatibility rule).
4. **Compatibility discipline**: new versions can be added without silently weakening security.

---

## 1. Terminology

- **Wire ID** – compact numeric identifier serialized on the wire (e.g., `suite=0x01`).
- **Algorithm ID** – canonical human-readable string constant (spec/audit-facing).
- **Label** – ASCII string used in transcript construction, signatures, and KDF info separation.
- **Suite** – a bundle of primitives (KDF + AEAD + nonce format + AAD schema) under one wire ID.
- **Domain separation** – strict separation of key derivations and signatures by label/info strings.

---

## 2. Canonical Encodings (Normative)

### 2.1 Base64url (no padding)
All binary fields transported in JSON MUST use base64url without padding (`=` removed).

- Alphabet: RFC 4648 URL-safe (`-` and `_`).
- Decoder MUST accept missing padding and restore as needed.
- Encoder MUST NOT emit padding.

### 2.2 Hex (lowercase)
All fixed-size identifiers that are represented as hex MUST be lowercase and fixed-length when applicable.

- `DeviceId`: 8 bytes => 16 hex chars
- `KeyId`: 8 bytes => 16 hex chars
- `SessionId`: **8 bytes => 16 hex chars** (normative for production)  
  - Rationale: 32-bit session IDs are acceptable for toy/prototype, but production requires collision resistance across time and shards. C6P v1 uses 64-bit session IDs for wire and storage.

### 2.3 Big-endian integer encoding
All integer IDs serialized as bytes MUST be big-endian.

---

## 3. Fixed-Length Types (Normative)

| Type | Length | Encoding | Notes |
|------|--------|----------|------|
| `X25519 public key` | 32 | base64url | Raw Montgomery u-coordinate |
| `X25519 private key` | 32 | internal | Stored locally only |
| `Ed25519 public key` | 32 | base64url | Identity signing public key |
| `Ed25519 signature` | 64 | base64url | Deterministic per RFC8032 |
| `RootKey` | 32 | base64url | Output of HKDF extract/expand schedule |
| `ChainKey` | 32 | base64url | Per-stream chain key state |
| `MessageKey` | 32 | base64url | Per-message AEAD key material |
| `TranscriptHash` | 32 | base64url | SHA-256 over canonical transcript |
| `Nonce` | suite-defined | bytes | Deterministic; see suites |

---

## 4. Cryptographic Primitives (Normative)

### 4.1 DH: X25519
- **Algorithm ID:** `C6P_DH_X25519_V1`
- Used in IslandAccord and session ratchet.
- Implementations MUST use a constant-time X25519 implementation.

### 4.2 Signatures: Ed25519
- **Algorithm ID:** `C6P_SIG_ED25519_V1`
- Used for identity signatures and **IslandAccord v1 initiator signature** (auditor-grade authentication & anti-splice).

### 4.3 Hash: SHA-256
- **Algorithm ID:** `C6P_HASH_SHA256_V1`
- Used for transcript hashing and registry-defined commitments.

### 4.4 KDF: HKDF-SHA256
- **Algorithm ID:** `C6P_KDF_HKDFSHA256_V1`
- Used for initial root derivation and chain/message derivations with explicit domain separation info.

---

## 5. AEAD Suites (Wire-Level) (Normative)

C6P v1 defines the following **wire-stable** suite IDs:

### 5.1 Suite registry

| Suite | Wire ID | Algorithm ID | Key | Nonce | AAD | Status |
|------|---------|--------------|-----|-------|-----|--------|
| ChaCha20-Poly1305 | `0x01` | `C6P_AEAD_CHACHA20POLY1305_V1` | 32B | 12B | required | REQUIRED |
| AEGIS-128L | `0x02` | `C6P_AEAD_AEGIS_128L_V1` | 16B derived from MK | 16B | required | OPTIONAL (v1) |
| XChaCha20-Poly1305 | `0x03` | `C6P_AEAD_XCHACHA20POLY1305_V1` | 32B | 24B | required | OPTIONAL (v1) |

**Production default:** `0x01` ChaCha20-Poly1305.  
**Negotiation rule:** if peers do not agree, the sender MUST fall back to `0x01` or abort depending on policy (see §10).

### 5.2 Deterministic Nonce Policy (Normative)

C6P uses **deterministic nonces** derived from:
- `session_id`
- `stream_id`
- `message_counter`
- suite-specific constant label

This is permitted ONLY because:
1. Message counters are monotonic per stream.
2. Nonce generation is injective over `(session, stream, counter)`.
3. Reuse across messages is cryptographically prevented by construction.

**Hard rule:** If a sender ever reuses the same `(session_id, stream_id, counter)` with the same suite and key, the implementation MUST treat it as a fatal invariant breach.

### 5.3 AAD Required (Normative)

All AEAD operations MUST include AAD. AAD MUST bind at least:
- protocol version
- message type (dm/group/channel/control)
- suite id
- session id
- stream id
- counter
- sender/receiver device binding (where applicable in envelope)

If wire format uses an envelope that already contains these fields, AAD MUST be computed as a canonical serialization over those exact fields (see `docs/wire/...` once present).

---

## 6. IslandAccord v1 Registry Entries (Normative)

IslandAccord v1 is the **canonical** prekey-based authenticated handshake for C6P v1.

### 6.1 Handshake identifier

- **Handshake name:** `IslandAccord`
- **Version:** `v1`
- **Handshake label:** `C6P_ISLAND_ACCORD_V1`
- **Prekey signature label:** `C6P_PREKEY_V1`
- **Key confirmation label:** `C6P_KC_V1`
- **Initiator signature label:** `C6P_IA_SIG_V1`

### 6.2 IslandAccord DH set (Auditor-grade)

IslandAccord v1 uses **3DH (+ optional OTP)** with explicit authentication and confirmation:

- `DH1 = X25519(IK_dh_initiator, SPK_responder)`
- `DH2 = X25519(EK_initiator, IK_dh_responder)`
- `DH3 = X25519(EK_initiator, SPK_responder)`
- `DH4 = X25519(EK_initiator, OTP_responder)` (optional; if OTP reserved)

**IK_dh** is an X25519 identity DH key associated with the account/device identity.  
**IK_sig** is Ed25519 identity signing key.

### 6.3 Initiator authentication (Normative)

The initiator MUST sign the handshake transcript commitment:

- `sig = Ed25519.Sign(IK_sig_initiator, H(transcript))`

Responder MUST verify it against initiator `IK_sig_pub`.

### 6.4 Key confirmation (Normative)

A key confirmation MAC MUST be computed by both parties after deriving the initial root:

- `kc = HMAC-SHA256(kc_key, transcript_hash || context)`
- `kc_key` is derived from the root via HKDF with `info = "C6P_KC_V1"`

The responder MUST send `kc_r`, initiator MUST verify before marking the session as active (or vice versa depending on wire flow). Confirmation MUST be explicit in the state machine.

---

## 7. Key Schedule Registry Hooks (Normative)

C6P key schedule MUST be domain-separated by fixed info strings:

- `C6P_ROOT_V1` – initial root extraction/expansion
- `C6P_CHAIN_V1` – per-stream chain derivation
- `C6P_MSG_V1` – per-message key derivation
- `C6P_NONCE_V1` – nonce derivation
- `C6P_REKEY_V1` – future rekey hooks (reserved)

Each info string MUST include:
- protocol version byte
- suite id
- message type
- stream id (where applicable)

---

## 8. Stream Registry (Wire-stable) (Normative)

Stream IDs MUST be stable and are part of the AEAD binding and ratchet.

| Stream | Wire ID | Meaning |
|--------|---------|---------|
| `i2r` | `0x01` | Initiator → Responder |
| `r2i` | `0x02` | Responder → Initiator |

---

## 9. Message Types (Wire-stable) (Normative)

| Type | Wire ID |
|------|---------|
| `dm` | `0x01` |
| `group` | `0x02` |
| `channel` | `0x03` |
| `control` | `0x10` |

Message type MUST be AAD-bound.

---

## 10. Negotiation & Compatibility Rules (Normative)

### 10.1 Supported suite list exchange
Any “capabilities” exchange MUST:
- be authenticated (inside an encrypted channel or signed during handshake),
- include `protocol_version`,
- include an ordered list of supported suite IDs.

### 10.2 Selection policy
- Preferred suite is the first common element by the sender’s policy order, unless overridden by compliance policy.
- If no overlap exists:
  - For **DM**: abort handshake/session creation.
  - For **group/channel**: abort membership or require server-mediated policy (explicit).

### 10.3 Unknown IDs
- Unknown suite ID or algorithm ID MUST cause fail-closed rejection.
- Unknown optional fields MAY be ignored only if the wire schema defines them as optional and they are not security-critical.

### 10.4 Deprecation
A suite can be deprecated only by:
1. marking it `DEPRECATED` in this registry,
2. updating negotiation policy docs,
3. retaining decoder support for a defined sunset period (explicitly stated).

---

## 11. Rust Implementation Notes (Non-normative but production-oriented)

Auditors will expect:
- constant-time primitives (use battle-tested crates),
- zeroization for secret material,
- strict separation between “wire parsing” and “crypto”.

Recommended mapping:
- X25519: `x25519-dalek`
- Ed25519: `ed25519-dalek`
- HKDF/HMAC/SHA256: `hkdf`, `hmac`, `sha2`
- ChaCha20-Poly1305 / XChaCha20-Poly1305: `chacha20poly1305`
- AEGIS-128L: only if using a reputable, reviewed crate; otherwise keep OPTIONAL and behind feature gate.

---

## 12. Versioning & Extension Process (Normative)

To add anything in v2:
1. Introduce `C6P_VERSION = 0x02`.
2. Add new suite IDs **without changing existing IDs**.
3. Add new labels with version suffix.
4. Provide migration guidance and compatibility matrix.

No backporting silent changes to v1 is allowed.

---

## 13. Security Invariants Checklist (Auditor-facing)

Implementations MUST enforce:

- [ ] Reject non-canonical base64url/hex encodings.
- [ ] Reject wrong-length keys/signatures.
- [ ] Reject unknown suite IDs.
- [ ] AAD is always present and canonical.
- [ ] Nonce never repeats for same `(session, stream, counter, suite)`.
- [ ] IslandAccord v1 transcript hash is identical on both sides.
- [ ] Initiator Ed25519 signature verified before session activation.
- [ ] Key confirmation verified before session activation.
- [ ] OTP usage is consistent: if offer references OTP id, responder must consume that OTP exactly once.

---

## Appendix A — Registry Constants (Copy/Paste)

### A.1 Algorithm IDs
- `C6P_DH_X25519_V1`
- `C6P_SIG_ED25519_V1`
- `C6P_HASH_SHA256_V1`
- `C6P_KDF_HKDFSHA256_V1`
- `C6P_AEAD_CHACHA20POLY1305_V1`
- `C6P_AEAD_AEGIS_128L_V1`
- `C6P_AEAD_XCHACHA20POLY1305_V1`

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

### A.3 Wire IDs
- Suites: `0x01`, `0x02`, `0x03`
- Streams: `0x01`, `0x02`
- Message types: `0x01`, `0x02`, `0x03`, `0x10`
