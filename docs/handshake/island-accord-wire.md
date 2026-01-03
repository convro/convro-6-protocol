# IslandAccord v1 — Wire Contract & Validation (island-accord-wire.md)

**Status:** PRODUCTION / CANONICAL / AUDIT-GRADE  
**Handshake:** IslandAccord v1  
**Scope:** HTTP + WS delivery formats, strict validation rules, server invariants, client invariants, and canonical error mapping.  
**Audience:** Security auditors, backend implementers, client implementers.  
**Principle:** **Fail-closed.** Any deviation from this contract MUST be rejected.

**Depends on (normative):**
- `docs/crypto/c6p-encoding-and-canonicalization.md`
- `docs/crypto/c6p-crypto-registry.md`
- `docs/handshake/island-accord-crypto.md`
- `docs/handshake/island-accord-state-machine.md`
- `docs/crypto/c6p-error-codes.md`

---

## 0. Normative Language

- **MUST / MUST NOT / SHOULD / MAY** are used as defined in RFC 2119.
- “Server” is **not trusted for secrecy** (never derives secrets), but is authoritative for **state/invariants**:
  - OTP reservation/consumption
  - session uniqueness
  - idempotency and TTL
  - routing/delivery

---

## 1. Canonical Identifiers & Encodings (Wire)

All encoding rules in this section are **strict**. No trimming. No “helpful” normalization.

### 1.1 Hex identifiers (strict, lowercase only)

All hex IDs MUST be lowercase and fixed-length:

- `deviceId`: **16 bytes** → **hex32**  
  - Regex: `^[0-9a-f]{32}$`
- `sessionId`: **8 bytes** → **hex16**  
  - Regex: `^[0-9a-f]{16}$`
- `keyId` / `spkId` / `otpId`: **8 bytes** → **hex16**  
  - Regex: `^[0-9a-f]{16}$`

**Server rule:** any uppercase hex or wrong length MUST be rejected with:
- `C6P.ENC.NON_CANONICAL_HEX` (uppercase) or `C6P.ENC.INVALID_HEX` / `C6P.ENC.LENGTH_MISMATCH`.

### 1.2 Base64url (no padding) (strict)

All binary fields are base64url without padding:
- Allowed characters: `A–Z a–z 0–9 - _`
- Regex: `^[A-Za-z0-9_-]+$`
- Padding (`=`) MUST NOT appear.
- Decoded length MUST match the table in §1.3 exactly.

Reject with:
- `C6P.ENC.INVALID_B64URL` (invalid alphabet / decode)
- `C6P.ENC.LENGTH_MISMATCH` (decoded size wrong)

### 1.3 Byte lengths (decoded, strict)

| Field | Encoding | Bytes |
|------|----------|------:|
| X25519 public key | b64url | 32 |
| Ed25519 public key | b64url | 32 |
| Ed25519 signature | b64url | 64 |
| SHA-256 hash | b64url | 32 |
| HMAC-SHA256 output | b64url | 32 |

---

## 2. Versioning & Suite Policy

### 2.1 Protocol version
- `version` MUST be integer `1`.

### 2.2 Suite
- `suiteId` MUST be a supported suite id (u8 semantics) as defined in `c6p-crypto-registry.md`.
- Unknown `suiteId` MUST be rejected with `C6P.AEAD.UNSUPPORTED_SUITE`.

**Production default (policy):** ChaCha20-Poly1305 (registry default; no downgrade-by-accident).  
If server restricts allowed suites, it MUST do so explicitly and consistently.

---

## 3. Counter Representation (JSON)

To avoid JS precision loss:
- `counter` on JSON wire MUST be **string decimal** (no whitespace, digits only).
- Parsed value MUST fit in `u64`.

Reject with:
- `C6P.ENC.INVALID_DECIMAL_U64` (parse fails / overflow)
- `C6P.WIRE.COUNTER_INVALID` (wrong type, missing, etc.)

---

## 4. Endpoints (Canonical)

All request/response bodies are JSON unless stated otherwise.

### 4.1 Prekeys status

**GET** `/v1/prekeys/status`  
**Auth:** Required

**Response (JSON):**
```json
{
  "ok": true,
  "deviceId": "0123abcd...<hex32>",
  "signedPrekeyId": "bbbbbbbbbbbbbbbb",
  "signedPrekeyFingerprint": "<b64url32>",
  "oneTimeAvailable": 64,
  "lastRotationAt": "2026-01-03T12:34:56.000Z"
}
```

Validation rules:

oneTimeAvailable MUST be integer ≥ 0.

Server MUST compute oneTimeAvailable from authoritative store (not client hints).

4.2 Fetch bundle (atomic OTP reservation)

GET /v1/prekeys/bundle?deviceId=<hex32>
Auth: Required
Semantics: Server returns responder bundle for a device. If OTP is available, server MUST atomically reserve one OTP and include it.

Response (JSON) — BundleResponse:

{
  "responderDeviceId": "aaaaaaaa...<hex32>",

  "identityPublicKeyEd25519": "<b64url32>",
  "identityPublicKeyX25519": "<b64url32>",

  "signedPrekeyId": "bbbbbbbbbbbbbbbb",
  "signedPrekeyPublicKeyX25519": "<b64url32>",
  "signedPrekeySignature": "<b64url64>",

  "oneTimePrekeyId": "cccccccccccccccc",
  "oneTimePrekeyPublicKeyX25519": "<b64url32>"
}


Rules (server):

responderDeviceId MUST equal requested deviceId.

OTP pair presence is all-or-nothing:

If oneTimePrekeyId exists, oneTimePrekeyPublicKeyX25519 MUST exist and vice versa.

If exactly one exists → reject internally and do not respond partial. Surface C6P.INVAR.ASSERTION_FAILED.

Reservation MUST be atomic:

Reserved OTP MUST NOT be returned to other initiators concurrently.

Reservation MUST have TTL (see §8.2).

Rules (client):

Strictly decode lengths.

Verify SPK signature using identityPublicKeyEd25519:

VerifyEd25519(IKsigPub, spkSig, LABEL_PREKEY || spkId_bytes || spkPub_bytes)

Where:

LABEL_PREKEY is defined in island-accord-crypto.md and registry labels,

spkId_bytes = hex_decode(signedPrekeyId) (8 bytes),

spkPub_bytes is 32 bytes.

If invalid → abort (C6P.HANDSHAKE.SPK_SIGNATURE_INVALID).

4.3 Upload prekeys

POST /v1/prekeys/upload
Auth: Required

Request (JSON):

{
  "identityPublicKeyEd25519": "<b64url32>",
  "identityPublicKeyX25519": "<b64url32>",
  "signedPrekey": {
    "keyId": "bbbbbbbbbbbbbbbb",
    "publicKeyX25519": "<b64url32>",
    "signatureEd25519": "<b64url64>"
  },
  "oneTimePrekeys": [
    { "prekeyId": "cccccccccccccccc", "publicKeyX25519": "<b64url32>" }
  ]
}


Validation (server):

All fields required except oneTimePrekeys MAY be empty list.

keyId / prekeyId must be lowercase hex16.

Signature MUST be valid (per handshake crypto spec):

Sig = SignEd25519(IK_sig_priv, LABEL_PREKEY || spkId_bytes || spkPub_bytes)

Server MUST reject duplicates for (deviceId, keyId) that do not match stored value exactly.

Server MUST store identity keys immutably per device (rotation is versioned; no silent overwrite).

Response (JSON):

{
  "ok": true,
  "acceptedOneTimePrekeyIds": ["cccccccccccccccc"]
}

5. DM Session Establishment (IslandAccord)
5.1 Open DM session (creates and stores offer)

POST /v1/dm/sessions/open
Auth: Required
Purpose: Initiator creates DM session request and stores the offer for responder delivery.

5.1.1 Request JSON — OpenRequest
{
  "peerUserId": 12345,
  "handshakeOffer": {
    "version": 1,
    "suiteId": 1,

    "sessionId": "1122334455667788",
    "initiatorDeviceId": "aaaaaaaa...<hex32>",
    "responderDeviceId": "bbbbbbbb...<hex32>",

    "initiatorIdentityDhPub": "<b64url32>",
    "initiatorIdentitySigPub": "<b64url32>",
    "initiatorEphemeralDhPub": "<b64url32>",

    "usedSignedPrekeyId": "cccccccccccccccc",
    "usedSignedPrekeyPublicKeyX25519": "<b64url32>",

    "usedOneTimePrekeyId": "dddddddddddddddd",

    "transcriptHash": "<b64url32>",
    "kc1": "<b64url32>",
    "offerSignatureEd25519": "<b64url64>"
  }
}


Notes:

usedOneTimePrekeyId MAY be omitted or null if OTP not used.

If present, it MUST be hex16 and must correspond to a server-reserved OTP for responder.

5.1.2 Server-side validation (MUST)

Structural:

peerUserId MUST be integer > 0.

handshakeOffer.version MUST equal 1.

suiteId must be supported by server policy.

All hex and base64url fields must pass strict decoding and length checks.

Binding / authorization:

initiatorDeviceId MUST equal authenticated deviceId from token/session.

If not: C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH.

responderDeviceId MUST belong to peerUserId (authoritative DB mapping).

If not: C6P.WIRE.INVALID_ENVELOPE or C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH (policy).

Prekey binding (server-side authoritative consistency):

usedSignedPrekeyId MUST exist for responder device AND MUST match stored usedSignedPrekeyPublicKeyX25519.

If not: C6P.KEYS.KEY_NOT_FOUND or C6P.WIRE.INVALID_ENVELOPE.

OTP reservation rules (if usedOneTimePrekeyId present):

OTP id MUST be reserved for this initiator + responder + session attempt OR referenced by a reservation token minted by server during bundle fetch (implementation choice, but MUST be enforced).

OTP MUST exist for responder device AND pub must match stored record.

OTP MUST be in state RESERVED and transition to PENDING_CONSUMPTION when the offer is accepted for storage.

Failures:

Not reserved: C6P.HANDSHAKE.OTP_MISSING or C6P.KEYS.KEY_NOT_FOUND (choose one policy and keep consistent).

Session replay/uniqueness:
sessionId MUST be unique per tuple:

(initiatorDeviceId, responderDeviceId, sessionId)

Duplicate MUST be rejected as replay with:

C6P.HANDSHAKE.REPLAYED_OFFER (or C6P.WIRE.INVALID_ENVELOPE only if you want less explicitness).

Server cryptography rule (strict):

Server MUST NOT recompute or validate transcriptHash, kc1, or signature cryptographically as part of correctness.

Server MAY decode and length-check only, enforcing state/routing invariants.

Rate limits (MUST):

Apply per initiator device and per peer target to mitigate spam/DoS.

On throttle: C6P.INVAR.CONFIG_INVALID is NOT appropriate; use your normal API throttling code + map to a safe error response (see §7).

5.1.3 Response JSON — OpenResponse
{
  "ok": true,
  "sessionDbId": 987,
  "sessionId": "1122334455667788",
  "responderUserId": 12345,
  "responderDeviceId": "bbbbbbbb...<hex32>",
  "state": "PENDING"
}


State meanings:

PENDING: offer stored, responder not yet accepted.

ACTIVE: accept stored (initiator still MUST verify kc2 client-side).

REJECTED / EXPIRED: explicit denial or TTL expiry.

5.2 Responder accept (attaches kc2)

POST /v1/dm/handshake/accept
Auth: Required (responder)
Purpose: Responder attaches key confirmation kc2 to existing session.

5.2.1 Request JSON — AcceptRequest
{
  "sessionId": "1122334455667788",
  "responderDeviceId": "bbbbbbbb...<hex32>",
  "kc2": "<b64url32>"
}

5.2.2 Server validation (MUST)

responderDeviceId MUST equal authenticated responder device.

Session MUST exist with:

same sessionId,

same responder device,

state PENDING.

Idempotency:

If session already ACTIVE, accept is idempotent only if kc2 matches stored value exactly.

If mismatch: C6P.HANDSHAKE.STATE_VIOLATION or C6P.WIRE.INVALID_ENVELOPE (choose one and keep consistent).

OTP consumption (atomic):

If offer references usedOneTimePrekeyId, server MUST transition OTP:

PENDING_CONSUMPTION -> CONSUMED

This MUST be atomic with storing the accept record.

5.2.3 Response JSON — AcceptResponse
{ "ok": true }

6. Delivery (Polling / WS)

Offer and accept may be delivered via WebSocket push, long-poll, or notification+pull.
Payloads MUST remain identical regardless of transport.

6.1 Responder incoming offer payload
{
  "type": "dm.handshake.offer.v1",
  "offer": { "...": "handshakeOffer" },
  "peerUserId": 111,
  "createdAt": "2026-01-03T12:34:56.000Z"
}

6.2 Initiator incoming accept payload
{
  "type": "dm.handshake.accept.v1",
  "sessionId": "1122334455667788",
  "responderDeviceId": "bbbbbbbb...<hex32>",
  "kc2": "<b64url32>",
  "createdAt": "2026-01-03T12:35:40.000Z"
}


Delivery rules:

Server MUST only deliver the offer to the responder user/device.

Server MUST only deliver the accept to the original initiator device.

Client MUST treat accept as valid only if it matches a local PENDING session state.

7. Error Handling (Canonical Mapping)

All server error responses for this module MUST use canonical registry codes from:

docs/crypto/c6p-error-codes.md

7.1 Error response shape (server)


{
  "ok": false,
  "errorCode": "C6P.WIRE.INVALID_ENVELOPE",
  "message": "Invalid request.",
  "retry": "NO_RETRY",
  "traceId": "t-7c9e..."
}


Rules:

errorCode REQUIRED.

traceId REQUIRED on backend.

message MUST be non-sensitive and MUST NOT reveal cryptographic correctness (kc/signature validity).

7.2 Suggested HTTP status mapping (non-normative)

400: invalid input / decode / non-canonical (C6P.ENC.*, C6P.WIRE.*)

409: state conflict (C6P.HANDSHAKE.STATE_VIOLATION, C6P.RATCHET.*)

422: semantically invalid but well-formed (rare here; generally keep fail-closed with safe text)

500: internal invariant (C6P.INVAR.*, store atomicity violations)

8. Storage & TTL (Server Invariants)
8.1 DM session record (conceptual)

A DM session record MUST store:

initiatorUserId, initiatorDeviceId

responderUserId, responderDeviceId

sessionId

offer payload (opaque blob)

accept payload (opaque blob, once present)

state enum

createdAt, updatedAt, expiresAt

referenced otpId (nullable)

8.2 Expiry rules

Offers MUST have TTL (e.g., 7 days) after which state becomes EXPIRED.

Reserved OTPs MUST have reservation TTL.

If session expires before accept, server MAY recycle the reserved OTP only after reservation TTL elapses.

If accept stored, OTP MUST be permanently CONSUMED.

9. Client-Side Strict Validation Checklist (Normative)
9.1 Initiator (creating offer)

Initiator MUST:

ensure local auth deviceId matches offer.initiatorDeviceId

ensure sessionId is freshly generated and never reused

validate bundle SPK signature before computing secrets

compute transcriptHash exactly per island-accord-crypto.md

compute kc1 and include it in offer

sign offer and include signature

store local session as PENDING

9.2 Responder (receiving offer)

Responder MUST:

validate JSON schema + encoding + lengths

ensure offer.responderDeviceId equals local deviceId

load SPK private by usedSignedPrekeyId (rotation window if supported)

if OTP present: load OTP private by id; if missing → abort

recompute transcriptHash; compare constant-time to offer.transcriptHash

verify initiator Ed25519 signature

verify kc1

derive session keys; store local state; send accept with kc2

9.3 Initiator (receiving accept)

Initiator MUST:

locate local PENDING session by sessionId

verify kc2

only then mark local state ACTIVE

10. Audit Notes (what auditors will try to break)

Auditors will test:

wrong length base64url fields

uppercase hex or wrong-length hex

padding in base64url

replay of sessionId tuple

OTP race: concurrent bundle fetches

accept idempotency correctness

authorization bypass (deviceId mismatch)

metadata leakage via errors/logs

Implementations MUST demonstrate:

unit tests for all validation branches

property tests for encoding/decoding strictness

state-machine tests for open/accept/expire/replay
