## Purpose

`KeySchedule.swift` defines the canonical key derivation pipeline for C6P sessions:
- deriving the session Root Key from handshake secret material
- deriving two initial Chain Keys (wire-stable streams I→R and R→I)
- deriving per-message AEAD keys with forward-only ratcheting

This module is protocol-facing: it defines **what keys exist**, **how they are derived**, and **what invariants they must satisfy**.

---

## Protocol assumptions

1. **Device-to-device sessions:** Keys are established between devices, not “accounts”.
2. **Two directional streams:** Every session has exactly two wire-stable streams:
   - `I→R` (initiator-to-responder)
   - `R→I` (responder-to-initiator)
3. **AEAD agility:** Message keys are suite-tagged; suite selection is negotiated during handshake.
4. **Domain separation:** Every HKDF invocation uses explicit labels and context binding.
5. **Per-message uniqueness:** Each message derives a fresh message key; message keys MUST NOT be reused.

---

## Key hierarchy

### Root Key (RK)
- 32 bytes
- derived once at session establishment
- derived from:
  - ECDH shared secret (X25519)
  - transcript salt (handshake hash / context)
  - sessionId and both device IDs
- RK is not used directly for encryption

### Chain Keys (CK)
- 32 bytes each
- two streams per session:
  - `CK_I2R`
  - `CK_R2I`
- chain keys are wire-stable (same CK for both peers for the same stream)
- CK is used only as KDF input to derive message keys and next CK

### Message Keys (MK)
- 32 bytes (AEAD key)
- derived per message from the current chain key
- suite-tagged (e.g., preferred AEGIS-128L, fallback XChaCha20-Poly1305)

---

## Stream semantics (critical invariant)

C6P MUST NOT use “local sending/receiving” as a protocol context.
Instead, it MUST use a wire-stable stream id:

- `stream = I→R`
- `stream = R→I`

This ensures both peers derive identical keys for the same traffic stream.

---

## Ratchet step (recommended)

Preferred derivation for each message:

`HKDF(CK_i, info, 64) => MK_i (32) || CK_{i+1} (32)`

This guarantees:
- per-message key uniqueness
- forward-only progression (forward secrecy across steps)
- no key reuse when counters advance

The message counter may be included in `info` to bind key derivation to the canonical message sequence.

---

## Failure semantics

- Any mismatch in suite, stream id, or context inputs is a protocol error.
- If chain state becomes inconsistent (e.g., counter/ratchet desync), the session MUST fail closed and require re-establishment or explicit recovery logic.

No silent “repair” or fallback is allowed.

---

## Security considerations

- **Domain separation:** labels + version + session + stream prevent cross-session/key confusion.
- **Wire-stable stream separation:** prevents sender/receiver deriving different keys due to local POV.
- **Minimal key exposure:** RK and CK are never used for AEAD directly.
- **Agility:** suite tagging prevents ambiguous usage of keys under different algorithms.

---

## Non-goals

- This module does not define:
  - handshake protocol details
  - nonce generation
  - AAD layout
  - replay windows or out-of-order handling
  - storage encryption policy

Those are defined in their respective modules.

---

## Future extensions

- Dual-track AEAD:
  - transport keys optimized for throughput (AEGIS-128L)
  - storage/offline keys hardened against nonce misuse (AES-GCM-SIV / XChaCha)
- Hybrid PQ KEM (X25519 + Kyber) as an extension impacting root derivation only (versioned and opt-in).
