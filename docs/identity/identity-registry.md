# C6P Identity Registry (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Device identity generation, identity key types, canonical fingerprints, and identity-related fixed sizes
**Applies to:** All C6P v1 implementations (Rust core, Swift client, Node backend)

---

## 0. Goals (Normative)

1. **Stable device identities** across platform reinstalls (where key material is preserved)
2. **Canonical fingerprinting** for identity key verification
3. **Hard separation** between signing keys (Ed25519) and DH keys (X25519)
4. **Deterministic device ID generation** from identity key material
5. **No silent key replacement** (rotation must be explicit and versioned)

---

## 1. Terminology (Normative)

- **DeviceId** (`C6PDeviceId`): 16-byte unique device identifier
- **Identity Key (IK)**: Long-term keypair bound to a device
  - `IK_sig`: Ed25519 keypair for signatures
  - `IK_dh`: X25519 keypair for key exchange
- **Fingerprint**: Canonical hash of a public key for human/UI verification

---

## 2. Device ID Generation (Normative)

### 2.1 Canonical Device ID Derivation

`DeviceId` MUST be deterministically derived from `IK_sig` public key:

```
device_id_bytes = SHA-256("C6P_DEVICE_ID_V1" || IK_sig_pub_bytes)[0..16]
```

Where:
- `"C6P_DEVICE_ID_V1"` is ASCII label (exact bytes)
- `IK_sig_pub_bytes` is 32-byte Ed25519 public key
- Output is first 16 bytes of SHA-256 hash

**Wire encoding:** hex32 lowercase

**Hard rules:**
- Device ID MUST be stable as long as `IK_sig` is unchanged
- Device ID MUST change if `IK_sig` is rotated
- Same `IK_sig` on different platforms MUST yield same device ID

---

## 3. Identity Key Types (Normative)

### 3.1 IK_sig (Ed25519 Signing Key)

**Purpose:** Device authentication, prekey signing, offer signing

**Lifecycle:**
- Generated once per device installation
- MUST be stored in platform secure storage (Keychain/KeyStore)
- Rotation requires explicit user action or policy trigger
- Old `IK_sig` MAY be retained for verification during migration window

**Usage:**
- Sign SPK (signed prekey)
- Sign IslandAccord offer (initiator authentication)
- Sign device attestation challenges (optional)

### 3.2 IK_dh (X25519 DH Key)

**Purpose:** Long-term key exchange component in handshake (DH1, DH2)

**Lifecycle:**
- Generated once per device installation
- Co-located with `IK_sig` in secure storage
- Rotation SHOULD be synchronized with `IK_sig` rotation

**Usage:**
- Handshake DH computations (see IslandAccord crypto spec)

---

## 4. Fingerprints (Normative)

### 4.1 Canonical Fingerprint Format

For UI/UX identity verification, use:

```
fingerprint = base64url( SHA-256("C6P_FINGERPRINT_V1" || pub_key_bytes) )
```

Output: 43 characters (base64url, no padding, 32 bytes)

**Display format (recommended):**
```
AAAA-BBBB-CCCC-DDDD-EEEE-FFFF-GGGG-HHHH-IIII-JJJJ-K
```
(Grouped in blocks of 4, hyphen-separated)

### 4.2 Short Fingerprint (Optional, Non-Normative)

For space-constrained UI:
```
short_fingerprint_hex = SHA-256("C6P_SHORT_FP_V1" || pub_key_bytes)[0..8]
```
Output: hex16 (8 bytes, 16 chars)

**Hard rule:** Short fingerprints MUST NOT be used for security-critical verification without additional confirmation.

---

## 5. Identity Key Storage Contract (Normative Pointers)

Detailed storage requirements are in:
- `docs/identity/key-storage-and-hardening.md`

Summary (MUST):
- Platform secure storage (iOS Keychain, Android KeyStore, etc.)
- Encryption at rest
- Access control (biometric/passcode)
- Zeroization on device wipe
- No plaintext export without explicit user consent

---

## 6. Identity Rotation Policy (Normative Pointers)

Detailed rotation rules are in:
- `docs/identity/key-rotation-policy.md`

Summary (MUST):
- Explicit version increments
- Migration window for old identity acceptance
- Server-side tracking of active identity versions per device
- Client-side re-upload of new prekeys after rotation

---

## 7. Error Codes (Normative)

Identity-related errors MUST use canonical codes from:
- `docs/identity/identity-error-codes.md`

Examples:
- `C6P.IDENTITY.DEVICE_ID_MISMATCH`
- `C6P.IDENTITY.KEY_ROTATION_REQUIRED`
- `C6P.IDENTITY.FINGERPRINT_MISMATCH`

---

## 8. Test Vectors (Normative Requirement)

This repo MUST include test vectors:
- `docs/identity/test-vectors/v1/device_id_vectors.json`
- `docs/identity/test-vectors/v1/identity_key_vectors.json`
- `docs/identity/test-vectors/v1/fingerprint_vectors.json`

---

## 9. Compliance Checklist (Fail-Closed)

- [ ] Device ID derived from `IK_sig` deterministically
- [ ] Identity keys stored in platform secure storage
- [ ] Fingerprints computed with canonical labels
- [ ] No silent key replacement
- [ ] Rotation requires explicit version bump

---
