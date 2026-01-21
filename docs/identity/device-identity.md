# C6P Device Identity (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Device identity model, identity key generation, platform integration, and identity lifecycle
**Applies to:** Client implementations (Swift iOS, Android, etc.)

---

## 0. Design Principles (Normative)

1. **One device = one identity**: Each device installation has a unique identity keypair
2. **Platform-native security**: Use OS-provided secure storage (Keychain, KeyStore)
3. **User owns keys**: Keys are local-only; server never learns private keys
4. **Explicit rotation**: Identity changes require user action or policy trigger
5. **Fail-closed**: Any identity verification failure aborts operation

---

## 1. Identity Model (Normative)

### 1.1 Device Identity Components

A C6P device identity consists of:

1. **`IK_sig`** (Ed25519 keypair)
   - Purpose: Authentication, signing
   - Size: 32-byte public + 64-byte private (Ed25519)

2. **`IK_dh`** (X25519 keypair)
   - Purpose: Key exchange
   - Size: 32-byte public + 32-byte private (X25519)

3. **`device_id`** (Derived identifier)
   - Computed from `IK_sig` public key
   - 16 bytes, wire encoding: hex32 lowercase

4. **Metadata** (Non-secret)
   - Platform (iOS, Android, etc.)
   - App version
   - Created timestamp
   - Last rotation timestamp

---

## 2. Identity Generation (Normative)

### 2.1 Initial Setup (First Install)

**Trigger:** First app launch, no existing identity found

**Steps:**
1. Generate `IK_sig` (Ed25519 keypair)
2. Generate `IK_dh` (X25519 keypair)
3. Derive `device_id` from `IK_sig` public key (see identity-registry.md §2.1)
4. Store keypairs in platform secure storage
5. Generate initial prekey set (SPK + OTP pool)
6. Upload identity + prekeys to server

**Hard rule:** Identity generation MUST happen offline-first (no server dependency for keypair creation).

### 2.2 Platform-Specific Generation

#### iOS (Swift)
```swift
// Pseudo-code
let ikSig = try Ed25519.generate()
let ikDh = try X25519.generate()
let deviceId = deriveDeviceId(from: ikSig.publicKey)

try Keychain.store(ikSig.privateKey, label: "c6p.ik_sig.priv")
try Keychain.store(ikDh.privateKey, label: "c6p.ik_dh.priv")
```

#### Android (Kotlin)
```kotlin
// Pseudo-code - use AndroidKeyStore
val ikSig = Ed25519KeyPair.generate()
val ikDh = X25519KeyPair.generate()
val deviceId = deriveDeviceId(ikSig.publicKey)

AndroidKeyStore.store("c6p_ik_sig_priv", ikSig.privateKey)
AndroidKeyStore.store("c6p_ik_dh_priv", ikDh.privateKey)
```

---

## 3. Identity Verification (Normative)

### 3.1 Self-Verification (Client-Side)

On app launch, client MUST:
1. Load `IK_sig` public key from storage
2. Recompute `device_id`
3. Compare to stored `device_id`
4. If mismatch → abort; log `C6P.IDENTITY.CORRUPTION`

### 3.2 Peer Verification (User-Facing)

**Scenario:** User wants to verify peer's identity

**Flow:**
1. Display peer's `IK_sig` fingerprint (see identity-registry.md §4)
2. User compares fingerprint via out-of-band channel (QR code, voice, etc.)
3. On match → mark peer as "verified"
4. On mismatch → warn user; block communication

**Hard rule:** Fingerprint comparison MUST be constant-time to prevent timing attacks.

---

## 4. Identity Binding (Normative)

### 4.1 Server-Side Identity Record

Server MUST maintain per-device:
- `user_id` (account owner)
- `device_id` (hex32)
- `ik_sig_pub` (Ed25519 public key, base64url)
- `ik_dh_pub` (X25519 public key, base64url)
- `created_at`
- `last_active_at`
- `rotation_version` (integer, default 1)

**Hard rule:** Server MUST NOT store private keys.

### 4.2 Device Registration Endpoint

**POST** `/v1/devices/register`

Request:
```json
{
  "deviceId": "0123456789abcdef0123456789abcdef",
  "identityPublicKeyEd25519": "<base64url>",
  "identityPublicKeyX25519": "<base64url>",
  "platform": "iOS 17.2",
  "appVersion": "1.0.0"
}
```

Response:
```json
{
  "ok": true,
  "deviceId": "0123456789abcdef0123456789abcdef",
  "rotationVersion": 1
}
```

**Validation (server MUST):**
- Verify `device_id` derives from `identityPublicKeyEd25519`
- Reject duplicate `device_id` with different public keys
- Store binding atomically

---

## 5. Identity Lifecycle (Normative)

### 5.1 States

- `ACTIVE`: Normal operational state
- `ROTATION_PENDING`: Old identity still valid, new identity uploaded
- `ROTATED`: Old identity deprecated, new identity active
- `REVOKED`: Identity explicitly revoked (compromise, device loss)

### 5.2 State Transitions

```
[NEW INSTALL] → ACTIVE
ACTIVE → ROTATION_PENDING (user-initiated or policy)
ROTATION_PENDING → ROTATED (migration window expires)
ACTIVE/ROTATED → REVOKED (explicit revocation)
```

---

## 6. Identity Backup & Recovery (Normative)

### 6.1 Platform Backup

**iOS iCloud Keychain:**
- MUST enable iCloud Keychain sync for identity keys
- User controls sync via OS settings

**Android Backup:**
- MUST use Android Backup Service for encrypted key backup
- Respect user's backup preferences

### 6.2 Manual Backup (Optional)

If platform backup unavailable, app MAY offer:
- Encrypted key export (user-provided passphrase)
- QR code export (encrypted, short-lived)

**Hard rule:** Backup MUST be encrypted; never export plaintext private keys.

### 6.3 Recovery Flow

**Scenario:** User restores device from backup

**Steps:**
1. Load identity keys from platform restore
2. Recompute `device_id`
3. Query server: `GET /v1/devices/{device_id}`
4. If found → resume session
5. If not found → treat as new device (re-register)

---

## 7. Multi-Device Support (Normative)

### 7.1 Separate Identities Per Device

**Hard rule:** Each device MUST have a distinct identity.

**Rationale:**
- Independent key compromise scope
- Platform-specific security boundaries
- Simplified revocation (revoke one device, not all)

### 7.2 Linked Devices (User Account)

Server maintains:
```
User Account (user_id)
  ├── Device 1 (device_id_1, ik_sig_1, ik_dh_1)
  ├── Device 2 (device_id_2, ik_sig_2, ik_dh_2)
  └── Device 3 (device_id_3, ik_sig_3, ik_dh_3)
```

**Hard rule:** Devices share `user_id` but have independent cryptographic identities.

---

## 8. Error Handling (Normative)

### 8.1 Identity Corruption

**Detection:** `device_id` recomputation mismatch

**Response:**
- Log `C6P.IDENTITY.CORRUPTION`
- Prompt user for recovery or reset
- MUST NOT silently generate new identity

### 8.2 Identity Conflict

**Scenario:** Server sees duplicate `device_id` with different public keys

**Response:**
- Reject registration with `C6P.IDENTITY.DEVICE_ID_CONFLICT`
- Client MUST NOT retry automatically

---

## 9. Compliance Checklist (Fail-Closed)

- [ ] Identity keys stored in platform secure storage
- [ ] Device ID derived deterministically from `IK_sig`
- [ ] Server never stores private keys
- [ ] Fingerprints computed with canonical labels
- [ ] Identity corruption triggers abort (no silent recovery)
- [ ] Multi-device = separate identities per device

---
