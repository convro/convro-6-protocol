# Concurrency and Ordering (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Multi-threaded send/receive, message ordering guarantees, race condition handling
**Applies to:** All C6P v1 implementations

---

## 0. Purpose

This document defines **concurrency** and **ordering** semantics for C6P v1 sessions. It specifies:
- Allowed concurrency patterns (send/receive parallelism)
- Ordering guarantees (what is guaranteed vs. best-effort)
- Synchronization requirements (locks, atomics)
- Race condition handling

---

## 1. Design Principles (Non-Negotiable)

1. **Counter uniqueness**: No two messages in a stream share the same counter (enforced by serialization)
2. **Atomic state updates**: State transitions are all-or-nothing
3. **Out-of-order tolerance**: Receivers accept messages within skip-window (2048)
4. **No global ordering**: No guarantees across different sessions or streams
5. **Fail-closed on race**: If synchronization fails, abort operation

---

## 2. Send Concurrency (Normative)

### 2.1 Per-Stream Serialization (MUST)

**Rule:** At most **one send operation** per stream at a time.

**Reason:** Counter increments must be serialized to ensure uniqueness.

**Implementation:**
```rust
struct StreamSendLock {
    stream_id: u8,
    mutex: Mutex<StreamState>,
}

fn send_message(stream: &StreamSendLock, payload: &[u8]) -> Result<Envelope> {
    let mut state = stream.mutex.lock()?;  // Block until available
    let counter = state.send_counter;
    let envelope = encrypt_and_build(state, payload)?;
    state.send_counter += 1;  // Atomic increment under lock
    state.chain_key = derive_next_ck(&state.chain_key, counter);
    persist_atomically(&state)?;
    Ok(envelope)
}
```

**Anti-pattern (FORBIDDEN):**
```rust
// WRONG: Concurrent sends to same stream
thread::spawn(|| send_message(i2r_stream, msg1));
thread::spawn(|| send_message(i2r_stream, msg2));
// Risk: Both threads may use counter=42, breaking uniqueness
```

### 2.2 Cross-Stream Parallelism (Allowed)

**Rule:** Sends to **different streams** (`i2r` vs `r2i`) MAY run concurrently.

**Example:**
```rust
// CORRECT: Parallel sends to i2r and r2i
let handle1 = thread::spawn(|| send_message(i2r_stream, msg1));
let handle2 = thread::spawn(|| send_message(r2i_stream, msg2));
handle1.join()?;
handle2.join()?;
```

**Safety:** Each stream has independent state and lock.

---

## 3. Receive Concurrency (Normative)

### 3.1 Out-of-Order Processing (Allowed)

**Rule:** Receivers MAY process messages concurrently if:
1. Counter validation is serialized (check consumed set atomically)
2. State persistence is serialized

**Example:**
```rust
fn receive_message(stream: &StreamReceiveLock, envelope: Envelope) -> Result<Plaintext> {
    let counter = envelope.counter;

    // Step 1: Validate counter (MUST be atomic)
    {
        let state = stream.mutex.lock()?;
        if state.consumed.contains(counter) {
            return Err(ReplayDetected);
        }
        if counter > state.recv_expected + SKIP_WINDOW {
            return Err(SkipWindowExceeded);
        }
    }

    // Step 2: Derive key and decrypt (can be parallel for different counters)
    let ck_at_counter = derive_ck_for_counter(&stream, counter)?;
    let plaintext = decrypt(ck_at_counter, envelope)?;

    // Step 3: Update state (MUST be atomic)
    {
        let mut state = stream.mutex.lock()?;
        state.consumed.insert(counter);
        if counter == state.recv_expected {
            state.recv_expected = advance_to_next_gap(&state.consumed, counter);
        }
        persist_atomically(&state)?;
    }

    Ok(plaintext)
}
```

**Optimization:** Decrypt multiple messages in parallel (step 2) before serializing state updates (step 3).

### 3.2 In-Order Delivery (Best-Effort)

**Guarantee:** C6P does NOT guarantee in-order delivery to application layer.

**Reasoning:** Network may reorder packets; C6P allows out-of-order processing within skip-window.

**Application layer:** If app requires ordering, buffer messages and deliver when gaps filled.

**Example (app-layer ordering):**
```rust
struct OrderedBuffer {
    next_expected: u64,
    buffered: HashMap<u64, Plaintext>,
}

fn deliver_in_order(buffer: &mut OrderedBuffer, counter: u64, plaintext: Plaintext) -> Vec<Plaintext> {
    buffer.buffered.insert(counter, plaintext);
    let mut deliverable = Vec::new();

    while let Some(msg) = buffer.buffered.remove(&buffer.next_expected) {
        deliverable.push(msg);
        buffer.next_expected += 1;
    }

    deliverable
}
```

---

## 4. Ordering Guarantees (Normative)

### 4.1 Per-Stream Ordering

**Guaranteed:**
- Counters are strictly increasing on send
- Counters are unique within a stream

**NOT guaranteed:**
- Delivery order matches send order (network may reorder)
- All messages eventually arrive (network may drop)

### 4.2 Cross-Stream Ordering

**NO guarantees:** Messages on `i2r` and `r2i` are independent.

**Example:**
- Timon sends msg1 on `i2r` (counter=10)
- Peter sends msg2 on `r2i` (counter=20)
- Timon may receive msg2 before sending msg1 (no causality enforcement)

**Application layer:** Use explicit sequence numbers or vector clocks if cross-stream causality needed.

### 4.3 Cross-Session Ordering

**NO guarantees:** Messages from different sessions are independent.

**Example:**
- Session A sends msg1
- Session B sends msg2
- No defined order between msg1 and msg2

---

## 5. Race Condition Handling (Normative)

### 5.1 Duplicate Counter Race

**Scenario:** Two threads attempt to send with the same counter (lock failure).

**Mitigation:** Serialize sends with mutex (see §2.1).

**If race occurs despite lock:**
- Detect duplicate counter on receive (consumed set check)
- Reject second message with `C6P.RATCHET.REPLAY_DETECTED`
- Do NOT advance state

### 5.2 Concurrent State Persistence Race

**Scenario:** Two threads attempt to update `consumed` set concurrently.

**Mitigation:** Use database transactions or file locks.

**Example (SQLite):**
```rust
tx.execute("BEGIN IMMEDIATE")?;  // Exclusive lock
tx.execute("UPDATE stream_state SET consumed = ? WHERE stream_id = ?", consumed, stream_id)?;
tx.execute("COMMIT")?;
```

**If race detected:**
- Rollback transaction
- Retry (exponential backoff, max 3 attempts)
- If retry fails, reject message with `C6P.SESSION.STORAGE_CONFLICT`

### 5.3 Read-Modify-Write Conflicts

**Scenario:** Thread A reads state, thread B modifies state, thread A writes stale state.

**Mitigation:** Use optimistic locking with version counter.

**Example:**
```rust
struct StreamState {
    version: u64,  // Increment on every write
    // ... other fields
}

fn update_state(state: &mut StreamState) -> Result<()> {
    let old_version = state.version;
    state.version += 1;

    let rows_affected = db.execute(
        "UPDATE stream_state SET version = ?, consumed = ? WHERE stream_id = ? AND version = ?",
        state.version, state.consumed, state.stream_id, old_version
    )?;

    if rows_affected == 0 {
        return Err(OptimisticLockFailure);  // Another thread updated state
    }
    Ok(())
}
```

---

## 6. Synchronization Primitives (Normative)

### 6.1 Mutex vs. RwLock

**Send path:** Use `Mutex` (exclusive access required for counter increment)

**Receive path:** Use `RwLock` (multiple readers, exclusive writer)

**Example:**
```rust
struct StreamState {
    send_lock: Mutex<SendState>,
    recv_lock: RwLock<ReceiveState>,
}
```

### 6.2 Atomic Operations

**Allowed:** For simple counters (metrics, sequence numbers)

**Example:**
```rust
static MESSAGES_SENT: AtomicU64 = AtomicU64::new(0);
MESSAGES_SENT.fetch_add(1, Ordering::Relaxed);  // OK for metrics
```

**FORBIDDEN:** For cryptographic state (CK, nonces) — MUST use locks

---

## 7. Platform-Specific Notes

### 7.1 iOS (Swift)

**Concurrency model:** `async`/`await` with actors

**Example:**
```swift
actor StreamSender {
    private var sendCounter: UInt64 = 0
    private var chainKey: Data

    func sendMessage(_ payload: Data) async throws -> Envelope {
        // Actor ensures serial execution
        let counter = sendCounter
        let envelope = try encrypt(payload, counter: counter, chainKey: chainKey)
        sendCounter += 1
        chainKey = deriveNext(chainKey, counter: counter)
        try await persist()
        return envelope
    }
}
```

### 7.2 Android (Kotlin)

**Concurrency model:** Coroutines with `Mutex`

**Example:**
```kotlin
class StreamSender {
    private val mutex = Mutex()
    private var sendCounter: ULong = 0u
    private var chainKey: ByteArray = ...

    suspend fun sendMessage(payload: ByteArray): Envelope {
        return mutex.withLock {
            val counter = sendCounter
            val envelope = encrypt(payload, counter, chainKey)
            sendCounter++
            chainKey = deriveNext(chainKey, counter)
            persist()
            envelope
        }
    }
}
```

### 7.3 Rust

**Concurrency model:** `tokio` or `std::sync`

**Example:**
```rust
struct StreamSender {
    state: Arc<Mutex<SendState>>,
}

impl StreamSender {
    async fn send_message(&self, payload: &[u8]) -> Result<Envelope> {
        let mut state = self.state.lock().await;
        let counter = state.send_counter;
        let envelope = encrypt(payload, counter, &state.chain_key)?;
        state.send_counter += 1;
        state.chain_key = derive_next(&state.chain_key, counter);
        persist(&state).await?;
        Ok(envelope)
    }
}
```

---

## 8. Performance Considerations

### 8.1 Lock Contention

**Problem:** High send rate may cause lock contention.

**Mitigation:**
- Batch sends (accumulate messages, send in single transaction)
- Use lockless queues for non-critical paths

**Trade-off:** Complexity vs. throughput (prefer simplicity for v1)

### 8.2 Skip-Window Size

**Default:** 2048 messages

**Impact:**
- Larger window → more out-of-order tolerance → higher memory for consumed set
- Smaller window → less tolerance → more rejections

**Tuning:** Profile app workload; 2048 is conservative for most use cases.

---

## 9. Test Scenarios

### 9.1 Concurrent Send Test

**Goal:** Verify counter uniqueness under concurrent sends

**Setup:**
```rust
let stream = Arc::new(StreamSender::new());
let handles: Vec<_> = (0..100).map(|i| {
    let s = stream.clone();
    thread::spawn(move || s.send_message(&[i]))
}).collect();

let envelopes: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
```

**Assert:** All envelopes have unique counters (0..100)

### 9.2 Out-of-Order Receive Test

**Goal:** Verify skip-window acceptance

**Setup:**
- Send messages with counters: [0, 1, 2, 5, 3, 4] (5 arrives before 3, 4)
- Receive in that order

**Assert:**
- All messages decrypt successfully
- `recv_expected` advances to 6 after receiving counter=5
- Consumed set: [0, 1, 2, 5] before receiving 3,4; [0,1,2,3,4,5] after

### 9.3 Replay Attack Test

**Goal:** Verify duplicate counter rejection

**Setup:**
- Receive message with counter=10
- Re-send same envelope (replay attack)

**Assert:**
- First receive succeeds
- Second receive fails with `C6P.RATCHET.REPLAY_DETECTED`
- State unchanged after second attempt

---

## 10. Compliance Checklist

- [ ] Send operations serialized per stream (mutex/lock)
- [ ] Counter uniqueness enforced (no duplicates)
- [ ] Out-of-order messages accepted within skip-window (2048)
- [ ] Replay detection via consumed set
- [ ] State updates are atomic (transactions)
- [ ] Cross-stream sends can run in parallel
- [ ] Race conditions fail-closed (reject, do not corrupt state)

---

## 11. Error Codes

See `docs/Sessions/sessions-error-codes.md`:
- `C6P.RATCHET.REPLAY_DETECTED`
- `C6P.RATCHET.SKIP_WINDOW_EXCEEDED`
- `C6P.SESSION.STORAGE_CONFLICT`

---

## 12. References

- Ratchet state machine: `docs/Sessions/dm-ratchet-state-machine.md`
- Replay protection: `docs/crypto/c6p-replay-and-skip-window.md`
- Storage contract: `docs/Sessions/session-storage-contract.md`

---
