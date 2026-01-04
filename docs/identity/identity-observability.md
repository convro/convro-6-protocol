# C6P Identity Observability (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Identity-related telemetry, metrics, logging, and alerting
**Aligned with:** `docs/crypto/c6p-error-codes.md`, `docs/handshake/island-accord-observability.md`
**Applies to:** Client and server implementations

---

## 0. Principles (Non-Negotiable)

1. **No secret leakage**: Logs MUST NOT include private keys, DH outputs, or session keys
2. **Privacy-preserving**: Hash or aggregate device identifiers where appropriate
3. **Structured events**: All telemetry uses canonical schema
4. **Fail-closed observability**: Errors detectable without exposing crypto correctness

---

## 1. Canonical Event Naming (Normative)

Identity events use namespace: `c6p.identity.v1.*`

Examples:
- `c6p.identity.v1.device.registered`
- `c6p.identity.v1.rotation.initiated`
- `c6p.identity.v1.prekey.uploaded`
- `c6p.identity.v1.error`

**Hard rule:** Event names MUST NOT change once used in production.

---

## 2. Structured Event Envelope (Normative)

### 2.1 Envelope Fields

```json
{
  "event": "c6p.identity.v1.device.registered",
  "ts": "2026-01-04T14:30:00.123Z",
  "build": "prod",
  "component": "server",
  "module": "identity/registration",
  "stage": "validate",
  "traceId": "t-abc123",
  "requestId": "r-xyz789",
  "severity": "INFO"
}
```

**Required fields:**
- `event` (string)
- `ts` (RFC3339 timestamp)
- `build` (prod/staging/test)
- `component` (server/client)
- `module` (path-like identifier)
- `stage` (decode/validate/store/etc.)
- `traceId` (server MUST include; client SHOULD include)
- `severity` (INFO/WARN/ERROR/SECURITY)

---

## 3. Server Events (Normative)

### 3.1 Device Registration

**Event:** `c6p.identity.v1.device.registered`

```json
{
  "event": "c6p.identity.v1.device.registered",
  "ts": "2026-01-04T14:30:00Z",
  "build": "prod",
  "component": "server",
  "module": "identity/registration",
  "stage": "store",
  "traceId": "t-abc123",
  "severity": "INFO",
  "context": {
    "device_id_hash": "<SHA-256 hash>",
    "user_id": 12345,
    "rotation_version": 1,
    "platform": "iOS 17.2",
    "app_version": "1.0.0"
  }
}
```

**Hard rule:** Use `device_id_hash` (not plaintext `device_id`) for long-term retention.

### 3.2 Key Rotation

**Event:** `c6p.identity.v1.rotation.initiated`

```json
{
  "event": "c6p.identity.v1.rotation.initiated",
  "ts": "2026-01-04T14:35:00Z",
  "severity": "INFO",
  "context": {
    "device_id_hash": "<hash>",
    "old_rotation_version": 1,
    "new_rotation_version": 2,
    "migration_window_days": 7,
    "rotation_expires_at": "2026-01-11T14:35:00Z"
  }
}
```

**Event:** `c6p.identity.v1.rotation.completed`

```json
{
  "event": "c6p.identity.v1.rotation.completed",
  "ts": "2026-01-11T14:35:00Z",
  "severity": "INFO",
  "context": {
    "device_id_hash": "<hash>",
    "rotation_version": 2,
    "old_identity_deprecated": true
  }
}
```

### 3.3 Prekey Upload

**Event:** `c6p.identity.v1.prekey.uploaded`

```json
{
  "event": "c6p.identity.v1.prekey.uploaded",
  "ts": "2026-01-04T14:40:00Z",
  "severity": "INFO",
  "context": {
    "device_id_hash": "<hash>",
    "spk_uploaded": true,
    "otp_count": 100,
    "total_otp_available": 187
  }
}
```

**Hard rule:** MUST NOT log prekey public keys or signatures (log counts/IDs only).

### 3.4 Identity Revocation

**Event:** `c6p.identity.v1.revoked`

```json
{
  "event": "c6p.identity.v1.revoked",
  "ts": "2026-01-04T14:45:00Z",
  "severity": "WARN",
  "context": {
    "device_id_hash": "<hash>",
    "reason": "device_lost",
    "sessions_invalidated": 15
  }
}
```

---

## 4. Client Events (Recommended)

### 4.1 Identity Generation

**Event:** `c6p.identity.v1.client.generated`

```json
{
  "event": "c6p.identity.v1.client.generated",
  "ts": "2026-01-04T14:50:00Z",
  "build": "prod",
  "component": "client",
  "module": "identity/device-identity",
  "stage": "generate",
  "severity": "INFO",
  "context": {
    "device_id": "0123456789abcdef...",
    "platform": "iOS 17.2",
    "first_install": true
  }
}
```

### 4.2 Identity Loaded

**Event:** `c6p.identity.v1.client.loaded`

```json
{
  "event": "c6p.identity.v1.client.loaded",
  "ts": "2026-01-04T14:51:00Z",
  "severity": "INFO",
  "context": {
    "device_id": "0123456789abcdef...",
    "rotation_version": 1
  }
}
```

### 4.3 Fingerprint Verification

**Event:** `c6p.identity.v1.client.fingerprint.verified`

```json
{
  "event": "c6p.identity.v1.client.fingerprint.verified",
  "ts": "2026-01-04T14:55:00Z",
  "severity": "INFO",
  "context": {
    "peer_device_id": "fedcba9876543210...",
    "result": "match"
  }
}
```

**Event:** `c6p.identity.v1.client.fingerprint.mismatch`

```json
{
  "event": "c6p.identity.v1.client.fingerprint.mismatch",
  "ts": "2026-01-04T14:56:00Z",
  "severity": "SECURITY",
  "context": {
    "peer_device_id": "fedcba9876543210...",
    "expected_fingerprint": "<base64url>",
    "actual_fingerprint": "<base64url>"
  }
}
```

**Hard rule:** Log fingerprints (hashes), not private keys.

---

## 5. Error Events (Normative)

### 5.1 Canonical Error Event

**Event:** `c6p.identity.v1.error`

```json
{
  "event": "c6p.identity.v1.error",
  "ts": "2026-01-04T15:00:00Z",
  "build": "prod",
  "component": "server",
  "module": "identity/registration",
  "stage": "validate",
  "traceId": "t-abc123",
  "severity": "WARN",
  "error": {
    "code": "C6P.IDENTITY.DEVICE_ID_CONFLICT",
    "retryPolicy": "NO_RETRY",
    "field": "deviceId"
  },
  "context": {
    "device_id_hash": "<hash>"
  }
}
```

**Hard rule:** `error.code` MUST be from canonical registry.

---

## 6. Metrics (Normative)

### 6.1 Server Counters

Server MUST expose:
- `identity_registration_total{result=ok|fail, code?}`
- `identity_rotation_total{result=ok|fail}`
- `identity_revocation_total{reason}`
- `identity_prekey_upload_total{spk=yes|no, otp_count}`
- `identity_error_total{code}`

### 6.2 Client Counters (Recommended)

Client SHOULD expose:
- `identity_generation_total`
- `identity_load_total{result=ok|fail}`
- `identity_fingerprint_verification_total{result=match|mismatch}`
- `identity_rotation_client_total{result=ok|fail}`

### 6.3 Gauges

Server SHOULD expose:
- `identity_active_devices_total{rotation_version?}`
- `identity_rotation_pending_total`
- `identity_revoked_total`

### 6.4 Histograms

Server SHOULD expose:
- `identity_registration_latency_ms`
- `identity_rotation_latency_ms`
- `identity_prekey_upload_latency_ms`

---

## 7. Tracing (Normative)

### 7.1 Trace Propagation

Server MUST propagate `traceId` across:
- HTTP handlers
- DB transactions
- Event emitters

### 7.2 Recommended Spans

- `identity.register.validate`
- `identity.register.store`
- `identity.rotate.validate`
- `identity.rotate.deprecate_old`
- `identity.prekey.upload`
- `identity.revoke`

---

## 8. Alerting Rules (Auditor-Facing)

### 8.1 Critical Alerts

- **Spike in `C6P.IDENTITY.DEVICE_ID_CONFLICT`**: Potential abuse or collision attack
- **Spike in `C6P.IDENTITY.CORRUPTION`**: Platform bug or attack
- **Spike in `C6P.IDENTITY.FINGERPRINT_MISMATCH`**: MITM attempts

### 8.2 Degradation Alerts

- `identity_registration_latency_ms` p95 > baseline
- `identity_prekey_upload_total{result=fail}` rate increase
- `identity_rotation_total{result=fail}` sustained failures

---

## 9. Privacy Rules (Normative)

### 9.1 Hashing Device IDs

For long-term retention:
```
device_id_hash = HMAC-SHA256(LOG_KEY, device_id_bytes)
```
Output: base64url (32 bytes)

**Hard rule:** Use server-secret `LOG_KEY` to prevent offline correlation.

### 9.2 Forbidden in Logs

- Private keys (Ed25519, X25519)
- DH outputs
- Session keys
- Plaintexts
- Raw nonces
- AAD bytes

### 9.3 Allowed in Logs

- Device ID (hashed for long-term retention)
- Fingerprints (public hashes)
- Rotation versions
- Error codes
- Timestamps

---

## 10. Redaction & Retention (Normative)

### 10.1 Redaction

Before shipping logs externally:
- Hash all `device_id` fields
- Remove `user_id` unless necessary
- Drop any raw public keys (keep fingerprints only)

### 10.2 Retention

- **SECURITY events**: 90 days (policy-defined)
- **General INFO/WARN**: 30 days
- **Metrics aggregates**: Indefinite (no PII)

**Hard rule:** Never retain private key material.

---

## 11. Compliance Checklist (Fail-Closed)

- [ ] All identity events use `c6p.identity.v1.*` namespace
- [ ] Structured events include `traceId`, `severity`, `error.code`
- [ ] No private keys or DH outputs in logs
- [ ] Device IDs hashed for long-term retention
- [ ] Metrics exposed for all critical operations
- [ ] Alerts configured for security violations

---
