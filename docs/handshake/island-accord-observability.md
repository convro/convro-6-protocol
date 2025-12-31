# docs/handshake/island-accord-observability.md
**IslandAccord v1 — Observability & Audit Telemetry (Canonical)**  
Status: **PRODUCTION / NORMATIVE**  
Scope: Node backend + Rust core + (optional) Swift client logging hooks  
Goal: audytowalność, SLO, forensics — **bez wycieków metadanych**.

---

## 0) Design Principles (MUST)

1) **No secret material in logs.**  
   Logs/metrics/traces **MUST NOT** contain: private keys, shared secrets, chain/root keys, plaintext, message keys, nonces, transcript hashes, or raw public keys.

2) **Metadata-minimized.**  
   Prefer *event types + coarse counts* over identifiers. Jeśli identyfikator jest konieczny do korelacji, używamy **opaque correlation ids**.

3) **Stable semantics.**  
   Nazwy eventów, pól i kodów błędów są stabilne (to też kontrakt audytowy).

4) **Correlation without deanonymization.**  
   Korelacja między usługami i etapami handshake odbywa się przez:
   - `requestId` (per HTTP request)
   - `flowId` (per IslandAccord attempt)
   - `sessionTag` (opaque, HMAC-based tag — nie sessionId)

5) **Fail-closed diagnostics.**  
   Debug-only detale istnieją, ale **nie w produkcji**.

---

## 1) Identifiers & Correlation (Canonical)

### 1.1 requestId (MUST)
- Generowany per request na backendzie (uuidv4 lub 128-bit random).  
- Zwracany do klienta tylko w headerze lub polu w JSON (jeśli wspólnie uzgodnione).  
- **MUST** być logowany w każdym evencie dot. requestu.

**Header (recommended):**
- Request in: `X-Request-Id` (accept if provided; otherwise generate)
- Response out: `X-Request-Id`

### 1.2 flowId (MUST)
- Generowany przy `open()` (pierwszy request inicjatora) i przenoszony w ramach state machine.  
- **Nie jest** sessionId.  
- 128-bit random, base64url.

### 1.3 sessionTag (MUST)
Zamiast logowania `sessionId` wprost, logujemy `sessionTag`:

- `sessionTag = base64url( HMAC-SHA256(server_observability_key, "IA1" || sessionId || responderDeviceId || initiatorDeviceId) )[0..16]`
- Truncation: 16 bytes output (128-bit tag).
- `server_observability_key` **MUST** być rotowany i trzymany tylko po stronie serwera.
- Dzięki temu audytor ma korelację zdarzeń handshake, ale **bez ujawnienia** realnych ID.

> Jeśli audyt wymaga “bridge” do realnego sessionId — robimy to **tylko** w offline forensics, w kontrolowanym narzędziu, nie w runtime logach.

---

## 2) Event Model (Structured Logs)

### 2.1 Log format (MUST)
JSON structured logs.

Minimalny szkielet:


{
  "ts": "2025-12-31T21:37:12.123Z",
  "level": "INFO",
  "service": "convro-backend",
  "component": "island-accord",
  "event": "IA_OPEN_ACCEPTED",
  "requestId": "…",
  "flowId": "…",
  "sessionTag": "…",
  "result": "ok",
  "code": null,
  "latencyMs": 42
}

2.2 Fields (Canonical)

ts (RFC3339 UTC) MUST

level (DEBUG|INFO|WARN|ERROR) MUST

service MUST

component = "island-accord" MUST

event (lista poniżej) MUST

requestId MUST

flowId MUST (od momentu open)

sessionTag MUST (od momentu posiadania sessionId na backendzie)

result = ok|fail MUST

code = error code z cs/handshake/island-accord-error-codes.md (gdy fail)

latencyMs (int) SHOULD

route (np. /v1/dm/sessions/open) SHOULD

actor = initiator|responder|server SHOULD

peerClass = dm SHOULD (pod przyszłe rozszerzenia)

2.3 MUST NOT fields

IP, UA, geolokacja

peerUserId/initiatorUserId/responderUserId wprost (jeśli wymagane — patrz §5)

deviceId wprost

sessionId wprost

otpId/spkId wprost

public keys / sig / transcriptHash

payload snippets

3) Canonical Event Catalog
3.1 Prekeys

IA_PREKEYS_STATUS_OK

IA_PREKEYS_UPLOAD_OK

IA_PREKEYS_UPLOAD_FAIL (code)

IA_BUNDLE_FETCH_OK

IA_BUNDLE_FETCH_FAIL (code)

IA_OTP_RESERVED (tylko fakt rezerwacji; bez otpId)

IA_OTP_RESERVE_FAIL (code)

3.2 Open (initiator)

IA_OPEN_REQUESTED

IA_OPEN_VALIDATED

IA_OPEN_ACCEPTED (PENDING created / idempotent success)

IA_OPEN_FAIL (code)

IA_OPEN_IDEMPOTENT_HIT

3.3 Accept (responder)

IA_ACCEPT_REQUESTED

IA_ACCEPT_VALIDATED

IA_ACCEPT_COMMITTED (ACTIVE)

IA_ACCEPT_FAIL (code)

IA_ACCEPT_IDEMPOTENT_HIT

3.4 State transitions (server authoritative)

IA_STATE_PENDING_CREATED

IA_STATE_ACTIVE

IA_STATE_EXPIRED

IA_STATE_REJECTED (jeśli istnieje)

IA_STATE_CONFLICT (MUST map to C6P_STATE_CONFLICT)

3.5 Security signals (MUST log as WARN)

IA_SIG_SUSPICIOUS_REPLAY (duplicate offer but different payload)

IA_SIG_DEVICE_MISMATCH

IA_SIG_SPK_MISMATCH (stale bundle / rotation)

IA_SIG_OTP_ANOMALY (invalid OTP state)

4) Metrics (Prometheus-style)
4.1 Counters (MUST)

ia_open_total{result="ok|fail",code="…"}

ia_accept_total{result="ok|fail",code="…"}

ia_bundle_fetch_total{result="ok|fail",code="…"}

ia_prekeys_upload_total{result="ok|fail",code="…"}

ia_state_transition_total{to="PENDING|ACTIVE|EXPIRED|REJECTED|CONFLICT"}

4.2 Latency histograms (MUST)

ia_open_latency_ms_bucket

ia_accept_latency_ms_bucket

ia_bundle_fetch_latency_ms_bucket

Buckets: 5,10,25,50,100,250,500,1000,2500,5000ms.

4.3 Gauges (SHOULD)

ia_pending_sessions (current PENDING count)

ia_otp_available (from status; coarse)

ia_otp_reservation_pressure (ratio)

5) Minimal Metadata Strategy (User/Device exposure)

Audytorzy często chcą “czy możemy zdiagnozować komu nie działa”. Robimy to tak:

5.1 Pseudonymous actorTag (OPTIONAL, controlled)

Jeśli musisz przypisać zdarzenie do konta w runtime, nie logujesz userId — logujesz:

actorTag = base64url( HMAC-SHA256(server_observability_key_2, "ACT" || userId) )[0..16]

deviceTag = base64url( HMAC-SHA256(server_observability_key_2, "DEV" || deviceId) )[0..16]

MUST: inne klucze niż sessionTag key, rotowane.

5.2 When allowed

Tylko na środowiskach production z polityką privacy approved.

W logach INFO tylko actorTag; pełne mapowanie offline.

5.3 When forbidden

W trybie high-privacy: w ogóle bez actorTag, tylko flowId/sessionTag.

6) Tracing (OpenTelemetry)
6.1 Spans (SHOULD)

islandaccord.open

islandaccord.accept

islandaccord.bundle_fetch

islandaccord.prekeys_upload

6.2 Span attributes (MUST NOT leak)

Allowed:

flowId, sessionTag, result, code, route
Forbidden:

userId/deviceId/sessionId raw

keys, payloads, OTP/SPK ids

6.3 Sampling

Default: 1–5% traces

100% sampling for WARN/ERROR flows (security signals) but still sanitized.

7) SLO / Alerting (Auditor-ready)
7.1 SLOs (recommended)

open success rate ≥ 99.5% (rolling 7d)

accept success rate ≥ 99.5%

p95 open latency ≤ 250ms

p95 accept latency ≤ 250ms

bundle fetch p95 ≤ 200ms

7.2 Alerts (MUST)

Spike C6P_STATE_CONFLICT > baseline

Spike C6P_PREKEY_SPK_MISMATCH (rotation storms / cache issues / abuse)

Spike C6P_RATE_LIMIT

Drop in ia_otp_available below threshold

8) Audit Logs vs Operational Logs
8.1 Operational logs (default)

Short retention (7–30d)

Sanitized as per this document

8.2 Audit logs (optional, stricter control)

Separate sink (append-only)

Includes: event, requestId, flowId, sessionTag, code, timestamp

No actorTag unless explicitly allowed

Retention 90–180d (policy)

9) Client-side Observability (Swift/Rust)
9.1 Client events (SHOULD)

Client może logować lokalnie:

IA_CLIENT_PHASE_CHANGE (starting → ensuringPrekeys → fetchingBundle → open → pending → active)

IA_CLIENT_RETRY_SCHEDULED (backoff class)

IA_CLIENT_ERROR (mapped code)

MUST NOT: plaintext, keys, raw identifiers.
Client logs mogą zawierać: flowId (jeśli znane), requestId z odpowiedzi.

9.2 Crash / bug reports

Sanitized payloads only

No raw deviceId/sessionId

10) Operational Playbooks (Minimal)
10.1 “Open failing”

Check:

ia_open_total{result="fail"} by code

If C6P_PREKEY_*: look at ia_bundle_fetch_total, SPK rotation frequency

If C6P_AUTH_*: token refresh failures upstream

If C6P_RATE_*: abuse or too strict limits

10.2 “Accept failing”

Check:

C6P_STATE_NOT_FOUND / C6P_STATE_EXPIRED: delivery delays, TTL too low

C6P_PREKEY_OTP_*: reservation/consumption state bugs

10.3 “Conflict detected”

Treat as security signal

Increase sampling

Trigger incident workflow

11) Compliance Checklist (MUST PASS)

 All IslandAccord endpoints return canonical error envelope.

 All logs structured JSON + sanitized.

 sessionTag implemented and used instead of sessionId.

 No raw keys / ids / OTP ids in logs.

 Metrics present for open/accept/bundle/status/upload.

 Alerts defined for conflict, spk mismatch spikes, OTP depletion.

 Tracing sanitized; sampling configured.
