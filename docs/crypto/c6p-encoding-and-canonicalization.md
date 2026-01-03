# C6P Encoding & Canonicalization (v1)

**Status:** Production / normative  
**Scope:** Canonical bytes for every field that crosses module/language boundaries; hex/base64url rules; endianness; JSON canonical forms; strict decoding; “no ambiguity” policy.  
**Depends on:** `docs/crypto/c6p-crypto-registry.md`, `docs/crypto/c6p-key-schedule.md`, `docs/crypto/c6p-aead-and-aad.md`, `docs/handshake/island-accord-wire.md`  
**Applies to:** Rust core, Node backend, Swift client (and any future implementation).

This document is deliberately strict. If something is “almost valid”, it MUST be rejected.

---

## 0. Design Principles (Non-negotiable)

1. **One canonical byte representation** for every logical value.
2. **Round-trip determinism** across Rust/Node/Swift.
3. **Fail-closed** parsing: reject invalid/ambiguous encodings.
4. **No “helpful” normalization** (no trimming, no case-folding beyond what is explicitly permitted).
5. **No dual encodings** for the same field (e.g., sometimes hex, sometimes base64url) unless explicitly specified.
6. **No locale/timezone effects** in cryptographic or protocol-critical material.

---

## 1. Terminology

- **Canonical bytes**: the unique byte sequence that represents a value *inside cryptographic operations* (hashing/AAD/KDF signatures).
- **Wire form**: the representation sent on the network (JSON fields, query parameters, websocket frames).
- **Transport encoding**: hex or base64url used to carry bytes over JSON.

---

## 2. Global Encoding Rules

### 2.1 ASCII labels
Protocol labels used in transcripts/KDF info/AAD are ASCII byte strings, not Unicode.

- MUST be ASCII
- MUST be exactly as specified (case-sensitive)
- MUST NOT include trailing NUL
- MUST NOT include whitespace unless explicitly included in the label string

Examples:
- `"C6P_AAD_V1"` (ASCII bytes)
- `"C6P_HANDSHAKE99_V1"` / `"C6P_PREKEY_V1"` (if used in IslandAccord v1 as specified in handshake docs)

### 2.2 Whitespace policy
**No trimming** in decoding of security-critical fields:
- hex strings: MUST NOT contain whitespace
- base64url strings: MUST NOT contain whitespace
- IDs: MUST NOT contain whitespace
- signatures: MUST NOT contain whitespace

If a value arrives with leading/trailing whitespace -> reject.

### 2.3 Case policy
- **hex**: MUST be lowercase on the wire (JSON).  
  - Decoder MAY accept uppercase **only** if explicitly allowed for that field.  
  - Default: reject uppercase to prevent dual canonical forms.
- **base64url**: case-sensitive; MUST use URL-safe alphabet (`A–Z a–z 0–9 - _`) with **no padding**.

### 2.4 Length policy
All fixed-size fields MUST validate their decoded length exactly.
- If it’s 31 or 33 bytes -> reject.
- “Close enough” -> reject.

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
- `counter` is `UInt64`, canonical bytes = `BE64(counter)`.

**Rule:** Do not encode counters as decimal strings inside cryptographic transcripts/AAD/KDF.
Decimal is allowed only as UI/debug presentation and must never be hashed.

---

## 4. Hex Encoding (Wire transport)

Hex is used for stable identifiers that are “small” and frequently used in routing/DB:
- `device_id` (8 bytes -> 16 hex chars)
- `session_id` (4 bytes -> 8 hex chars)
- `key_id` (8 bytes -> 16 hex chars)

### 4.1 Hex alphabet
- Allowed: `[0-9a-f]` only (lowercase)
- Length MUST be even
- MUST be exact for the field (see §4.3)

### 4.2 Decoding rules
A hex string MUST be rejected if:
- contains non-hex characters
- contains uppercase A–F (unless explicitly permitted)
- contains prefix `0x`
- contains whitespace
- wrong length

### 4.3 Canonical lengths (normative)
| Field | Bytes | Hex chars | Example |
|---|---:|---:|---|
| `C6PDeviceId` | 8 | 16 | `7f01ab...` |
| `C6PSessionId` | 4 | 8 | `0a1b2c3d` |
| `C6PKeyId` | 8 | 16 | `0011223344556677` |

**Rule:** Session IDs on the wire MUST be 8 hex characters (lowercase) and represent exactly 4 bytes.

### 4.4 Canonical bytes
Hex is *only transport*. Canonical bytes are always the decoded fixed-width bytes:
- `device_id_bytes = hex_decode(device_id_hex)` (must be 8 bytes)
- `session_id_bytes = hex_decode(session_id_hex)` (must be 4 bytes)
- `key_id_bytes = hex_decode(key_id_hex)` (must be 8 bytes)

---

## 5. Base64url (Wire transport for binary)

Base64url is used for:
- public keys (X25519: 32 bytes, Ed25519: 32 bytes)
- signatures (Ed25519: 64 bytes)
- ciphertext blobs, tags, nonces, derived keys (varies)
- hashes (SHA-256: 32 bytes)

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
- Reject invalid JSON, duplicate keys (where possible), and type mismatches.
- Enforce strict types:
  - IDs: string
  - counters: number OR string? (choose one canonical—see §6.3)
  - binary: base64url string

### 6.2 No JSON-in-crypto
**Critical rule:** Cryptographic transcripts/AAD/KDF MUST NOT be defined as “JSON bytes” or “string concatenation of JSON fields”.  
Only canonical byte layouts defined in crypto/handshake docs are used.

### 6.3 Counter wire type (normative recommendation)
To avoid JS integer precision issues:
- `counter` MUST be encoded as a **string** on JSON wire if it can exceed `2^53-1`.
- In DM baseline, you might not hit that soon, but production-grade should still be correct.

**Normative choice for Convro/IslandAccord v1:**
- `counter` on JSON wire = **string decimal**  
- Canonical bytes = `BE64(parse_u64(counter_string))`

(If you already ship `counter` as JSON number in Node, keep it for now but document a migration path + validation caps. Auditors will ask.)

### 6.4 Stable field names
Field names are case-sensitive; do not accept aliases.
Example:
- accept `sessionId` if spec says `sessionId`
- reject `session_id` if spec says `sessionId`

(Choose one naming convention and lock it. In docs we treat those as wire-contract.)

---

## 7. Canonicalization of Protocol-Critical Objects

This section defines exactly what bytes are used when hashing/signing.

### 7.1 DeviceId / SessionId / KeyId canonical bytes
- `device_id_bytes = BE64(device_id_u64)` OR `hex_decode(device_id_hex)` (must match)
- `session_id_bytes = BE32(session_id_u32)` OR `hex_decode(session_id_hex)`
- `key_id_bytes = BE64(key_id_u64)` OR `hex_decode(key_id_hex)`

**Rule:** We do not mix “numeric ID in DB” with “wire hex string” without a stable conversion.

### 7.2 Public keys
- X25519/Ed25519 public keys are treated as raw bytes (`32`).
- Canonical bytes are exactly those 32 bytes, no prefixes.

### 7.3 Signatures
- Ed25519 signature is exactly 64 bytes.

### 7.4 Hashes
- SHA-256 hash canonical bytes are 32 bytes.

---

## 8. Canonical Transcript Rules for IslandAccord v1

IslandAccord transcripts MUST use:
- fixed-width IDs (device/session/key IDs) as raw bytes
- public keys as raw bytes
- explicit flags/markers for optional parts
- protocol labels as ASCII bytes

**Rule:** A transcript MUST NOT depend on:
- JSON stringification
- platform-specific UTF-8 normalization
- locale settings
- unordered maps/dictionaries

If the handshake doc defines an “OTP-present marker”, it MUST be a single byte with fixed value (e.g., `0x00` / `0x01`) and MUST be included even when OTP is absent.

---

## 9. Canonical AAD Rules (link)

AAD is defined in `docs/crypto/c6p-aead-and-aad.md` and is **fully canonical**:
- ASCII label
- fixed-width numeric fields
- fixed byte order
- stable length

This doc adds only the **encoding contracts**:
- session_id hex -> decode -> 4 bytes
- device_id hex -> decode -> 8 bytes
- counter string -> parse -> u64 -> 8 bytes BE64

---

## 10. Error Handling (Normative)

Decoders MUST return structured error codes (see `docs/handshake/island-accord-error-codes.md` and crypto error registry).

Minimum error categories:
- `ENC_HEX_INVALID_CHAR`
- `ENC_HEX_INVALID_LEN`
- `ENC_B64URL_INVALID_CHAR`
- `ENC_B64URL_PADDING_NOT_ALLOWED`
- `ENC_B64URL_INVALID_DECODE`
- `ENC_LEN_MISMATCH`
- `ENC_JSON_TYPE_MISMATCH`
- `ENC_RANGE_INVALID` (e.g., counter > u64)

**Rule:** Do not “best effort” decode. Reject early.

---

## 11. Interop Test Vectors (Must-have)

This repo MUST include cross-language vectors in `docs/crypto/test-vectors/`.

Vectors MUST cover:
1. Hex decode/encode round-trips for IDs.
2. Base64url decode/encode round-trips for 32/64/16 bytes.
3. AAD bytes for fixed inputs (`aad_hex`).
4. Nonce derivation bytes for fixed inputs (`nonce_b64u`).
5. Full seal/open for each suite:
   - plaintext -> sealed (b64u)
   - ensure Swift decrypts Rust output and vice versa

Vector file format recommendation (JSON):
- `case_id`
- `device_id_hex_initiator`, `device_id_hex_responder`
- `session_id_hex`
- `stream_id`, `message_type`, `suite_id`
- `counter_wire` (string)
- `aad_hex`
- `suite_key_b64u`
- `nonce_b64u`
- `plaintext_utf8`
- `sealed_b64u`

**Rule:** Vectors must be generated by the Rust reference implementation and verified by Swift and Node test harnesses.

---

## 12. Implementation Guidance (Rust / Node / Swift)

### 12.1 Rust
- Treat hex/base64url decoding as separate audited modules.
- Use constant-time comparisons where relevant (`subtle` crate) for MAC/tag comparisons if you ever manually compare.
- Never accept both padded and unpadded base64url.

### 12.2 Node
- Never use JS numbers for counters beyond `2^53-1`.
- Prefer string counters in API and convert using BigInt -> bounds-check -> u64 for canonical bytes.

### 12.3 Swift
- Use strict decoding; do not auto-trim.
- Ensure base64url decoder rejects padding and non-url alphabet.

---

## 13. Security Notes (Audit-Facing)

1. **Ambiguity attacks** (multiple encodings for same bytes) are prevented by strict rejection of non-canonical encodings.
2. **Precision loss** in JS is mitigated by representing counters as decimal strings.
3. **Cross-language drift** is mitigated by test vectors and canonical byte layouts.

---

## Appendix A — Reference Implementations (Pseudo-code)

### A.1 Strict hex decode (no trim, lowercase only)

fn hex_decode_strict(s: &str, expected_len: usize) -> Result<Vec<u8>, EncErr> {
if s.len() != expected_len { return Err(ENC_HEX_INVALID_LEN); }
if !s.chars().all(|c| matches!(c, '0'..='9'|'a'..='f')) { return Err(ENC_HEX_INVALID_CHAR); }
// decode pairs...
}


### A.2 Strict base64url decode (no padding)



fn b64url_decode_strict(s: &str, expected_bytes: Option<usize>) -> Result<Vec<u8>, EncErr> {
if s.contains('=') { return Err(ENC_B64URL_PADDING_NOT_ALLOWED); }
if s.chars().any(|c| !is_b64url(c)) { return Err(ENC_B64URL_INVALID_CHAR); }
let bytes = decode_urlsafe_no_pad(s).map_err(|_| ENC_B64URL_INVALID_DECODE)?;
if let Some(n) = expected_bytes { if bytes.len() != n { return Err(ENC_LEN_MISMATCH); } }
Ok(bytes)
}


### A.3 Counter from wire string



fn parse_counter_u64(s: &str) -> Result<u64, EncErr> {
// no whitespace, only digits
if s.is_empty() || !s.chars().all(|c| c.is_ascii_digit()) { return Err(ENC_RANGE_INVALID); }
let v = s.parse::<u128>().map_err(|_| ENC_RANGE_INVALID)?;
if v > u64::MAX as u128 { return Err(ENC_RANGE_INVALID); }
Ok(v as u64)
}


---

## Appendix B — Canonical Length Table (Quick Reference)

- device_id_hex: 16 chars -> 8 bytes
- session_id_hex: 8 chars -> 4 bytes
- key_id_hex: 16 chars -> 8 bytes
- x25519 pub: 32 bytes (b64url)
- ed25519 pub: 32 bytes (b64url)
- ed25519 sig: 64 bytes (b64url)
- sha256 hash: 32 bytes (b64url)
- tag: 16 bytes (inside sealed)
- nonce: 12 / 24 / 16 bytes depending on suite

