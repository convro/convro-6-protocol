# IslandAccord v1 — State Machine & Server Invariants (island-accord-state-machine.md)

**Status:** Production / Canonical  
**Handshake family:** IslandAccord v1  
**Scope:** DM session state machine (server authority), invariants, idempotency rules, TTL/replay/OTP reservation lifecycle, concurrency notes.  
**Audience:** Security auditors, backend implementers, client implementers.  
**Principle:** The server is **not trusted for secrecy**, but is **authoritative for state, routing and scarcity resources** (OTP).  
**Fail-closed:** Invalid transitions MUST be rejected.

---

## 0. Entities & Terms

### 0.1 Actors
- **Initiator (I):** party creating the DM session.
- **Responder (R):** party receiving and accepting the DM session.
- **Server (S):** message router + state authority, never derives secrets.

### 0.2 Identifiers
- `sessionId`: hex8, unique per `(initiatorDeviceId, responderDeviceId, sessionId)` tuple.
- `initiatorDeviceId`: hex16
- `responderDeviceId`: hex16
- `otpId`: hex16 (optional)

### 0.3 Records (conceptual)
- **DM Session Record** (`dm_sessions`):
  - initiatorUserId, initiatorDeviceId
  - responderUserId, responderDeviceId
  - sessionId
  - offerBlob (immutable once written)
  - acceptBlob (immutable once written)
  - state
  - otpId (nullable)
  - createdAt, updatedAt, expiresAt
- **OTP Record** (`prekeys_otp`):
  - deviceId
  - otpId
  - pubKey
  - status: AVAILABLE / RESERVED / PENDING_CONSUMPTION / CONSUMED / EXPIRED
  - reservedFor (optional binding; see §5)
  - reservedAt, expiresAt, consumedAt

---

## 1. Canonical States (Server)

### 1.1 DM Session states
- `PENDING` — offer stored and deliverable to responder; not yet accepted
- `ACTIVE` — accept stored; deliverable to initiator; considered established at server-level
- `REJECTED` — responder explicitly rejected (optional endpoint) or policy reject
- `EXPIRED` — TTL elapsed without accept
- `CANCELLED` — initiator cancelled before accept (optional endpoint)
- `ABORTED` — server terminated due to invariants violation or admin action (rare)

**Note:** Even if server says `ACTIVE`, clients still MUST validate `kc2` and only then mark local crypto session active.

### 1.2 OTP states (server authority)
- `AVAILABLE` — can be reserved for bundle fetch
- `RESERVED` — reserved during bundle fetch for a specific flow
- `PENDING_CONSUMPTION` — referenced by a stored offer; cannot be used elsewhere
- `CONSUMED` — permanently consumed by stored accept
- `EXPIRED` — reservation TTL elapsed without offer/accept completion

---

## 2. State Machine Diagram (DM Sessions)

Text diagram (canonical):



         ┌───────────────┐
open() │ │ accept()
────────────▶│ PENDING ├────────────▶ ACTIVE
│ │
└──────┬────────┘
│
reject() │ expire() / ttl
│
▼
REJECTED
│
│ (terminal)
▼
(END)

PENDING ── cancel() ──▶ CANCELLED (terminal)
PENDING ── abort() ──▶ ABORTED (terminal)
ACTIVE ── abort() ──▶ ABORTED (terminal)
PENDING ── expire() ──▶ EXPIRED (terminal)


**Terminal states:** ACTIVE, REJECTED, EXPIRED, CANCELLED, ABORTED  
(“ACTIVE” is terminal with respect to handshake; it may later transition to chat/session lifecycle states outside this document.)

---

## 3. Transitions (Normative)

### 3.1 `open()` — POST `/v1/dm/sessions/open`
**Preconditions (MUST):**
- Authenticated as initiator.
- `initiatorDeviceId` equals auth deviceId.
- `responderDeviceId` belongs to `peerUserId` and exists.
- `(initiatorDeviceId, responderDeviceId, sessionId)` is not already present.
- Referenced SPK exists and matches offered SPK pub.
- If offer references `otpId`, it MUST be in a valid reserved pipeline (see §5).

**Effects (MUST):**
- Create dm_session row with state `PENDING`.
- Persist immutable `offerBlob`.
- Set `expiresAt = createdAt + DM_OFFER_TTL`.
- Make offer deliverable to responder.

**Idempotency (MUST):**
- If the exact same `(initiatorDeviceId, responderDeviceId, sessionId)` already exists:
  - If `offerBlob` matches byte-for-byte, server SHOULD return same `sessionId` and current state.
  - If `offerBlob` differs, server MUST reject with `C6P_SESSION_REPLAY` or `C6P_STATE_CONFLICT`.

### 3.2 `accept()` — POST `/v1/dm/handshake/accept`
**Preconditions (MUST):**
- Authenticated as responder.
- `responderDeviceId` equals auth deviceId.
- dm_session exists with matching sessionId + responderDeviceId.
- dm_session.state == `PENDING`.
- dm_session is not expired.

**Effects (MUST):**
- Store immutable `acceptBlob` containing `kc2`.
- Transition dm_session.state to `ACTIVE`.
- Atomically consume OTP if session references one (see §5.4).
- Make accept deliverable to initiator.

**Idempotency (MUST):**
- If dm_session.state == `ACTIVE`:
  - If provided `kc2` matches stored accept `kc2`, return ok (idempotent success).
  - Else reject with `C6P_STATE_CONFLICT`.

### 3.3 `reject()` — OPTIONAL endpoint (recommended)
**POST** `/v1/dm/handshake/reject` (optional but auditor-friendly)
- Preconditions: authenticated responder, session exists in `PENDING`.
- Effect: state -> `REJECTED`, store reason code (non-sensitive).
- OTP cleanup: if OTP was `PENDING_CONSUMPTION`, it SHOULD become `EXPIRED` only after reservation TTL, or be marked `UNUSABLE` for that offer (policy-dependent).

### 3.4 `cancel()` — OPTIONAL endpoint (recommended)
**POST** `/v1/dm/handshake/cancel` (initiator)
- Preconditions: authenticated initiator, session exists in `PENDING`.
- Effect: state -> `CANCELLED`, stop delivery.
- OTP handling: same as reject() policy.

### 3.5 `expire()` — internal scheduler / on-read enforcement
- Trigger: `now >= expiresAt` and state == `PENDING`.
- Effect: state -> `EXPIRED` (terminal), stop delivery.
- OTP cleanup: see §5.5.

### 3.6 `abort()` — admin/policy termination
- Used for abuse, corrupted rows, emergency.
- Moves any non-terminal to `ABORTED`.

---

## 4. Server Invariants (Must-Hold Always)

### 4.1 Authorization invariants
- A dm_session belongs to exactly one initiator device and one responder device.
- Server MUST NOT allow:
  - accept by a device that is not the responder device
  - retrieval of offer by non-responder
  - retrieval of accept by non-initiator

### 4.2 Uniqueness / replay invariants
- Unique constraint MUST exist:
  - `UNIQUE(initiatorDeviceId, responderDeviceId, sessionId)`
- Server MUST reject any `open()` that tries to reuse an existing tuple with different offer content.

### 4.3 Immutability invariants
- `offerBlob` MUST be immutable once stored.
- `acceptBlob` MUST be immutable once stored.
- State transitions MUST be monotonic according to §2 and §3.

### 4.4 Delivery invariants
- Offer deliverable only when `PENDING`.
- Accept deliverable only when `ACTIVE`.
- Terminal states stop delivery.

### 4.5 Logging invariants (privacy)
- Server logs MUST NOT include:
  - raw offer blobs
  - any derived key material (not applicable by design)
  - full base64 key fields (store only hashes/fingerprints)
- Logs MAY include:
  - sessionId, deviceIds, state transition, requestId, timestamps, reason codes

---

## 5. OTP Reservation / Consumption Lifecycle (Atomic + Concurrency)

IslandAccord treats OTP as a **scarce resource** managed by the server.

### 5.1 Goals
- Prevent two initiators from receiving the same OTP.
- Prevent malicious initiator from referencing arbitrary OTP ids.
- Ensure OTP cannot be “replayed” into multiple sessions.

### 5.2 Reservation: bundle fetch (GET `/v1/prekeys/bundle`)
**If OTP available**, server MUST:
1) pick one `AVAILABLE` OTP for responder device
2) atomically set it to `RESERVED`
3) set `reservedAt = now`, `expiresAt = now + OTP_RESERVATION_TTL`
4) return it in bundle

**Recommendation (auditor candy):** Bind reservation to a `reservationToken` (opaque) or to `(initiatorDeviceId)` if already known.  
If you do not add a token, then binding MUST happen at `open()` time using strict checks (see §5.3).

### 5.3 Link OTP to session at `open()` time
When initiator calls `open()` referencing `usedOneTimePrekeyId`:
- Server MUST verify OTP is:
  - owned by responder device
  - currently `RESERVED`
  - not expired
- Server MUST transition OTP -> `PENDING_CONSUMPTION` **atomically within the same transaction** that creates the dm_session row.

**Binding rule:**
- OTP MUST become linked to that dm_session:
  - `otp.sessionDbId = dm_sessions.id` (or equivalent)
  - `otp.reservedForInitiatorDeviceId = initiatorDeviceId` (recommended)
- After this, OTP MUST NOT be eligible for any other session.

### 5.4 Consume OTP at accept time (atomic)
When responder accepts:
- If session has `otpId`, server MUST in the same transaction:
  - set OTP -> `CONSUMED`
  - set `consumedAt = now`
- If OTP already consumed or not in expected state -> reject accept with `C6P_STATE_CONFLICT` (or `C6P_PREKEY_NOT_FOUND` depending on policy).

### 5.5 Reservation expiry cleanup
A scheduled job MUST:
- find OTPs in `RESERVED` where `now >= expiresAt` and no dm_session linked
- set them to `EXPIRED` (or return to `AVAILABLE` only if your model allows safe reuse; generally **do not reuse** OTP ids; instead mint new OTPs)

**Strong recommendation:** Never reuse OTP ids; create new OTPs on top-up.

---

## 6. Timing / TTL Policy (Recommended Defaults)

These values are policy; auditors will want them explicit.

- `DM_OFFER_TTL`: 7 days (or shorter if you want aggressive cleanup)
- `OTP_RESERVATION_TTL`: 10 minutes (tight window reduces hoarding)
- `MAX_PENDING_PER_PEER`: e.g., 3 pending sessions from same initiator->responder pair
- `OPEN_RATE_LIMIT`: e.g., 10 per minute per initiator device (plus peer-targeted limit)

**Note:** “Tight TTL” reduces metadata and abuse surface.

---

## 7. Idempotency Rules (Detailed)

### 7.1 open() idempotency key
The idempotency key is effectively `(initiatorDeviceId, responderDeviceId, sessionId)`.
- Same tuple + same offer => same response.
- Same tuple + different offer => reject.

### 7.2 accept() idempotency key
The idempotency key is `(sessionId, responderDeviceId)`.
- Same accept `kc2` => ok.
- Different `kc2` => reject.

---

## 8. Race & Concurrency Scenarios (What auditors test)

### 8.1 Two initiators fetch bundle simultaneously
**Expected behavior:**
- They MUST receive distinct OTPs (or one gets OTP, other gets none).

### 8.2 Initiator fetches bundle but never opens
- OTP remains `RESERVED` then expires by TTL -> `EXPIRED` (not reused).

### 8.3 Initiator opens twice with same otpId
- Second open MUST fail once otp moved to `PENDING_CONSUMPTION` (or session uniqueness triggers).

### 8.4 Responder accepts twice
- Second accept with same kc2 returns ok.
- Second accept with different kc2 rejected.

### 8.5 Offer delivery replay
- Server may deliver offer multiple times (WS reconnect).
- Client must handle idempotently.
- Server should be able to re-send `PENDING` offer until accepted/expired.

---

## 9. Recommended DB Constraints (Auditor-Facing)

### 9.1 dm_sessions
- UNIQUE `(initiator_device_id, responder_device_id, session_id)`
- INDEX `(responder_user_id, state, created_at)` for delivery
- INDEX `(initiator_user_id, state, created_at)` for accept delivery

### 9.2 otp_prekeys
- UNIQUE `(device_id, otp_id)`
- INDEX `(device_id, status, expires_at)`
- OPTIONAL UNIQUE `(session_db_id)` if OTP can only attach to one session

---

## 10. Non-Goals / Security Clarifications (Explicit)

- The server does **not** derive handshake secrets.
- The server does **not** cryptographically validate `kc1/kc2/signatures` as a security boundary.
- The server’s responsibility is:
  - enforce state machine correctness
  - enforce authorization and routing
  - enforce OTP scarcity, uniqueness, TTL
  - enforce replay resistance at protocol metadata level

Clients remain the ultimate authority for cryptographic acceptance.

---

## 11. Implementation Checklist (Server)

- [ ] Unique constraint for session tuple
- [ ] Atomic transaction for `open()`:
  - validate
  - write dm_session(PENDING)
  - move OTP -> PENDING_CONSUMPTION
- [ ] Atomic transaction for `accept()`:
  - validate
  - write acceptBlob
  - move session -> ACTIVE
  - move OTP -> CONSUMED
- [ ] TTL job for session expiry
- [ ] TTL job for OTP reservation expiry
- [ ] Rate limits (initiator + per-target)
- [ ] Non-sensitive error messages and logging
- [ ] Comprehensive test matrix coverage (see `island-accord-test-matrix.md`)

---
