# IslandAccord v1 — Wire Contract & Validation (island-accord-wire.md)

**Status:** Production / Canonical  
**Handshake:** IslandAccord v1  
**Scope:** HTTP + WS delivery formats, strict validation rules, server invariants, client invariants, error taxonomy.  
**Audience:** Security auditors, backend implementers, client implementers.  
**Principle:** **Fail-closed.** Any deviation from this contract MUST be rejected.

---

## 0. Normative Language

- **MUST / MUST NOT / SHOULD / MAY** are used as defined in RFC 2119.
- “Server” is untrusted for secrecy but trusted to enforce **state/invariants** (OTP reservation, session uniqueness, replay mitigation).

---

## 1. Canonical Identifiers & Encodings

### 1.1 Hex identifiers (strict)
- `deviceId`: **8 bytes** encoded as **hex16 lowercase**.
  - Regex: `^[0-9a-f]{16}$`
- `sessionId`: **4 bytes** encoded as **hex8 lowercase**.
  - Regex: `^[0-9a-f]{8}$`
- `keyId` (SPK/OTP): **8 bytes** encoded as **hex16 lowercase**.
  - Regex: `^[0-9a-f]{16}$`

**Normalization rule:**  
Clients MUST lower-case all hex on output. Servers MUST reject any hex not lowercase or not matching regex.

### 1.2 base64url (no padding) (strict)
All binary fields (keys/hashes/mac/signatures) are base64url without padding:
- Characters: `A–Z a–z 0–9 - _`
- Regex: `^[A-Za-z0-9_-]+$`
- MUST decode to exact byte length specified per field.

**Padding:** MUST NOT be present (`=` forbidden).  
If present, server MUST reject.

### 1.3 Byte lengths (strict table)

| Field | Type | Bytes (decoded) |
|------|------|------------------|
| X25519 public key | b64url | 32 |
| Ed25519 public key | b64url | 32 |
| SHA-256 hash | b64url | 32 |
| HMAC-SHA256 output | b64url | 32 |
| Ed25519 signature | b64url | 64 |

---

## 2. Protocol Versioning & Suite

### 2.1 Version
- `version` MUST be integer `1`.

### 2.2 Suite
- `suiteId` MUST be a valid one-byte suite id supported by the implementation.
- Unknown suiteId MUST be rejected.
- `suiteId` MUST be included in transcript and in initiator signature input (downgrade resistance).

---

## 3. Endpoints (Canonical)

### 3.1 Prekeys status
**GET** `/v1/prekeys/status`

**Auth:** Required  
**Response (JSON):**
json
{
  "ok": true,
  "deviceId": "0123abcd4567ef89",
  "signedPreKeyFingerprint": "…",
  "oneTimeAvailable": 64,
  "lastRotationAt": "2025-12-31T12:34:56.000Z"
}

Validation rules:

oneTimeAvailable MUST be integer ≥ 0.

Server MUST compute oneTimeAvailable from authoritative store (not client hints).

3.2 Fetch bundle (atomic OTP reservation)

GET /v1/prekeys/bundle?device_id=<hex16>

Auth: Required
Semantics: Server returns responder bundle for a device. If OTP is available, server MUST atomically reserve one OTP and include it in response.

Response (JSON) — BundleResponse:

{
  "responderDeviceId": "aaaaaaaaaaaaaaaa",
  "identityPublicKeyEd25519": "<b64url32>",
  "identityPublicKeyX25519": "<b64url32>",
  "signedPrekeyId": "bbbbbbbbbbbbbbbb",
  "signedPrekeyPublicKeyX25519": "<b64url32>",
  "signedPrekeySignature": "<b64url64>",
  "oneTimePrekeyId": "cccccccccccccccc",
  "oneTimePrekeyPublicKeyX25519": "<b64url32>"
}

Rules:

responderDeviceId MUST equal requested device_id.

If oneTimePrekeyId is present, oneTimePrekeyPublicKeyX25519 MUST be present (and vice versa).
If exactly one exists => reject/abort (server bug or tampering).

Server MUST ensure OTP returned in bundle is reserved for the requesting initiator (or reserved for that session creation attempt) and cannot be returned to another initiator concurrently.

Client validation:

Decode lengths strictly.

Verify SPK signature using identityPublicKeyEd25519:

VerifyEd25519(idSigPub, spkSig, LABEL_PREKEY || spkId_bytes || spkPub_bytes)

If signature invalid => client MUST abort.

3.3 Upload prekeys

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
Validation:

All fields required except oneTimePrekeys MAY be empty list.

keyId / prekeyId must be lowercase hex16.

Signatures MUST be valid:

Sig = SignEd25519(IK_sig_priv, LABEL_PREKEY || spkId_bytes || spkPub_bytes)

Server MUST reject duplicates for (deviceId, keyId) that do not match stored value exactly.

Server MUST store identity keys immutably per device (rotation is versioned, never “overwrite without record”).

Response (JSON):

{
  "accepted": true,
  "message": "ok",
  "acceptedOneTimePrekeyIds": ["cccccccccccccccc"]
}

4. DM Session Establishment (IslandAccord)
4.1 Open DM session (creates and delivers offer)

POST /v1/dm/sessions/open

Auth: Required
Purpose: Initiator creates DM session request and stores offer for responder delivery.

4.1.1 Request JSON — OpenRequest
{
  "peerUserId": 12345,
  "handshakeOffer": {
    "version": 1,
    "suiteId": 1,
    "sessionId": "11223344",
    "initiatorDeviceId": "aaaaaaaaaaaaaaaa",
    "responderDeviceId": "bbbbbbbbbbbbbbbb",

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
4.1.2 Server-side validation (MUST)

Structural:

peerUserId MUST be integer > 0.

handshakeOffer.version MUST equal 1.

suiteId must be supported by server policy (server may restrict suites).

All hex must be lowercase and match regex.

All b64url must match regex and decode to exact length.

Binding / sanity checks:

initiatorDeviceId MUST equal authenticated deviceId from token/session.

responderDeviceId MUST belong to peerUserId (canonical mapping in DB).

usedSignedPrekeyId MUST exist for responder device and MUST match usedSignedPrekeyPublicKeyX25519.

If usedOneTimePrekeyId present:

MUST be reserved for this initiator-session creation attempt OR be “reserved token” minted by server during bundle fetch.

MUST exist for responder device and MUST match stored OTP pub.

MUST be in state RESERVED and transition to PENDING_CONSUMPTION.

sessionId MUST be unique per tuple:

(initiatorDeviceId, responderDeviceId, sessionId)

Duplicate MUST be rejected (replay).

Server cryptography rule:

Server MUST NOT verify or recompute transcriptHash / kc1 / signature as security-critical secrets.
(Server MAY do superficial checks like decoding lengths only.)

Correctness is enforced client-side; server enforces state & routing invariants.

Rate limits:

MUST apply per initiator device and per peer target to mitigate spam/DoS.

4.1.3 Response JSON — OpenResponse
{
  "ok": true,
  "sessionDbId": 987,
  "sessionId": "11223344",
  "responderUserId": 12345,
  "responderDeviceId": "bbbbbbbbbbbbbbbb",
  "state": "PENDING"
}
State meanings:

PENDING: offer stored, responder not yet accepted.

ACTIVE: accept stored (but initiator still MUST verify kc2).

REJECTED / EXPIRED: explicit denial or TTL expiry.

4.2 Responder accept (delivers kc2)

POST /v1/dm/handshake/accept

Auth: Required (responder)
Purpose: Responder attaches key confirmation kc2 to existing session.

4.2.1 Request JSON — AcceptRequest
{
  "sessionId": "11223344",
  "responderDeviceId": "bbbbbbbbbbbbbbbb",
  "kc2": "<b64url32>"
}
4.2.2 Server validation (MUST)

responderDeviceId MUST equal authenticated responder device.

Session must exist in DB with:

same sessionId

same responder device

state PENDING

If session already ACTIVE, accept is idempotent only if kc2 matches stored value exactly; otherwise reject.

OTP consumption rules:

If the session offer references usedOneTimePrekeyId, server MUST transition OTP:

from PENDING_CONSUMPTION -> CONSUMED

This must happen atomically with storing accept record.

Server MUST ensure OTP cannot be used in any other session once consumed.

4.2.3 Response JSON — AcceptResponse
{
  "ok": true
}

5. Delivery (Polling / WS)

Implementations may deliver offer/accept via:

WebSocket push

Long-poll

Notification + pull

The wire payload MUST remain identical.

5.1 Responder incoming offer payload
{
  "type": "dm.handshake.offer.v1",
  "offer": { ...handshakeOffer... },
  "peerUserId": 111,
  "createdAt": "2025-12-31T12:34:56.000Z"
}

5.2 Initiator incoming accept payload
{
  "type": "dm.handshake.accept.v1",
  "sessionId": "11223344",
  "responderDeviceId": "bbbbbbbbbbbbbbbb",
  "kc2": "<b64url32>",
  "createdAt": "2025-12-31T12:35:40.000Z"
}


Delivery rules:

Server MUST only deliver offer to responder user/device.

Server MUST only deliver accept to the original initiator device.

Payloads MUST be replay-safe at the client:

client treats accept as valid only if it matches a local PENDING session state.

6. Client-Side Strict Validation Checklist
6.1 Initiator (on creating offer)

Initiator MUST:

ensure local auth deviceId matches offer.initiatorDeviceId

ensure sessionId is freshly generated and not reused

validate bundle signature before computing secrets

compute transcriptHash exactly per spec

compute kc1 and include in offer

sign offer with Ed25519 and include signature

store session locally as PENDING

6.2 Responder (on receiving offer)

Responder MUST:

Validate JSON schema + encoding + lengths.

Check responderDeviceId matches local device.

Load appropriate SPK private:

must match usedSignedPrekeyId and pub must match usedSignedPrekeyPublicKeyX25519

supports rotation window if implemented, else reject.

If OTP id present:

load OTP private by id; if missing => reject

Recompute transcriptHash and compare with offer.transcriptHash (constant-time compare).

Verify initiator Ed25519 signature.

Verify kc1.

Derive session keys and store as ACTIVE.

Consume OTP locally after successful session creation.

Send accept with kc2.

6.3 Initiator (on receiving accept)

Initiator MUST:

locate local PENDING session by sessionId

verify kc2

only then mark local state ACTIVE

7. Error Taxonomy (Auditor-grade)
7.1 Server error response shape

Servers MUST return:

{
  "ok": false,
  "code": "C6P_…",
  "message": "human readable (non-sensitive)",
  "requestId": "…"
}

7.2 Canonical error codes

C6P_BAD_REQUEST — malformed JSON, missing field

C6P_BAD_ENCODING — invalid hex/b64url or wrong length

C6P_UNAUTHORIZED — missing/invalid auth

C6P_FORBIDDEN — deviceId mismatch vs auth

C6P_PEER_NOT_FOUND — peer user/device unknown

C6P_PREKEY_NOT_FOUND — referenced SPK/OTP missing

C6P_OTP_NOT_RESERVED — OTP id not reserved for this flow

C6P_SESSION_REPLAY — duplicate sessionId tuple

C6P_STATE_CONFLICT — accept/open invalid for current state

C6P_RATE_LIMIT — throttled

No sensitive leakage rule:
Server MUST NOT reveal whether kc1/kc2/signature were “cryptographically correct”.

8. Storage & TTL (Server Invariants)
8.1 dm_sessions row invariants (conceptual)

A DM session record MUST store:

initiatorUserId, initiatorDeviceId

responderUserId, responderDeviceId

sessionId

offer payload (opaque blob)

accept payload (opaque blob, once present)

state enum

createdAt, updatedAt, expiresAt

referenced OTP id (nullable)

8.2 Expiry rules

Offers MUST have TTL (e.g., 7 days) after which state becomes EXPIRED.

Reserved OTPs MUST have reservation TTL.

If session expires before accept, server MAY recycle OTP only after reservation TTL elapses.

If accept stored, OTP MUST be permanently consumed.

9. Privacy / Metadata Minimization (Wire-Level)

IslandAccord v1 wire minimizes metadata by:

Not sending phone numbers / emails in handshake.

Using device-scoped identifiers and ephemeral sessionId.

Keeping offer payload free of UI/extra profile fields.

For delivery, server SHOULD avoid including peer full profile; client can fetch profile separately.

10. Audit Notes (what auditors will try to break)

Auditors will test:

wrong length base64url fields

uppercase hex

padding in base64url

signature and kc mismatch paths (must fail-closed)

replay of sessionId

OTP race: two initiators fetching bundle concurrently

SPK rotation edge cases

accept idempotency correctness

authorization bypass (deviceId mismatch)

metadata leakage (error messages, logs)

Implementations MUST demonstrate:

unit tests for all validation branches

property-based tests for encoding/decoding

state machine tests for open/accept/expire/replay
