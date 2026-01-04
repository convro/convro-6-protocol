# C6P Identity Test Matrix (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Comprehensive test scenarios for device identity, key rotation, prekeys, and storage
**Audience:** QA engineers, security auditors, client implementers

---

## 0. Test Harness Requirements

### 0.1 Setup
- Mock Keychain/KeyStore (platform-specific)
- Mock server API (identity registration, rotation, prekey endpoints)
- Deterministic key generation (for test vectors)
- Time mocking (for TTL/expiry tests)

### 0.2 Fixtures
- Pre-generated identity keypairs (Ed25519 + X25519)
- Device ID test vectors
- Fingerprint test vectors
- SPK/OTP test pools

---

## 1. Device Identity Tests

### 1.1 Identity Generation

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| DI-001 | First install generates identity | No stored identity → generate | ✅ `IK_sig`, `IK_dh` generated; `device_id` derived |
| DI-002 | Device ID deterministic | Generate twice with same `IK_sig` | ✅ Same `device_id` |
| DI-003 | Device ID changes on rotation | Generate new `IK_sig` | ✅ New `device_id` (different from old) |

### 1.2 Identity Loading

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| DI-101 | Load existing identity | Stored identity → load on launch | ✅ Keys loaded; `device_id` recomputed and matches |
| DI-102 | Detect corruption | Tamper stored `IK_sig` | ❌ `C6P.IDENTITY.CORRUPTION` |
| DI-103 | Missing identity (post-wipe) | No stored identity | ✅ Treat as first install |

---

## 2. Key Rotation Tests

### 2.1 Rotation Trigger

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| KR-001 | User-initiated rotation | User triggers "Rotate Keys" | ✅ New identity generated; old → `ROTATION_PENDING` |
| KR-002 | Policy-triggered rotation (age) | Advance time > 365 days | ✅ App prompts user to rotate |
| KR-003 | Rotation during migration window | Rotate; send offer with old `device_id` | ✅ Accepted during window |
| KR-004 | Rotation after window expiry | Rotate; wait window; send offer with old `device_id` | ❌ `C6P.IDENTITY.MIGRATION_WINDOW_EXPIRED` |

### 2.2 Rotation State Machine

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| KR-101 | `ACTIVE` → `ROTATION_PENDING` | Upload new identity | ✅ Old state → `ROTATION_PENDING` |
| KR-102 | `ROTATION_PENDING` → `ACTIVE` (new) | Window expires | ✅ New identity → `ACTIVE`; old → `DEPRECATED` |
| KR-103 | Revocation during rotation | Rotate; revoke mid-window | ✅ Both old and new → `REVOKED` |

---

## 3. Fingerprint Tests

### 3.1 Fingerprint Computation

| ID | Scenario | Input | Expected |
|---:|---|---|---|
| FP-001 | Canonical fingerprint | Known `IK_sig` public key | ✅ Matches test vector |
| FP-002 | Short fingerprint (8 bytes) | Known public key | ✅ Matches test vector |
| FP-003 | Fingerprint stability | Compute twice | ✅ Identical output |

### 3.2 Fingerprint Verification

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| FP-101 | Successful verification | User compares matching fingerprints | ✅ Peer marked "verified" |
| FP-102 | Failed verification | User compares mismatching fingerprints | ❌ Warn user; block communication |

---

## 4. Prekey Tests

### 4.1 SPK Lifecycle

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| PK-001 | Generate and upload SPK | Generate → sign → upload | ✅ SPK stored as `ACTIVE` |
| PK-002 | SPK signature verification | Server verifies `spkSig` with `IK_sig` | ✅ Accepted |
| PK-003 | Invalid SPK signature | Upload with wrong signature | ❌ `C6P.HANDSHAKE.SPK_SIGNATURE_INVALID` |
| PK-004 | SPK rotation | Generate new SPK → upload | ✅ Old → `ROTATION_PENDING`; new → `ACTIVE` |

### 4.2 OTP Lifecycle

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| PK-101 | Upload OTP pool (100) | Generate 100 OTPs → upload | ✅ All `AVAILABLE` |
| PK-102 | Reserve OTP (bundle fetch) | Fetch bundle → OTP reserved | ✅ OTP → `RESERVED` |
| PK-103 | Consume OTP (session open) | Open session with reserved OTP | ✅ OTP → `PENDING_CONSUMPTION` → `CONSUMED` |
| PK-104 | OTP expiry | Reserve → wait TTL → fetch bundle again | ✅ Expired OTP not returned; state → `EXPIRED` |
| PK-105 | OTP depletion | Consume all OTPs | ✅ Bundle returns no OTP; client refills |

### 4.3 Concurrency (OTP)

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| PK-201 | Concurrent bundle fetches | 2 clients fetch simultaneously | ✅ Distinct OTPs OR one gets none |
| PK-202 | Double-reserve attempt | Force same OTP reservation | ❌ Second fails |

---

## 5. Storage Tests

### 5.1 Platform Secure Storage

| ID | Scenario | Platform | Steps | Expected |
|---:|---|---|---|---|
| ST-001 | Store in iOS Keychain | iOS | Store `IK_sig` with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` | ✅ Stored |
| ST-002 | Retrieve from Keychain | iOS | Load `IK_sig` | ✅ Retrieved |
| ST-003 | Store in AndroidKeyStore | Android | Store with `setUserAuthenticationRequired(true)` | ✅ Stored |
| ST-004 | Access denied (locked device) | iOS/Android | Device locked → attempt load | ❌ `C6P.IDENTITY.STORAGE_UNAVAILABLE` |

### 5.2 Zeroization

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| ST-101 | Zeroize after use (Rust) | Load key → use → zeroize | ✅ Memory cleared (verify with debugger if possible) |
| ST-102 | Zeroize on background (iOS) | App backgrounds → zeroize in-memory keys | ✅ Keys cleared from memory |

---

## 6. Backup & Recovery Tests

### 6.1 Platform Backup

| ID | Scenario | Platform | Steps | Expected |
|---:|---|---|---|---|
| BK-001 | iCloud Keychain sync | iOS | Enable sync → restore on new device | ✅ Identity restored |
| BK-002 | Android Backup Service | Android | Backup → restore | ✅ Identity restored |

### 6.2 Manual Backup

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| BK-101 | Encrypted export | Export with passphrase | ✅ Encrypted JSON with PBKDF2 |
| BK-102 | Import from backup | Import encrypted export | ✅ Identity restored |
| BK-103 | Weak passphrase rejected | Export with "123" | ❌ Require min 12 chars |

---

## 7. Error Handling Tests

### 7.1 Identity Corruption

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| ER-001 | Detect `device_id` mismatch | Tamper `device_id` in storage | ❌ `C6P.IDENTITY.CORRUPTION` on load |
| ER-002 | Missing keys | Delete `IK_sig` from Keychain | ❌ `C6P.IDENTITY.CORRUPTION` |

### 7.2 Server Conflicts

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| ER-101 | Duplicate `device_id` conflict | Register same `device_id` with different keys | ❌ `C6P.IDENTITY.DEVICE_ID_CONFLICT` |
| ER-102 | Revoked identity | Attempt handshake with revoked identity | ❌ `C6P.IDENTITY.REVOKED` |

---

## 8. Multi-Device Tests

### 8.1 Independent Identities

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| MD-001 | 2 devices for same user | Register device 1 → register device 2 | ✅ Distinct `device_id`, `IK_sig`, `IK_dh` |
| MD-002 | Cross-device session | Device 1 offers to Device 2 | ✅ Handshake succeeds with distinct identities |

---

## 9. Observability Tests

### 9.1 Metrics

| ID | Metric | Trigger | Expected Value |
|---:|---|---|---|
| OB-001 | `identity_registration_total` | Register 10 devices | `10` |
| OB-002 | `identity_rotation_total` | Rotate 5 times | `5` |
| OB-003 | `identity_error_total{code=C6P.IDENTITY.CORRUPTION}` | Trigger corruption | `>0` |

### 9.2 Logs

| ID | Scenario | Steps | Log Must Include | Log Must NOT Include |
|---:|---|---|---|---|
| OB-101 | Identity registered | Register device | `device_id`, `rotation_version` | `IK_sig` private bytes |
| OB-102 | Rotation triggered | Rotate keys | `old_rotation_version`, `new_rotation_version` | Private keys |

---

## 10. Security Properties Tests

### 10.1 Platform Compromise Resistance

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| SEC-001 | Jailbreak detection (optional) | Run on jailbroken iOS | ⚠️ Optional warning; app MAY refuse to run |
| SEC-002 | Hardware-backed KeyStore | Android with TEE | ✅ `KeyInfo.isInsideSecureHardware = true` |

### 10.2 Timing Attack Resistance

| ID | Scenario | Steps | Expected |
|---:|---|---|---|
| SEC-101 | Fingerprint comparison | Compare matching vs mismatching | ✅ Constant-time comparison |

---

## 11. Compliance Checklist

- [ ] All test scenarios pass
- [ ] Platform-specific storage tests pass (iOS, Android)
- [ ] Zeroization verified (best-effort)
- [ ] Error codes match canonical registry
- [ ] No key material in logs (verified)
- [ ] Observability metrics accurate

---
