# IslandAccord v1 — State Machine & Server Invariants (island-accord-state-machine.md)

**Status:** PRODUCTION / CANONICAL / NORMATIVE  
**Handshake family:** IslandAccord v1  
**Scope:** DM session state machine (server authority), invariants, idempotency rules, TTL/replay/OTP reservation lifecycle, and concurrency notes.  
**Audience:** Security auditors, backend implementers, client implementers.  
**Principle:** The server is **not trusted for secrecy**, but is **authoritative for state, routing, and scarcity resources** (OTP).  
**Fail-closed:** Invalid transitions MUST be rejected.

**Depends on (normative):**
- `docs/handshake/island-accord-wire.md`
- `docs/handshake/island-accord-crypto.md`
- `docs/crypto/c6p-error-codes.md`
- `docs/crypto/c6p-crypto-registry.md`
- `docs/crypto/c6p-replay-and-skip-window.md` (for DM ratchet replay semantics; handshake replay is covered here)

---

## 0. Entities & Terms

### 0.1 Actors
- **Initiator (I):** party creating the DM session.
- **Responder (R):** party receiving and accepting the DM session.
- **Server (S):** message router + state authority; **never derives secrets**.

### 0.2 Canonical identifiers (wire-stable)

All IDs MUST follow `island-accord-wire.md` §1.

- `sessionId`: **8 bytes** encoded as **hex16 lowercase**  
  - Regex: `^[0-9a-f]{16}$`
- `initiatorDeviceId`: **16 bytes** encoded as **hex32 lowercase**
- `responderDeviceId`: **16 bytes** encoded as **hex32 lowercase**
- `spkId`, `otpId`: **8 bytes** encoded as **hex16 lowercase** (prekey ids)

### 0.3 Cryptographic suite policy (server-level)
- `suiteId` is carried in the offer and is part of transcript/signature binding (client-side).
- Server MUST enforce supported suites per policy.
- **Production default policy:** ChaCha20-Poly1305 (`suite_id = 0x01`) unless explicitly configured otherwise.
- Unknown or disallowed `suiteId` MUST be rejected:
  - `C6P.AEAD.UNSUPPORTED_SUITE`

### 0.4 Records (conceptual)

#### 0.4.1 DM Session Record (`dm_sessions`)
Minimum conceptual fields (implementation may split/normalize):
- `id` (server db id)
- `initiatorUserId`, `initiatorDeviceId`
- `responderUserId`, `responderDeviceId`
- `sessionId` (hex16)
- `suiteId` (u8 semantics)
- `offerBlob` (immutable once written; opaque to server beyond strict decoding checks)
- `acceptBlob` (immutable once written; opaque to server beyond strict decoding checks)
- `state` (enum)
- `otpId` (nullable, hex16)
- `createdAt`, `updatedAt`, `expiresAt`

#### 0.4.2 OTP Record (`prekeys_otp`)
- `deviceId` (hex32)  // owner device (responder)
- `otpId` (hex16)
- `pubKeyX25519` (b64url32)
- `status` enum:
  - `AVAILABLE` / `RESERVED` / `PENDING_CONSUMPTION` / `CONSUMED` / `EXPIRED`
- optional bindings (recommended):
  - `reservedForInitiatorDeviceId` (hex32, nullable)
  - `linkedSessionDbId` (nullable)
- `reservedAt`, `expiresAt`, `consumedAt`

---

## 1. Canonical Server States

### 1.1 DM session states (handshake-layer)
- `PENDING` — offer stored and deliverable to responder; not yet accepted
- `ACTIVE` — accept stored; deliverable to initiator; established at server-level (clients still must verify `kc2`)
- `REJECTED` — responder explicitly rejected (optional endpoint) or policy reject
- `EXPIRED` — offer TTL elapsed without accept
- `CANCELLED` — initiator cancelled before accept (optional endpoint)
- `ABORTED` — server terminated due to invariants violation or admin action (rare)

**Terminal states:** `ACTIVE`, `REJECTED`, `EXPIRED`, `CANCELLED`, `ABORTED`  
(“ACTIVE” is terminal for handshake; chat lifecycle continues elsewhere.)

### 1.2 OTP states (server authority)
- `AVAILABLE` — can be reserved for bundle fetch
- `RESERVED` — reserved during bundle fetch for a specific flow (TTL bounded)
- `PENDING_CONSUMPTION` — referenced by a stored offer; cannot be used elsewhere
- `CONSUMED` — permanently consumed by stored accept
- `EXPIRED` — reservation TTL elapsed without successful progression

---

## 2. State Machine Diagram (DM Sessions)

Canonical transitions:

open() ─────────────▶ PENDING ─────────────▶ ACTIVE
│ │
│ ├──────────────▶ EXPIRED (ttl / expire job)
│
├──────────────▶ REJECTED (optional reject endpoint)
├──────────────▶ CANCELLED (optional cancel endpoint)
└──────────────▶ ABORTED (admin/policy)
ACTIVE ───────────────▶ ABORTED (admin/policy)


---

## 3. Transitions (Normative)

### 3.1 `open()` — POST `/v1/dm/sessions/open`

See `island-accord-wire.md` §5.1 for wire shape.

#### Preconditions (MUST)
1) **Auth / binding**
- Request authenticated as initiator.
- `handshakeOffer.initiatorDeviceId` MUST equal auth device id.
  - else `C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH`

2) **Target binding**
- `handshakeOffer.responderDeviceId` MUST belong to `peerUserId`.
  - else `C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH` or `C6P.WIRE.INVALID_ENVELOPE` (choose one policy; keep stable)

3) **Uniqueness / replay**
- `(initiatorDeviceId, responderDeviceId, sessionId)` MUST be unique.
  - duplicates handled per §6.1 idempotency

4) **Suite policy**
- `suiteId` MUST be supported by server policy (production default: allow ChaCha20-Poly1305).
  - else `C6P.AEAD.UNSUPPORTED_SUITE`

5) **Responder SPK binding (authoritative DB check)**
- `usedSignedPrekeyId` MUST exist for responder device and MUST match stored SPK pub key.
  - if missing: `C6P.KEYS.KEY_NOT_FOUND`
  - if mismatch: `C6P.WIRE.INVALID_ENVELOPE` or `C6P.KEYS.KEY_STATE_INVALID` (policy; mismatch is suspicious)

6) **OTP pipeline (if `usedOneTimePrekeyId` is present)**
- OTP MUST:
  - belong to responder device
  - be in `RESERVED`
  - not expired
  - (recommended) be bound to initiator device or reservation token minted at bundle fetch
- If not satisfied: `C6P.HANDSHAKE.OTP_MISSING` or `C6P.KEYS.KEY_NOT_FOUND` (pick one and keep consistent)
- Server MUST transition OTP `RESERVED -> PENDING_CONSUMPTION` atomically with session creation (see §5.3).

#### Effects (MUST)
- Create `dm_sessions` row:
  - state = `PENDING`
  - store `offerBlob` (immutable)
  - set `expiresAt = createdAt + DM_OFFER_TTL`
  - store `suiteId` and referenced `otpId` if any
- Make offer deliverable to responder.

#### Fail-closed behavior (MUST)
- If any validation fails: do not create or partially create session rows.
- If OTP transition fails: abort entire transaction; do not create session.

---

### 3.2 `accept()` — POST `/v1/dm/handshake/accept`

See `island-accord-wire.md` §5.2 for wire shape.

#### Preconditions (MUST)
1) Authenticated as responder.
2) `responderDeviceId` equals auth device id.
   - else `C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH`
3) Session exists for `(sessionId, responderDeviceId)`.
   - else `C6P.WIRE.SESSION_ID_MISMATCH` or `C6P.WIRE.INVALID_ENVELOPE`
4) Session state MUST be `PENDING`.
   - if terminal already: handle per idempotency rules below
5) Session MUST NOT be expired (`now < expiresAt`).
   - else transition to `EXPIRED` and reject accept with `C6P.HANDSHAKE.STATE_VIOLATION` (or return state)

#### Effects (MUST)
- Store `acceptBlob` (immutable) containing `kc2`.
- Transition session state: `PENDING -> ACTIVE`.
- Atomically consume OTP if session references one (see §5.4):
  - `PENDING_CONSUMPTION -> CONSUMED`
- Make accept deliverable to initiator.

---

### 3.3 `reject()` — OPTIONAL (recommended, auditor-friendly)
**POST** `/v1/dm/handshake/reject` (optional)
- Preconditions: authenticated responder; session exists in `PENDING`; not expired.
- Effect: session state -> `REJECTED` (terminal); optional non-sensitive reason code.
- OTP policy:
  - If OTP is `PENDING_CONSUMPTION`, it MUST NOT be reattached to another session.
  - It SHOULD remain bound until reservation TTL cleanup marks it `EXPIRED` (or a dedicated `UNUSABLE` policy state).

### 3.4 `cancel()` — OPTIONAL (recommended)
**POST** `/v1/dm/handshake/cancel` (initiator)
- Preconditions: authenticated initiator; session exists in `PENDING`; not expired.
- Effect: state -> `CANCELLED` (terminal); stop delivery.
- OTP policy: same as `reject()`.

### 3.5 `expire()` — internal scheduler / on-read enforcement
- Trigger: `now >= expiresAt` and session state == `PENDING`.
- Effect: state -> `EXPIRED` (terminal); stop delivery.
- OTP cleanup: see §5.5.

### 3.6 `abort()` — admin/policy termination
- Can move `PENDING` or `ACTIVE` to `ABORTED` (terminal).
- Used for abuse, corrupted rows, emergency containment.

---

## 4. Server Invariants (MUST hold always)

### 4.1 Authorization invariants
- A session belongs to exactly one initiator device and one responder device.
- Server MUST NOT allow:
  - accept by a device that is not the responder device
  - offer delivery to non-responder user/device
  - accept delivery to non-initiator user/device

### 4.2 Uniqueness / replay invariants
- DB MUST enforce unique tuple:
  - `UNIQUE(initiatorDeviceId, responderDeviceId, sessionId)`
- Server MUST reject reuse of the tuple if offer differs (see §6.1).
- This is handshake-level replay resistance; message-level replay is in ratchet docs.

### 4.3 Immutability invariants
- `offerBlob` MUST be immutable after first write.
- `acceptBlob` MUST be immutable after first write.
- State transitions MUST follow §2 and §3 (no illegal backward transitions).

### 4.4 OTP scarcity invariants
- An OTP id MUST be attachable to at most one DM session.
- Once moved to `PENDING_CONSUMPTION`, it MUST NOT be returned by bundle fetch to another initiator.
- Once `CONSUMED`, it MUST NOT return to `AVAILABLE`.

### 4.5 Delivery invariants
- Offer deliverable only when `state == PENDING`.
- Accept deliverable only when `state == ACTIVE`.
- Terminal states MUST stop delivery.

### 4.6 Logging invariants (privacy)
Server logs MUST NOT include:
- raw offer/accept blobs
- any derived key material (not applicable by design)
- raw base64 key fields (store only hashes/fingerprints if needed)

Logs MAY include:
- `sessionId`, hashed device identifiers (or deviceId if already public in your system), state transitions, timestamps, reason codes, `traceId`.

---

## 5. OTP Reservation / Consumption Lifecycle (Atomic + Concurrency)

IslandAccord treats OTP as a **scarce resource** managed by the server.

### 5.1 Goals
- Prevent two initiators from receiving the same OTP.
- Prevent initiators from referencing arbitrary OTP ids.
- Ensure OTP cannot be reused across sessions.

### 5.2 Reservation at bundle fetch — GET `/v1/prekeys/bundle`
If OTP is available, server MUST:
1) select one `AVAILABLE` OTP for responder device
2) atomically set status to `RESERVED`
3) set `reservedAt = now`
4) set `expiresAt = now + OTP_RESERVATION_TTL`
5) return it in bundle

**Recommended binding:** store `reservedForInitiatorDeviceId` at reservation if initiator is authenticated and known at fetch time.  
If you cannot bind at fetch time, binding MUST occur at `open()` time and MUST be strict (see §5.3).

### 5.3 Link OTP to session at `open()` time (atomic)
When `open()` references `usedOneTimePrekeyId`:
- Server MUST verify OTP:
  - owner device == responderDeviceId
  - status == `RESERVED`
  - not expired
  - (if `reservedForInitiatorDeviceId` exists) equals initiatorDeviceId
- In the SAME transaction as session creation, server MUST:
  - set OTP status: `RESERVED -> PENDING_CONSUMPTION`
  - set `linkedSessionDbId = dm_sessions.id`
  - (recommended) persist `reservedForInitiatorDeviceId = initiatorDeviceId` if not already set

**Fail-closed:** if OTP cannot be moved to `PENDING_CONSUMPTION`, `open()` MUST fail and no session must be created.

### 5.4 Consume OTP at accept time (atomic)
When responder calls `accept()`:
- If session has `otpId`, in the SAME transaction server MUST:
  - move OTP: `PENDING_CONSUMPTION -> CONSUMED`
  - set `consumedAt = now`
- If OTP is not in `PENDING_CONSUMPTION` (already consumed/expired/missing):
  - reject accept with `C6P.HANDSHAKE.STATE_VIOLATION` or `C6P.KEYS.KEY_ALREADY_CONSUMED` (pick one and keep consistent)

### 5.5 Reservation expiry cleanup (scheduled job)
A scheduled job MUST:
- find OTPs in `RESERVED` where `now >= expiresAt` AND not linked to any session
- move them to `EXPIRED`

**Strong recommendation:** never reuse OTP ids. Refill by minting new OTP rows.

---

## 6. Idempotency Rules (Normative)

### 6.1 open() idempotency
Idempotency key:
- `(initiatorDeviceId, responderDeviceId, sessionId)`

Rules:
- If tuple exists and `offerBlob` matches byte-for-byte:
  - server SHOULD return the existing session state (PENDING/ACTIVE/terminal) without mutation.
- If tuple exists and `offerBlob` differs:
  - server MUST reject:
    - `C6P.HANDSHAKE.REPLAYED_OFFER` or `C6P.HANDSHAKE.STATE_VIOLATION` (choose one stable mapping)

### 6.2 accept() idempotency
Idempotency key:
- `(sessionId, responderDeviceId)`

Rules:
- If session is `ACTIVE` and provided `kc2` matches stored accept:
  - return OK (idempotent success).
- If session is `ACTIVE` and provided `kc2` differs:
  - reject with `C6P.HANDSHAKE.STATE_VIOLATION`.
- If session is terminal non-ACTIVE (`REJECTED/EXPIRED/CANCELLED/ABORTED`):
  - reject with `C6P.HANDSHAKE.STATE_VIOLATION` (fail-closed).

---

## 7. TTL / Rate-Limit Policy (Recommended Defaults)

Auditors expect explicit values (policy; can be configured, but defaults MUST be documented).

- `DM_OFFER_TTL`: **7 days**
- `OTP_RESERVATION_TTL`: **10 minutes**
- `MAX_PENDING_PER_PEER`: **3** pending sessions per `(initiatorDeviceId, responderDeviceId)`
- `OPEN_RATE_LIMIT`: **10/min** per initiator device + additional per-target throttling

Tight TTL reduces hoarding and abuse surface.

---

## 8. Concurrency Scenarios (Auditor Test Plan)

### 8.1 Two initiators fetch bundle simultaneously
Expected:
- They MUST receive distinct OTPs, or one gets OTP while the other gets no OTP.

### 8.2 Initiator fetches bundle but never calls open()
Expected:
- OTP stays `RESERVED` then becomes `EXPIRED` after TTL.

### 8.3 Initiator calls open() twice with same otpId
Expected:
- Second open MUST fail once OTP moved to `PENDING_CONSUMPTION` (or session uniqueness fires).

### 8.4 Responder accepts twice
Expected:
- same `kc2` => OK
- different `kc2` => reject

### 8.5 Offer delivery replay (WS reconnect)
Expected:
- Server may re-deliver offer while session is `PENDING`.
- Client must handle idempotently.
- Delivery MUST stop on terminal state.

---

## 9. Database Constraints (Auditor-Facing)

### 9.1 dm_sessions
- `UNIQUE(initiator_device_id, responder_device_id, session_id)`
- Indexes:
  - `(responder_user_id, state, created_at)` for delivering offers
  - `(initiator_user_id, state, created_at)` for delivering accepts

### 9.2 prekeys_otp
- `UNIQUE(device_id, otp_id)`
- Indexes:
  - `(device_id, status, expires_at)`
- Recommended:
  - `UNIQUE(linked_session_db_id)` if OTP must attach to only one session

---

## 10. Error Mapping (Canonical Codes)

This module MUST use codes from `docs/crypto/c6p-error-codes.md`.

Recommended mappings (stable):
- invalid hex/b64 lengths: `C6P.ENC.*`
- malformed envelopes/state: `C6P.WIRE.INVALID_ENVELOPE`, `C6P.HANDSHAKE.STATE_VIOLATION`
- device binding mismatch: `C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH`
- prekey missing: `C6P.KEYS.KEY_NOT_FOUND`
- otp missing/unreserved: `C6P.HANDSHAKE.OTP_MISSING` or `C6P.KEYS.KEY_NOT_FOUND` (choose once globally)
- otp already consumed: `C6P.KEYS.KEY_ALREADY_CONSUMED` (recommended)
- session replay: `C6P.HANDSHAKE.REPLAYED_OFFER` (recommended)

**Non-leakage rule:** server MUST NOT reveal whether `kc1/kc2/signature` are cryptographically correct.

---

## 11. Explicit Non-Goals (Security Clarifications)

- Server does **not** derive: DH, PRK, root, chain keys, message keys, nonces.
- Server does **not** validate cryptographic correctness of `transcriptHash`, `kc1`, `kc2`, or signatures as a security boundary.
- Server enforces:
  - authorization/routing
  - state machine correctness
  - tuple uniqueness/replay resistance
  - OTP scarcity + TTL + atomic transitions

Clients remain the ultimate authority for cryptographic acceptance.

---

## 12. Implementation Checklist (Server)

- [ ] Strict decoding/validation per `island-accord-wire.md`
- [ ] Unique constraint for session tuple
- [ ] Atomic transaction for `open()`:
  - validate
  - write `dm_sessions(PENDING)`
  - OTP: `RESERVED -> PENDING_CONSUMPTION` (+ link)
- [ ] Atomic transaction for `accept()`:
  - validate
  - write acceptBlob
  - session: `PENDING -> ACTIVE`
  - OTP: `PENDING_CONSUMPTION -> CONSUMED`
- [ ] TTL job for session expiry (`PENDING -> EXPIRED`)
- [ ] TTL job for OTP reservation expiry (`RESERVED -> EXPIRED`)
- [ ] Rate limits (initiator + per-target)
- [ ] Non-sensitive structured error payloads + logging
- [ ] Test suite covering concurrency scenarios (§8)

---
