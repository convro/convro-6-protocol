# IslandAccord v1 — Test Matrix (ocs/handshake/island-accord-test-matrix.md)

**Status:** Production / Canonical  
**Scope:** Server-state machine + wire validation + OTP scarcity lifecycle + delivery semantics + concurrency/race tests.  
**Audience:** Auditors, backend implementers, security QA.  
**Principle:** Fail-closed + idempotent + atomic transitions.  
**Legend:** ✅ expected success, ❌ expected reject, ⚠️ expected soft-fail (rate-limit / retry / idempotent ok).

---

## 0) Test Harness & Setup

### 0.1 Required test components
- DB fixtures for:
  - Users: `U_I`, `U_R`
  - Devices: `D_I` (initiatorDeviceId hex16), `D_R` (responderDeviceId hex16)
  - Prekeys for responder:
    - Identity Ed25519 public key
    - SignedPrekey (SPK) X25519 pub + signature
    - OTP pool: N entries (default N=10)
- API client that can:
  - sign in as initiator/responder (separate tokens)
  - call:
    - `GET /v1/prekeys/status`
    - `GET /v1/prekeys/bundle?device_id=...`
    - `POST /v1/dm/sessions/open`
    - `POST /v1/dm/handshake/accept`
  - optional:
    - `POST /v1/dm/handshake/reject`
    - `POST /v1/dm/handshake/cancel`
- Optional delivery channels:
  - WebSocket deliver (server → client)
  - Polling endpoints for pending offers/accepts (if used)

### 0.2 Global constants for tests (policy)
- `DM_OFFER_TTL` (e.g., 7d)
- `OTP_RESERVATION_TTL` (e.g., 10m)
- `MAX_PENDING_PER_PEER` (e.g., 3)
- rate limits: `OPEN_RATE_LIMIT`, etc.

### 0.3 Notation
- `Offer(O)` = valid IslandAccord offer payload
- `Offer(O')` = same tuple but different bytes / fields
- `KC2` = key confirmation (accept blob)
- `sid` = sessionId hex8
- `otpId` = oneTime prekey id hex16 (optional)
- `spkPub` = signed prekey public key used in offer

---

## 1) Wire Validation Tests (Field-level)

### 1.1 Offer required fields
| ID | Scenario | Input | Expected |
|---:|---|---|---|
| W-001 | version missing | offer.version absent | ❌ 400 `C6P_SCHEMA` |
| W-002 | version wrong | version != 1 | ❌ 400 `C6P_VERSION` |
| W-003 | initiatorDeviceId invalid | non-hex / wrong len | ❌ 400 `C6P_DEVICE_ID` |
| W-004 | responderDeviceId invalid | non-hex / wrong len | ❌ 400 `C6P_DEVICE_ID` |
| W-005 | sessionId invalid | non-hex / wrong len | ❌ 400 `C6P_SESSION_ID` |
| W-006 | eph pub invalid b64url | malformed | ❌ 400 `C6P_B64` |
| W-007 | eph pub wrong size | decoded != 32 bytes | ❌ 400 `C6P_KEYLEN` |
| W-008 | used SPK pub invalid | malformed / wrong size | ❌ 400 `C6P_KEYLEN` |
| W-009 | usedOneTimePrekeyId invalid | wrong hex len | ❌ 400 `C6P_KEY_ID` |

### 1.2 Accept required fields (kc2)
| ID | Scenario | Input | Expected |
|---:|---|---|---|
| W-101 | accept missing sessionId | absent | ❌ 400 `C6P_SCHEMA` |
| W-102 | accept wrong responderDeviceId | invalid | ❌ 400 `C6P_DEVICE_ID` |
| W-103 | kc2 missing | absent | ❌ 400 `C6P_SCHEMA` |
| W-104 | kc2 invalid b64url | malformed | ❌ 400 `C6P_B64` |
| W-105 | kc2 wrong size | decoded != expected | ❌ 400 `C6P_KEYLEN` |

---

## 2) Authorization & Routing Tests

### 2.1 open() auth binding
| ID | Scenario | Actor | Input | Expected |
|---:|---|---|---|---|
| A-001 | unauth open | none | open() | ❌ 401 |
| A-002 | initiatorDeviceId != auth.deviceId | initiator | offer initiatorDeviceId != D_I | ❌ 403 `C6P_AUTH_DEVICE_MISMATCH` |
| A-003 | responderDeviceId not owned by peer user | initiator | peerUserId=U_R, responderDeviceId=foreign | ❌ 404/400 `C6P_PEER_DEVICE` |
| A-004 | open for self | initiator | peerUserId=U_I | ❌ 400 `C6P_INVALID_PEER` |

### 2.2 accept() auth binding
| ID | Scenario | Actor | Input | Expected |
|---:|---|---|---|---|
| A-101 | accept by non-responder | initiator | accept() for sid | ❌ 403 `C6P_NOT_RESPONDER` |
| A-102 | accept responderDeviceId != auth.deviceId | responder | mismatch | ❌ 403 `C6P_AUTH_DEVICE_MISMATCH` |
| A-103 | accept unknown sid | responder | sid not found | ❌ 404 `C6P_SESSION_NOT_FOUND` |

---

## 3) Session State Machine Tests (Core)

### 3.1 open() success path
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| S-001 | open creates PENDING | open(valid Offer) | ✅ 200 state=`PENDING`, expiresAt set |
| S-002 | offer immutable | open(valid Offer) then server read row | ✅ stored offerBlob equals request |
| S-003 | delivery available | after open, responder can fetch/receive offer | ✅ offer deliverable only to responder |

### 3.2 accept() success path
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| S-101 | accept transitions to ACTIVE | open → accept(valid KC2) | ✅ 200 state=`ACTIVE` |
| S-102 | accept immutable | open → accept, then read row | ✅ acceptBlob unchanged |
| S-103 | initiator receives accept | open → accept, initiator fetch/receive accept | ✅ accept deliverable only to initiator |

### 3.3 invalid transitions
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| S-201 | accept before open | accept(sid not existing) | ❌ 404 |
| S-202 | open twice with new sid but exceeds MAX_PENDING_PER_PEER | open x (MAX+1) | ❌ 429/400 policy |
| S-203 | accept on EXPIRED | open, advance time > TTL, accept | ❌ 409 `C6P_EXPIRED` |
| S-204 | accept on CANCELLED | open → cancel → accept | ❌ 409 `C6P_STATE` |
| S-205 | accept on REJECTED | open → reject → accept | ❌ 409 `C6P_STATE` |

---

## 4) Idempotency & Replay Tests (Auditor Candy)

### 4.1 open() idempotency
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| I-001 | same tuple, same offer | open(Offer O) → open(Offer O) | ⚠️ 200 same state/sessionId (idempotent) |
| I-002 | same tuple, different offer | open(Offer O) → open(Offer O') | ❌ 409 `C6P_STATE_CONFLICT` |
| I-003 | same sid but swapped devices | open with same sid, different (D_I,D_R) | ✅ allowed (different tuple) OR ❌ if policy forbids reuse of sid globally (declare) |

### 4.2 accept() idempotency
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| I-101 | accept twice same KC2 | open → accept(KC2) → accept(KC2) | ⚠️ 200 ok (idempotent) |
| I-102 | accept twice different KC2 | open → accept(KC2) → accept(KC2') | ❌ 409 `C6P_STATE_CONFLICT` |

### 4.3 delivery replay tolerance
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| I-201 | offer delivered multiple times | open → WS reconnect/resend | ✅ responder must handle dedupe by (sid, initiatorDeviceId) |
| I-202 | accept delivered multiple times | accept → WS reconnect/resend | ✅ initiator must handle dedupe by sid |

---

## 5) OTP Scarcity & Lifecycle Tests (Atomic + Concurrency)

### 5.1 bundle reservation
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| O-001 | bundle returns OTP when available | seed N OTP AVAILABLE → fetch bundle | ✅ returns otpId, OTP becomes `RESERVED` |
| O-002 | bundle returns none when depleted | seed 0 OTP → fetch bundle | ✅ otpId absent |
| O-003 | reservation TTL expiry | fetch bundle → advance time > OTP_TTL → run job | ✅ OTP becomes `EXPIRED` (or policy terminal) |

### 5.2 open binds OTP to session
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| O-101 | open transitions OTP to PENDING_CONSUMPTION | fetch bundle (otpId) → open referencing otpId | ✅ OTP state becomes `PENDING_CONSUMPTION` + linked to session |
| O-102 | open with otpId not RESERVED | open referencing arbitrary otpId | ❌ 409/400 `C6P_PREKEY_STATE` |
| O-103 | open with otpId for wrong device | otp belongs to other responderDeviceId | ❌ 409/400 `C6P_PREKEY_BINDING` |
| O-104 | open after reservation expired | fetch bundle, wait > TTL, open | ❌ 409 `C6P_PREKEY_EXPIRED` |

### 5.3 accept consumes OTP atomically
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| O-201 | accept consumes OTP | fetch bundle+open(otp) → accept | ✅ OTP -> `CONSUMED`, consumedAt set |
| O-202 | accept when OTP not in expected state | tamper OTP state | ❌ 409 `C6P_STATE_CONFLICT` |

### 5.4 concurrency: two initiators racing for OTP
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| O-301 | two bundle fetches concurrent | start 2 parallel fetch bundle | ✅ distinct OTPs OR one gets none |
| O-302 | two opens with same otpId | force both clients reference same otpId | ✅ one succeeds, one ❌ conflict |

### 5.5 cleanup after non-completion
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| O-401 | initiator never opens | fetch bundle (RESERVED), do nothing, TTL job | ✅ OTP expires |
| O-402 | open created but never accepted | fetch bundle+open (PENDING_CONSUMPTION), TTL job after DM_TTL | ✅ session EXPIRED; OTP policy: terminal (EXPIRED/UNUSABLE) |

---

## 6) SPK / Key Binding Tests (Server-level constraints)

> Server doesn’t verify crypto, but enforces **binding constraints** to reduce splicing.

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| K-001 | offer references SPK pub that is not current | set responder SPK to new, open with old spkPub | ❌ 400/409 `C6P_SPK_MISMATCH` |
| K-002 | offer references SPK pub for another device | spkPub belongs to other device | ❌ `C6P_SPK_BINDING` |
| K-003 | offer references OTP id but missing OTP pub in bundle | server must not allow fabricated | ❌ `C6P_PREKEY_BINDING` |

---

## 7) Expiry & Time-based Tests

### 7.1 DM offer TTL
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| T-001 | PENDING expires | open → advance > DM_OFFER_TTL → fetch session | ✅ state=`EXPIRED`, not deliverable |
| T-002 | accept after expiry | open → advance > TTL → accept | ❌ 409 `C6P_EXPIRED` |
| T-003 | accept just before expiry | open → accept just before TTL | ✅ ACTIVE |

### 7.2 clock skew (client)
| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| T-101 | client skew doesn’t break server | client sends late accept | ❌/✅ only based on server time, deterministic |

---

## 8) Rate Limiting & Abuse Controls

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| R-001 | open spam | open loop > OPEN_RATE_LIMIT | ❌ 429 |
| R-002 | per-target pending limit | many pending to same responder | ❌ 429/400 policy |
| R-003 | accept spam | accept loop | ❌ 429 |

**Privacy note:** Rate limit errors MUST be generic (no leaking peer existence beyond what caller already knows).

---

## 9) Logging & Privacy Tests (Meta Minimization)

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| P-001 | logs do not include offer blobs | open with big payload | ✅ logs show hashes/fingerprints only |
| P-002 | logs do not include base64 keys | open/accept | ✅ no raw key material in logs |
| P-003 | error messages are non-sensitive | trigger failures | ✅ stable error codes, no internal DB ids |

---

## 10) Property-based & Fuzz Tests (Highly Recommended)

### 10.1 Schema fuzz
- Randomly mutate:
  - hex fields (length, charset)
  - b64url fields (padding, invalid chars, truncated)
  - JSON type swaps (string→int etc.)
**Expected:** No crash; always fail-closed.

### 10.2 State fuzz
- Randomly pick valid session, apply random operation in random order:
  - open/accept/cancel/reject
- Verify invariants:
  - no illegal state transitions
  - immutability of offer/accept
  - OTP uniqueness holds

### 10.3 Concurrency fuzz
- N threads:
  - fetch bundle concurrently
  - open concurrently
  - accept concurrently
- Assertions:
  - at most 1 accept wins
  - each otpId bound to <=1 session
  - unique constraint never violated

---

## 11) DB Constraint Verification Tests

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| D-001 | uniqueness enforced | attempt to insert same tuple twice with different payload | ✅ second fails |
| D-002 | OTP unique (device, otpId) | duplicate otpId for same device | ✅ DB reject |
| D-003 | OTP single-session binding | attach same otpId to two sessions | ✅ DB reject |

---

## 12) Minimal “Audit Run” Checklist

A single high-value run (smoke + security):
1) Seed responder prekeys with N OTP.
2) Fetch bundle → open (otp) → accept → verify ACTIVE.
3) Repeat open idempotency: open same offer again → ok.
4) Attempt open with same tuple different offer → reject.
5) Attempt accept with different kc2 → reject.
6) Run concurrency: 50 parallel bundle fetches; verify otpIds unique.
7) Run TTL job: create pending, advance time, verify EXPIRED.
8) Verify log scrubbing rules.

---

## Appendix A — Expected Error Codes (Suggestive)

These are stable “auditor friendly” codes; adapt to your backend:
- `C6P_SCHEMA`, `C6P_VERSION`
- `C6P_DEVICE_ID`, `C6P_SESSION_ID`, `C6P_KEY_ID`, `C6P_B64`, `C6P_KEYLEN`
- `C6P_AUTH_DEVICE_MISMATCH`, `C6P_NOT_RESPONDER`
- `C6P_SESSION_NOT_FOUND`, `C6P_EXPIRED`, `C6P_STATE_CONFLICT`
- `C6P_PREKEY_STATE`, `C6P_PREKEY_EXPIRED`, `C6P_PREKEY_BINDING`
- `C6P_SPK_MISMATCH`, `C6P_SPK_BINDING`
- `C6P_RATE_LIMIT`

---
