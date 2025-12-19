## Purpose

`C6PSessionState` represents the complete local state of a C6P device-to-device session.
It is persisted locally and restored on startup.

The session state is the source of truth for:
- selecting session keys
- deterministic nonce reconstruction
- counter allocation and replay/out-of-order policy
- fail-closed behavior (needs re-handshake)

---

## Core identity

A C6P session is defined by:
- `sessionId` (shared between both parties)
- `localDeviceId` and `remoteDeviceId` (device-scoped sessions)
- `role` of local device (`initiator` or `responder`)

This design supports multi-device accounts without pretending a single account key decrypts everywhere.

---

## Crypto agility

`suite` stores the negotiated encryption suite for the session.

Requirements:
- suite is negotiated during handshake and remains stable for session lifetime
- envelopes include `suite` as a pre-decrypt hint
- AAD binds `suite` to prevent downgrade/mismatch

Fallback suites may exist for compatibility but must be explicit and versioned.

---

## Chain keys and ratchet

The state holds:
- `rootKey`
- `sendChainKey` and `recvChainKey`

Requirements:
- each chain key is bound to (sessionId, local/remote device ids, role, direction)
- message keys are derived from the chain key + wire-stable stream + counter + message type (per spec)
- chain advancement rules are enforced by SessionService

---

## Wire-stable streams and counters

C6P uses **wire-stable** stream identifiers:
- `I2R` (Initiator -> Responder)
- `R2I` (Responder -> Initiator)

Session state tracks:
- `nextI2RCounter`
- `nextR2ICounter`

This avoids ambiguity when local POV differs between devices.
It also makes envelope fields stable and easy to audit.

Outgoing:
- allocate counter only via `allocateOutgoingCounter()`
- counter increments monotonically per stream

Incoming:
- validate counter via replay policy
- for strict policy: accept only `counter == expected`

---

## Replay policy

`replayPolicy` defines how to handle ordering:
- `STRICT_IN_ORDER`: simplest and safest for v1, fail closed on gaps
- `WINDOWED`: optional extension for buffering/out-of-order

v1 can ship with STRICT only. WINDOWED requires explicit spec for buffering limits.

---

## Session status and fail-closed behavior

Session status is explicit:
- `ACTIVE`
- `CLOSED`
- `NEEDS_REHANDSHAKE`

If crypto verification fails or counters desync beyond policy:
- session must transition to `NEEDS_REHANDSHAKE`
- clients should not silently continue with "best effort" fallbacks

---

## Storage requirements

SessionState persistence must be:
- atomic on update (counters and keys)
- versioned/migratable
- resistant to partial writes (crash-safety)

Key material must be stored in secure storage when possible (e.g., Keychain on iOS).

---

## Nonce reconstruction requirement

C6P does not transmit nonces.
Nonce is reconstructed from:
- suite
- sessionId
- streamId
- messageType
- counter

Therefore envelopes must carry these hints.
