# Sessions Error Codes (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Canonical error codes for session and ratchet operations
**Applies to:** All C6P v1 implementations

---

## 0. Error Code Structure

All C6P error codes follow the namespace pattern:

```
C6P.<MODULE>.<SPECIFIC_ERROR>
```

**Example:** `C6P.SESSION.NOT_FOUND`

**Module namespaces for sessions:**
- `C6P.SESSION.*` — Session lifecycle, storage, state management
- `C6P.RATCHET.*` — Symmetric ratchet operations (send/receive)

---

## 1. Session Lifecycle Errors (`C6P.SESSION.*`)

### 1.1 Not Found

**Code:** `C6P.SESSION.NOT_FOUND`

**HTTP Status:** 404

**Trigger:** Attempted operation on non-existent session_id

**Recovery:** Verify session_id; may need to create new session

**Example:**
```json
{
  "error": "C6P.SESSION.NOT_FOUND",
  "details": {
    "session_id": "0123456789abcdef"
  }
}
```

---

### 1.2 Expired

**Code:** `C6P.SESSION.EXPIRED`

**HTTP Status:** 410 (Gone)

**Trigger:** Session TTL exceeded (default 90 days of inactivity)

**Recovery:** Create new session (expired session cannot be resumed)

**Example:**
```json
{
  "error": "C6P.SESSION.EXPIRED",
  "details": {
    "session_id": "0123456789abcdef",
    "expired_at": 1672531200,
    "ttl_seconds": 7776000
  }
}
```

---

### 1.3 Terminated

**Code:** `C6P.SESSION.TERMINATED`

**HTTP Status:** 410 (Gone)

**Trigger:** Session explicitly closed by user or policy

**Recovery:** Create new session (terminated session cannot be reactivated)

**Example:**
```json
{
  "error": "C6P.SESSION.TERMINATED",
  "details": {
    "session_id": "0123456789abcdef",
    "terminated_at": 1672531200,
    "reason": "user_request"
  }
}
```

---

### 1.4 Suspended

**Code:** `C6P.SESSION.SUSPENDED`

**HTTP Status:** 423 (Locked)

**Trigger:** Session paused by user (e.g., archived conversation)

**Recovery:** Resume session (if policy allows) or create new session

**Example:**
```json
{
  "error": "C6P.SESSION.SUSPENDED",
  "details": {
    "session_id": "0123456789abcdef",
    "suspended_at": 1672531200
  }
}
```

---

### 1.5 Already Exists

**Code:** `C6P.SESSION.ALREADY_EXISTS`

**HTTP Status:** 409 (Conflict)

**Trigger:** Attempted to create session with duplicate session_id

**Recovery:** Use existing session or generate new session_id

**Example:**
```json
{
  "error": "C6P.SESSION.ALREADY_EXISTS",
  "details": {
    "session_id": "0123456789abcdef"
  }
}
```

---

### 1.6 Invalid State Transition

**Code:** `C6P.SESSION.INVALID_STATE_TRANSITION`

**HTTP Status:** 400

**Trigger:** Illegal state transition (e.g., TERMINATED → ACTIVE)

**Recovery:** Check current state; may need new session

**Example:**
```json
{
  "error": "C6P.SESSION.INVALID_STATE_TRANSITION",
  "details": {
    "current_state": "TERMINATED",
    "attempted_state": "ACTIVE"
  }
}
```

---

### 1.7 Incompatible State Version

**Code:** `C6P.SESSION.INCOMPATIBLE_STATE_VERSION`

**HTTP Status:** 422 (Unprocessable Entity)

**Trigger:** Loaded state has unsupported `state_version` field

**Recovery:** Migration required, or create new session

**Example:**
```json
{
  "error": "C6P.SESSION.INCOMPATIBLE_STATE_VERSION",
  "details": {
    "found_version": 2,
    "expected_version": 1
  }
}
```

---

### 1.8 Storage Errors

#### Storage Encryption Failed

**Code:** `C6P.SESSION.STORAGE_ENCRYPTION_FAILED`

**HTTP Status:** 500

**Trigger:** Failed to encrypt session state during persistence

**Recovery:** Check master key availability (Keychain/KeyStore)

**Example:**
```json
{
  "error": "C6P.SESSION.STORAGE_ENCRYPTION_FAILED",
  "details": {
    "session_id": "0123456789abcdef",
    "cause": "master_key_unavailable"
  }
}
```

#### Storage Decryption Failed

**Code:** `C6P.SESSION.STORAGE_DECRYPTION_FAILED`

**HTTP Status:** 500

**Trigger:** Failed to decrypt session state on load

**Recovery:** Check master key; may indicate corruption

**Example:**
```json
{
  "error": "C6P.SESSION.STORAGE_DECRYPTION_FAILED",
  "details": {
    "session_id": "0123456789abcdef",
    "cause": "aead_open_failed"
  }
}
```

#### Storage Corruption

**Code:** `C6P.SESSION.STORAGE_CORRUPTION`

**HTTP Status:** 500

**Trigger:** State file corrupted (checksum mismatch, invalid format)

**Recovery:** Delete corrupted session, create new session

**Example:**
```json
{
  "error": "C6P.SESSION.STORAGE_CORRUPTION",
  "details": {
    "session_id": "0123456789abcdef",
    "cause": "invalid_json"
  }
}
```

#### Storage Conflict

**Code:** `C6P.SESSION.STORAGE_CONFLICT`

**HTTP Status:** 409

**Trigger:** Optimistic lock failure (concurrent state update)

**Recovery:** Retry operation

**Example:**
```json
{
  "error": "C6P.SESSION.STORAGE_CONFLICT",
  "details": {
    "session_id": "0123456789abcdef",
    "expected_version": 42,
    "found_version": 43
  }
}
```

---

## 2. Ratchet Errors (`C6P.RATCHET.*`)

### 2.1 Replay Detected

**Code:** `C6P.RATCHET.REPLAY_DETECTED`

**HTTP Status:** 400

**Trigger:** Received message with counter already in `consumed` set

**Recovery:** Reject message; likely replay attack or duplicate network delivery

**Example:**
```json
{
  "error": "C6P.RATCHET.REPLAY_DETECTED",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1,
    "counter": 42,
    "recv_expected": 50
  }
}
```

---

### 2.2 Skip Window Exceeded

**Code:** `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`

**HTTP Status:** 400

**Trigger:** Received counter outside allowed range: `|counter - recv_expected| > SKIP_WINDOW`

**Recovery:** Sender should resend missing messages or renegotiate session

**Example:**
```json
{
  "error": "C6P.RATCHET.SKIP_WINDOW_EXCEEDED",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1,
    "counter": 5000,
    "recv_expected": 42,
    "skip_window": 2048
  }
}
```

---

### 2.3 Counter Below Window

**Code:** `C6P.RATCHET.COUNTER_BELOW_WINDOW`

**HTTP Status:** 400

**Trigger:** Received counter older than `recv_expected - SKIP_WINDOW`

**Recovery:** Reject message (too old, may be replay attempt)

**Example:**
```json
{
  "error": "C6P.RATCHET.COUNTER_BELOW_WINDOW",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1,
    "counter": 5,
    "recv_expected": 2100,
    "skip_window": 2048
  }
}
```

---

### 2.4 Invalid Stream ID

**Code:** `C6P.RATCHET.INVALID_STREAM_ID`

**HTTP Status:** 400

**Trigger:** Received envelope with stream_id not in {0x01, 0x02}

**Recovery:** Reject message (protocol violation)

**Example:**
```json
{
  "error": "C6P.RATCHET.INVALID_STREAM_ID",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 99,
    "expected": [1, 2]
  }
}
```

---

### 2.5 Decryption Failed

**Code:** `C6P.RATCHET.DECRYPTION_FAILED`

**HTTP Status:** 400

**Trigger:** AEAD.Open failed (authentication tag mismatch)

**Recovery:** Reject message; may indicate tampering or wrong key

**Example:**
```json
{
  "error": "C6P.RATCHET.DECRYPTION_FAILED",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1,
    "counter": 42,
    "cause": "aead_tag_mismatch"
  }
}
```

---

### 2.6 Chain Key Derivation Failed

**Code:** `C6P.RATCHET.CHAIN_KEY_DERIVATION_FAILED`

**HTTP Status:** 500

**Trigger:** HKDF failed during chain key or message key derivation

**Recovery:** Internal error; log and investigate

**Example:**
```json
{
  "error": "C6P.RATCHET.CHAIN_KEY_DERIVATION_FAILED",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1,
    "counter": 42,
    "cause": "hkdf_expand_failed"
  }
}
```

---

## 3. Stream Errors (`C6P.STREAM.*`)

### 3.1 Stream Not Initialized

**Code:** `C6P.STREAM.NOT_INITIALIZED`

**HTTP Status:** 500

**Trigger:** Attempted operation on stream before handshake completed

**Recovery:** Complete handshake first

**Example:**
```json
{
  "error": "C6P.STREAM.NOT_INITIALIZED",
  "details": {
    "session_id": "0123456789abcdef",
    "stream_id": 1
  }
}
```

---

### 3.2 Wrong Direction

**Code:** `C6P.STREAM.WRONG_DIRECTION`

**HTTP Status:** 400

**Trigger:** Initiator attempted to send on `r2i` stream (or vice versa)

**Recovery:** Use correct stream for device role

**Example:**
```json
{
  "error": "C6P.STREAM.WRONG_DIRECTION",
  "details": {
    "device_role": "initiator",
    "attempted_stream": "r2i",
    "allowed_stream": "i2r"
  }
}
```

---

## 4. Error Response Format (Wire Protocol)

**HTTP errors:**
```http
HTTP/1.1 400 Bad Request
Content-Type: application/json

{
  "error": "C6P.RATCHET.REPLAY_DETECTED",
  "details": {
    "session_id": "0123456789abcdef",
    "counter": 42
  },
  "timestamp": 1672531200
}
```

**Local SDK errors (Rust):**
```rust
pub enum SessionError {
    NotFound { session_id: SessionId },
    Expired { session_id: SessionId, expired_at: u64 },
    ReplayDetected { counter: u64, stream_id: u8 },
    SkipWindowExceeded { counter: u64, recv_expected: u64 },
    // ... etc.
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, f: &mut std::fmt::Formatter) -> std::fmt::Result {
        match self {
            SessionError::NotFound { session_id } => {
                write!(f, "C6P.SESSION.NOT_FOUND: session_id={}", hex::encode(session_id))
            }
            // ... etc.
        }
    }
}
```

---

## 5. Client Handling Guidance

### 5.1 Retryable Errors

**Retry with exponential backoff:**
- `C6P.SESSION.STORAGE_CONFLICT` (optimistic lock failure)
- Network timeouts (not C6P errors, but relevant)

**Retry limit:** 3 attempts, then fail

### 5.2 Terminal Errors (Do Not Retry)

**Fail immediately:**
- `C6P.SESSION.EXPIRED`
- `C6P.SESSION.TERMINATED`
- `C6P.RATCHET.REPLAY_DETECTED`
- `C6P.RATCHET.DECRYPTION_FAILED`

### 5.3 User-Facing Messages

**Mapping C6P errors to user messages:**

| Error Code | User Message |
|------------|--------------|
| `C6P.SESSION.NOT_FOUND` | "Session not found. Please restart the conversation." |
| `C6P.SESSION.EXPIRED` | "This conversation has expired. Start a new one?" |
| `C6P.RATCHET.REPLAY_DETECTED` | "Security error: duplicate message detected." |
| `C6P.RATCHET.SKIP_WINDOW_EXCEEDED` | "Message out of order. Please resend missing messages." |
| `C6P.SESSION.STORAGE_CORRUPTION` | "Session data corrupted. Creating new session..." |

---

## 6. Observability

### 6.1 Error Metrics

**Track error rates by code:**
- `c6p.session.error.rate{code="C6P.SESSION.NOT_FOUND"}`
- `c6p.ratchet.error.rate{code="C6P.RATCHET.REPLAY_DETECTED"}`

### 6.2 Alerts

**Critical errors (page on-call):**
- `C6P.SESSION.STORAGE_CORRUPTION` (data integrity issue)
- Spike in `C6P.RATCHET.REPLAY_DETECTED` (potential attack)

**Warning alerts:**
- High rate of `C6P.RATCHET.SKIP_WINDOW_EXCEEDED` (network issues?)

---

## 7. Compliance Checklist

- [ ] All errors use canonical `C6P.*` namespace
- [ ] Error responses include structured details (session_id, counter, etc.)
- [ ] No secret leakage in error messages (keys, nonces, plaintexts)
- [ ] HTTP status codes align with error semantics (404, 410, 400, 500)
- [ ] Retryable vs. terminal errors clearly documented

---

## 8. References

- Session lifecycle: `docs/Sessions/sessions-overview.md`
- Ratchet state machine: `docs/Sessions/dm-ratchet-state-machine.md`
- Crypto error codes: `docs/crypto/c6p-error-codes.md`
- Handshake error codes: `docs/handshake/island-accord-error-codes.md`

---
