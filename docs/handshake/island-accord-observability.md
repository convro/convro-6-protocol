# IslandAccord v1 — Observability & Security Telemetry (island-accord-observability.md)

**Status:** PRODUCTION / CANONICAL (Normative)  
**Handshake family:** IslandAccord v1  
**Scope:** Handshake + server state pipeline observability, security telemetry, structured event schema, logging privacy rules, metrics, tracing, and alerting guidance.  
**Applies to:** Node backend, Rust core (reference), Swift client, and any service handling IslandAccord offers/accepts or OTP reservation/consumption.  
**Aligned with (normative pointers):**
- `docs/crypto/c6p-crypto-error-codes.md` (canonical error registry, severity, retry policy)
- `docs/handshake/island-accord-wire.md` (wire validation + endpoint behavior)
- `docs/handshake/island-accord-state-machine.md` (server session states + OTP lifecycle)
- `docs/crypto/c6p-crypto-registry.md` (IDs, lengths, suite IDs, message types, stream IDs)
- `docs/crypto/c6p-aead-and-aad.md` (session binding concept + AAD fields; never log keys/nonces)

This document is **normative**. Implementations MUST follow it exactly. Any deviation MUST be treated as a security and audit risk.

---

## 0. Principles (Non-Negotiable)

### 0.1 Fail-Closed, But Observable
Any handshake validation failure, invariant failure, or state machine violation MUST:
- reject the operation (fail-closed)
- emit a **structured** security/telemetry event with a canonical error code
- avoid leaking secrets or sensitive correlation data

### 0.2 No Secret Leakage (Hard Rule)
Telemetry and logs MUST NOT include:
- private keys, DH outputs (`DH1..DH4`), `IKM`, `PRK`, `root_key`, chain keys, message keys
- plaintext, ciphertext, tags, derived nonces, derived AAD bytes
- raw transcript bytes
- raw base64 key blobs from offers/bundles (store fingerprints only if needed)
- any “why signature failed” oracle detail beyond canonical error code + stage

Allowed:
- canonical error code (e.g., `C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED`)
- endpoint + stage + module + severity + retry policy
- fixed-size public identifiers already visible at that stage:
  - `session_id` (8 bytes on bytes level; wire hex16)
  - `device_id` (16 bytes; wire hex32)
- lengths/format errors (expected vs actual)
- timestamps and coarse counters
- opaque `traceId` / `requestId`

### 0.3 Stable Contracts
Event names, field names, and canonical error codes are **stable contracts**.  
Once shipped, they MUST NOT be repurposed.

### 0.4 Minimal Metadata, Privacy-First
Operators need enough signal to detect abuse and regressions without collecting personal data.  
Telemetry MUST be metadata-minimal and SHOULD support privacy-preserving aggregation.

---

## 1. Canonical Identifiers & Sizes (Normative)

These definitions are authoritative for observability payloads (must match Registry).

- `C6PDeviceId`:
  - canonical bytes: **16 bytes**
  - wire encoding: **hex32 lowercase**
- `C6PSessionId`:
  - canonical bytes: **8 bytes**
  - wire encoding: **hex16 lowercase**
- `C6PKeyId` (SPK/OTP id):
  - canonical bytes: **8 bytes**
  - wire encoding: **hex16 lowercase**
- `suite_id`: u8
  - production default: `0x01` (ChaCha20-Poly1305)

**Hard rule:** Any telemetry that includes IDs MUST encode them in the same canonical wire form (hex lowercase, fixed-length).

---

## 2. Where Observability Lives (Normative)

IslandAccord has three observation surfaces:

### 2.1 Server (Authoritative for state + OTP scarcity)
Server MUST emit events for:
- OTP reservation/expiry/consumption
- session creation (`open()`), accept, reject/cancel/expire/abort
- state conflicts, replays, rate limits, and authorization violations
- wire validation failures

Server MUST NOT emit events that depend on verifying cryptographic correctness of the handshake beyond:
- strict decoding/format checks
- DB invariants / state transitions

### 2.2 Client (Authoritative for cryptographic acceptance)
Clients SHOULD emit local events for:
- SPK signature verification result
- transcript recompute mismatch
- initiator signature verification result
- key confirmation verification result
- local store errors (atomicity, corruption)
- ratchet init success/fail (but never secrets)

### 2.3 Rust Core (Reference)
Rust reference implementation SHOULD expose:
- deterministic test vector checks
- strict parser errors mapped to canonical error codes
- internal invariant failures (`C6P.INVAR.*`)

---

## 3. Canonical Event Naming (Normative)

Event names MUST be dot-separated and versioned:

- Prefix: `c6p.ia.v1.*` for IslandAccord v1
- Prefix: `c6p.crypto.v1.*` for cross-cutting crypto errors (optional)

Examples:
- `c6p.ia.v1.session.open`
- `c6p.ia.v1.session.accept`
- `c6p.ia.v1.otp.reserved`
- `c6p.ia.v1.error`
- `c6p.ia.v1.security.violation`

**Hard rule:** Event names MUST NOT be changed once used in production dashboards/alerts.

---

## 4. Structured Event Envelope (Normative)

All telemetry records MUST conform to this envelope shape.

### 4.1 Envelope Fields (Required)
```json
{
  "event": "c6p.ia.v1.session.open",
  "ts": "2026-01-03T14:59:12.123Z",
  "build": "prod",
  "component": "server",
  "module": "handshake/open",
  "stage": "validate",
  "traceId": "t-5e8b4c2d0f6a",
  "requestId": "r-9d0a3f",
  "severity": "INFO"
}
```






Field rules:

event (string, required)

ts (RFC3339, required)

build ∈ {prod, staging, test} (required)

component ∈ {server, client, rust} (required)

module (string, required): stable path-like identifier

stage (string, required): e.g. decode, validate, state, store, crypto_verify, deliver

traceId (string, required on server; SHOULD on clients)

requestId (string, required on server)

severity ∈ {INFO, WARN, ERROR, SECURITY} (required)

4.2 Optional Common Fields (Allowed)

sessionId (hex16) if known

initiatorDeviceId (hex32) if known and authorized

responderDeviceId (hex32) if known and authorized

suiteId (u8) if present

otpId (hex16) if present

http object (method, path, status)

net object (transport: http/ws, client version)

expectedLength, actualLength (numbers)

retryPolicy ∈ {NO_RETRY, RETRY_SAFE, RETRY_AFTER_SYNC, RETRY_AFTER_ROTATION}

Hard rule: Never add arbitrary free-form debug dumps to production telemetry.

5. Privacy-Preserving Identifiers (Normative)
5.1 When to Hash Identifiers

By default, sessionId may be logged (it is short-lived and protocol-scoped).
deviceId MAY be logged in server internal logs only if your privacy policy permits and access is restricted.

For analytics/dashboards and long-term retention, implementations SHOULD use hashed identifiers.

5.2 Canonical Hashing Method (Recommended)

To prevent cross-system correlation, use a server-secret keyed hash:

deviceId_hash = HMAC-SHA256(LOG_KEY, deviceId_bytes)

sessionId_hash = HMAC-SHA256(LOG_KEY, sessionId_bytes)

Output encoding:

base64url (no padding) or hex lowercase (pick one and stay consistent across telemetry)

Hard rule: Never use raw SHA-256 without a secret key for long-term identifiers (enables offline correlation).

6. Canonical Error Event (Normative)

All failures MUST emit exactly one canonical error event:

6.1 c6p.ia.v1.error
{
  "event": "c6p.ia.v1.error",
  "ts": "2026-01-03T14:59:12.123Z",
  "build": "prod",
  "component": "server",
  "module": "handshake/open",
  "stage": "decode",
  "traceId": "t-5e8b4c2d0f6a",
  "requestId": "r-9d0a3f",
  "severity": "WARN",
  "error": {
    "code": "C6P.ENC.INVALID_B64URL",
    "retryPolicy": "NO_RETRY",
    "field": "handshakeOffer.initiatorIdentityDhPub",
    "expectedLength": 32,
    "actualLength": 31
  },
  "context": {
    "sessionId": "0011223344556677",
    "initiatorDeviceId": "0123456789abcdef0123456789abcdef",
    "responderDeviceId": "fedcba9876543210fedcba9876543210",
    "suiteId": 1
  }
}


Rules:

error.code MUST be one from docs/crypto/c6p-crypto-error-codes.md

severity MUST match the registry entry for that code

retryPolicy MUST match the registry entry for that code

field SHOULD be included when meaningful

length fields MUST be included when relevant

Hard rule: Do not emit multiple error events for the same failing request path (avoid alert amplification).

7. Canonical Security Violation Event (Normative)

Some failures indicate active abuse or severe state corruption.

7.1 c6p.ia.v1.security.violation

Use this ONLY for severity=SECURITY errors and invariants like replay or OTP abuse.

{
  "event": "c6p.ia.v1.security.violation",
  "ts": "2026-01-03T14:59:12.123Z",
  "build": "prod",
  "component": "server",
  "module": "handshake/open",
  "stage": "state",
  "traceId": "t-5e8b4c2d0f6a",
  "requestId": "r-9d0a3f",
  "severity": "SECURITY",
  "error": {
    "code": "C6P.HANDSHAKE.REPLAYED_OFFER",
    "retryPolicy": "NO_RETRY"
  },
  "context": {
    "sessionId": "0011223344556677",
    "initiatorDeviceId": "0123456789abcdef0123456789abcdef",
    "responderDeviceId": "fedcba9876543210fedcba9876543210",
    "suiteId": 1,
    "reason": "duplicate_session_tuple"
  }
}


Hard rule: Never include “this signature failed” vs “KC failed” differential hints in server responses.
Server may log the canonical code internally, but HTTP responses MUST remain non-oracular.

8. Required Server Events (Normative)

Server MUST emit these events when the corresponding transition occurs.

8.1 Session lifecycle
8.1.1 c6p.ia.v1.session.open

Emitted after open() passes validation and the DB transaction commits.

Required fields:

sessionId

initiatorDeviceId (or hashed form)

responderDeviceId (or hashed form)

suiteId

state = PENDING

expiresAt

optional otpId if referenced in offer

Example:

{
  "event": "c6p.ia.v1.session.open",
  "ts": "2026-01-03T15:02:11.002Z",
  "build": "prod",
  "component": "server",
  "module": "handshake/open",
  "stage": "store",
  "traceId": "t-acde1",
  "requestId": "r-acde1",
  "severity": "INFO",
  "context": {
    "sessionId": "0011223344556677",
    "initiatorDeviceId": "0123456789abcdef0123456789abcdef",
    "responderDeviceId": "fedcba9876543210fedcba9876543210",
    "suiteId": 1,
    "state": "PENDING",
    "expiresAt": "2026-01-10T15:02:11.002Z",
    "otpId": "aabbccddeeff0011"
  }
}

8.1.2 c6p.ia.v1.session.accept

Emitted after accept() commits (session -> ACTIVE) and any OTP consumption is committed.

Required fields:

sessionId

responderDeviceId

state = ACTIVE

otpConsumed boolean

if otpConsumed=true, include otpId

8.1.3 c6p.ia.v1.session.reject (if endpoint exists)

Required fields:

sessionId, responderDeviceId, state=REJECTED

reasonCode (u8 or short string; non-sensitive)

8.1.4 c6p.ia.v1.session.cancel (if endpoint exists)

Required fields:

sessionId, initiatorDeviceId, state=CANCELLED

8.1.5 c6p.ia.v1.session.expire

Emitted when the scheduler (or on-read enforcement) transitions PENDING -> EXPIRED.

Required fields:

sessionId, state=EXPIRED

expiredAt

8.1.6 c6p.ia.v1.session.abort

Required fields:

sessionId, state=ABORTED

policyReason (non-sensitive)

8.2 OTP lifecycle
8.2.1 c6p.ia.v1.otp.reserved

Emitted when bundle fetch reserves an OTP (AVAILABLE -> RESERVED).

Required fields:

responderDeviceId

otpId

expiresAt

optional reservedForInitiatorDeviceId or reservationToken (if implemented)

8.2.2 c6p.ia.v1.otp.pending_consumption

Emitted when open() links OTP to a session (RESERVED -> PENDING_CONSUMPTION).

Required fields:

responderDeviceId

otpId

sessionId

optional initiatorDeviceId (or hash)

8.2.3 c6p.ia.v1.otp.consumed

Emitted when accept consumes OTP (PENDING_CONSUMPTION -> CONSUMED).

Required fields:

responderDeviceId

otpId

sessionId

consumedAt

8.2.4 c6p.ia.v1.otp.expired

Emitted when reservation TTL elapses without linking to a session (RESERVED -> EXPIRED).

Required fields:

responderDeviceId

otpId

expiredAt

Hard rule: OTP events MUST NOT include OTP public key bytes.

9. Client Cryptographic Acceptance Events (Recommended)

Clients SHOULD emit local events to support debugging without server-side oracles.

9.1 c6p.ia.v1.client.offer.verify

Emitted when responder verifies offer.

Fields:

sessionId, initiatorDeviceId, responderDeviceId, suiteId

result: ok | fail

on failure: canonical error.code (e.g., C6P.KEYS.INVALID_SIGNATURE, C6P.KDF.TRANSCRIPT_HASH_MISMATCH, C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED)

Hard rule: Clients MUST NOT log DH outputs or derived keys.

9.2 c6p.ia.v1.client.accept.verify

Emitted when initiator verifies kc2.

Fields:

sessionId, responderDeviceId, result

on failure: C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED

9.3 Store integrity

Clients SHOULD emit:

c6p.ia.v1.client.store.write_failed -> C6P.STORE.WRITE_FAILED

c6p.ia.v1.client.store.atomicity_violation -> C6P.STORE.ATOMICITY_VIOLATION

c6p.ia.v1.client.store.state_corrupt -> C6P.RATCHET.STATE_CORRUPT or C6P.KEYS.KEY_STATE_INVALID

10. Metrics (Normative for Server, Recommended for Clients)
10.1 Required server counters

Server MUST expose counters:

ia_open_total{result=ok|fail, code?}

ia_accept_total{result=ok|fail, code?}

ia_bundle_total{otp=reserved|none, result=ok|fail, code?}

ia_session_state_total{state} (gauge)

ia_otp_state_total{state} (gauge)

10.2 Latency histograms

Server SHOULD expose:

ia_open_latency_ms

ia_accept_latency_ms

ia_bundle_latency_ms

ia_db_tx_latency_ms{tx=open|accept|bundle}

10.3 High-signal security rates

Server SHOULD track rates:

ia_security_violation_total{code}

ia_replay_total

ia_otp_abuse_total (e.g., invalid reservation binding attempts)

ia_rate_limit_total{scope=device|peer|ip}

Hard rule: Metrics labels MUST NOT include raw device IDs (high cardinality). Use hashed buckets or omit.

11. Tracing (Normative for Server)
11.1 Trace propagation

Server MUST propagate:

traceId across HTTP handlers, DB transactions, and WS delivery pipeline

requestId per inbound request

if WS: include deliveryId for each pushed payload

11.2 Trace spans (recommended)

Recommended spans:

ia.bundle.validate

ia.bundle.reserve_otp

ia.open.validate

ia.open.persist_session

ia.open.link_otp

ia.accept.validate

ia.accept.persist_accept

ia.accept.consume_otp

ia.deliver.offer

ia.deliver.accept

12. Alerting Rules (Auditor-Facing)

These are recommended alerts; implementations SHOULD adopt them.

12.1 Critical security alerts

spike in C6P.HANDSHAKE.REPLAYED_OFFER

spike in C6P.KEYS.KEY_ALREADY_CONSUMED / C6P.KEYS.KEY_NOT_FOUND for OTP

spike in C6P.AEAD.AUTH_FAILED (post-handshake channel failures; indicates tampering or desync)

repeated C6P.STORE.ATOMICITY_VIOLATION (data corruption)

12.2 Degradation alerts

ia_open_latency_ms p95 increase beyond baseline

ia_db_tx_latency_ms p95 increase

high C6P.STORE.WRITE_FAILED rates

12.3 Abuse/DoS signals

high ia_open_total{result=fail, code=C6P.RATE_LIMIT...} rate (if mapped)

high open attempts per initiatorDeviceId_hash / per target (privacy-preserving)

13. Redaction & Retention (Normative)
13.1 Redaction

Before shipping logs externally or storing long-term:

prefer hashed IDs (deviceId_hash, sessionId_hash)

drop peerUserId unless strictly necessary

drop any raw request payload copies

13.2 Retention

SECURITY events: retain longer (policy-defined), but still minimal fields

general INFO/WARN: short retention recommended (e.g., 7–30 days)

Hard rule: Never retain any secret material; never store raw offer/accept blobs in logs.

14. Required Mapping to Canonical Error Codes (Normative)

All internal errors MUST map to docs/crypto/c6p-crypto-error-codes.md.

Examples (non-exhaustive):

invalid hex/base64url/length -> C6P.ENC.*

unknown suite/version/type/stream -> C6P.AAD.VERSION_MISMATCH or C6P.AEAD.UNSUPPORTED_SUITE (depending on stage)

session tuple duplicate -> C6P.HANDSHAKE.REPLAYED_OFFER or C6P.WIRE.SESSION_ID_MISMATCH (policy)

OTP not reserved / mismatch -> C6P.HANDSHAKE.OTP_MISSING or C6P.KEYS.KEY_NOT_FOUND (choose one and keep consistent)

illegal transitions -> C6P.HANDSHAKE.STATE_VIOLATION

store failures -> C6P.STORE.*

Hard rule: Do not create new ad-hoc codes outside the registry.

15. Compliance Checklist (Fail-Closed)

Server MUST:

 emit exactly one structured c6p.ia.v1.error on any failure

 emit c6p.ia.v1.security.violation for SECURITY-severity cases

 include traceId + requestId in all server events

 never log secrets, nonces, keys, transcript bytes, or offer blobs

 avoid high-cardinality metrics labels (no raw device IDs)

 emit OTP lifecycle events (reserved/pending/consumed/expired)

 emit session lifecycle events (open/accept/expire/abort, and optional reject/cancel)

Clients SHOULD:

 emit local verify results with canonical error codes

 never log keys/DH/IKM/PRK/root/chain/mk/nonces/AAD bytes

 gate any debug-only crypto traces behind explicit compile/runtime flags (off by default)

Appendix A — Minimal “Operator Safe” Error Response (Server)

Server HTTP error responses MUST remain non-oracular and minimal:

{
  "ok": false,
  "errorCode": "C6P.HANDSHAKE.STATE_VIOLATION",
  "retry": "NO_RETRY",
  "requestId": "r-9d0a3f"
}


Rules:

no stack traces

no “KC failed” vs “signature failed” distinctions in server responses

detailed cause MAY exist only in server-internal logs under access control, still without secrets
