# Session Storage Contract (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Persistent storage requirements for C6P session state
**Applies to:** All C6P v1 implementations (iOS, Android, server, desktop)

---

## 0. Purpose

This document defines the **storage contract** for C6P session state. It specifies:
- What MUST be persisted
- Atomicity requirements
- Encryption at rest
- Platform-specific guidance (iOS Keychain, Android KeyStore, server DBs)
- Backup and migration policies

---

## 1. Storage Requirements (Normative)

### 1.1 Session State Components

Each active session MUST persist:

```rust
struct PersistedSession {
    // Session identity
    session_id: [u8; 8],
    initiator_device_id: [u8; 16],
    responder_device_id: [u8; 16],

    // Handshake-derived secrets
    root_key: [u8; 32],                 // Master secret from KC
    session_binding: [u8; 32],          // SHA-256 of session identity

    // Ratchet state (per stream)
    i2r_state: StreamState,
    r2i_state: StreamState,

    // Metadata
    suite_id: u16,
    created_at: u64,                    // Unix timestamp (seconds)
    last_activity: u64,
    state: SessionLifecycleState,       // ACTIVE, SUSPENDED, etc.
    state_version: u8,                  // Always 1 for v1
}

struct StreamState {
    stream_id: u8,
    chain_key: [u8; 32],
    send_counter: u64,
    recv_expected: u64,
    consumed: Vec<u64>,                 // Or bitmap representation
}
```

### 1.2 Atomicity (MUST)

**Hard rule:** All state updates MUST be atomic.

**Failure modes to prevent:**
- Partial counter update (counter incremented but CK not saved)
- Inconsistent consumed set (message marked consumed but recv_expected not advanced)
- Orphaned state (session deleted but stream state remains)

**Implementation:** Use transactions, write-ahead logs, or atomic file operations.

---

## 2. Encryption at Rest (Normative)

### 2.1 Key Material Protection

**Hard rule:** All session state MUST be encrypted at rest.

**Components requiring encryption:**
- `root_key`
- `chain_key` (both streams)
- Any cached intermediate keys

**Exempt from encryption:** Non-secret metadata (session_id, timestamps, state)

### 2.2 Master Encryption Key

**Derivation:** Platform-specific

**iOS:**
- Store master key in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Use `kSecAttrAccessControl` with biometric protection if available
- Never export master key outside Secure Enclave

**Android:**
- Use AndroidKeyStore with `setUserAuthenticationRequired(true)`
- Hardware-backed if available (TEE/StrongBox)
- Key alias: `c6p_session_master_key_v1`

**Server/Desktop:**
- Derive master key from user password via PBKDF2-HMAC-SHA256 (min 100k iterations)
- Store salt separately, never alongside encrypted state
- Consider HSM integration for production servers

### 2.3 Encryption Scheme

**Algorithm:** AES-256-GCM

**Construction:**
```
key = master_key (256 bits from Keychain/KeyStore)
nonce = random(96 bits) per session state blob
AAD = "C6P_SESSION_STORAGE_V1" || session_id
ciphertext = AES-GCM.Encrypt(key, nonce, plaintext_state, AAD)
stored_blob = nonce || ciphertext || tag
```

**On load:**
```
(nonce, ciphertext, tag) = parse(stored_blob)
plaintext_state = AES-GCM.Decrypt(master_key, nonce, ciphertext, AAD)
```

---

## 3. Platform-Specific Guidance (Normative)

### 3.1 iOS (Swift + CoreData / SQLite)

**Storage backend:** SQLite with encrypted WAL mode

**Setup:**
```swift
// Enable encrypted WAL
let options = [
    NSDictionary(contentsOf: Bundle.main.url(forResource: "EncryptedSQLite", withExtension: "plist")!)!,
    NSPersistentStoreFileProtectionKey: FileProtectionType.completeUntilFirstUserAuthentication
]
```

**Keychain integration:**
```swift
let masterKey = try Keychain.load(
    service: "com.convro.c6p",
    account: "session_master_key_v1",
    accessControl: [.biometryAny, .devicePasscode]
)
```

**Atomic writes:**
- Use Core Data transactions or SQLite `BEGIN IMMEDIATE` transactions
- Commit only after all state components updated

### 3.2 Android (Kotlin + Room)

**Storage backend:** Room (SQLite) with encrypted database

**Setup:**
```kotlin
val passphrase = KeyStore.getKey("c6p_session_master_key_v1")
val database = Room.databaseBuilder(context, SessionDatabase::class.java, "c6p_sessions.db")
    .openHelperFactory(SupportFactory(passphrase))
    .build()
```

**KeyStore integration:**
```kotlin
val keyGenerator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
val keySpec = KeyGenParameterSpec.Builder(
    "c6p_session_master_key_v1",
    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
)
    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
    .setUserAuthenticationRequired(true)
    .setUserAuthenticationValidityDurationSeconds(300)
    .build()
keyGenerator.init(keySpec)
keyGenerator.generateKey()
```

**Atomic writes:**
- Use Room `@Transaction` annotation
- Wrap multi-table updates in `database.runInTransaction { ... }`

### 3.3 Server (Rust + PostgreSQL / SQLite)

**Storage backend:** PostgreSQL with `pgcrypto` or SQLite with `SQLCipher`

**PostgreSQL example:**
```sql
CREATE TABLE sessions (
    session_id BYTEA PRIMARY KEY,
    encrypted_state BYTEA NOT NULL,
    nonce BYTEA NOT NULL,
    created_at BIGINT NOT NULL,
    last_activity BIGINT NOT NULL,
    state TEXT NOT NULL,  -- 'ACTIVE', 'SUSPENDED', etc.
    state_version INT NOT NULL DEFAULT 1
);

CREATE INDEX idx_sessions_last_activity ON sessions(last_activity);
```

**Atomic writes:**
```rust
let mut tx = pool.begin().await?;
sqlx::query!(
    "UPDATE sessions SET encrypted_state = $1, nonce = $2, last_activity = $3 WHERE session_id = $4",
    encrypted_state, nonce, now(), session_id
).execute(&mut tx).await?;
tx.commit().await?;
```

---

## 4. Schema Versioning (Normative)

### 4.1 State Version Field

**Purpose:** Allow future schema migrations without breaking existing state

**Current version:** `state_version = 1`

**Loading logic:**
```rust
let state: PersistedSession = decrypt_and_parse(blob)?;
if state.state_version != 1 {
    return Err(SessionError::IncompatibleStateVersion {
        found: state.state_version,
        expected: 1,
    });
}
```

### 4.2 Future Migrations

**When state_version increments (hypothetical v2):**
1. Implement migration function: `migrate_v1_to_v2(v1_state) -> v2_state`
2. On load, check version and apply migration chain
3. Persist migrated state with new version

**Fallback:** If migration fails, mark session as `CORRUPTED` and refuse to load.

---

## 5. Backup and Export (Normative)

### 5.1 Encrypted Backup

**Allowed:** Sessions MAY be backed up if encrypted with user-controlled password.

**Scheme:**
```
backup_key = PBKDF2-HMAC-SHA256(user_password, salt, 100k iterations)
backup_blob = AES-256-GCM.Encrypt(backup_key, nonce, sessions_json, AAD="C6P_BACKUP_V1")
```

**Storage:** Cloud (iCloud, Google Drive) or local file

**Restore:**
- Prompt user for password
- Decrypt backup_blob
- Import sessions with integrity checks

### 5.2 Export Restrictions

**NEVER export:**
- Unencrypted session state
- Raw `root_key` or `chain_key` in plaintext
- Session state to untrusted apps (no inter-app sharing)

**Acceptable exports:**
- Encrypted backups (user password)
- Session metadata (session_id, timestamps) without keys

---

## 6. Cleanup and Expiration (Normative)

### 6.1 TTL Policy

**Default TTL:** 90 days of inactivity (configurable per app)

**Cleanup logic:**
```rust
let cutoff = now() - TTL_SECONDS;
db.execute("DELETE FROM sessions WHERE last_activity < ? AND state = 'ACTIVE'", cutoff)?;
```

**Exceptions:** `SUSPENDED` sessions may have longer TTL (user preference)

### 6.2 Explicit Termination

**On session close (user action or policy):**
1. Update state to `TERMINATED`
2. Overwrite keys with zeros (best-effort zeroization)
3. Delete record from database
4. Emit `c6p.session.terminated` event

**Security:** Ensure deleted keys are not recoverable (use secure deletion APIs if available)

---

## 7. Multi-Device Sync (Future)

**v1 limitation:** Sessions are device-local, not synced across devices.

**Future (v2+):** May support encrypted session export/import for multi-device scenarios.

---

## 8. Crash Safety (Normative)

### 8.1 Write-Ahead Log (WAL)

**Recommendation:** Enable WAL mode for SQLite

```sql
PRAGMA journal_mode = WAL;
PRAGMA synchronous = FULL;
```

**Benefit:** Atomic commits survive process crashes

### 8.2 Fsync Requirements

**On critical writes:**
- Call `fsync()` / `FileHandle.synchronize()` after state updates
- Ensure data persisted to stable storage before proceeding

**Trade-off:** Slight performance cost vs. crash safety (choose safety)

---

## 9. Observability (Normative)

### 9.1 Storage Metrics

Emit metrics for:
- `c6p.storage.write.latency_ms` (p50, p95, p99)
- `c6p.storage.read.latency_ms`
- `c6p.storage.sessions.count` (gauge: active sessions)
- `c6p.storage.error.rate` (encryption failures, DB errors)

### 9.2 Audit Events

Log (without secrets):
- Session creation timestamp
- Last activity timestamp
- State transitions (ACTIVE → SUSPENDED)
- Deletion events

**Privacy:** Hash session_id for long-term logs

---

## 10. Compliance Checklist

- [ ] All session state encrypted at rest (AES-256-GCM)
- [ ] Master key stored in platform secure storage (Keychain/KeyStore)
- [ ] State updates are atomic (transactions or WAL)
- [ ] State version field included (`state_version=1`)
- [ ] TTL-based cleanup implemented (default 90 days)
- [ ] Crash-safe persistence (fsync + WAL)
- [ ] Backup exports are encrypted (user password)
- [ ] No plaintext keys in logs or error messages

---

## 11. Error Codes

See `docs/Sessions/sessions-error-codes.md`:
- `C6P.SESSION.STORAGE_ENCRYPTION_FAILED`
- `C6P.SESSION.STORAGE_CORRUPTION`
- `C6P.SESSION.INCOMPATIBLE_STATE_VERSION`

---

## 12. References

- Key storage: `docs/identity/key-storage-and-hardening.md`
- Session lifecycle: `docs/Sessions/sessions-overview.md`
- Error taxonomy: `docs/Sessions/sessions-error-codes.md`

---
