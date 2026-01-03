# C6P Encoding & Canonicalization (v1)

**Status:** Production / normative  
**Scope:** Canonical bytes for every field crossing module/language boundaries; strict hex/base64url rules; endianness; JSON wire contracts; strict decoding; “no ambiguity” policy.  
**Registry authority:** `docs/crypto/c6p-crypto-registry.md` (wire-stable IDs, suites, types)  
**Depends on:** `docs/crypto/c6p-crypto-registry.md`, `docs/crypto/c6p-key-schedule.md`, `docs/crypto/c6p-aead-and-aad.md`, `docs/crypto/c6p-nonce-policy.md`, `docs/handshake/island-accord-wire.md`  
**Applies to:** Rust core, Node backend, Swift bridge/client (and any future implementation).

This document is deliberately strict. If something is “almost valid”, it MUST be rejected.

> **Authority rule (normative):** If any document conflicts with the registry’s fixed sizes / IDs / suite mapping, the other document MUST be updated.  
> This file is aligned to the registry as canonical.

---

## 0. Design Principles (Non-negotiable)

1. **One canonical byte representation** for every logical value used in crypto.
2. **Round-trip determinism** across Rust/Node/Swift.
3. **Fail-closed parsing:** reject invalid/ambiguous encodings.
4. **No “helpful normalization”** (no trimming, no case-folding unless explicitly permitted).
5. **No dual encodings** for the same field unless explicitly specified.
6. **No locale/timezone effects** in protocol-critical material.
7. **Registry-aligned:** fixed sizes, IDs, and suite mapping MUST match `c6p-crypto-registry.md`.

---

## 1. Terminology

- **Canonical bytes:** the unique byte sequence that represents a value inside cryptographic operations (hashing/AAD/KDF/signatures).
- **Wire form:** the representation sent on the network (JSON fields, query parameters, websocket frames).
- **Transport encoding:** hex or base64url used to carry bytes over JSON.

---

## 2. Global Encoding Rules (Wire)

### 2.1 ASCII labels
Protocol labels used in transcripts/KDF info/AAD are **ASCII byte strings**, not Unicode.

- MUST be ASCII
- MUST be exactly as specified (case-sensitive)
- MUST NOT include trailing NUL
- MUST NOT include whitespace unless explicitly present in the label bytes

Examples (illustrative, registry defines the authoritative list):
- `"C6P_AAD_V1"`
- `"C6P_ISLAND_ACCORD_V1"`
- `"C6P_PREKEY_V1"`
- `"C6P_KC_V1"`

### 2.2 Whitespace policy
**No trimming** in decoding of security-critical fields:

- hex strings: MUST NOT contain whitespace
- base64url strings: MUST NOT contain whitespace
- IDs: MUST NOT contain whitespace
- signatures: MUST NOT contain whitespace
- counters (wire string): MUST NOT contain whitespace

If any value arrives with leading/trailing whitespace → reject.

### 2.3 Case policy
- **hex:** MUST be lowercase on the wire (`[0-9a-f]` only).  
  Default behavior: reject uppercase to prevent dual canonical forms.
- **base64url:** case-sensitive and MUST use URL-safe alphabet (`A–Z a–z 0–9 - _`) with **no padding**.

### 2.4 Length policy
All fixed-size fields MUST validate decoded length exactly.
- 31 or 33 bytes → reject
- “close enough” → reject

---

## 3. Endianness & Fixed-width Integers (Canonical)

C6P uses **big-endian** for fixed-width integer encodings inside canonical bytes.

### 3.1 UInt64 (8 bytes)
Canonical bytes for `UInt64 x`:
- `BE64(x)` = 8 bytes, most significant byte first.

### 3.2 UInt32 (4 bytes)
Canonical bytes for `UInt32 x`:
- `BE32(x)` = 4 bytes, most significant byte first.

### 3.3 Counters
- `counter` is `UInt64`.
- canonical bytes = `BE64(counter)`.

**Hard rule:** Do not encode counters as decimal strings inside cryptographic transcripts/AAD/KDF.  
Decimal is allowed only as wire/UI/debug and must never be hashed directly.

---

## 4. Hex Encoding (Wire transport)

Hex is used for stable identifiers that are small, frequent, and DB/routing-friendly.

### 4.1 Hex alphabet
- Allowed: `[0-9a-f]` only (lowercase)
- Length MUST be even
- MUST be exact for the field (see §4.3)

### 4.2 Decoding rules
A hex string MUST be rejected if:
- contains non-hex characters
- contains uppercase A–F
- contains prefix `0x`
- contains whitespace
- wrong length

### 4.3 Canonical lengths (normative; registry-aligned)
| Field | Canonical bytes | Hex chars | Example |
|---|---:|---:|---|
| `C6PDeviceId` | 16 | 32 | `001122...ffeedd` |
| `C6PSessionId` | 8 | 16 | `0a1b2c3d4e5f6071` |
| `C6PKeyId` | 8 | 16 | `0011223344556677` |

### 4.4 Canonical bytes
Hex is transport only. Canonical bytes are always decoded bytes:
- `device_id_bytes = hex_decode(device_id_hex)` (must be 16 bytes)
- `session_id_bytes = hex_decode(session_id_hex)` (must be 8 bytes)
- `key_id_bytes = hex_decode(key_id_hex)` (must be 8 bytes)

---

## 5. Base64url (Wire transport for binary)

Base64url is used for:
- public keys (X25519: 32, Ed25519: 32)
- signatures (Ed25519: 64)
- ciphertext blobs, tags, derived keys, hashes
- nonces (suite-defined length)

### 5.1 Alphabet & padding
Base64url MUST:
- use `-` and `_` instead of `+` and `/`
- have **no `=` padding**
- contain only `[A-Za-z0-9-_]`

### 5.2 Decoding strictness
Decoder MUST reject:
- any `=` padding
- `+` or `/`
- whitespace
- invalid base64
- decoded length mismatch for fixed-size fields

### 5.3 Canonical length expectations (decoded)
| Field | Decoded bytes |
|---|---:|
| X25519 public key | 32 |
| Ed25519 public key | 32 |
| Ed25519 signature | 64 |
| SHA-256 hash | 32 |
| AEAD tag | 16 |
| ChaCha20-Poly1305 nonce | 12 |
| XChaCha20-Poly1305 nonce | 24 |
| AEGIS-128L nonce | 16 |

**Rule:** Always validate decoded byte count.

---

## 6. JSON Wire Canonicalization (Transport-level)

JSON is used as the wire format for HTTP and for some WS messages.

### 6.1 JSON parsing policy
- Use a standards-compliant JSON parser.
- Reject invalid JSON.
- Reject type mismatches.
- Reject duplicate keys **where the platform permits** (or enforce schema validation that detects duplicates).

Strict types:
- IDs: string
- binary: base64url string (no padding)
- enums (`suite_id`, `stream_id`, `message_type`): integer in range 0–255 (or string if wire schema defines string; choose one and lock it)
- counters: see §6.3

### 6.2 No JSON-in-crypto (critical)
Cryptographic transcripts/AAD/KDF MUST NOT be defined as “JSON bytes” or “string concatenation of JSON fields”.

Only canonical byte layouts defined in crypto/handshake docs are used.

### 6.3 Counter wire type (normative)
To avoid JS integer precision issues:
- `counter` on JSON wire MUST be a **decimal string** containing only digits (`[0-9]+`), no sign, no whitespace.
- parser MUST bounds-check to `u64`.

Canonical bytes remain:
- `counter_bytes = BE64(parse_u64(counter_string))`

---

## 7. Canonicalization of Protocol-Critical Objects

This section defines exactly what bytes are used when hashing/signing/deriving.

### 7.1 IDs canonical bytes
- `C6PDeviceId` canonical bytes: 16 bytes (decoded from wire hex32)
- `C6PSessionId` canonical bytes: 8 bytes (decoded from wire hex16)
- `C6PKeyId` canonical bytes: 8 bytes (decoded from wire hex16)

**Hard rule:** Implementations MUST NOT maintain an alternative “numeric DB id” and treat it as equivalent unless there is a single canonical conversion path and tests proving equivalence. Wire IDs are authoritative.

### 7.2 Public keys
- X25519/Ed25519 public keys are treated as raw bytes (`32`).
- Canonical bytes are exactly those 32 bytes, no prefixes, no type tags.

### 7.3 Signatures
- Ed25519 signature canonical bytes are exactly 64 bytes.

### 7.4 Hashes
- SHA-256 hash canonical bytes are exactly 32 bytes.

---

## 8. Canonical Transcript Rules for IslandAccord v1 (Normative)

IslandAccord transcripts MUST use:
- fixed-width IDs as raw bytes (per registry sizes)
- public keys as raw bytes
- explicit presence markers for optional parts
- protocol labels as ASCII bytes

**Hard rule:** A transcript MUST NOT depend on:
- JSON stringification
- platform-specific UTF-8 normalization
- locale settings
- unordered maps/dictionaries

If the handshake defines an “OTP-present marker”, it MUST be a single byte with fixed value (e.g., `0x00`/`0x01`) and MUST be included even when OTP is absent.

---

## 9. Canonical AAD Rules (Normative pointer)

AAD is fully defined in `docs/crypto/c6p-aead-and-aad.md`.

This document defines only the encoding contracts used to build AAD:
- `session_id_hex16 -> decode -> 8 bytes`
- `device_id_hex32 -> decode -> 16 bytes` (for session binding and local session context)
- `counter_wire_string -> parse_u64 -> BE64`

**Hard rule:** AAD bytes MUST be constructed only from canonical bytes and the exact AAD layout.

---

## 10. Error Handling (Normative)

Decoders MUST return structured error codes (see `docs/crypto/c6p-error-codes.md` and handshake error registries).

Minimum encoding error categories:
- `ENC_HEX_INVALID_CHAR`
- `ENC_HEX_INVALID_LEN`
- `ENC_B64URL_INVALID_CHAR`
- `ENC_B64URL_PADDING_NOT_ALLOWED`
- `ENC_B64URL_INVALID_DECODE`
- `ENC_LEN_MISMATCH`
- `ENC_JSON_TYPE_MISMATCH`
- `ENC_RANGE_INVALID` (e.g., counter > u64)

**Hard rule:** Do not “best effort” decode. Reject early.

---

## 11. Interop Test Vectors (Requirement)

This repo MUST include cross-language vectors in:
- `docs/crypto/test-vectors/`
- `docs/handshake/test-vectors/`
- `docs/identity/test-vectors/`
- `docs/Sessions/test-vectors/`

Vectors MUST cover:
1. Hex decode/encode round-trips for IDs (device/session/key).
2. Base64url decode/encode round-trips for fixed sizes (32/64/16, nonce sizes).
3. Counter parsing: wire decimal string → u64 bounds-check → BE64.
4. Canonical AAD bytes for fixed inputs.
5. Deterministic nonce derivation bytes for fixed inputs.
6. AEAD seal/open round-trip per suite:
   - plaintext → sealed
   - Swift decrypts Rust output and vice versa
7. Negative vectors:
   - uppercase hex
   - `0x` prefix
   - base64 padding
   - invalid lengths
   - whitespace contamination
   - counter overflow

**Hard rule:** Vectors MUST be generated by the Rust reference implementation and verified by Swift and Node harnesses.

---

## 12. Implementation Guidance (Non-normative)

### 12.1 Rust
- Keep hex/base64url decode in small audited modules.
- Use constant-time comparisons where relevant for tags/MAC.
- Never accept both padded and unpadded base64url.

### 12.2 Node
- Counters MUST be string on wire; parse via `BigInt`, bounds-check to u64, then build BE64 bytes.
- Enforce strict schema validation before any crypto/routing decisions.

### 12.3 Swift
- Use strict decoding; no trimming.
- Ensure base64url decoder rejects padding and non-url alphabet.

---

## Appendix A — Strict decoding reference (Pseudo-code)

### A.1 Strict hex decode (no trim, lowercase only)
```rust
fn hex_decode_strict(s: &str, expected_len: usize) -> Result<Vec<u8>, EncErr> {
  if s.len() != expected_len { return Err(ENC_HEX_INVALID_LEN); }
  if !s.chars().all(|c| matches!(c, '0'..='9'|'a'..='f')) { return Err(ENC_HEX_INVALID_CHAR); }
  // decode pairs...
  Ok(bytes)
}
