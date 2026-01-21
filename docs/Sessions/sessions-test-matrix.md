# Sessions Test Matrix (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Comprehensive test scenarios for session and ratchet operations
**Applies to:** All C6P v1 implementations (unit, integration, E2E tests)

---

## 0. Test Organization

Tests are grouped by:
- **Unit tests**: Individual functions (key derivation, counter increment)
- **Integration tests**: Multi-component flows (send → encrypt → persist)
- **E2E tests**: Full protocol flows (handshake → messaging → session close)
- **Negative tests**: Error conditions, invalid inputs, attacks

---

## 1. Session Lifecycle Tests

### SL-001: Create Session

**Type:** Integration

**Setup:**
- Complete IslandAccord handshake
- Derive root_key and session_binding

**Steps:**
1. Create new session with `session_id`, `initiator_device_id`, `responder_device_id`
2. Initialize `i2r` and `r2i` stream states (CK from root_key)
3. Persist session state

**Assert:**
- Session state stored with `state = ACTIVE`
- Both streams have `send_counter = 0`, `recv_expected = 0`
- `consumed` set is empty

---

### SL-002: Load Session

**Type:** Unit

**Setup:**
- Persisted session from SL-001

**Steps:**
1. Load session by `session_id`
2. Decrypt state blob
3. Parse `PersistedSession` struct

**Assert:**
- All fields match persisted values
- `state_version = 1`
- `root_key` and `chain_key` recovered correctly

---

### SL-003: Suspend Session

**Type:** Integration

**Setup:**
- Active session

**Steps:**
1. Call `suspend_session(session_id)`
2. Update state to `SUSPENDED`
3. Persist

**Assert:**
- State transitions to `SUSPENDED`
- Session cannot send/receive messages (reject with `C6P.SESSION.SUSPENDED`)

---

### SL-004: Resume Session

**Type:** Integration

**Setup:**
- Suspended session from SL-003

**Steps:**
1. Call `resume_session(session_id)`
2. Update state to `ACTIVE`
3. Persist

**Assert:**
- State transitions to `ACTIVE`
- Messages can be sent/received again

---

### SL-005: Expire Session (TTL)

**Type:** Integration

**Setup:**
- Active session with `last_activity = now() - 91 days`

**Steps:**
1. Run cleanup job
2. Check if session TTL exceeded (default 90 days)
3. Update state to `EXPIRED`

**Assert:**
- State transitions to `EXPIRED`
- Session cannot be resumed (reject with `C6P.SESSION.EXPIRED`)

---

### SL-006: Terminate Session

**Type:** Integration

**Setup:**
- Active session

**Steps:**
1. Call `terminate_session(session_id)`
2. Update state to `TERMINATED`
3. Overwrite keys (zeroize)
4. Delete from storage

**Assert:**
- Session deleted
- Keys zeroized (best-effort check)
- Cannot be reactivated

---

### SL-007: Invalid State Transition

**Type:** Negative

**Setup:**
- Terminated session

**Steps:**
1. Attempt `resume_session(session_id)` on `TERMINATED` session

**Assert:**
- Reject with `C6P.SESSION.INVALID_STATE_TRANSITION`

---

## 2. Ratchet Send Tests

### RS-001: First Message Send

**Type:** Unit

**Setup:**
- Fresh session (`i2r` stream: `send_counter = 0`)

**Steps:**
1. Call `send_message(i2r, "Hello")`
2. Derive message key from `CK` + counter 0
3. Encrypt with AEAD
4. Advance `send_counter` to 1, update `CK`

**Assert:**
- Envelope has `counter = 0`
- Ciphertext authenticates with correct AAD
- `send_counter = 1` after send

---

### RS-002: Sequential Sends

**Type:** Integration

**Setup:**
- Session from RS-001

**Steps:**
1. Send messages: "msg1", "msg2", "msg3"

**Assert:**
- Counters: 1, 2, 3 (strictly increasing)
- Each has unique `CK` (chain key advanced)
- No counter reuse

---

### RS-003: Concurrent Send (Same Stream)

**Type:** Concurrency / Negative

**Setup:**
- Session with `send_counter = 0`
- Spawn 100 threads, each sends 1 message on `i2r`

**Steps:**
1. Threads attempt concurrent sends
2. Lock serializes counter increments

**Assert:**
- All 100 envelopes have unique counters (0..99)
- No duplicate counters
- `send_counter = 100` after all sends

---

### RS-004: Cross-Stream Parallel Sends

**Type:** Concurrency

**Setup:**
- Session with `i2r.send_counter = 0`, `r2i.send_counter = 0`

**Steps:**
1. Thread A sends on `i2r`
2. Thread B sends on `r2i` (simultaneously)

**Assert:**
- Both sends succeed without blocking each other
- `i2r` envelope has counter 0, `r2i` envelope has counter 0
- Independent streams

---

### RS-005: Send After Crash Recovery

**Type:** Integration

**Setup:**
- Session with `send_counter = 42` persisted
- Simulate app restart

**Steps:**
1. Load session from storage
2. Send next message

**Assert:**
- First post-restart envelope has `counter = 42`
- No counter reuse (gap acceptable if send failed before persist)

---

## 3. Ratchet Receive Tests

### RR-001: In-Order Receive

**Type:** Unit

**Setup:**
- Session with `recv_expected = 0`

**Steps:**
1. Receive envelope with `counter = 0`
2. Derive key, decrypt
3. Mark counter consumed, advance `recv_expected` to 1

**Assert:**
- Plaintext recovered
- `recv_expected = 1`
- `consumed = {0}`

---

### RR-002: Out-of-Order Receive

**Type:** Integration

**Setup:**
- Session with `recv_expected = 0`

**Steps:**
1. Receive counters: 0, 2, 1 (out of order)

**Assert:**
- All decrypt successfully
- After receiving 0: `recv_expected = 1`, `consumed = {0}`
- After receiving 2: `recv_expected = 1`, `consumed = {0, 2}`
- After receiving 1: `recv_expected = 3`, `consumed = {0, 1, 2}`

---

### RR-003: Skip-Forward Receive

**Type:** Integration

**Setup:**
- Session with `recv_expected = 0`

**Steps:**
1. Receive counter = 100 (skip 0..99)

**Assert:**
- Within skip-window (2048), accept
- `recv_expected = 0` (no in-order messages yet)
- `consumed = {100}`

---

### RR-004: Skip-Window Exceeded

**Type:** Negative

**Setup:**
- Session with `recv_expected = 0`

**Steps:**
1. Receive counter = 3000 (exceeds skip-window of 2048)

**Assert:**
- Reject with `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`
- State unchanged

---

### RR-005: Replay Attack

**Type:** Negative

**Setup:**
- Session with `consumed = {42}`

**Steps:**
1. Receive envelope with `counter = 42` (duplicate)

**Assert:**
- Reject immediately with `C6P.RATCHET.REPLAY_DETECTED`
- Do not attempt decryption

---

### RR-006: Counter Below Window

**Type:** Negative

**Setup:**
- Session with `recv_expected = 3000`

**Steps:**
1. Receive counter = 5 (below `recv_expected - SKIP_WINDOW`)

**Assert:**
- Reject with `C6P.RATCHET.COUNTER_BELOW_WINDOW`

---

### RR-007: Decryption Failure (Tampered Ciphertext)

**Type:** Negative

**Setup:**
- Valid envelope with counter = 0
- Flip 1 byte in ciphertext

**Steps:**
1. Attempt to decrypt

**Assert:**
- AEAD.Open fails
- Reject with `C6P.RATCHET.DECRYPTION_FAILED`
- State unchanged (counter NOT marked consumed)

---

### RR-008: Wrong AAD

**Type:** Negative

**Setup:**
- Envelope with counter = 0
- Construct AAD with wrong `stream_id`

**Steps:**
1. Attempt decrypt

**Assert:**
- AEAD fails (AAD mismatch)
- Reject with `C6P.RATCHET.DECRYPTION_FAILED`

---

## 4. Concurrency Tests

### CT-001: Concurrent Receives (Different Counters)

**Type:** Concurrency

**Setup:**
- Session with `recv_expected = 0`
- 10 threads, each receives different counter (0..9)

**Steps:**
1. Threads decrypt concurrently
2. State updates serialized (consumed set)

**Assert:**
- All 10 messages decrypt successfully
- `recv_expected = 10` after all complete
- `consumed = {0..9}`

---

### CT-002: Concurrent Send + Receive

**Type:** Concurrency

**Setup:**
- Session
- Thread A sends on `i2r`, Thread B receives on `r2i`

**Steps:**
1. Run simultaneously

**Assert:**
- Both succeed
- Independent streams, no lock contention

---

### CT-003: Lock Contention Under High Load

**Type:** Performance / Stress

**Setup:**
- Session
- 1000 sends on `i2r` (concurrent threads)

**Steps:**
1. Measure lock wait time
2. Ensure no deadlocks

**Assert:**
- All sends complete (no deadlock)
- Counters 0..999 all unique
- Latency acceptable (p99 < 100ms)

---

## 5. Storage Tests

### ST-001: Atomic Persistence

**Type:** Integration

**Setup:**
- Session with `send_counter = 10`

**Steps:**
1. Start send operation
2. Simulate crash after CK updated but before persist
3. Restart, load session

**Assert:**
- Loaded state shows `send_counter = 10` (not 11)
- No partial update

---

### ST-002: Encryption at Rest

**Type:** Security

**Setup:**
- Session persisted

**Steps:**
1. Read raw storage file
2. Verify contents are encrypted

**Assert:**
- No plaintext keys in file
- AES-GCM ciphertext + nonce present

---

### ST-003: Corrupted State Load

**Type:** Negative

**Setup:**
- Corrupt session state file (invalid JSON)

**Steps:**
1. Attempt to load session

**Assert:**
- Reject with `C6P.SESSION.STORAGE_CORRUPTION`
- Do not crash

---

### ST-004: Master Key Unavailable

**Type:** Negative

**Setup:**
- Session state encrypted with master key
- Master key deleted from Keychain/KeyStore

**Steps:**
1. Attempt to load session

**Assert:**
- Reject with `C6P.SESSION.STORAGE_DECRYPTION_FAILED`

---

## 6. State Machine Tests

### SM-001: Full Lifecycle

**Type:** E2E

**Steps:**
1. Create session → `ACTIVE`
2. Send/receive messages
3. Suspend → `SUSPENDED`
4. Resume → `ACTIVE`
5. Terminate → `TERMINATED`

**Assert:**
- All state transitions valid
- Messages only sent/received in `ACTIVE` state

---

### SM-002: Expired Session Cleanup

**Type:** Integration

**Setup:**
- 100 sessions, 50 with `last_activity > 90 days ago`

**Steps:**
1. Run cleanup job
2. Mark expired sessions

**Assert:**
- 50 sessions marked `EXPIRED`
- 50 remain `ACTIVE`

---

## 7. Error Handling Tests

### EH-001: Session Not Found

**Type:** Negative

**Steps:**
1. Attempt to send message on non-existent `session_id`

**Assert:**
- Reject with `C6P.SESSION.NOT_FOUND`

---

### EH-002: Invalid Stream ID

**Type:** Negative

**Steps:**
1. Receive envelope with `stream_id = 99` (invalid)

**Assert:**
- Reject with `C6P.RATCHET.INVALID_STREAM_ID`

---

### EH-003: Storage Conflict (Optimistic Lock)

**Type:** Negative / Concurrency

**Setup:**
- Session with state version 42

**Steps:**
1. Thread A loads state (version 42)
2. Thread B updates state (version 43)
3. Thread A attempts to persist (expects version 42)

**Assert:**
- Thread A gets `C6P.SESSION.STORAGE_CONFLICT`
- Thread A retries

---

## 8. Security Tests

### SEC-001: Replay Resistance

**Type:** Security

**Steps:**
1. Capture envelope with counter = 10
2. Replay 100 times

**Assert:**
- First receive succeeds
- Next 99 rejected with `C6P.RATCHET.REPLAY_DETECTED`

---

### SEC-002: Forward Secrecy

**Type:** Security

**Setup:**
- Session with 100 messages sent

**Steps:**
1. Compromise current `CK` (at counter 100)
2. Attempt to decrypt message at counter 50

**Assert:**
- Cannot derive old message keys from current CK
- Past messages remain secure

---

### SEC-003: No Counter Reuse

**Type:** Security

**Steps:**
1. Send 1000 messages
2. Check all counters unique

**Assert:**
- No duplicate counters
- No nonce reuse (breaks AEAD security)

---

## 9. Interoperability Tests

### INTEROP-001: Cross-Implementation Send/Receive

**Type:** E2E

**Setup:**
- Device A: Rust implementation
- Device B: Swift implementation

**Steps:**
1. A sends message to B
2. B decrypts and replies
3. A receives reply

**Assert:**
- Both decrypt successfully
- Compatible key derivation, AEAD, encoding

---

### INTEROP-002: State Migration

**Type:** Integration

**Setup:**
- Device A exports encrypted session state
- Device B imports state

**Steps:**
1. A persists session
2. B loads session (same master password)
3. B sends message using imported state

**Assert:**
- Counters continue from A's last state
- No counter collision

---

## 10. Performance Benchmarks

### PERF-001: Send Throughput

**Goal:** Measure max messages/second

**Setup:**
- Session
- 10,000 small messages (100 bytes each)

**Benchmark:**
- Time to send all messages

**Target:** > 1000 msg/sec (single-threaded)

---

### PERF-002: Receive Latency

**Goal:** Measure decryption latency

**Setup:**
- Pre-generated envelopes (counters 0..1000)

**Benchmark:**
- Time to decrypt each (p50, p95, p99)

**Target:** p99 < 5ms

---

## 11. Compliance Checklist

- [ ] All test cases pass (unit, integration, E2E)
- [ ] Negative tests cover all error codes
- [ ] Concurrency tests pass (no race conditions)
- [ ] Security tests validate replay, forward secrecy, counter uniqueness
- [ ] Performance meets targets (throughput, latency)
- [ ] Interop tests pass (cross-implementation compatibility)

---

## 12. Test Automation

**CI/CD Integration:**
- Run all tests on every commit
- Fail build if any test fails
- Generate coverage report (target: > 90%)

**Test Vectors:**
- Use deterministic test vectors from `docs/Sessions/test-vectors/` (to be created)

---

## 13. References

- Session overview: `docs/Sessions/sessions-overview.md`
- Ratchet state machine: `docs/Sessions/dm-ratchet-state-machine.md`
- Error codes: `docs/Sessions/sessions-error-codes.md`
- Storage contract: `docs/Sessions/session-storage-contract.md`

---
