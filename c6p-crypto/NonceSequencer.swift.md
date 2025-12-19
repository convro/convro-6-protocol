## Purpose

`NonceSequencer.swift` defines deterministic nonce construction for C6P AEAD encryption.
Its primary goal is to guarantee nonce uniqueness without relying on randomness and without relying on local-perspective fields that could desynchronize peers.

---

## Core invariant (must-have)

Nonce inputs MUST be wire-stable and reconstructable identically by both peers.

C6P therefore uses a canonical stream identifier:
- I→R (initiator-to-responder)
- R→I (responder-to-initiator)

Local “sending/receiving” is NOT a protocol context and MUST NOT be used directly.

---

## Suite-aware nonce lengths

Nonce length is suite-defined:

- ChaCha20-Poly1305: 12 bytes
- AEGIS-128L: 16 bytes
- XChaCha20-Poly1305: 24 bytes

`C6PNonce` is protocol-level and must validate length based on the selected suite.

---

## Deterministic nonce policy

C6P requires deterministic nonces:
- no RNG
- no probabilistic uniqueness
- uniqueness guaranteed by `(sessionId, streamId, counter)`.

---

## Canonical layouts (v1)

### ChaCha20-Poly1305 (12B)
[0..3] sessionId (4B)
[4]    streamId (1B)
[5]    messageType (1B)
[6..11] counter48 (6B, BE)

### AEGIS-128L (16B)
[0..3]  sessionId (4B)
[4]     streamId (1B)
[5]     messageType (1B)
[6..7]  reserved (0x00)
[8..15] counter64 (8B, BE)

### XChaCha20-Poly1305 (24B)
[0..3]   sessionId (4B)
[4]      streamId (1B)
[5]      messageType (1B)
[6..7]   reserved (0x00)
[8..15]  counter64 (8B, BE)
[16..23] reserved (0x00)

Reserved bytes are explicitly defined to keep the layout stable and extensible.

---

## Counter rules

- For 12-byte nonce (ChaChaPoly), counter is restricted to 48 bits (overflow = protocol error).
- For 16/24-byte nonces, full 64-bit counter is used.

The counter must be monotonic per stream.

---

## Security considerations

- Nonce reuse with the same AEAD key is catastrophic. Deterministic, counter-based nonces prevent this class of bugs.
- Using wire-stable stream ids prevents sender/receiver mismatches that would break nonce/AAD consistency and cause permanent decrypt failures.
- Binding messageType in the nonce implies messageType must be known pre-decrypt (e.g., via envelope routing hint). This must be consistent with `c6p-wire/`.

---

## Non-goals

- This module does not define replay windows or out-of-order policies.
- This module does not define the AEAD AAD layout (see `AEAD.swift`).
