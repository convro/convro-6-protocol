# C6P Encoding & Canonicalization (v1)

**Status:** Production / normative  
**Scope:** Canonical byte representations for every security-critical value; strict wire decoding rules; hex/base64url contracts; endianness; JSON wire typing; “no ambiguity” policy.  
**Registry authority:** `docs/crypto/c6p-crypto-registry.md` (IDs, suites, stream IDs, message types)  
**Crypto binding:** `docs/crypto/c6p-aead-and-aad.md` (AAD layout, session_binding)  
**Key derivation:** `docs/crypto/c6p-key-schedule.md` (CTX/STREAM_CTX/BE64 usage across KDF)  
**Applies to:** Rust core, Node backend, Swift client, and any future implementation.

This document is deliberately strict. If something is “almost valid”, it MUST be rejected.

---

## 0. Design Principles (Non-negotiable)

1. **One canonical byte representation** for every logical value used in crypto (hashing/AAD/KDF/signatures).
2. **Round-trip determinism** across Rust/Node/Swift.
3. **Fail-closed parsing:** reject invalid/ambiguous encodings early.
4. **No “helpful” normalization** (no trimming, no Unicode normalization, no case-folding beyond what is explicitly permitted).
5. **No dual encodings** for the same field (e.g., sometimes hex, sometimes base64url) unless explicitly specified.
6. **No locale/timezone effects** in protocol-critical values.

---

## 1. Terminology

- **Canonical bytes:** the unique byte sequence used inside cryptographic operations (SHA/HKDF/HMAC/AAD/AEAD).
- **Wire form:** representation sent on the network (JSON fields, query params, WS frames).
- **Transport encoding:** hex or base64url used to carry bytes over JSON.

---

## 2. Global Encoding Rules (Normative)

### 2.1 ASCII labels
Protocol labels used in transcripts/KDF info/AAD MUST be ASCII byte strings (not Unicode semantics).

- MUST be ASCII
- MUST be exactly as specified (case-sensitive)
- MUST NOT include trailing NUL
- MUST NOT include whitespace unless explicitly present in the label

Examples (ASCII bytes):
- `"C6P_AAD_V1"`
- `"C6P_ROOT_V1"`, `"C6P_CHAIN_V1"`, `"C6P_MSG_V1"`, `"C6P_NONCE_V1"`, `"C6P_KC_V1"`

### 2.2 Whitespace policy
**No trimming** for any security-critical field. If any leading/trailing whitespace exists -> reject.

- hex strings: MUST NOT contain whitespace
- base64url strings: MUST NOT contain whitespace
- IDs: MUST NOT contain whitespace
- signatures: MUST NOT contain whitespace
- numeric strings (counters): MUST NOT contain whitespace

### 2.3 Case policy
- **hex:** MUST be lowercase on the wire (JSON). Default: reject uppercase A–F to prevent dual canonical forms.
- **base64url:** case-sensitive; MUST use URL-safe alphabet (`A–Z a–z 0–9 - _`) with **no padding**.

### 2.4 Length policy
All fixed-size fields MUST validate decoded length exactly.
- If it’s 15 bytes or 17 bytes when 16 expected -> reject.
- “Close enough” -> reject.

---

## 3. Endianness & Fixed-width Integers (Canonical)

C6P uses **big-endian** for fixed-width integer encodings inside canonical bytes.

### 3.1 UInt64 (8 bytes)
`BE64(x)` = 8 bytes, most significant byte first.

### 3.2 UInt32 (4 bytes)
`BE32(x)` = 4 bytes, most significant byte first.

### 3.3 Counters (Normative)
- `counter` is `UInt64`
- canonical bytes = `BE64(counter)`

**Rule:** Do not encode counters as decimal strings inside cryptographic transcripts/AAD/KDF.  
Decimal is wire/UI only.

---

## 4. Hex Encoding (Wire transport)

Hex is used for stable identifiers used frequently in routing/DB.

### 4.1 Hex alphabet (strict)
- Allowed: `[0-9a-f]` only (lowercase)
- Length MUST be even
- MUST be exact for the field
- MUST NOT contain prefix `0x`
- MUST NOT contain whitespace

### 4.2 Decoding rules (strict)
A hex string MUST be rejected if:
- contains non-hex characters
- contains uppercase A–F
- contains prefix `0x`
- contains whitespace
- wrong length

### 4.3 Canonical lengths (normative)
| Field | Bytes | Hex chars | Example |
|---|---:|---:|---|
| `C6PDeviceId` | 16 | 32 | `7f01ab...` (32 chars) |
| `C6PSessionId` | 8 | 16 | `0a1b2c3d4e5f6789` |
| `C6PKeyId` | 8 | 16 | `0011223344556677` |

**Hard rule:** `session_id` on wire MUST be **hex16** (lowercase) and represent exactly **8 bytes**.

### 4.4 Canonical bytes
Hex is *transport only*. Canonical bytes are always the decoded fixed-width bytes:

- `device_id_bytes = hex_decode(device_id_hex)` (must be 16 bytes)
- `session_id_bytes = hex_decode(session_id_hex)` (must be 8 bytes)
- `key_id_bytes = hex_decode(key_id_hex)` (must be 8 bytes)

---

## 5. Base64url (Wire transport for binary)

Base64url is used for binary fields (keys, signatures, hashes, ciphertext, tags, derived keys, nonces).

### 5.1 Alphabet & padding (strict)
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
| `mk_material` | 32 |
| `root_key` / `chain_key` / `kc_key` | 32 |

**Hard rule:** Always validate decoded byte count.

---

## 6. JSON Wire Canonicalization (Transport-level)

JSON is used for HTTP and some WS messages.

### 6.1 JSON parsing policy (strict)
- Use a standards-compliant JSON parser.
- Reject invalid JSON and type mismatches.
- Reject duplicate keys **where possible** (preferred in Rust; in Node/Swift document parser behavior and add explicit checks if needed).
- Enforce strict types:
  - IDs: `string`
  - enums: `number` (0–255) OR `string` (choose one; see §6.4)
  - counters: `string` (decimal)
  - binary: `string` (base64url no padding)

### 6.2 No JSON-in-crypto (critical)
Cryptographic transcripts/AAD/KDF MUST NOT be defined as “JSON bytes” or “string concatenation of JSON fields”.

Only canonical byte layouts defined by crypto docs are hashed/signed.

### 6.3 Counter wire type (normative)
To avoid JS integer precision issues:

- `counter` on JSON wire MUST be a **decimal string** with digits only (`[0-9]+`), no leading/trailing whitespace.
- Parse using u128/BigInt, bounds-check to u64, then canonicalize to `BE64(counter)`.

**Hard rule:** Any non-digit, empty string, or value > `u64::MAX` MUST be rejected.

### 6.4 Enum wire type (normative choice)
To minimize ambiguity, C6P v1 uses **numeric u8** for enums on wire:

- `suite_id`: JSON number in `[0..255]` (must match registry)
- `stream_id`: JSON number in `[0..255]` (must match registry)
- `message_type`: JSON number in `[0..255]` (must match registry)

**Hard rule:** Unknown enum values MUST be rejected.

(If you later want string enums for readability, that is a v2 wire change and must be versioned.)

### 6.5 Stable field names (strict)
Field names are case-sensitive; do not accept aliases.

Examples:
- accept `session_id` **only if** spec says `session_id`
- reject `sessionId` if spec says `session_id`

**Hard rule:** Choose one naming convention per endpoint/schema and lock it. (This doc does not mandate snake vs camel globally; it mandates “no aliases”.)

---

## 7. Canonicalization of Protocol-Critical Objects

This section defines exactly what bytes are used when hashing/signing/KDF/AAD are constructed.

### 7.1 DeviceId / SessionId / KeyId canonical bytes
- `device_id_bytes = hex_decode(device_id_hex)` (16 bytes)
- `session_id_bytes = hex_decode(session_id_hex)` (8 bytes)
- `key_id_bytes = hex_decode(key_id_hex)` (8 bytes)

**Hard rule:** Do not mix “numeric DB ID” and “wire hex string” without a stable conversion rule. Canonical bytes are the decoded fixed-width bytes.

### 7.2 Public keys
- X25519/Ed25519 public keys are raw 32 bytes.
- Canonical bytes are exactly those 32 bytes, no prefixes.

### 7.3 Signatures
- Ed25519 signature is exactly 64 bytes.

### 7.4 Hashes
- SHA-256 hash canonical bytes are 32 bytes.

---

## 8. Canonical CTX and STREAM_CTX (Cross-doc binding)

These byte layouts MUST be identical everywhere:

### 8.1 CTX (from Key Schedule)
`CTX = session_id(8) || initiator_device_id(16) || responder_device_id(16)` (40 bytes)

### 8.2 STREAM_CTX (from Key Schedule)
`STREAM_CTX = U8(stream_id) || U8(message_type) || U8(suite_id)` (3 bytes)

### 8.3 Session binding (from AEAD/AAD)
`session_binding = SHA256("C6P_BIND_V1" || session_id(8) || initiator_device_id(16) || responder_device_id(16))` (32 bytes)

**Hard rule:** `session_binding` is computed from canonical local session state and MUST NOT be attacker-influenced.

---

## 9. Canonical AAD Wire→Bytes Mapping (Cross-doc binding)

When reconstructing AAD (see `c6p-aead-and-aad.md`), fields are mapped as:

- `session_id_hex` (wire) → `session_id_bytes` (8 bytes)
- `counter` (wire decimal string) → parse u64 → `BE64(counter)` (8 bytes)
- enums are u8 (JSON number) → `U8(x)`

**Hard rule:** Wire parsing MUST be strict before any crypto.

---

## 10. Error Handling (Normative)

Decoders MUST return structured error codes (see `docs/crypto/c6p-error-codes.md` and handshake error registry).

Minimum error categories:
- `ENC_HEX_INVALID_CHAR`
- `ENC_HEX_INVALID_LEN`
- `ENC_HEX_UPPERCASE_NOT_ALLOWED`
- `ENC_HEX_PREFIX_NOT_ALLOWED`
- `ENC_B64URL_INVALID_CHAR`
- `ENC_B64URL_PADDING_NOT_ALLOWED`
- `ENC_B64URL_INVALID_DECODE`
- `ENC_LEN_MISMATCH`
- `ENC_JSON_TYPE_MISMATCH`
- `ENC_RANGE_INVALID` (e.g., counter overflow)
- `ENC_ENUM_UNKNOWN` (unknown suite/type/stream)

**Hard rule:** Do not “best effort” decode. Reject early.

---

## 11. Interop Test Vectors (Must-have)

This repo MUST include cross-language vectors in:

- `docs/crypto/test-vectors/v1/` (or the per-topic subfolders you outlined)

Vectors MUST cover:
1. Hex decode/encode round-trips for IDs (device/session/key).
2. Base64url decode/encode round-trips for fixed sizes (32/64/16/12/24).
3. Counter parsing vectors (valid, invalid, overflow).
4. AAD bytes for fixed inputs (63 bytes hex).
5. Nonce derivation bytes for fixed inputs (suite-dependent lengths).
6. Full AEAD seal/open for each suite:
   - Rust seals, Swift opens (and vice versa)
   - Node validation harness (at least parsing + vector equality; AEAD optional if you keep Node “no secrets” policy)

**Hard rule:** Vectors MUST be generated by the Rust reference implementation and verified by Swift and any other implementation in CI.

---

## Appendix A — Reference Implementations (Pseudo-code)

### A.1 Strict hex decode (lowercase only, no trim)
```rust
fn hex_decode_strict(s: &str, expected_len: usize) -> Result<Vec<u8>, EncErr> {
  if s.len() != expected_len { return Err(ENC_HEX_INVALID_LEN); }
  if s.starts_with("0x") { return Err(ENC_HEX_PREFIX_NOT_ALLOWED); }
  if s.chars().any(|c| c.is_whitespace()) { return Err(ENC_HEX_INVALID_CHAR); }
  if s.chars().any(|c| matches!(c, 'A'..='F')) { return Err(ENC_HEX_UPPERCASE_NOT_ALLOWED); }
  if !s.chars().all(|c| matches!(c, '0'..='9'|'a'..='f')) { return Err(ENC_HEX_INVALID_CHAR); }
  // decode pairs...
  Ok(out)
}


A.2 Strict base64url decode (no padding)

fn b64url_decode_strict(s: &str, expected_bytes: Option<usize>) -> Result<Vec<u8>, EncErr> {
  if s.contains('=') { return Err(ENC_B64URL_PADDING_NOT_ALLOWED); }
  if s.chars().any(|c| c.is_whitespace()) { return Err(ENC_B64URL_INVALID_CHAR); }
  if s.chars().any(|c| !matches!(c,
      'A'..='Z'|'a'..='z'|'0'..='9'|'-'|'_')) { return Err(ENC_B64URL_INVALID_CHAR); }
  let bytes = decode_urlsafe_no_pad(s).map_err(|_| ENC_B64URL_INVALID_DECODE)?;
  if let Some(n) = expected_bytes { if bytes.len() != n { return Err(ENC_LEN_MISMATCH); } }
  Ok(bytes)
}

A.3 Counter from wire decimal string
fn parse_counter_u64(s: &str) -> Result<u64, EncErr> {
  if s.is_empty() { return Err(ENC_RANGE_INVALID); }
  if s.chars().any(|c| !c.is_ascii_digit()) { return Err(ENC_RANGE_INVALID); }
  let v = s.parse::<u128>().map_err(|_| ENC_RANGE_INVALID)?;
  if v > u64::MAX as u128 { return Err(ENC_RANGE_INVALID); }
  Ok(v as u64)
}

Appendix B — Canonical Length Quick Reference

device_id_hex: 32 chars → 16 bytes

session_id_hex: 16 chars → 8 bytes

key_id_hex: 16 chars → 8 bytes

counter_wire: decimal string → u64 → 8 bytes BE64

x25519 pub: 32 bytes (b64url)

ed25519 pub: 32 bytes (b64url)

ed25519 sig: 64 bytes (b64url)

sha256 hash: 32 bytes (b64url)

tag: 16 bytes (inside sealed)

nonce: 12 / 24 / 16 bytes depending on suite
