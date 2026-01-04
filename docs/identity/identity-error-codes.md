# C6P Identity Error Codes (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Canonical error codes for identity-related failures
**Aligned with:** `docs/crypto/c6p-error-codes.md` (global registry)
**Applies to:** Client implementations and server identity management

---

## 0. Principles (Non-Negotiable)

1. **Stable codes**: Once shipped, codes MUST NOT be repurposed
2. **Fail-closed**: Any identity failure aborts the operation
3. **No secret leakage**: Errors MUST NOT reveal key material or crypto correctness
4. **Structured payloads**: All errors include `errorCode`, `severity`, `retry`

---

## 1. Error Code Format (Normative)

Identity errors use namespace: `C6P.IDENTITY.*`

Examples:
- `C6P.IDENTITY.DEVICE_ID_MISMATCH`
- `C6P.IDENTITY.KEY_ROTATION_REQUIRED`
- `C6P.IDENTITY.CORRUPTION`

---

## 2. Canonical Error Registry (Normative)

### 2.1 Device Identity Errors

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|-------|
| `C6P.IDENTITY.DEVICE_ID_MISMATCH` | WARN | NO_RETRY | Computed device_id != expected | Client-side detection; requires investigation |
| `C6P.IDENTITY.DEVICE_ID_CONFLICT` | ERROR | NO_RETRY | Server sees duplicate device_id with different keys | Registration rejected |
| `C6P.IDENTITY.CORRUPTION` | ERROR | NO_RETRY | Stored identity keys corrupted or missing | Requires user intervention (re-register or restore) |
| `C6P.IDENTITY.MISSING` | WARN | RETRY_AFTER_SYNC | No identity found locally | First install or post-wipe |

### 2.2 Key Rotation Errors

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|-------|
| `C6P.IDENTITY.KEY_ROTATION_REQUIRED` | WARN | NO_RETRY | Server requires identity rotation | User must rotate keys |
| `C6P.IDENTITY.ROTATION_IN_PROGRESS` | WARN | RETRY_SAFE | Identity rotation not yet complete | Transient state |
| `C6P.IDENTITY.MIGRATION_WINDOW_EXPIRED` | WARN | NO_RETRY | Old identity no longer valid | Peer must fetch new bundle |
| `C6P.IDENTITY.REVOKED` | SECURITY | NO_RETRY | Identity explicitly revoked | Device compromised or lost |

### 2.3 Fingerprint Errors

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|-------|
| `C6P.IDENTITY.FINGERPRINT_MISMATCH` | SECURITY | NO_RETRY | User-verified fingerprint doesn't match | Potential MITM or user error |
| `C6P.IDENTITY.FINGERPRINT_INVALID` | WARN | NO_RETRY | Malformed fingerprint string | Parsing/encoding issue |

### 2.4 Prekey Errors

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|-------|
| `C6P.IDENTITY.SPK_MISSING` | WARN | RETRY_AFTER_SYNC | No valid SPK found | Rotation pending or initial upload failed |
| `C6P.IDENTITY.OTP_DEPLETED` | WARN | RETRY_AFTER_SYNC | No OTP available | Client should refill proactively |
| `C6P.IDENTITY.PREKEY_UPLOAD_FAILED` | ERROR | RETRY_SAFE | Server rejected prekey upload | Check signature/encoding |

### 2.5 Storage Errors

| Code | Severity | Retry | When | Notes |
|------|----------|-------|------|-------|
| `C6P.IDENTITY.STORAGE_UNAVAILABLE` | ERROR | RETRY_SAFE | Keychain/KeyStore inaccessible | Device locked or OS error |
| `C6P.IDENTITY.STORAGE_ACCESS_DENIED` | ERROR | NO_RETRY | Biometric/passcode auth failed | User must authenticate |
| `C6P.IDENTITY.STORAGE_CORRUPT` | ERROR | NO_RETRY | Keychain data malformed | Requires recovery or reset |

---

## 3. Error Response Format (Normative)

### 3.1 Client-Side Errors

```json
{
  "ok": false,
  "errorCode": "C6P.IDENTITY.CORRUPTION",
  "severity": "ERROR",
  "retry": "NO_RETRY",
  "module": "identity/device-identity",
  "stage": "load",
  "message": "Identity keys corrupted. Please re-register device."
}
```

### 3.2 Server-Side Errors

**HTTP Response:**
```json
{
  "ok": false,
  "errorCode": "C6P.IDENTITY.DEVICE_ID_CONFLICT",
  "severity": "ERROR",
  "retry": "NO_RETRY",
  "traceId": "t-abc123",
  "message": "Device ID conflict detected."
}
```

**Hard rule:** Server MUST NOT include details that reveal key material or DB state.

---

## 4. Logging Policy (Normative)

### 4.1 Allowed in Logs

- `errorCode` (canonical)
- `severity`, `retry`
- `device_id` (hex, or hashed)
- `rotation_version`
- `module`, `stage`
- timestamps

### 4.2 Forbidden in Logs

- Private keys (Ed25519, X25519)
- Public keys (full bytes; log fingerprints only)
- DH outputs
- Session keys
- Plaintexts

**Hard rule:** Even in debug builds, key material MUST NOT be logged.

---

## 5. Observability (Normative)

### 5.1 Metrics

Server SHOULD expose:
- `identity_registration_total{result=ok|fail, code?}`
- `identity_rotation_total{result=ok|fail}`
- `identity_revocation_total{reason}`
- `identity_error_total{code}`

### 5.2 Alerts

High-signal alerts:
- Spike in `C6P.IDENTITY.DEVICE_ID_CONFLICT` (abuse or attack)
- Spike in `C6P.IDENTITY.CORRUPTION` (platform bug or attack)
- Spike in `C6P.IDENTITY.FINGERPRINT_MISMATCH` (MITM attempts)

---

## 6. Cross-References (Normative)

Identity errors integrate with:
- `docs/crypto/c6p-error-codes.md` (global registry)
- `docs/handshake/island-accord-error-codes.md` (handshake-specific)
- `docs/identity/identity-observability.md` (telemetry)

---

## 7. Compliance Checklist (Fail-Closed)

- [ ] All identity errors use `C6P.IDENTITY.*` namespace
- [ ] Errors include `severity` and `retry` policy
- [ ] No key material in logs or error messages
- [ ] Server errors include `traceId` for observability
- [ ] Client errors include `module` and `stage`

---
