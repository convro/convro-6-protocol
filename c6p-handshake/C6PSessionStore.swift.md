## Purpose

`C6PSessionStore` defines how C6P sessions are persisted on the client.

Sessions are device-to-device and must be retrievable to:
- decrypt incoming envelopes (which carry `sessionId`)
- allocate counters and update chain state atomically
- present session health/debug views

---

## Synchronous semantics (hard requirement)

The protocol is synchronous.

This means:
- `saveSession()` must commit before returning
- `deleteSession()` must commit before returning

If a store uses async IO internally, it must block until the write is durable.

Reason: crypto state (counters/ratchets) cannot tolerate “eventual consistency”.
A `load()` immediately after `save()` must see the new state.

---

## Required lookups

### Pair-based
`loadSession(localDeviceId, remoteDeviceId)` is useful for UI and “active session with this device”.

### Envelope-based (must exist)
Envelopes carry `sessionId`, so the store must support:
`loadSession(localDeviceId, sessionId)`

A default implementation may scan `allSessions(for:)`, but production stores SHOULD implement O(1) lookup.

---

## Atomic updates

The store must persist `C6PSessionState` atomically:
- chain keys
- counters
- status transitions (e.g., NEEDS_REHANDSHAKE)

Partial writes or lost updates can cause:
- nonce/AAD mismatch
- counter desync
- permanent decrypt failures

---

## Thread-safety

Implementations must be thread-safe because:
- networking receive loop
- UI sending
- background sync

may touch the store concurrently.

---

## Deletion semantics

`deleteSession` may be used for:
- logout / wipe
- key compromise response
- pruning old/closed sessions

Delete-all must clear both primary storage and any indexes.

---

## In-memory reference store

`C6PMemorySessionStore` is a reference implementation for:
- unit tests
- prototyping

It provides:
- sync barrier writes (immediate visibility)
- O(1) lookup by (localDeviceId, sessionId) via an index
