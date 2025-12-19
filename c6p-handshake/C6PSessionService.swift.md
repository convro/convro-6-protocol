## Purpose

`C6PSessionService` is the only API the app/UI should use for C6P DM crypto.

It owns:
- session acquisition (load or create)
- DM encryption into `C6PEnvelopeDM`
- DM decryption from `C6PEnvelopeDM`
- ratcheting (chain keys + counters)
- strict validation + fail-closed error handling

The UI should not touch primitives directly.

---

## v1 assumptions

- One active session per `(localDeviceId, remoteDeviceId)`
- DM delivery is assumed *in-order* for a given session direction
- If state becomes inconsistent, the session is marked `NEEDS_REHANDSHAKE`
  and a new handshake must be performed.

This is deliberate to keep v1 auditable and predictable.

---

## Envelope-driven session lookup

Incoming envelopes carry `sessionId`.
Therefore the service loads sessions by `(localDeviceId, sessionId)`.

This avoids incorrect pairing when:
- multiple sessions exist over time
- remote changes devices
- an attacker attempts to inject across device-pairs

The store should support O(1) lookup for `(localDeviceId, sessionId)`.

---

## Strict validation (fail-closed)

Before any decryption:
- `envelope.c6pVersion` must equal `C6P_VERSION`
- `messageType` must be `.dm`
- `toDeviceId` must equal `localDeviceId`
- loaded session must be `ACTIVE`
- `envelope.fromDeviceId` must match `session.remoteDeviceId`

If any check fails, the envelope is rejected.

---

## Mandatory wire-AAD binding (DM)

Even though the envelope contains routing metadata in plaintext,
we still authenticate critical fields via AEAD AAD to prevent **envelope swapping**.

Mandatory AAD (DM):
- fromDeviceId
- toDeviceId
- sessionId
- clientMessageId

This ensures an attacker cannot:
- copy a ciphertext+tag into another envelope with different routing fields
- mutate `clientMessageId` without detection

If this schema changes, the AAD label/version must change too
(e.g., `C6P_WIRE_AAD_DM_V2`).

---

## Ratchet rules

### Encrypt (sending)
1) derive messageKey from `sendChainKey` + `sendCounter`
2) build nonce from `sessionId + role + direction + type + counter`
3) AEAD seal
4) ONLY THEN:
   - ratchet chain key forward
   - increment sendCounter
   - persist session

### Decrypt (receiving)
1) derive messageKey from `recvChainKey` + `recvCounter`
2) build nonce
3) AEAD open
4) ONLY THEN:
   - ratchet recvChainKey forward
   - increment recvCounter
   - persist session

This prevents losing sync on failed operations.

---

## Failure handling

If AEAD open fails:
- session is marked `NEEDS_REHANDSHAKE`
- error is thrown (no silent fallbacks)

This is intentional: if integrity/authenticity cannot be verified,
the system must fail closed.

---

## Extension points

- `extraAAD` allows optional additional authenticated context.
  It must be deterministic and identically reproducible by the receiver.
- For advanced out-of-order support, v2 can add:
  - skipped-key cache
  - bounded lookahead window
  - explicit message numbers inside encrypted payload
  but v1 keeps it minimal.
