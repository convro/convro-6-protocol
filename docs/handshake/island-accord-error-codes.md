**IslandAccord v1 — Error Codes (Canonical)**  
Status: **PRODUCTION / NORMATIVE**  
Applies to: **/v1/prekeys/**, **/v1/dm/sessions/open**, **/v1/dm/handshake/accept**  
Audience: auditors, backend (Node), client (Swift/Rust), QA.

> Cel: stabilne, niezmienne kody błędów + deterministyczne zachowanie klienta, **bez wycieków metadanych**.

---

## 1) Canonical Error Envelope (JSON)

Wszystkie endpointy IslandAccord **MUST** zwracać błędy w jednym, spójnym formacie:


{
  "ok": false,
  "code": "C6P_...",
  "message": "Safe short message",
  "retryable": false
}
1.1 Zasady (normatywne)
code MUST być stabilny (nigdy nie zmieniamy znaczenia).

message MUST NOT ujawniać: istnienia peer’a, szczegółów DB, fingerprintów kluczy, ID OTP/SPK, stacktrace.

retryable to tylko hint dla klienta.

Opcjonalnie (ale jeśli dodasz — to WSZĘDZIE): requestId jako losowy token do korelacji logów.
NIE DODAJEMY details w produkcji (nie ma „optional extras”).

2) Canonical Wire Constraints (dla walidacji)
To jest podstawą do C6P_WIRE_*.

2.1 Długości i formaty
deviceId: 16 hex (8 bytes)

sessionId: 8 hex (4 bytes)

keyId (SPK/OTP): 16 hex (8 bytes)

X25519 pub: 32 bytes encoded as base64url (no padding)

Ed25519 pub: 32 bytes base64url (no padding)

Ed25519 sig: 64 bytes base64url (no padding)

2.2 Canonicalizacja
hex: lowercase only, bez spacji, bez prefixów typu 0x.

base64url: tylko A–Z a–z 0–9 - _, bez =.

3) Error Code Taxonomy
Prefixy:

C6P_SCHEMA_* — JSON/typy/pola

C6P_WIRE_* — hex/b64/length/canonicalization

C6P_AUTH_* — token, device binding

C6P_RATE_* — limity

C6P_STATE_* — state machine, idempotency, konflikt

C6P_PREKEY_* — SPK/OTP lifecycle i binding

C6P_INTERNAL_* — awarie serwera (bez wycieków)

4) Canonical Error Codes (Production)
Poniżej są jedynymi dopuszczalnymi kodami w IslandAccord v1.

4.1 Schema (C6P_SCHEMA_*)
C6P_SCHEMA_INVALID_JSON
Invalid JSON body (parse fail).

C6P_SCHEMA_MISSING_FIELD
Required field missing.

C6P_SCHEMA_INVALID_TYPE
Field has wrong type.

C6P_SCHEMA_UNKNOWN_FIELD
Unknown field present (strict schema; fail-closed).

4.2 Wire / Validation (C6P_WIRE_*)
C6P_WIRE_INVALID_VERSION
offer.version not supported.

C6P_WIRE_INVALID_HEX
Non-hex characters.

C6P_WIRE_INVALID_HEX_LEN
Wrong hex length (deviceId/sessionId/keyId).

C6P_WIRE_INVALID_B64URL
Invalid base64url string.

C6P_WIRE_INVALID_KEY_LENGTH
Decoded key has wrong length (e.g., X25519 != 32 bytes).

C6P_WIRE_CANONICALIZATION
Uppercase hex, whitespace, prefix 0x, padded base64, etc.

4.3 Auth / Binding (C6P_AUTH_*)
C6P_AUTH_REQUIRED
Missing/invalid auth token.

C6P_AUTH_FORBIDDEN
Auth OK, action forbidden by policy.

C6P_AUTH_DEVICE_MISMATCH
Auth deviceId != required deviceId for this action.
(open: initiatorDeviceId, accept: responderDeviceId)

C6P_AUTH_NOT_RESPONDER
accept called by non-responder.

4.4 Rate limiting (C6P_RATE_*)
C6P_RATE_LIMIT
Generic throttle.

C6P_RATE_TOO_MANY_PENDING
Too many PENDING sessions for same initiator/pair.

C6P_RATE_TOO_MANY_BUNDLE_FETCH
Bundle fetch abuse / OTP reservation pressure.

4.5 State machine / Idempotency (C6P_STATE_*)
C6P_STATE_NOT_FOUND
sessionId unknown (accept).

C6P_STATE_EXPIRED
Session TTL exceeded (PENDING expired).

C6P_STATE_INVALID_TRANSITION
Action not allowed in current state.

C6P_STATE_CONFLICT
Same tuple/session but payload differs (immutability violation).
Treat as security event.

C6P_STATE_ALREADY_ACTIVE
Repeated open/accept on already ACTIVE session (idempotent success path).

C6P_STATE_ALREADY_FINAL
Repeated accept/reject/cancel after finalization.

4.6 Prekeys (C6P_PREKEY_*)
C6P_PREKEY_SPK_MISMATCH
offer.usedSignedPrekeyPublicKeyX25519 != current SPK pub for responderDeviceId.
(SPK rotated, stale bundle, or attack attempt)

C6P_PREKEY_SPK_BINDING
SPK does not belong to that responder device/user (ownership mismatch).

C6P_PREKEY_OTP_INVALID
Offer references otpId not owned by responderDeviceId.

C6P_PREKEY_OTP_EXPIRED
Reserved OTP TTL expired before accept.

C6P_PREKEY_OTP_STATE
OTP in unexpected state (not RESERVED / not PENDING_CONSUMPTION).

C6P_PREKEY_OTP_ALREADY_USED
OTP already consumed.

C6P_PREKEY_OTP_REQUIRED_MISSING
Offer references OTP but server cannot satisfy it (reservation missing).

4.7 Peer / Routing (C6P_PEER_*)
C6P_PEER_INVALID
peerUserId == self OR invalid peer selector.

C6P_PEER_DEVICE_UNKNOWN
responderDeviceId not found within peer ownership scope.

C6P_PEER_NOT_REACHABLE
blocked/disabled/policy denies.

Privacy rule: dla „nieznanych” peerów preferuj C6P_PEER_DEVICE_UNKNOWN / C6P_PEER_NOT_REACHABLE
zamiast komunikatów potwierdzających istnienie.

4.8 Internal (C6P_INTERNAL_*)
C6P_INTERNAL
Unexpected server failure.

C6P_INTERNAL_DB
DB unavailable / transaction failed.

C6P_INTERNAL_TIMEOUT
Upstream timeout.

5) Canonical Client Actions (deterministyczne)
Klient (Swift/Rust) MUST mapować kody do akcji:

5.1 “Fix request / do not retry”
C6P_SCHEMA_*, C6P_WIRE_*
→ Bug w kliencie / nie retry.

5.2 “Re-auth”
C6P_AUTH_REQUIRED
→ re-login/refresh token i dopiero retry.

5.3 “Stop (policy/security)”
C6P_AUTH_FORBIDDEN, C6P_AUTH_DEVICE_MISMATCH, C6P_AUTH_NOT_RESPONDER
→ nie retry; pokaż błąd bezpieczeństwa.

5.4 “Restart handshake from bundle fetch”
C6P_PREKEY_* oraz C6P_STATE_EXPIRED
→ fetch bundle ponownie, wygeneruj nowy offer, otwórz nową sesję.

5.5 “Treat as suspicious”
C6P_STATE_CONFLICT
→ stop + log client-side safety event; UI: “Session conflict”.

5.6 “Backoff & retry”
C6P_RATE_*, C6P_INTERNAL_*
→ exponential backoff + jitter; respektuj Retry-After jeśli występuje.

6) Idempotency & Immutability Rules (server MUST)
6.1 open()
Jeśli istnieje identyczna sesja (ten sam initiator/responder/sessionId) i offer bytes są identyczne
→ return success (idempotent), ok: true.

Jeśli tuple pasuje, ale payload różny
→ C6P_STATE_CONFLICT.

6.2 accept()
Jeśli już ACTIVE i KC2 identyczny
→ return success (idempotent).

Jeśli KC2 różny
→ C6P_STATE_CONFLICT.

7) Minimal Safe Messages (server-side)
Serwer może używać krótkich, neutralnych komunikatów:

C6P_SCHEMA_INVALID_JSON: "Invalid request body."

C6P_WIRE_INVALID_HEX_LEN: "Invalid identifier format."

C6P_AUTH_DEVICE_MISMATCH: "Device not authorized for this action."

C6P_PREKEY_SPK_MISMATCH: "Prekey set changed. Retry handshake."

C6P_STATE_CONFLICT: "Request conflicts with existing session state."

MUST NOT: “OTP not found”, “user does not exist”, “wrong device”, “spk fingerprint …”.

8) Example Error Payloads
8.1 Device mismatch
json
Skopiuj kod
{
  "ok": false,
  "code": "C6P_AUTH_DEVICE_MISMATCH",
  "message": "Device not authorized for this action.",
  "retryable": false
}
8.2 SPK mismatch (stale bundle)
json
Skopiuj kod
{
  "ok": false,
  "code": "C6P_PREKEY_SPK_MISMATCH",
  "message": "Prekey set changed. Retry handshake.",
  "retryable": false
}
8.3 Rate limit
json
Skopiuj kod
{
  "ok": false,
  "code": "C6P_RATE_LIMIT",
  "message": "Try again later.",
  "retryable": true
}
