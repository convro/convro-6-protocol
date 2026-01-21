# C6P Key Storage & Hardening (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Platform-specific secure storage, zeroization, access control, and key material protection
**Applies to:** Client implementations (iOS, Android, Desktop)

---

## 0. Security Principles (Non-Negotiable)

1. **Platform secure storage MUST be used** (Keychain, KeyStore, OS-level encryption)
2. **No plaintext keys in memory longer than necessary**
3. **Zeroization after use** (best-effort on platforms that support it)
4. **Access control**: Keys protected by biometric/passcode
5. **No logging of key material** (not even in debug builds)

---

## 1. Storage Requirements (Normative)

### 1.1 Identity Keys (`IK_sig`, `IK_dh`)

**Storage location:**
- **iOS:** Keychain (with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **Android:** AndroidKeyStore (hardware-backed if available)
- **Desktop:** OS-native keychain (macOS Keychain, Windows DPAPI, Linux Secret Service)

**Protection level:**
- MUST require device unlock (biometric or passcode)
- MUST be device-bound (not synced by default, unless explicit iCloud Keychain opt-in)
- MUST be encrypted at rest

**Hard rule:** Private keys MUST NEVER be stored in:
- UserDefaults / SharedPreferences
- Application sandbox without encryption
- Cloud storage unencrypted

### 1.2 Prekeys (SPK, OTP)

**SPK private key:**
- Same storage as identity keys (Keychain/KeyStore)
- MUST be tagged with `spkId` for retrieval

**OTP private keys:**
- Option 1: Store in Keychain/KeyStore (100 entries)
- Option 2: Encrypted database with master key in Keychain
  - Recommended for large OTP pools
  - Database encryption key MUST be in Keychain

**Hard rule:** OTP private keys MUST be deleted immediately after consumption or expiry.

### 1.3 Session Keys (DM Ratchet State)

**Storage:**
- Encrypted local database (SQLite with SQLCipher or equivalent)
- Encryption key stored in Keychain/KeyStore
- Per-session: `root_key`, `CK_i2r`, `CK_r2i`, counters, skip-window state

**Hard rule:** Session keys MUST be atomically persisted (crash-safe).

---

## 2. iOS Implementation (Normative)

### 2.1 Keychain Configuration

```swift
// Pseudo-code
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.example.c6p.identity",
    kSecAttrAccount as String: "ik_sig_priv",
    kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    kSecAttrSynchronizable as String: false, // Do not sync unless explicitly enabled
    kSecValueData as String: ikSigPrivBytes
]

let status = SecItemAdd(query as CFDictionary, nil)
```

**Hard rules:**
- Use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` (not `AfterFirstUnlock`)
- Set `kSecAttrSynchronizable = false` by default
- Tag all keys with `kSecAttrLabel` for easy retrieval

### 2.2 Biometric Protection

```swift
let access = SecAccessControlCreateWithFlags(
    nil,
    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    .biometryCurrentSet,
    nil
)

query[kSecAttrAccessControl as String] = access
```

**Hard rule:** If biometric authentication fails, fallback to passcode (do not store plaintext).

---

## 3. Android Implementation (Normative)

### 3.1 AndroidKeyStore Configuration

```kotlin
// Pseudo-code
val keyGenerator = KeyGenerator.getInstance(
    KeyProperties.KEY_ALGORITHM_AES,
    "AndroidKeyStore"
)

val keyGenParameterSpec = KeyGenParameterSpec.Builder(
    "c6p_ik_sig_priv",
    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
)
    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
    .setUserAuthenticationRequired(true)
    .setUserAuthenticationValidityDurationSeconds(30)
    .build()

keyGenerator.init(keyGenParameterSpec)
val secretKey = keyGenerator.generateKey()
```

**Hard rules:**
- Use `setUserAuthenticationRequired(true)`
- Use hardware-backed KeyStore if available (`KeyInfo.isInsideSecureHardware`)
- Never export keys from KeyStore

### 3.2 Encrypted Preferences (for metadata)

```kotlin
val masterKey = MasterKey.Builder(context)
    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
    .build()

val encryptedPrefs = EncryptedSharedPreferences.create(
    context,
    "c6p_identity_prefs",
    masterKey,
    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
)
```

---

## 4. Zeroization (Best-Effort Normative)

### 4.1 Memory Zeroization

**Languages with manual memory management (Rust, C++):**
```rust
use zeroize::Zeroize;

let mut ik_sig_priv = [0u8; 64];
// ... use key ...
ik_sig_priv.zeroize();
```

**Swift:**
```swift
var ikSigPriv = Data(count: 64)
// ... use key ...
ikSigPriv.resetBytes(in: 0..<ikSigPriv.count)
ikSigPriv = Data() // release
```

**Hard rule:** Zeroize keys immediately after cryptographic operation completes.

### 4.2 Limitations

**Garbage-collected languages (Kotlin, Swift, Node.js):**
- Zeroization is best-effort (GC may leave copies in memory)
- Use native crypto APIs that handle zeroization internally
- Minimize key lifetime in memory

---

## 5. Access Control (Normative)

### 5.1 Authentication Requirements

**For identity key operations:**
- MUST require device unlock (biometric or passcode)
- MAY cache authentication for short duration (30 seconds max)

**For session key operations (ratchet):**
- MAY use cached authentication (no prompt per message)
- Encryption key for session DB MUST be protected by Keychain/KeyStore

### 5.2 App Background Protection

**iOS:**
```swift
NotificationCenter.default.addObserver(
    forName: UIApplication.willResignActiveNotification,
    object: nil,
    queue: nil
) { _ in
    // Zeroize in-memory keys
    // Lock session state
}
```

**Android:**
```kotlin
override fun onPause() {
    super.onPause()
    // Zeroize in-memory keys
    // Lock session state
}
```

---

## 6. Key Export (Normative)

### 6.1 Backup Export

**Allowed:**
- Encrypted export with user-provided strong passphrase
- Platform backup (iCloud Keychain, Android Backup Service)

**Forbidden:**
- Plaintext export
- Automatic cloud sync without encryption
- Export to clipboard

### 6.2 Export Format

If export is implemented:
```json
{
  "version": "1.0",
  "exported_at": "2026-01-04T12:00:00Z",
  "encryption": "AES-256-GCM",
  "kdf": "PBKDF2-SHA256",
  "iterations": 100000,
  "salt": "<base64url>",
  "nonce": "<base64url>",
  "ciphertext": "<base64url encrypted key material>"
}
```

**Hard rule:** Export MUST be encrypted with PBKDF2 (min 100k iterations) or Argon2id.

---

## 7. Logging & Debugging (Normative)

### 7.1 Forbidden in Logs

**NEVER log:**
- Private keys (Ed25519, X25519)
- DH outputs (`DH1`, `DH2`, `DH3`, `DH4`)
- Root/chain/message keys
- Nonces (derived)
- AAD bytes (raw)
- Plaintexts
- Session binding material

**Allowed:**
- Public keys (fingerprints only, not full keys)
- Key IDs (`device_id`, `spk_id`, `otp_id`)
- Key state transitions (e.g., "SPK rotated")
- Error codes

### 7.2 Debug Builds

**Recommendation:**
- Use compile-time flags: `#if DEBUG`
- Log only metadata (not secrets)
- Disable verbose crypto logging in release builds

---

## 8. Threat Model Considerations (Normative)

### 8.1 Platform Compromise

**Scenario:** OS-level keylogger or jailbreak/root access

**Mitigations:**
- Use hardware-backed KeyStore (Android TEE, iOS Secure Enclave)
- Jailbreak/root detection (optional, can be bypassed)
- Server-side anomaly detection (unusual activity patterns)

**Residual risk:** Platform compromise defeats local storage protection.

### 8.2 Memory Dump Attacks

**Scenario:** Debugger attached, memory dump captured

**Mitigations:**
- Zeroize keys after use (best-effort)
- Anti-debugging protections (optional, fragile)
- Minimize key lifetime in memory

**Residual risk:** Determined attacker with physical access can extract keys from memory.

### 8.3 Backup Leakage

**Scenario:** Unencrypted backup stored on untrusted cloud

**Mitigations:**
- Use platform-encrypted backups only
- Opt-in for iCloud Keychain sync (user choice)
- Never auto-sync identity keys to untrusted storage

---

## 9. Platform-Specific Hardening (Recommendations)

### 9.1 iOS

- Enable Data Protection (`NSFileProtectionComplete`)
- Use `kSecAttrAccessControl` with biometric flags
- Store keys in Secure Enclave if available (iOS 9+)

### 9.2 Android

- Use StrongBox-backed KeyStore (Android 9+)
- Enable `setUnlockedDeviceRequired(true)` for critical keys
- Use `setUserAuthenticationRequired(true)` + `setUserAuthenticationValidityDurationSeconds(30)`

### 9.3 Desktop

- macOS: Use Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Windows: Use DPAPI with `CryptProtectData`
- Linux: Use Secret Service API (GNOME Keyring, KWallet)

---

## 10. Compliance Checklist (Fail-Closed)

- [ ] Identity keys stored in platform secure storage (Keychain/KeyStore)
- [ ] Zeroization implemented (best-effort on all platforms)
- [ ] Access control enforced (biometric or passcode)
- [ ] No plaintext keys in logs (even in debug builds)
- [ ] Encrypted export only (if export feature exists)
- [ ] Session keys in encrypted DB with master key in Keychain

---
