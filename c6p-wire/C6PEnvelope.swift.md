## Purpose

`C6PEnvelope.swift` defines the wire-level envelope for C6P v1 messages.
It is the object exchanged with the backend and persisted in storage.

The envelope is split into:
- **routing metadata** (untrusted)
- **crypto-required routing hints** (required pre-decrypt)
- **sealed payload** (ciphertext + tag)

The backend routes/stores envelopes but cannot validate content authenticity beyond transport-layer concerns.

---

## Why a unified envelope (DM / group / channel)

A single envelope reduces duplication and prevents subtle divergences across message kinds.
Differences live in:
- `messageType`
- `target` (DM device / group id / channel id)
- payload schema inside encryption

This keeps the protocol auditable and consistent.

---

## Untrusted metadata vs crypto contract

Everything outside `sealed` is untrusted and may be modified by the server or network attackers.

C6P therefore does **not** trust envelope fields for security decisions.
Security decisions are driven by:
- selecting the correct session state using `sessionId`
- computing nonce deterministically (requires `suite`, `streamId`, `counter`, `messageType`)
- AEAD verification (AAD binding + tag verification)

If AEAD verification fails, the message must be rejected.

---

## Required pre-decrypt hints

Because C6P uses deterministic nonces and binds context via AAD, the receiver must know:
- `suite` (nonce length / suite binding)
- `sessionId` (select session state)
- `streamId` (wire-stable direction: I2R / R2I)
- `counter` (nonce + replay/out-of-order policy)
- `messageType` (nonce/AAD binding)

Nonce is not transmitted; it is reconstructed.

---

## Counter semantics

`counter` is the monotonic message index for a given `(sessionId, streamId)`.

Receivers may implement:
- strict in-order requirement (fail closed on gaps)
- windowed acceptance (replay window) with buffering

The envelope does not define the window; session/state layer does.

---

## Target model

`C6PTarget` identifies the routing destination:
- DM: explicit `toDeviceId`
- Group: `groupId`
- Channel: `channelId`

These identifiers are policy-defined and may be server-visible.
They must never contain plaintext content.

---

## Timestamps and delivery state

- `clientTimestamp` is informational and not trusted.
- `serverTimestamp` is assigned by backend in UTC.
- `deliveryState` is UI-facing and may be overwritten by backend.
None of these fields participate in crypto.

---

## Security considerations

- A malicious server can reorder, duplicate, or drop envelopes.
- Authenticity/integrity is enforced only by AEAD verification using session-derived keys.
- Any mismatch in suite/stream/counter/type will be detected by nonce/AAD mismatch and tag failure.
