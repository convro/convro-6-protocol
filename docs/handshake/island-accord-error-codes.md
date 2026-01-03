# IslandAccord v1 — Error Codes & Failure Semantics (island-accord-error-codes.md)

**Status:** **PRODUCTION — NORMATIVE**  
**Handshake family:** IslandAccord v1  
**Scope:** Canonical error taxonomy for **handshake** endpoints and delivery (HTTP/WS/push), including strict failure behavior, retry policy, privacy rules, and mapping into the global C6P crypto error registry.  
**Audience:** Security auditors, backend implementers, client implementers.  
**Principle:** **Fail-closed.** Invalid, non-canonical, or out-of-state inputs MUST be rejected.

**Authoritative registries (MUST align):**
- `docs/crypto/c6p-crypto-error-codes.md` *(canonical code registry + severity + retry policy)*  
- `docs/crypto/c6p-crypto-registry.md` *(wire-stable IDs, labels, fixed sizes, suite_id values)*  
- `docs/handshake/island-accord-wire.md` *(wire contract + strict validation rules)*  
- `docs/handshake/island-accord-state-machine.md` *(server state machine + OTP lifecycle)*  
- `docs/handshake/island-accord-crypto.md` *(handshake cryptographic spec, transcript, KC, signatures)*

> **Authority rule (normative):** For crypto-critical failures (decode/validate/transcript/signature/KC/ratchet/AAD/AEAD), implementations MUST emit **C6P canonical codes** from `docs/crypto/c6p-crypto-error-codes.md`.  
> This document adds **handshake-specific mapping** and endpoint semantics; it MUST NOT invent conflicting codes.

---

## 0. Non-Negotiable Principles (Normative)

### 0.1 Fail-Closed, Deterministic
- Any validation, decoding, binding, or state invariant failure **MUST** abort the operation.
- Errors MUST be deterministic for a given input/state (no “best effort” acceptance).

### 0.2 No Secret Leakage
Server/client error surfaces and logs MUST NOT include:
- private keys / shared secrets / root keys / chain keys / message keys
- plaintext
- raw nonces
- raw AAD bytes
- raw transcript bytes
- “why signature failed” beyond a canonical error code (no oracle)

Allowed in logs/responses:
- `errorCode` (canonical)
- `severity`, `retry`
- `module`, `stage`, `field`
- expected length vs actual length
- public identifiers (deviceId/sessionId) **only if already known in that stage**
- opaque `traceId` / `requestId`
- responder/peer user id only if already available to caller context

### 0.3 Stable Wire Contracts
Once shipped, canonical codes MUST NOT be repurposed. New codes require explicit registry update.

### 0.4 Uniform Surfaces Across Platforms
Rust core, Node backend, and clients MUST map internal failures into canonical codes consistently.
Platform-specific errors MUST be wrapped into nearest canonical code.

---

## 1. Canonical Code Format (Normative)

All crypto-critical codes are of the form:

- `C6P.<DOMAIN>.<NAME>`

Where `<DOMAIN>` is one of (non-exhaustive; see registry):
- `ENC`, `WIRE`, `KEYS`, `KDF`, `HANDSHAKE`, `RATCHET`, `AAD`, `AEAD`, `STORE`, `RNG`, `INVAR`

Examples:
- `C6P.ENC.INVALID_B64URL`
- `C6P.WIRE.INVALID_ENVELOPE`
- `C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED`
- `C6P.KEYS.KEY_ALREADY_CONSUMED`

**Hard rule:** No endpoint MAY return a non-canonical “string code” for crypto-critical failures.

---

## 2. Severity & Retry Policy (Normative)

Severity values are those from `docs/crypto/c6p-crypto-error-codes.md`:
- `INFO`, `WARN`, `ERROR`, `SECURITY`

Retry policy values (canonical):
- `NO_RETRY`
- `RETRY_SAFE`
- `RETRY_AFTER_ROTATION`
- `RETRY_AFTER_SYNC`

**Hard rule:** Every error response MUST include `errorCode`.  
**Strong recommendation:** Include `severity` and `retry` in all surfaces (server + client).

---

## 3. Error Surfaces (Normative)

### 3.1 HTTP JSON (server)
For handshake-related endpoints, server responses MUST be one of:

#### Success
```json
{ "ok": true, "...": "..." }
```

```json
{
  "ok": false,
  "errorCode": "C6P.WIRE.INVALID_ENVELOPE",
  "severity": "WARN",
  "retry": "NO_RETRY",
  "message": "Invalid request payload.",
  "traceId": "t-7c9e..."
}
```

Rules:

errorCode is REQUIRED.

traceId is REQUIRED on backend responses (observability).

message is OPTIONAL and MUST be human-safe and non-oracular.

NEVER return stack traces.

3.2 WebSocket / Push (server)
If WS delivery includes an error event, it MUST be shaped as:

```json
{
  "type": "c6p.error.v1",
  "errorCode": "C6P.HANDSHAKE.STATE_VIOLATION",
  "severity": "WARN",
  "retry": "NO_RETRY",
  "sessionId": "…", 
  "traceId": "t-…"
}

```


Rules:

MUST include errorCode and traceId.

SHOULD include sessionId if already known/authorized in that delivery context.

MUST NOT include secrets.

3.3 Local (Rust core / client)
Clients MUST expose a structured error object with:

errorCode (canonical)

optional structured fields (field, expectedLength, actualLength, stage, module)

optional “cause string” only in debug/test builds behind explicit flags

4. HTTP Status Mapping (Normative)
Servers SHOULD use these status conventions (non-secrets, fail-closed):

400 — malformed JSON, missing required field, invalid encoding, wrong length

401/403 — auth/access mismatch (non-crypto domain; still MUST avoid oracles)

404 — referenced session not found only if caller is authorized to know it exists (see §9)

409 — state conflict / idempotency mismatch / concurrency conflict (safe)

422 — semantically invalid but well-formed (e.g., invalid signature/KC) (optional; many deployments use 400/409 only to avoid oracles)

429 — rate limited

500 — internal invariant / unexpected failure (fail-closed)

Anti-oracle guidance (normative): For cryptographic validation failures (signature/KC/transcript mismatch), servers SHOULD prefer 400 or 409 with a generic message, never revealing which check failed. The canonical errorCode is sufficient for internal observability.

5. Handshake Endpoint Error Mapping (Normative)
This section defines mapping for IslandAccord v1 endpoints. The listed codes MUST come from the canonical registry.

5.1 GET /v1/prekeys/status
Failure classes:

Invalid auth/session context: (non-crypto; map to your API auth errors without revealing anything sensitive)

Store read errors:

C6P.STORE.READ_FAILED (ERROR, RETRY_SAFE)

Internal invariant:

C6P.INVAR.ASSERTION_FAILED (ERROR, NO_RETRY)

5.2 GET /v1/prekeys/bundle?device_id=<hex>
Typical failures:

Bad encoding / non-canonical:

C6P.ENC.INVALID_HEX

C6P.ENC.NON_CANONICAL_HEX

C6P.ENC.LENGTH_MISMATCH

Unknown / invalid device id format:

C6P.WIRE.INVALID_ENVELOPE

Prekeys not found / not available:

C6P.KEYS.KEY_NOT_FOUND (e.g., missing SPK)

OTP reservation conflicts (atomic reservation invariant):

C6P.KEYS.KEY_ALREADY_CONSUMED (if OTP appears consumed/unavailable when expected available)

C6P.HANDSHAKE.STATE_VIOLATION (if reservation pipeline is violated)

Store failures:

C6P.STORE.READ_FAILED, C6P.STORE.WRITE_FAILED

Important semantics:

The server MUST NOT reveal whether a specific OTP exists beyond what bundle returns.

If OTP cannot be reserved, the server MAY return a bundle without OTP (preferred) rather than erroring, provided SPK/IK are present and policy allows.

5.3 POST /v1/prekeys/upload
Typical failures:

Bad base64url / wrong lengths:

C6P.ENC.INVALID_B64URL

C6P.ENC.LENGTH_MISMATCH

Invalid public keys:

C6P.KEYS.INVALID_PUBLIC_KEY

Invalid SPK signature:

C6P.HANDSHAKE.SPK_SIGNATURE_INVALID or C6P.KEYS.INVALID_SIGNATURE (choose the canonical one your registry uses; MUST be consistent repo-wide)

Duplicate key IDs / inconsistent re-uploads:

C6P.KEYS.KEY_STATE_INVALID (if stored bytes mismatch)

C6P.HANDSHAKE.STATE_VIOLATION (if upload violates immutability rules)

Store failure:

C6P.STORE.WRITE_FAILED

Anti-oracle rule: Server MUST NOT confirm “signature was correct” in a way that helps attackers probe; it may only accept or reject with canonical code.

5.4 POST /v1/dm/sessions/open (offer store + delivery)
This endpoint is state/authorization heavy. Codes below MUST be used consistently with:

island-accord-wire.md validation

island-accord-state-machine.md invariants

Failure classes:

(A) Structural / encoding failures (fail early)
C6P.ENC.MISSING_FIELD

C6P.ENC.INVALID_HEX

C6P.ENC.NON_CANONICAL_HEX

C6P.ENC.INVALID_B64URL

C6P.ENC.LENGTH_MISMATCH

C6P.WIRE.INVALID_ENVELOPE

C6P.WIRE.MESSAGE_TYPE_INVALID (if wire includes message type)

C6P.WIRE.COUNTER_INVALID (if any counters included; generally not in offer)

(B) Binding / routing invariants (authorization without leaks)
C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH (initiatorDeviceId ≠ auth device, responderDevice mismatch vs peer mapping, etc.)

C6P.WIRE.SESSION_ID_MISMATCH (if session id doesn’t match expected context)

(C) Replay / idempotency conflicts
C6P.HANDSHAKE.REPLAYED_OFFER (same tuple already exists; offer differs)

C6P.HANDSHAKE.STATE_VIOLATION (illegal transition / duplicate state)

C6P.RATCHET.REPLAY_DETECTED (reserved for message layer; do not use for offer unless your registry mandates)

(D) OTP pipeline failures (server scarcity authority)
C6P.HANDSHAKE.OTP_MISSING (offer references OTP id that server cannot validate as reserved for this flow)

C6P.KEYS.KEY_ALREADY_CONSUMED (OTP already moved to PENDING/CONSUMED by another session)

C6P.KEYS.KEY_NOT_FOUND (OTP id unknown for that device)

C6P.HANDSHAKE.STATE_VIOLATION (reservation TTL expired / invalid status transitions)

(E) Store failures
C6P.STORE.WRITE_FAILED

C6P.STORE.ATOMICITY_VIOLATION

Hard rule: Server MUST NOT verify crypto correctness as a security boundary here (transcript hash, KC1, signature). Server may validate format/length only, and enforce state/OTP/authorization.

5.5 POST /v1/dm/handshake/accept (store accept + consume OTP)
Failure classes:

Structural/encoding:

C6P.ENC.MISSING_FIELD

C6P.ENC.INVALID_HEX

C6P.ENC.INVALID_B64URL

C6P.ENC.LENGTH_MISMATCH

C6P.WIRE.INVALID_ENVELOPE

Binding/authorization:

C6P.HANDSHAKE.DEVICE_BINDING_MISMATCH (responderDeviceId ≠ auth device)

State conflicts:

C6P.HANDSHAKE.STATE_VIOLATION (session not PENDING / expired / terminal)

C6P.STORE.ATOMICITY_VIOLATION (partial write detected)

OTP consumption failures:

C6P.KEYS.KEY_ALREADY_CONSUMED (OTP not in expected PENDING_CONSUMPTION)

C6P.KEYS.KEY_STATE_INVALID (stored OTP row corrupted / inconsistent)

Store failures:

C6P.STORE.WRITE_FAILED

Idempotency rule (normative):
If session already ACTIVE:

accept is idempotent ONLY if kc2 matches stored value exactly (byte-for-byte).

if kc2 differs, server MUST reject with C6P.HANDSHAKE.STATE_VIOLATION (or your canonical “state conflict” code if registry defines one).

6. Client-Side Handshake Validation Errors (Normative)
Clients MUST use canonical codes for cryptographic failures even if they happen locally.

6.1 Bundle validation (initiator)
SPK signature invalid:

C6P.HANDSHAKE.SPK_SIGNATURE_INVALID (SECURITY, NO_RETRY)

Key parse failure:

C6P.KEYS.INVALID_PUBLIC_KEY

Encoding/length issues:

C6P.ENC.INVALID_B64URL, C6P.ENC.LENGTH_MISMATCH

6.2 Offer processing (responder)
Transcript mismatch:

C6P.HANDSHAKE.TRANSCRIPT_MISMATCH (SECURITY, NO_RETRY)

Initiator signature invalid:

C6P.HANDSHAKE.INITIATOR_SIGNATURE_INVALID (SECURITY, NO_RETRY)

KC1 mismatch:

C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED (SECURITY, NO_RETRY)

Missing OTP private when offer references OTP id:

C6P.KEYS.KEY_NOT_FOUND (ERROR, RETRY_AFTER_SYNC) or C6P.HANDSHAKE.OTP_MISSING depending on your registry meaning
(must be consistent across repos; preferred: C6P.KEYS.KEY_NOT_FOUND for local store missing)

6.3 Accept processing (initiator)
KC2 mismatch:

C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED (SECURITY, NO_RETRY)

Hard rule: Client MUST NOT mark a session cryptographically ACTIVE unless KC passes.

7. Non-Crypto API Errors (Guidance)
This document primarily covers crypto-critical / handshake-critical failures.
For API/auth/business errors, you MAY use a separate namespace (e.g., C6P.API.*) only if:

those codes are documented and stable,

they do not overlap/conflict with crypto registry,

they do not create security oracles.

Examples (non-normative):

C6P.API.UNAUTHORIZED

C6P.API.FORBIDDEN

C6P.API.RATE_LIMITED

If you do not maintain a separate API registry, then:

express non-crypto failures via HTTP status + generic message,

still include a canonical code from the crypto registry when the failure is crypto/handshake related.

8. Privacy & Anti-Oracle Rules (Normative)
8.1 Do not reveal cryptographic correctness
Servers MUST NOT expose:

“signature invalid” vs “kc mismatch” vs “transcript mismatch” distinctions to attackers,
unless the caller is already authenticated and authorized and you accept the risk.

Recommended server practice:

Return a generic message always.

Still emit canonical errorCode for internal telemetry; do not vary timing/wording.

8.2 Not-found semantics (important)
If a caller is not authorized to know whether a session exists:

avoid returning 404 that confirms existence,

prefer 400/403/409 with generic response.

8.3 Logging policy
All handshake errors MUST log structured fields:

errorCode, severity, retry

module, stage

traceId

sessionId / deviceId only when already authorized/known

no blobs (no raw offer/accept payloads), no keys

9. Canonical Error Response Examples (Copy/Paste)
9.1 Invalid encoding (bundle request)
```json

{
  "ok": false,
  "errorCode": "C6P.ENC.INVALID_HEX",
  "severity": "WARN",
  "retry": "NO_RETRY",
  "message": "Invalid device_id format.",
  "traceId": "t-1a2b3c"
}

```


9.2 OTP not reserved / pipeline violation (open)
```json

{
  "ok": false,
  "errorCode": "C6P.HANDSHAKE.OTP_MISSING",
  "severity": "WARN",
  "retry": "RETRY_AFTER_SYNC",
  "message": "Handshake offer rejected.",
  "traceId": "t-88fd0a"
}

```


9.3 State conflict (accept called twice with different kc2)
```json

{
  "ok": false,
  "errorCode": "C6P.HANDSHAKE.STATE_VIOLATION",
  "severity": "WARN",
  "retry": "NO_RETRY",
  "message": "Handshake state conflict.",
  "traceId": "t-0c0ffee"
}

```


9.4 Store failure (atomicity)
```json

{
  "ok": false,
  "errorCode": "C6P.STORE.ATOMICITY_VIOLATION",
  "severity": "ERROR",
  "retry": "NO_RETRY",
  "message": "Internal storage invariant failure.",
  "traceId": "t-deadbeef"
}

```


10. Required Test Coverage (Normative)
This repo MUST include tests that assert:

10.1 Wire validation → canonical codes
uppercase hex rejected → C6P.ENC.NON_CANONICAL_HEX

wrong length IDs → C6P.ENC.LENGTH_MISMATCH

base64url padding present → C6P.ENC.INVALID_B64URL

missing required fields → C6P.ENC.MISSING_FIELD

unknown enums (suite_id, etc.) → appropriate C6P.WIRE.* or C6P.AEAD.UNSUPPORTED_SUITE depending on layer

10.2 State machine → canonical codes
duplicate open with different offer → C6P.HANDSHAKE.REPLAYED_OFFER or C6P.HANDSHAKE.STATE_VIOLATION (pick one and lock it)

accept in non-PENDING state → C6P.HANDSHAKE.STATE_VIOLATION

OTP reservation violations:

open references non-reserved OTP → C6P.HANDSHAKE.OTP_MISSING

accept when OTP not in PENDING_CONSUMPTION → C6P.KEYS.KEY_ALREADY_CONSUMED or C6P.HANDSHAKE.STATE_VIOLATION (choose and lock)

10.3 No secret leakage
Ensure logs do not contain:

b64 key fields

offer/accept raw blobs

stack traces

Ensure errors do not include oracles beyond canonical errorCode.

11. Cross-Document Consistency Checklist (Normative)
Before release, auditors MUST be able to verify:

 All handshake-related crypto errors map into codes defined in docs/crypto/c6p-crypto-error-codes.md.

 ID lengths and encodings match docs/crypto/c6p-crypto-registry.md.

 Server invariants and transition rejection match docs/handshake/island-accord-state-machine.md.

 Wire strictness matches docs/handshake/island-accord-wire.md.

 Crypto failures (signature/KC/transcript) are fail-closed per docs/handshake/island-accord-crypto.md.

 Error surfaces do not leak secrets and do not create attacker oracles.
