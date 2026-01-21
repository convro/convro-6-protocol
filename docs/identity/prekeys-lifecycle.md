# C6P Prekeys Lifecycle (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Signed prekey (SPK) and one-time prekey (OTP) generation, rotation, reservation, consumption, and cleanup
**Applies to:** Client implementations and server prekey management

---

## 0. Design Principles (Normative)

1. **SPK rotation**: Medium-term keys rotated periodically (policy-defined)
2. **OTP scarcity**: Server enforces atomic reservation/consumption
3. **Fail-safe refill**: OTP pool never fully depletes (proactive refill)
4. **Server authority**: Server enforces SPK/OTP state transitions (clients never bypass)

---

## 1. Prekey Types (Normative)

### 1.1 Signed Prekey (SPK)

**Type:** X25519 keypair
**Purpose:** Medium-term DH component in handshake (DH1, DH3)
**Signature:** Ed25519 signature by `IK_sig` over `(spkId || spkPub)`
**Rotation policy:** Every 30 days (default) or on-demand

**Hard rule:** SPK MUST be signed; server MUST verify signature on upload.

### 1.2 One-Time Prekey (OTP)

**Type:** X25519 keypair
**Purpose:** Short-term DH component (DH4, optional)
**Single-use:** Server enforces OTP can only be used once
**Refill policy:** Client refills when pool drops below threshold

**Hard rule:** OTP MUST be atomically consumed (server authority).

---

## 2. SPK Lifecycle (Normative)

### 2.1 SPK States

- `ACTIVE`: Current SPK in use
- `ROTATION_PENDING`: New SPK uploaded, old SPK still valid
- `DEPRECATED`: Old SPK no longer returned in bundles
- `REVOKED`: SPK explicitly revoked (compromise)

### 2.2 SPK Generation

**Steps:**
1. Generate X25519 keypair
2. Assign `spkId` (8 bytes, random or sequential)
3. Sign: `spkSig = Ed25519.Sign(IK_sig_priv, "C6P_PREKEY_V1" || spkId_bytes || spkPub_bytes)`
4. Store private key locally
5. Upload to server: `POST /v1/prekeys/upload`

**Hard rule:** SPK MUST be generated on-device (server never generates prekeys).

### 2.3 SPK Rotation

**Trigger:**
- Age > 30 days (default policy)
- Compromise suspected
- Identity key rotation (new `IK_sig` requires new SPK signature)

**Flow:**
1. Generate new SPK (X25519 keypair)
2. Sign with current `IK_sig`
3. Upload new SPK to server
4. Server marks old SPK as `ROTATION_PENDING`
5. After overlap window (7 days default):
   - Old SPK → `DEPRECATED`
   - New SPK → `ACTIVE`

### 2.4 SPK Storage (Server)

```sql
CREATE TABLE signed_prekeys (
  device_id BYTEA NOT NULL,
  spk_id BYTEA NOT NULL,
  spk_pub BYTEA NOT NULL,
  spk_sig BYTEA NOT NULL,
  state VARCHAR(32) NOT NULL, -- ACTIVE, ROTATION_PENDING, DEPRECATED, REVOKED
  created_at TIMESTAMP NOT NULL,
  rotated_at TIMESTAMP,
  rotation_expires_at TIMESTAMP,
  PRIMARY KEY (device_id, spk_id)
);
```

---

## 3. OTP Lifecycle (Normative)

### 3.1 OTP States

- `AVAILABLE`: In pool, ready for reservation
- `RESERVED`: Reserved during bundle fetch
- `PENDING_CONSUMPTION`: Linked to a pending session
- `CONSUMED`: Permanently used
- `EXPIRED`: Reservation TTL elapsed without consumption

### 3.2 OTP Generation & Upload

**Recommended pool size:** 100 OTPs per device

**Steps:**
1. Generate 100 X25519 keypairs
2. Assign each `otpId` (8 bytes, random)
3. Store private keys locally (indexed by `otpId`)
4. Upload to server: `POST /v1/prekeys/upload` (batch)

**Hard rule:** Client MUST retain OTP private keys until consumption confirmed or expiry.

### 3.3 OTP Reservation (Bundle Fetch)

**Endpoint:** `GET /v1/prekeys/bundle?deviceId=...`

**Server behavior:**
1. Select one `AVAILABLE` OTP for target device
2. Atomically transition: `AVAILABLE → RESERVED`
3. Set `reserved_at = now`, `expires_at = now + OTP_RESERVATION_TTL`
4. Return OTP in bundle

**Hard rule:** Same OTP MUST NOT be returned to multiple initiators.

### 3.4 OTP Consumption (Session Open)

**Endpoint:** `POST /v1/dm/sessions/open` (offer references `usedOneTimePrekeyId`)

**Server behavior:**
1. Verify OTP is `RESERVED` for this initiator/session
2. Atomically transition: `RESERVED → PENDING_CONSUMPTION`
3. Link OTP to session
4. On accept: `PENDING_CONSUMPTION → CONSUMED`

**Hard rule:** OTP consumption MUST be atomic with session state transition.

### 3.5 OTP Expiry Cleanup

**Trigger:** Scheduled job (e.g., every 5 minutes)

**Logic:**
```sql
UPDATE one_time_prekeys
SET state = 'EXPIRED'
WHERE state = 'RESERVED'
  AND expires_at < NOW();
```

**Hard rule:** Expired OTPs MUST NOT be reused (move to `EXPIRED`, not back to `AVAILABLE`).

### 3.6 OTP Refill

**Trigger:** Client detects pool depletion

**Detection:**
- Client calls `GET /v1/prekeys/status`
- Response includes `oneTimeAvailable` count
- If `oneTimeAvailable < 20` (threshold): trigger refill

**Flow:**
1. Generate new batch (e.g., 100 OTPs)
2. Upload via `POST /v1/prekeys/upload`
3. Server adds to `AVAILABLE` pool

---

## 4. Prekey Upload Endpoint (Normative)

**POST** `/v1/prekeys/upload`

Request:
```json
{
  "identityPublicKeyEd25519": "<base64url>",
  "identityPublicKeyX25519": "<base64url>",
  "signedPrekey": {
    "keyId": "0011223344556677",
    "publicKeyX25519": "<base64url>",
    "signatureEd25519": "<base64url>"
  },
  "oneTimePrekeys": [
    { "prekeyId": "aabbccddeeff0011", "publicKeyX25519": "<base64url>" },
    { "prekeyId": "aabbccddeeff0012", "publicKeyX25519": "<base64url>" }
  ]
}
```

Response:
```json
{
  "ok": true,
  "acceptedOneTimePrekeyIds": ["aabbccddeeff0011", "aabbccddeeff0012"],
  "totalOneTimeAvailable": 102
}
```

**Validation (server MUST):**
- Verify SPK signature using `identityPublicKeyEd25519`
- Reject duplicate `spkId` or `otpId`
- Enforce rate limits (max 1000 OTPs per upload)

---

## 5. Prekey Status Endpoint (Normative)

**GET** `/v1/prekeys/status`

Response:
```json
{
  "ok": true,
  "deviceId": "0123456789abcdef...",
  "signedPrekeyId": "0011223344556677",
  "signedPrekeyFingerprint": "<base64url SHA-256>",
  "oneTimeAvailable": 87,
  "lastRotationAt": "2026-01-01T00:00:00Z"
}
```

**Hard rule:** `oneTimeAvailable` MUST reflect authoritative server count (not client hints).

---

## 6. Prekey Deletion Policy (Normative)

### 6.1 OTP Cleanup

**Trigger:** Scheduled job (daily)

**Logic:**
```sql
DELETE FROM one_time_prekeys
WHERE state IN ('CONSUMED', 'EXPIRED')
  AND updated_at < NOW() - INTERVAL '30 days';
```

### 6.2 SPK Cleanup

**Trigger:** Manual or policy-triggered

**Logic:**
- `DEPRECATED` SPKs: Delete after 90 days
- `REVOKED` SPKs: Delete immediately (or retain for audit trail)

**Hard rule:** `ACTIVE` or `ROTATION_PENDING` SPKs MUST NOT be deleted.

---

## 7. Error Handling (Normative)

### 7.1 OTP Depletion

**Scenario:** Bundle fetch finds no `AVAILABLE` OTPs

**Server response:**
- Return bundle without OTP field
- Client MAY proceed with 3DH-only handshake

**Recommended:** Client proactively refills before depletion.

### 7.2 SPK Signature Verification Failure

**Scenario:** Server detects invalid SPK signature on upload

**Response:**
- Reject upload: `C6P.HANDSHAKE.SPK_SIGNATURE_INVALID`
- Client MUST NOT retry without fixing signature

---

## 8. Security Properties (Normative)

### 8.1 Forward Secrecy Enhancement

- OTP provides additional forward secrecy layer (DH4)
- Even if SPK compromised later, OTP-protected sessions remain secure

### 8.2 Replay Resistance

- OTP single-use prevents replay of old bundles
- Server enforces `CONSUMED` state is permanent

### 8.3 Server Authority

- Server is authoritative for OTP scarcity
- Clients cannot bypass reservation/consumption pipeline

---

## 9. Compliance Checklist (Fail-Closed)

- [ ] SPK signed with `IK_sig` on generation
- [ ] SPK rotation every 30 days (or policy-defined)
- [ ] OTP pool refilled proactively (threshold: 20 remaining)
- [ ] OTP reservation is atomic (no double-reservation)
- [ ] OTP consumption linked to session creation
- [ ] Expired OTPs never reused

---
