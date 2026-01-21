# C6P Key Rotation Policy (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Identity key rotation triggers, migration windows, backward compatibility, and rotation lifecycle
**Applies to:** Client implementations and server-side identity management

---

## 0. Goals (Normative)

1. **Explicit rotation**: Identity changes are never silent
2. **Migration window**: Old identity remains valid during transition
3. **Backward compatibility**: Peers with old identity can still initiate sessions during window
4. **Fail-safe**: Rotation failures do not brick the device

---

## 1. Rotation Triggers (Normative)

### 1.1 User-Initiated Rotation

**Scenarios:**
- User suspects key compromise
- User wants to regenerate identity explicitly
- Compliance policy requires periodic rotation

**Flow:**
1. User triggers "Rotate Identity Keys" in settings
2. App generates new `IK_sig` + `IK_dh`
3. Derives new `device_id`
4. Uploads new identity to server with `rotation_version++`
5. Old identity enters `ROTATION_PENDING` state

### 1.2 Policy-Triggered Rotation

**Scenarios:**
- Key age exceeds policy threshold (e.g., 365 days)
- Cryptographic suite upgrade (e.g., Ed25519 → post-quantum)
- Platform security event (OS-level key compromise detected)

**Flow:**
1. App detects policy trigger on launch
2. Prompts user: "Identity rotation required"
3. User confirms → proceed with rotation
4. If user declines → app MAY operate in degraded mode (no new sessions)

### 1.3 Compromise-Triggered Rotation

**Scenario:** Device loss, theft, or suspected compromise

**Flow:**
1. User accesses account from another device or web
2. Remotely revokes compromised device identity
3. Server marks old identity as `REVOKED`
4. All existing sessions using old identity → invalidated
5. Compromised device blocked from new handshakes

---

## 2. Rotation States (Normative)

### 2.1 State Definitions

- `ACTIVE_v1`: Current identity, version 1
- `ROTATION_PENDING`: Old identity valid for receiving, new identity uploaded
- `ACTIVE_v2`: New identity active, old identity deprecated
- `REVOKED`: Identity explicitly revoked (not recoverable)

### 2.2 State Transitions

```
ACTIVE_v1 ──┬─→ ROTATION_PENDING ─→ ACTIVE_v2
            │
            └─→ REVOKED (explicit revocation)
```

---

## 3. Migration Window (Normative)

### 3.1 Window Duration

**Default:** 7 days

**Rationale:**
- Allows peers to discover new identity gradually
- Balances security (short window) and UX (long enough for offline peers)

**Configuration:**
- Server SHOULD allow per-deployment configuration
- Minimum: 24 hours
- Maximum: 30 days

### 3.2 Behavior During Window

**Old identity (`rotation_version=1`):**
- MAY be used for receiving handshake offers
- MUST NOT be used for initiating new sessions
- Existing sessions continue unaffected

**New identity (`rotation_version=2`):**
- MUST be used for all new outgoing sessions
- MUST be advertised in bundles
- Prekeys MUST be regenerated and uploaded

### 3.3 Window Expiry

**Trigger:** `now >= rotation_started_at + MIGRATION_WINDOW`

**Effect:**
- Server transitions old identity: `ROTATION_PENDING → DEPRECATED`
- Old identity no longer returned in bundles
- Incoming offers using old identity → rejected with `C6P.IDENTITY.KEY_ROTATION_REQUIRED`

---

## 4. Server-Side Rotation Tracking (Normative)

### 4.1 Identity Record Schema

```sql
CREATE TABLE device_identities (
  device_id BYTEA PRIMARY KEY,
  user_id BIGINT NOT NULL,
  rotation_version INT NOT NULL DEFAULT 1,
  ik_sig_pub BYTEA NOT NULL,
  ik_dh_pub BYTEA NOT NULL,
  state VARCHAR(32) NOT NULL, -- ACTIVE, ROTATION_PENDING, DEPRECATED, REVOKED
  created_at TIMESTAMP NOT NULL,
  rotated_at TIMESTAMP,
  rotation_expires_at TIMESTAMP,
  revoked_at TIMESTAMP
);
```

### 4.2 Rotation Endpoint

**POST** `/v1/devices/{device_id}/rotate`

Request:
```json
{
  "newIdentityPublicKeyEd25519": "<base64url>",
  "newIdentityPublicKeyX25519": "<base64url>",
  "newDeviceId": "fedcba9876543210...",
  "migrationWindowDays": 7
}
```

Response:
```json
{
  "ok": true,
  "oldRotationVersion": 1,
  "newRotationVersion": 2,
  "rotationExpiresAt": "2026-01-11T10:30:00Z"
}
```

**Server MUST:**
- Mark old identity as `ROTATION_PENDING`
- Create new identity record with `rotation_version=2`, state `ACTIVE`
- Set `rotation_expires_at = now + migrationWindowDays`
- Invalidate old prekeys; require new prekey upload

---

## 5. Client-Side Rotation Flow (Normative)

### 5.1 Initiating Rotation

**Steps:**
1. Generate new `IK_sig` + `IK_dh` keypairs
2. Derive new `device_id`
3. Store new keys in secure storage (separate keychain entries)
4. Call `POST /v1/devices/{old_device_id}/rotate`
5. Upload new prekeys: `POST /v1/prekeys/upload`
6. Mark local state as `ROTATION_PENDING`

### 5.2 Using New Identity

**Outgoing sessions:**
- MUST use new `IK_sig`, `IK_dh`, `device_id`
- Old identity MUST NOT be used for offers

**Incoming sessions:**
- MUST accept offers addressed to either old or new `device_id` (during window)
- After window expiry, reject offers to old `device_id`

### 5.3 Completing Rotation

**Trigger:** `rotation_expires_at` passed

**Steps:**
1. Client queries server: `GET /v1/devices/{old_device_id}/rotation-status`
2. If server confirms `DEPRECATED`, client:
   - Deletes old identity keys from storage
   - Removes old `device_id` from local state
   - Marks rotation complete

---

## 6. Prekey Re-Upload (Normative)

**Hard rule:** After identity rotation, client MUST generate and upload fresh prekeys.

**Rationale:**
- Old SPK signed with old `IK_sig` is invalid
- OTP pool must be regenerated with new keys

**Steps:**
1. Generate new SPK (X25519 keypair)
2. Sign SPK with new `IK_sig`
3. Generate new OTP pool (recommended: 100 keys)
4. Call `POST /v1/prekeys/upload` with new keys

---

## 7. Backward Compatibility (Normative)

### 7.1 Peer Discovery During Rotation

**Scenario:** Peer A rotates identity; Peer B is offline and has old bundle cached

**Flow:**
1. Peer B initiates session using old bundle
2. Server detects old `device_id` in offer
3. If within migration window:
   - Server forwards offer to Peer A (old identity still bound)
   - Peer A accepts using old `IK_dh` private key
   - Session proceeds normally
4. If migration window expired:
   - Server rejects offer: `C6P.IDENTITY.KEY_ROTATION_REQUIRED`
   - Peer B fetches fresh bundle with new identity

### 7.2 Session Continuity

**Hard rule:** Existing active sessions MUST continue unaffected by rotation.

**Rationale:**
- Session keys are independent of identity keys post-handshake
- Rotation only affects new handshake initialization

---

## 8. Revocation (Normative)

### 8.1 Explicit Revocation

**Trigger:** User reports device compromise or loss

**Flow:**
1. User authenticates from trusted device/web
2. Calls `POST /v1/devices/{compromised_device_id}/revoke`
3. Server:
   - Marks identity as `REVOKED`
   - Invalidates all sessions for that device
   - Removes all prekeys
   - Prevents new handshakes

**Hard rule:** Revocation MUST be immediate (no migration window).

### 8.2 Revocation Endpoint

**POST** `/v1/devices/{device_id}/revoke`

Request:
```json
{
  "reason": "device_lost",
  "revokeAllSessions": true
}
```

Response:
```json
{
  "ok": true,
  "revokedAt": "2026-01-04T12:00:00Z",
  "sessionsInvalidated": 15
}
```

---

## 9. Error Codes (Normative)

Rotation-related errors MUST use canonical codes:
- `C6P.IDENTITY.KEY_ROTATION_REQUIRED`
- `C6P.IDENTITY.ROTATION_IN_PROGRESS`
- `C6P.IDENTITY.REVOKED`
- `C6P.IDENTITY.MIGRATION_WINDOW_EXPIRED`

---

## 10. Compliance Checklist (Fail-Closed)

- [ ] Rotation is explicit (never silent)
- [ ] Migration window enforced (7-day default)
- [ ] Old identity deprecated after window expiry
- [ ] Prekeys regenerated and re-uploaded post-rotation
- [ ] Existing sessions unaffected by rotation
- [ ] Revocation is immediate (no window)

---
