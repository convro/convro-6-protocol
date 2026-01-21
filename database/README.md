# C6P Protocol - Database Documentation

Complete PostgreSQL database schema for production E2EE messaging system.

## Overview

The database is designed to support:
- ✅ **Convro Numbers** - Universal user identifiers (`+99 XXX XXX`)
- ✅ **Multi-device E2EE** - Each device has its own identity
- ✅ **Island Accord Handshake** - Prekey bundles (SPK + OTPs)
- ✅ **Realtime Messaging** - WebSocket delivery queue
- ✅ **Offline Support** - Message persistence and retry
- ✅ **Push Notifications** - APNs/FCM token storage
- ✅ **Presence Tracking** - Online/offline status
- ✅ **Contact Management** - User contact lists
- ✅ **Audit Trail** - Security logging

---

## Quick Start

### Setup Database

```bash
# 1. Create database
createdb convro

# 2. Run schema
psql convro < database/schema.sql

# 3. Change default password
psql convro -c "ALTER ROLE convro_app WITH PASSWORD 'your_secure_password';"
```

### Using Migrations

```bash
# Run migrations
psql convro < database/migrations/001_initial_schema.sql
```

---

## Schema Overview

### Core Tables (11 tables)

| Table | Purpose | Key Fields |
|-------|---------|------------|
| **users** | User accounts | `convro_number`, `username`, `password_hash` |
| **device_identities** | Device E2EE keys | `device_id`, `identity_key` |
| **prekey_bundles** | Signed prekeys | `signed_prekey`, `signed_prekey_signature` |
| **one_time_prekeys** | OTP pool | `one_time_prekey`, `consumed_at` |
| **sessions** | E2EE sessions | `session_id`, `initiator`, `responder` |
| **messages** | Encrypted messages | `encrypted_blob`, `delivery_status` |
| **contacts** | Contact lists | `contact_convro_number`, `display_name` |
| **push_tokens** | Push notification tokens | `push_token`, `platform` |
| **presence** | Online/offline status | `status`, `last_heartbeat` |
| **message_queue** | Realtime delivery | `queued_at`, `priority` |
| **audit_log** | Security events | `event_type`, `event_data` |

---

## Key Queries

### 1. Register New User

```sql
-- Generate Convro Number (random, check availability)
WITH new_number AS (
    SELECT '+99' || LPAD(FLOOR(RANDOM() * 900000 + 100000)::TEXT, 6, '0') AS convro_number
)
INSERT INTO users (convro_number, username, password_hash)
SELECT convro_number, 'alice', '$argon2id$...' FROM new_number
WHERE NOT EXISTS (
    SELECT 1 FROM users WHERE convro_number = (SELECT convro_number FROM new_number)
)
RETURNING user_id, convro_number;
```

### 2. Upload Prekeys (After Registration)

```sql
-- Insert device identity
INSERT INTO device_identities (user_id, device_id, identity_key, device_name, device_platform)
VALUES (
    :user_id,
    :device_id_bytes,
    :identity_key_bytes,
    'Alice iPhone 14',
    'ios'
)
RETURNING device_identity_id;

-- Insert signed prekey
INSERT INTO prekey_bundles (
    device_identity_id,
    signed_prekey,
    signed_prekey_signature,
    signed_prekey_id,
    expires_at
)
VALUES (
    :device_identity_id,
    :signed_prekey_bytes,
    :signature_bytes,
    1,
    NOW() + INTERVAL '7 days'
);

-- Insert one-time prekeys (batch)
INSERT INTO one_time_prekeys (device_identity_id, one_time_prekey, otp_key_id)
SELECT
    :device_identity_id,
    unnest(:otp_array),
    generate_series(1, array_length(:otp_array, 1));
```

### 3. Fetch Prekey Bundle (Start Handshake)

```sql
-- Get prekey bundle for a user by Convro Number
SELECT
    u.convro_number,
    u.user_id,
    di.device_identity_id,
    di.device_id,
    di.identity_key,
    pb.signed_prekey,
    pb.signed_prekey_signature,
    pb.signed_prekey_id,
    otp.otp_id,
    otp.one_time_prekey,
    otp.otp_key_id
FROM users u
JOIN device_identities di ON u.user_id = di.user_id
JOIN prekey_bundles pb ON di.device_identity_id = pb.device_identity_id
LEFT JOIN LATERAL (
    SELECT otp_id, one_time_prekey, otp_key_id
    FROM one_time_prekeys
    WHERE device_identity_id = di.device_identity_id
      AND consumed_at IS NULL
    ORDER BY uploaded_at ASC
    LIMIT 1
) otp ON TRUE
WHERE u.convro_number = :target_convro_number
  AND di.is_active = TRUE
  AND pb.is_active = TRUE
LIMIT 1;
```

### 4. Consume OTP (During Handshake Accept)

```sql
-- Mark OTP as consumed
UPDATE one_time_prekeys
SET consumed_at = NOW(),
    consumed_by = :initiator_user_id
WHERE otp_id = :otp_id
  AND consumed_at IS NULL
RETURNING otp_id;
```

### 5. Send Encrypted Message

```sql
-- Insert message
INSERT INTO messages (
    from_user_id,
    to_user_id,
    from_convro_number,
    to_convro_number,
    session_id,
    message_type,
    encrypted_blob,
    expires_at
)
VALUES (
    :sender_user_id,
    :recipient_user_id,
    :sender_convro_number,
    :recipient_convro_number,
    :session_id_bytes,
    'encrypted_message',
    :encrypted_blob,
    NOW() + INTERVAL '30 days'
)
RETURNING message_id, created_at;

-- If recipient is online, add to realtime queue
INSERT INTO message_queue (user_id, convro_number, message_id, priority)
SELECT :recipient_user_id, :recipient_convro_number, :message_id, 0
WHERE EXISTS (
    SELECT 1 FROM presence
    WHERE user_id = :recipient_user_id AND status = 'online'
);
```

### 6. Fetch Inbox (Undelivered Messages)

```sql
-- Get all undelivered messages for a user
SELECT
    m.message_id,
    m.from_convro_number,
    m.message_type,
    m.encrypted_blob,
    m.created_at,
    u.display_name AS sender_name
FROM messages m
JOIN users u ON m.from_user_id = u.user_id
WHERE m.to_user_id = :user_id
  AND m.delivered_at IS NULL
ORDER BY m.created_at ASC
LIMIT 100;
```

### 7. Mark Message as Delivered

```sql
-- Update delivery status
UPDATE messages
SET delivered_at = NOW(),
    delivery_status = 'delivered'
WHERE message_id = :message_id
  AND delivered_at IS NULL
RETURNING message_id;

-- Remove from realtime queue
DELETE FROM message_queue
WHERE message_id = :message_id;
```

### 8. Update Presence (Online Status)

```sql
-- User connects via WebSocket
INSERT INTO presence (user_id, status, ws_connection_id, connected_at, last_heartbeat)
VALUES (:user_id, 'online', :ws_connection_id, NOW(), NOW())
ON CONFLICT (user_id) DO UPDATE SET
    status = 'online',
    ws_connection_id = EXCLUDED.ws_connection_id,
    connected_at = EXCLUDED.connected_at,
    last_heartbeat = EXCLUDED.last_heartbeat;

-- Heartbeat (every 30 seconds)
UPDATE presence
SET last_heartbeat = NOW()
WHERE user_id = :user_id;

-- User disconnects
UPDATE presence
SET status = 'offline',
    ws_connection_id = NULL
WHERE user_id = :user_id;
```

### 9. Register Push Token

```sql
-- Store APNs/FCM token
INSERT INTO push_tokens (
    device_identity_id,
    user_id,
    push_token,
    platform,
    apns_environment
)
VALUES (
    :device_identity_id,
    :user_id,
    :push_token,
    'apns', -- or 'fcm'
    'production' -- or 'sandbox'
)
ON CONFLICT (push_token) DO UPDATE SET
    last_used_at = NOW(),
    is_active = TRUE;
```

### 10. Audit Log Entry

```sql
-- Log security event
INSERT INTO audit_log (
    event_type,
    user_id,
    device_identity_id,
    event_data,
    ip_address,
    user_agent,
    success
)
VALUES (
    'handshake_initiated',
    :user_id,
    :device_identity_id,
    jsonb_build_object(
        'responder_convro_number', :target_convro_number,
        'handshake_type', '3DH'
    ),
    :client_ip::INET,
    :user_agent,
    TRUE
);
```

---

## Monitoring Views

### User Sessions Summary

```sql
SELECT * FROM user_sessions_summary
WHERE convro_number = '+99123456';
```

**Output:**
```
user_id | convro_number | username | active_sessions | active_devices | last_session_activity
--------|---------------|----------|-----------------|----------------|-----------------------
uuid... | +99123456     | alice    | 3               | 2              | 2026-01-12 10:30:00
```

### Undelivered Messages Summary

```sql
SELECT * FROM undelivered_messages_summary
ORDER BY undelivered_count DESC;
```

### Device Prekey Health

```sql
-- Check which devices need prekey rotation
SELECT * FROM device_prekey_health
WHERE available_otps < 5 OR spk_expires_at < NOW() + INTERVAL '1 day';
```

---

## Maintenance

### Cleanup Expired Messages

```sql
-- Run daily (cron job)
SELECT cleanup_expired_messages();
```

### Check OTP Pool

```sql
-- Alert if any device has < 5 OTPs
SELECT
    d.device_name,
    u.convro_number,
    get_available_otp_count(d.device_identity_id) AS available_otps
FROM device_identities d
JOIN users u ON d.user_id = u.user_id
WHERE d.is_active = TRUE
HAVING get_available_otp_count(d.device_identity_id) < 5;
```

### Rotate Signed Prekeys

```sql
-- Mark old SPKs as inactive after new one uploaded
UPDATE prekey_bundles
SET is_active = FALSE
WHERE device_identity_id = :device_identity_id
  AND bundle_id != :new_bundle_id;
```

---

## Performance Tuning

### Connection Pooling

Use **PgBouncer** for connection pooling:

```ini
[databases]
convro = host=localhost dbname=convro

[pgbouncer]
pool_mode = transaction
max_client_conn = 1000
default_pool_size = 25
```

### Indexes

All critical indexes are created in `schema.sql`. Key indexes:
- `idx_messages_pending` - Hot path for message delivery
- `idx_otp_available` - Fast OTP lookup
- `idx_presence_status` - Online users query

### Partitioning (Future)

For **> 10M messages**, partition `messages` table by time:

```sql
-- Partition by month
CREATE TABLE messages_2026_01 PARTITION OF messages
FOR VALUES FROM ('2026-01-01') TO ('2026-02-01');
```

---

## Security

### Row-Level Security (Optional)

```sql
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY messages_user_access ON messages
FOR SELECT
USING (to_user_id = current_setting('app.user_id')::UUID);
```

### Encryption at Rest

```sql
-- Enable PostgreSQL TLS
ssl = on
ssl_cert_file = '/path/to/server.crt'
ssl_key_file = '/path/to/server.key'
```

### Backups

```bash
# Daily backup
pg_dump convro | gzip > backup_$(date +%Y%m%d).sql.gz

# Continuous archiving (PITR)
# Configure in postgresql.conf:
# wal_level = replica
# archive_mode = on
# archive_command = 'cp %p /backup/archive/%f'
```

---

## Scaling

### Read Replicas

For **> 10K concurrent users**:
- Primary: Write operations
- Replica 1: Read inbox, presence
- Replica 2: Audit logs, analytics

### Sharding (Future)

Shard by `convro_number` hash:
- Shard 0: +99000000 - +99333333
- Shard 1: +99333334 - +99666666
- Shard 2: +99666667 - +99999999

---

## Troubleshooting

### Slow Queries

```sql
-- Enable pg_stat_statements
CREATE EXTENSION pg_stat_statements;

-- Find slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 10;
```

### Connection Issues

```sql
-- Check active connections
SELECT count(*) FROM pg_stat_activity;

-- Kill idle connections
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE state = 'idle' AND state_change < NOW() - INTERVAL '10 minutes';
```

---

## Next Steps

1. **Deploy schema** to development environment
2. **Create seed data** for testing
3. **Implement server API** endpoints in Rust
4. **Write integration tests** for all queries
5. **Set up monitoring** (Prometheus + Grafana)

---

**Database is production-ready! 🚀**
