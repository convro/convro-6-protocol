# IslandAccord v1 — Wire Contracts (HTTP + WS)

Status: Production Target Spec (must-implement)
Scope: Prekeys + DM session opening + key confirmation + WS routing.
Non-scope: UI, App Store, client UX flows.

---

## 1) Conventions (MUST)

### 1.1 Encodings
- **hex16**: 16 lowercase hex chars (`^[0-9a-f]{16}$`) = 8 bytes (DeviceId, KeyId).
- **hex8**: 8 lowercase hex chars (`^[0-9a-f]{8}$`) = 4 bytes (SessionId).
- **b64url (no padding)**: base64url without `=` padding (URL-safe):
  - `+` → `-`, `/` → `_`, remove `=`

### 1.2 Normalization
- All ids MUST be lowercase when sent.
- All b64url fields MUST decode cleanly; server MUST reject invalid encodings.

### 1.3 Trust model (wire-level)
- Server is a **router** and **state machine only**.
- Server MUST NOT compute, derive, or store session secrets.
- Client-side cryptographic transcript binding is enforced with `transcriptHash`.

---

## 2) HTTP: Prekeys

### 2.1 GET `/v1/prekeys/status`
Auth: REQUIRED

**Response (200)**
```json
{
  "ok": true,
  "deviceId": "a1b2c3d4e5f60708",
  "signedPreKeyFingerprint": "b64url_32B",
  "oneTimeAvailable": 57,
  "lastRotationAt": "2025-12-31T19:51:22.123Z"
}



Validation (server)

deviceId MUST be hex16.

oneTimeAvailable MUST be >= 0.

signedPreKeyFingerprint MUST be b64url(32B) (fingerprint bytes) if present, else empty string is forbidden.

2.2 POST /v1/prekeys/upload

Auth: REQUIRED

Request
{
  "identityPublicKeyEd25519": "b64url_32B",
  "signedPrekey": {
    "keyId": "0123456789abcdef",
    "publicKeyX25519": "b64url_32B",
    "signatureEd25519": "b64url_64B"
  },
  "oneTimePrekeys": [
    { "prekeyId": "aaaaaaaaaaaaaaaa", "publicKeyX25519": "b64url_32B" },
    { "prekeyId": "bbbbbbbbbbbbbbbb", "publicKeyX25519": "b64url_32B" }
  ]
}
Validation (server MUST fail-closed)

identityPublicKeyEd25519 decodes to 32 bytes.

signedPrekey.keyId is hex16.

signedPrekey.publicKeyX25519 decodes to 32 bytes.

signedPrekey.signatureEd25519 decodes to 64 bytes.

Server MUST verify: signatureEd25519 = Ed25519Sig("C6P_PREKEY_V1" || signedPrekey.publicKeyX25519_raw) under identityPublicKeyEd25519.

Each OTP:

prekeyId is hex16

publicKeyX25519 decodes to 32 bytes

Server MUST cap OTP batch size (anti-abuse), e.g. max 256.

Response (200)
{
  "accepted": true,
  "acceptedOneTimePrekeyIds": ["aaaaaaaaaaaaaaaa","bbbbbbbbbbbbbbbb"]
}

2.3 GET /v1/prekeys/bundle?device_id={hex16}

Auth: REQUIRED (production requirement to reduce scraping)
Rate limit: REQUIRED

Query:

device_id: responder deviceId (hex16)

Response (200)
{
  "responderDeviceId": "1122334455667788",
  "identityPublicKeyEd25519": "b64url_32B",

  "signedPrekeyId": "0123456789abcdef",
  "signedPrekeyPublicKeyX25519": "b64url_32B",
  "signedPrekeySignature": "b64url_64B",

  "oneTimePrekeyId": "aaaaaaaaaaaaaaaa",
  "oneTimePrekeyPublicKeyX25519": "b64url_32B"
}
OTP semantics (server MUST)

Server MUST atomically issue an OTP:

if available: include oneTimePrekeyId + oneTimePrekeyPublicKeyX25519

if unavailable: server MUST return:

oneTimePrekeyId as empty string

oneTimePrekeyPublicKeyX25519 as empty string

Server MUST mark issued OTP as reserved for a short TTL until session open is received, then consumed (or returned to pool on expiration).

Server MUST prevent OTP reuse across any two issued bundles.

Client requirements (MUST)

Client MUST verify SPK signature using bundle identity key.

Client MUST support both:

OTP present (non-empty)

OTP absent (empty strings)

3) HTTP: DM Session Opening (IslandAccord Offer)
3.1 POST /v1/dm/sessions/open

Auth: REQUIRED

Purpose:

Create DM session record and route handshake offer to responder.

Server MUST NOT alter cryptographic fields.

Request
{
  "peerUserId": 12345,
  "handshakeOffer": {
    "version": 1,

    "initiatorDeviceId": "a1b2c3d4e5f60708",
    "responderDeviceId": "1122334455667788",
    "sessionId": "deadbeef",

    "identityPublicKeyEd25519": "b64url_32B",
    "signedPrekeyId": "0123456789abcdef",
    "signedPrekeySignature": "b64url_64B",

    "ephemeralPublicKeyX25519": "b64url_32B",
    "usedSignedPrekeyPublicKeyX25519": "b64url_32B",
    "usedOneTimePrekeyId": "aaaaaaaaaaaaaaaa",

    "transcriptHash": "b64url_32B"
  }
}
Validation (server MUST fail-closed)

peerUserId > 0.

handshakeOffer.version == 1.

initiatorDeviceId hex16.

responderDeviceId hex16.

sessionId hex8.

identityPublicKeyEd25519 decodes to 32 bytes.

signedPrekeyId hex16.

signedPrekeySignature decodes to 64 bytes.

ephemeralPublicKeyX25519 decodes to 32 bytes.

usedSignedPrekeyPublicKeyX25519 decodes to 32 bytes.

usedOneTimePrekeyId MUST be hex16 or empty string (if no OTP was issued).

transcriptHash decodes to 32 bytes.

Cross-checks (server MUST)

Server MUST bind initiator user from auth token as the session initiator (no spoof).

Server MUST ensure responderDeviceId belongs to peerUserId (active device).

OTP rules:

if usedOneTimePrekeyId non-empty: server MUST ensure it was the OTP reserved/issued for the latest bundle of (responderDeviceId, sessionId) and mark it consumed.

if empty: server MUST ensure bundle for responder had no OTP available at the time of issue.

Response (200)
{
  "ok": true,
  "sessionDbId": 9876,
  "sessionId": "deadbeef",
  "responderUserId": 12345,
  "responderDeviceId": "1122334455667788",
  "state": "PENDING"
}
State machine (MUST)

PENDING: offer routed, awaiting key confirmation.

ACTIVE: key confirmation complete on both ends.

FAILED: invalid offer / invalid OTP / responder rejected.

EXPIRED: TTL exceeded before ACTIVE.

4) WebSocket: Offer delivery + confirmation routing

Transport: existing authenticated socket connection.

4.1 Event: dm.session.offer (server → responder)

Payload
{
  "type": "dm.session.offer",
  "sessionId": "deadbeef",
  "state": "PENDING",
  "handshakeOffer": {
    "version": 1,

    "initiatorDeviceId": "a1b2c3d4e5f60708",
    "responderDeviceId": "1122334455667788",
    "sessionId": "deadbeef",

    "identityPublicKeyEd25519": "b64url_32B",
    "signedPrekeyId": "0123456789abcdef",
    "signedPrekeySignature": "b64url_64B",

    "ephemeralPublicKeyX25519": "b64url_32B",
    "usedSignedPrekeyPublicKeyX25519": "b64url_32B",
    "usedOneTimePrekeyId": "aaaaaaaaaaaaaaaa",

    "transcriptHash": "b64url_32B"
  }
}
Responder MUST:

Validate offer structure and encodings.

Verify signedPrekeySignature using identityPublicKeyEd25519.

Verify SPK binding: local SPK pub MUST equal usedSignedPrekeyPublicKeyX25519.

If OTP id non-empty: MUST load OTP private key; fail if missing.

Derive session keys locally and proceed to Key Confirmation.

5) Key Confirmation (MANDATORY, production)

IslandAccord v1 defines KC messages that are transported inside DM encrypted control messages.
Server routes them as regular DM messages; server does not interpret ciphertext.

5.1 KC1 (initiator → responder)

First encrypted control message after /open MUST be KC1.

KC1 plaintext structure (inside DM control message)
{
  "t": "KC1",
  "v": 1,
  "sessionId": "deadbeef",
  "confirm": "b64url_32B"
}
here:

confirm = SHA256("IA_KC1_V1" || transcriptHash_raw || initiatorDeviceId_raw || responderDeviceId_raw || sessionId_raw)

Responder MUST verify confirm. If fails → mark FAILED.

5.2 KC2 (responder → initiator)

Responder replies with KC2:
{
  "t": "KC2",
  "v": 1,
  "sessionId": "deadbeef",
  "confirm": "b64url_32B"
}
Where:

confirm = SHA256("IA_KC2_V1" || transcriptHash_raw || responderDeviceId_raw || initiatorDeviceId_raw || sessionId_raw)

Initiator MUST verify KC2. If OK → mark ACTIVE.

5.3 Server session state update

When server observes authenticated delivery of KC2 to initiator (message-level receipt), server MUST set session state=ACTIVE.
(If you track “READ” separately, do not conflate with ACTIVE.)

6) Error format (MUST)

Server MUST return structured errors:
{
  "ok": false,
  "code": "INVALID_HANDSHAKE_OFFER",
  "message": "ephemeralPublicKeyX25519 must decode to 32 bytes"
}

Required codes:

INVALID_DEVICE_ID

INVALID_SESSION_ID

INVALID_B64URL

INVALID_SIGNATURE

OTP_NOT_ISSUED

OTP_ALREADY_CONSUMED

PEER_DEVICE_NOT_FOUND

UNAUTHORIZED

7) Minimal metadata policy (MUST)

Server MUST store:

sessionId, initiatorUserId, responderUserId, initiatorDeviceId, responderDeviceId, state, timestamps

Server MUST NOT store:

ciphertext payloads beyond standard message storage rules

derived keys or any secret material

Logs MUST be TTL-limited and redact b64url fields where possible.

END.
