# Sessions Observability (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Telemetry, metrics, logging, and tracing for session operations
**Applies to:** All C6P v1 implementations

---

## 0. Observability Principles

1. **No secret leakage**: Never log keys, nonces, plaintexts, or AAD
2. **Structured events**: Use consistent schema for all events
3. **Metrics first**: Prefer counters/histograms over logs for high-frequency events
4. **Privacy by default**: Hash or redact PII (session_id, device_id in long-term storage)
5. **Fail-closed**: If logging fails, continue operation (do not block)

---

## 1. Event Taxonomy

All session events use namespace: `c6p.session.v1.*`

### 1.1 Lifecycle Events

- `c6p.session.v1.created`
- `c6p.session.v1.loaded`
- `c6p.session.v1.suspended`
- `c6p.session.v1.resumed`
- `c6p.session.v1.expired`
- `c6p.session.v1.terminated`

### 1.2 Ratchet Events

- `c6p.ratchet.v1.send.start`
- `c6p.ratchet.v1.send.complete`
- `c6p.ratchet.v1.send.failed`
- `c6p.ratchet.v1.receive.start`
- `c6p.ratchet.v1.receive.complete`
- `c6p.ratchet.v1.receive.failed`

### 1.3 Storage Events

- `c6p.storage.v1.persist.start`
- `c6p.storage.v1.persist.complete`
- `c6p.storage.v1.persist.failed`
- `c6p.storage.v1.load.start`
- `c6p.storage.v1.load.complete`
- `c6p.storage.v1.load.failed`

### 1.4 Error Events

- `c6p.error.v1.replay_detected`
- `c6p.error.v1.skip_window_exceeded`
- `c6p.error.v1.decryption_failed`
- `c6p.error.v1.storage_corruption`

---

## 2. Event Schema (Normative)

### 2.1 Base Schema

All events include:

```json
{
  "event": "c6p.session.v1.created",
  "timestamp": 1672531200,
  "version": "1.0",
  "device_id_hash": "sha256(device_id)[0..8] hex",
  "session_id_hash": "sha256(session_id)[0..8] hex",
  "attributes": { ... }
}
```

**Privacy:** Use SHA-256 hash of IDs, truncated to 8 bytes (16 hex chars) for correlation without revealing full ID.

### 2.2 Lifecycle Event Schema

**`c6p.session.v1.created`:**
```json
{
  "event": "c6p.session.v1.created",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "suite_id": 1,
    "role": "initiator",
    "peer_device_id_hash": "fedcba9876543210"
  }
}
```

**`c6p.session.v1.terminated`:**
```json
{
  "event": "c6p.session.v1.terminated",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "reason": "user_request",
    "session_age_seconds": 86400,
    "total_messages_sent": 42,
    "total_messages_received": 38
  }
}
```

### 2.3 Ratchet Event Schema

**`c6p.ratchet.v1.send.complete`:**
```json
{
  "event": "c6p.ratchet.v1.send.complete",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "stream_id": 1,
    "counter": 42,
    "payload_size_bytes": 256,
    "latency_ms": 5,
    "suite_id": 1
  }
}
```

**Privacy:** Log `counter` and `stream_id` (not secret), but NEVER log ciphertext, plaintext, or keys.

**`c6p.ratchet.v1.receive.complete`:**
```json
{
  "event": "c6p.ratchet.v1.receive.complete",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "stream_id": 2,
    "counter": 38,
    "out_of_order": true,
    "skip_distance": 2,
    "latency_ms": 3
  }
}
```

**`out_of_order`:** True if `counter != recv_expected` at time of receive.

**`skip_distance`:** `|counter - recv_expected|` (useful for detecting network reordering).

### 2.4 Error Event Schema

**`c6p.error.v1.replay_detected`:**
```json
{
  "event": "c6p.error.v1.replay_detected",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "stream_id": 1,
    "counter": 42,
    "recv_expected": 50,
    "error_code": "C6P.RATCHET.REPLAY_DETECTED"
  }
}
```

**`c6p.error.v1.skip_window_exceeded`:**
```json
{
  "event": "c6p.error.v1.skip_window_exceeded",
  "timestamp": 1672531200,
  "session_id_hash": "0123456789abcdef",
  "attributes": {
    "stream_id": 1,
    "counter": 5000,
    "recv_expected": 42,
    "skip_window": 2048,
    "error_code": "C6P.RATCHET.SKIP_WINDOW_EXCEEDED"
  }
}
```

---

## 3. Metrics (Normative)

### 3.1 Counter Metrics

**Message counts:**
- `c6p.messages.sent.count{stream_id, suite_id}`
- `c6p.messages.received.count{stream_id, suite_id}`
- `c6p.messages.failed.count{stream_id, error_code}`

**Session counts:**
- `c6p.sessions.active.gauge` (current active sessions)
- `c6p.sessions.created.count`
- `c6p.sessions.terminated.count{reason}`

**Error counts:**
- `c6p.errors.count{error_code}`
- `c6p.errors.replay.count`
- `c6p.errors.skip_window.count`

### 3.2 Histogram Metrics

**Latencies (milliseconds):**
- `c6p.ratchet.send.latency_ms` (p50, p95, p99)
- `c6p.ratchet.receive.latency_ms` (p50, p95, p99)
- `c6p.storage.persist.latency_ms` (p50, p95, p99)
- `c6p.storage.load.latency_ms` (p50, p95, p99)

**Message sizes (bytes):**
- `c6p.messages.payload_size_bytes` (p50, p95, p99)

### 3.3 Gauge Metrics

**State:**
- `c6p.sessions.active.gauge{state}` (ACTIVE, SUSPENDED, etc.)
- `c6p.sessions.send_counter.gauge{session_id_hash}` (current send counter)
- `c6p.sessions.recv_expected.gauge{session_id_hash}` (current recv_expected)

---

## 4. Logging (Normative)

### 4.1 Log Levels

**ERROR:** Critical failures (storage corruption, decryption failures)
**WARN:** Recoverable errors (replay detected, skip-window exceeded)
**INFO:** Lifecycle events (session created, terminated)
**DEBUG:** Detailed flow (counter increments, key derivation steps)

**Production default:** INFO

### 4.2 Structured Logging

**Format:** JSON (for machine parsing)

**Example (ERROR):**
```json
{
  "level": "ERROR",
  "timestamp": "2024-01-01T00:00:00Z",
  "event": "c6p.storage.v1.persist.failed",
  "session_id_hash": "0123456789abcdef",
  "error_code": "C6P.SESSION.STORAGE_ENCRYPTION_FAILED",
  "error_message": "Master key unavailable",
  "trace_id": "abc123"
}
```

**Example (INFO):**
```json
{
  "level": "INFO",
  "timestamp": "2024-01-01T00:00:00Z",
  "event": "c6p.session.v1.created",
  "session_id_hash": "0123456789abcdef",
  "suite_id": 1,
  "role": "initiator"
}
```

### 4.3 Forbidden in Logs

**NEVER log:**
- `root_key`, `chain_key`, `message_key`
- `nonce`, `suite_key`, `mk_material`
- Plaintext payloads
- Full `session_id` or `device_id` (use hash)
- Ciphertext (except length in bytes)

**Allowed:**
- Counter values
- Stream IDs
- Suite IDs
- Error codes
- Latencies
- Hashed IDs (SHA-256 truncated)

---

## 5. Tracing (Optional)

### 5.1 Distributed Tracing

**For E2E flows (handshake → send → receive):**
- Use OpenTelemetry or similar
- Propagate `trace_id` across operations

**Spans:**
- `c6p.session.create` (root span)
  - Child: `c6p.handshake.complete`
  - Child: `c6p.ratchet.send`
    - Child: `c6p.crypto.derive_key`
    - Child: `c6p.crypto.aead_seal`
    - Child: `c6p.storage.persist`

**Span attributes:**
- `session_id_hash`
- `counter`
- `stream_id`
- `latency_ms`

### 5.2 Sampling

**Production:** 1% sampling rate (reduce overhead)
**Debug/staging:** 100% sampling

---

## 6. Privacy and Compliance

### 6.1 GDPR / Privacy Considerations

**PII redaction:**
- Hash `session_id` and `device_id` before logging
- Do NOT correlate logs with user email/phone without consent
- Implement log retention policy (default: 30 days for DEBUG, 90 days for INFO/WARN/ERROR)

**Right to erasure:**
- On user request, purge logs containing `device_id_hash` for that user

### 6.2 Audit Logs

**Immutable logs for compliance:**
- Session creation/termination timestamps
- Key rotation events (in `docs/identity/identity-observability.md`)
- Error rates (for security monitoring)

**Storage:** Write-only append log (tamper-evident)

---

## 7. Alerting (Normative)

### 7.1 Critical Alerts (Page On-Call)

**Storage corruption:**
```
ALERT: c6p.errors.count{error_code="C6P.SESSION.STORAGE_CORRUPTION"} > 10 in 5 minutes
```

**Replay attack spike:**
```
ALERT: c6p.errors.replay.count > 100 in 1 minute
```

**High error rate:**
```
ALERT: c6p.errors.count / c6p.messages.received.count > 0.05 (5%)
```

### 7.2 Warning Alerts (Investigate)

**High skip-window rejections:**
```
WARN: c6p.errors.skip_window.count > 50 in 5 minutes
```

**Storage latency degradation:**
```
WARN: c6p.storage.persist.latency_ms.p99 > 100ms
```

---

## 8. Platform-Specific Instrumentation

### 8.1 iOS (Swift)

**Use `os_log` or custom logger:**
```swift
import os.log

let logger = Logger(subsystem: "com.convro.c6p", category: "session")

logger.info("Session created: session_id_hash=\(sessionIdHash)")
logger.error("Replay detected: counter=\(counter)")
```

**Metrics:** Integrate with Apple Analytics or custom backend

### 8.2 Android (Kotlin)

**Use `Timber` or `Logcat`:**
```kotlin
import timber.log.Timber

Timber.tag("C6P-Session").i("Session created: session_id_hash=%s", sessionIdHash)
Timber.tag("C6P-Ratchet").e("Replay detected: counter=%d", counter)
```

**Metrics:** Integrate with Firebase Analytics or custom backend

### 8.3 Server (Rust)

**Use `tracing` crate:**
```rust
use tracing::{info, error, instrument};

#[instrument(skip(session))]
async fn create_session(session: &Session) -> Result<()> {
    info!(session_id_hash = %session.id_hash(), "Session created");
    Ok(())
}

#[instrument]
async fn receive_message(envelope: &Envelope) -> Result<Plaintext> {
    if consumed.contains(envelope.counter) {
        error!(counter = envelope.counter, "Replay detected");
        return Err(ReplayDetected);
    }
    // ...
}
```

**Metrics:** Export to Prometheus

---

## 9. Dashboards (Recommended)

### 9.1 Session Health Dashboard

**Panels:**
- Active sessions (gauge)
- Session creation rate (counter)
- Session termination rate (by reason)
- Average session age

### 9.2 Ratchet Performance Dashboard

**Panels:**
- Send latency (p50, p95, p99)
- Receive latency (p50, p95, p99)
- Out-of-order rate (% of receives where `out_of_order=true`)
- Skip distance histogram

### 9.3 Error Dashboard

**Panels:**
- Error rate by code (top 10)
- Replay detections over time
- Skip-window exceedances
- Storage failures

---

## 10. Example Instrumentation (Rust)

```rust
use tracing::{info, warn, error, instrument};
use metrics::{counter, histogram};

#[instrument(skip(payload))]
async fn send_message(
    session: &Session,
    stream_id: u8,
    payload: &[u8],
) -> Result<Envelope> {
    let start = Instant::now();

    // Increment attempt counter
    counter!("c6p.messages.sent.attempts", 1, "stream_id" => stream_id.to_string());

    // Lock and derive
    let mut state = session.stream(stream_id).lock().await;
    let counter = state.send_counter;

    // Encrypt
    let envelope = match encrypt_payload(&state, payload) {
        Ok(env) => env,
        Err(e) => {
            error!(counter, stream_id, error = %e, "Send failed");
            counter!("c6p.messages.sent.failed", 1, "stream_id" => stream_id.to_string());
            return Err(e);
        }
    };

    // Persist
    state.send_counter += 1;
    state.chain_key = derive_next_ck(&state.chain_key, counter);
    persist(&state).await?;

    // Success metrics
    let latency_ms = start.elapsed().as_millis() as u64;
    counter!("c6p.messages.sent.count", 1, "stream_id" => stream_id.to_string());
    histogram!("c6p.ratchet.send.latency_ms", latency_ms as f64);
    histogram!("c6p.messages.payload_size_bytes", payload.len() as f64);

    info!(
        session_id_hash = %session.id_hash(),
        counter,
        stream_id,
        latency_ms,
        "Send complete"
    );

    Ok(envelope)
}

#[instrument]
async fn receive_message(
    session: &Session,
    envelope: Envelope,
) -> Result<Plaintext> {
    let start = Instant::now();
    let counter = envelope.counter;
    let stream_id = envelope.stream_id;

    // Validate counter
    let state = session.stream(stream_id).lock().await;
    if state.consumed.contains(counter) {
        error!(counter, stream_id, "Replay detected");
        counter!("c6p.errors.replay.count", 1);
        return Err(ReplayDetected);
    }

    let skip_distance = (counter as i64 - state.recv_expected as i64).abs();
    if skip_distance > SKIP_WINDOW as i64 {
        warn!(counter, recv_expected = state.recv_expected, "Skip window exceeded");
        counter!("c6p.errors.skip_window.count", 1);
        return Err(SkipWindowExceeded);
    }

    // Decrypt
    let plaintext = decrypt_payload(&state, &envelope)?;

    // Update state
    state.consumed.insert(counter);
    let out_of_order = counter != state.recv_expected;
    if counter == state.recv_expected {
        state.recv_expected = advance_to_next_gap(&state.consumed, counter);
    }
    persist(&state).await?;

    // Success metrics
    let latency_ms = start.elapsed().as_millis() as u64;
    counter!("c6p.messages.received.count", 1, "stream_id" => stream_id.to_string());
    histogram!("c6p.ratchet.receive.latency_ms", latency_ms as f64);

    info!(
        session_id_hash = %session.id_hash(),
        counter,
        stream_id,
        out_of_order,
        skip_distance,
        latency_ms,
        "Receive complete"
    );

    Ok(plaintext)
}
```

---

## 11. Compliance Checklist

- [ ] No secret leakage in logs (keys, nonces, plaintexts)
- [ ] Structured event schema for all events
- [ ] Metrics emitted for send/receive/errors
- [ ] Hashed session_id and device_id in logs
- [ ] Alerting configured for critical errors
- [ ] Log retention policy defined (GDPR compliance)
- [ ] Dashboards created for session health, performance, errors

---

## 12. References

- Error codes: `docs/Sessions/sessions-error-codes.md`
- Session overview: `docs/Sessions/sessions-overview.md`
- Identity observability: `docs/identity/identity-observability.md`
- Handshake observability: `docs/handshake/island-accord-observability.md`

---
