## Purpose

`Primitives.swift` is the foundation layer for C6P v1:
- global protocol constants (version)
- canonical algorithm identifiers
- wire-level suite identifiers
- wire-stable stream identifiers
- secure randomness (CSPRNG)
- encoding helpers (hex, base64url, big-endian ints)
- HKDF-SHA256 (RFC 5869)
- small protocol primitives (KeyId, DeviceId, SessionId, MessageCounter)
- message type identifiers
- fingerprint helper for UI verification

This file contains **no protocol state machine**. It is the dependency base used by higher layers.

---

## Global constants

- `C6P_VERSION = 1`  
Used in AAD, HKDF `info` domain separation, envelopes, downgrade checks.

---

## Algorithm identifiers

`C6PAlgorithmId.*` are spec-facing string constants used for:
- audits and documentation
- transcript binding (HKDF info)
- explicit labeling of choices in logs/specs

They are not wire-compact; wire uses `C6PEncryptionSuite`.

---

## Encryption suites (wire-level)

`C6PEncryptionSuite` defines compact suite IDs:
- `v1_chachaPoly`   (0x01) — Swift reference (CryptoKit)
- `v1_aegis128l`    (0x02) — protocol preferred
- `v1_xchachaPoly`  (0x03) — fallback

Suite IDs must remain stable forever once deployed.

---

## Stream semantics (critical)

`C6PStreamId` is the **canonical** “direction” concept:
- `i2r` = Initiator → Responder
- `r2i` = Responder → Initiator

This prevents local-PoV mismatches and is used in:
- chain key separation
- message key derivation context
- nonce construction
- AEAD AAD binding

Local sending/receiving must never be used directly as wire context.

---

## Randomness

`C6PRandom` provides cryptographically secure random bytes via `SecRandomCopyBytes`.
Used for identifiers, salts, and any cryptographic material explicitly defined as random.

Nonce generation is not RNG-based in C6P (nonces are deterministic).

---

## Encoding helpers

### base64url (no padding)
Used for URLs/JSON safe encoding (no `=` padding).

### hex
Used for stable JSON-friendly representations of identifiers.

### big-endian integers
All integer conversions are implemented without alignment assumptions.

---

## HKDF-SHA256

`C6PHKDF` implements HKDF (RFC 5869):
- Extract (HMAC-SHA256)
- Expand
- deriveKey (Extract + Expand)

HKDF `info` must be used consistently for domain separation across modules.

---

## Identifiers & counters

- `C6PKeyId` (8B) — key identifiers (identity/prekeys/etc.), JSON = lowercase hex
- `C6PDeviceId` (8B) — device identifiers, JSON = lowercase hex
- `C6PSessionId` (4B) — v1 session identifier (note: may be widened in future versions)
- `C6PMessageCounter` (u64) — monotonic counter used for nonce/AAD and ratcheting

---

## Message types

`C6PMessageType` provides compact wire IDs:
- dm, group, channel, control

If messageType is used in nonce/AAD, the envelope/routing layer must ensure it is known pre-decrypt.

---

## Fingerprint helper

`C6PFingerprint` provides a short user-facing verification string:
- first 8 bytes of SHA256(pubkey)
- uppercase hex formatted as `XXXX-XXXX-XXXX-XXXX`

This is not a cryptographic binding primitive; it is a UX verification aid.

---

## Security considerations

- Fail-closed design: unknown suite/version should be rejected by upper layers.
- Domain separation: all HKDF usage must bind to version, suite, session, stream, and purpose labels.
- Stream id is wire-stable: do not substitute local direction.
