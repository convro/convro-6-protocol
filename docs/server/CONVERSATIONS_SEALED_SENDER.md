# Conversations + Sealed Sender - Design Document

**Version:** 1.0
**Date:** 2026-01-13
**Status:** Implementation Ready

---

## Overview

This document describes two critical enhancements to the Convro server:

1. **Conversations List** - User-facing conversation aggregation (essential UI feature)
2. **Sealed Sender** - Metadata minimization (privacy differentiator)

Both features work together to provide Signal-level privacy with excellent UX.

---

## Part 1: Conversations List

### Problem Statement

Users need to see all their active conversations, similar to WhatsApp/Signal conversation list.

**Current state:**
- ✅ `sessions` table tracks device-to-device sessions
- ✅ `messages` table stores all messages
- ❌ No user-facing conversation aggregation

### Solution: Hybrid Approach

We'll use a **materialized view** with triggers for automatic updates.

#### Database Schema

```sql
-- Materialized view for fast queries
CREATE MATERIALIZED VIEW user_conversations AS
SELECT
    -- Conversation identity
    CASE
        WHEN s.initiator_user_id < s.responder_user_id
        THEN s.initiator_user_id || '_' || s.responder_user_id
        ELSE s.responder_user_id || '_' || s.initiator_user_id
    END as conversation_id,

    -- User perspective (who owns this conversation view)
    u.user_id as owner_user_id,

    -- Other participant
    CASE
        WHEN s.initiator_user_id = u.user_id
        THEN s.responder_user_id
        ELSE s.initiator_user_id
    END as participant_user_id,

    -- Session info
    s.session_id,
    s.created_at as conversation_started_at,
    s.last_activity,
    s.message_count as total_messages,

    -- Last message (for preview)
    lm.message_id as last_message_id,
    lm.message_type as last_message_type,
    lm.created_at as last_message_at,

    -- Unread count (messages pending delivery)
    COALESCE(unread.count, 0) as unread_count,

    -- Status
    s.is_active

FROM sessions s
CROSS JOIN users u
LEFT JOIN LATERAL (
    SELECT message_id, message_type, created_at
    FROM messages
    WHERE session_id = s.session_id
    ORDER BY created_at DESC
    LIMIT 1
) lm ON TRUE
LEFT JOIN LATERAL (
    SELECT COUNT(*) as count
    FROM messages
    WHERE session_id = s.session_id
    AND to_user_id = u.user_id
    AND delivery_status = 'pending'
) unread ON TRUE
WHERE
    (s.initiator_user_id = u.user_id OR s.responder_user_id = u.user_id)
    AND s.is_active = TRUE;

-- Index for fast lookups
CREATE UNIQUE INDEX idx_conversations_owner_participant
    ON user_conversations(owner_user_id, participant_user_id);
CREATE INDEX idx_conversations_last_activity
    ON user_conversations(owner_user_id, last_activity DESC);

-- Refresh trigger (update on message insert/update)
CREATE OR REPLACE FUNCTION refresh_conversations_on_message()
RETURNS TRIGGER AS $$
BEGIN
    -- Refresh only affected conversation
    REFRESH MATERIALIZED VIEW CONCURRENTLY user_conversations;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_refresh_conversations
    AFTER INSERT OR UPDATE ON messages
    FOR EACH STATEMENT
    EXECUTE FUNCTION refresh_conversations_on_message();
```

**Why Materialized View?**
- ✅ Fast queries (pre-computed)
- ✅ Automatic updates via triggers
- ✅ Simple JOIN for participant details
- ✅ No duplicate data (view, not table)

#### API Endpoint

```
GET /v1/conversations

Query params:
- limit: int (default: 50, max: 100)
- offset: int (default: 0)
- include_archived: bool (default: false) - for future

Response: 200 OK
{
  "conversations": [
    {
      "conversation_id": "550e8400..._660e8400...",
      "participant": {
        "user_id": "660e8400-e29b-41d4-a716-446655440001",
        "convro_number": "+99 654 321",
        "display_name": "Bob Jones"
      },
      "last_message": {
        "message_id": "770e8400-e29b-41d4-a716-446655440002",
        "message_type": "encrypted_message",
        "created_at": "2026-01-12T15:30:00Z"
      },
      "unread_count": 3,
      "last_activity": "2026-01-12T15:30:00Z",
      "conversation_started_at": "2026-01-10T10:00:00Z",
      "total_messages": 127
    }
  ],
  "total": 15,
  "limit": 50,
  "offset": 0
}
```

---

## Part 2: Sealed Sender (Privacy Enhancement)

### Problem Statement

**Current state:**
- Server sees `from_user_id` and `to_user_id` (full social graph exposure)
- Metadata includes: who talks to whom, when, how often
- Convro identical to WhatsApp (poor metadata privacy)

**Goal:**
- Hide sender identity from server
- Match Signal's sealed sender privacy level
- Server only knows recipient (for routing)

### Solution: Encrypted Sender Envelope

#### Architecture

```
┌─────────────────────────────────────────────────────┐
│ Sealed Message Structure                            │
├─────────────────────────────────────────────────────┤
│                                                     │
│  ┌──────────────────────────────────────┐          │
│  │ Outer Envelope (Server sees)        │          │
│  ├──────────────────────────────────────┤          │
│  │ to_user_id: UUID                    │ ← Routing │
│  │ message_type: "sealed_sender"       │          │
│  │ created_at: TIMESTAMP (rounded)     │ ← Timing obfuscation │
│  │ encrypted_envelope: BYTEA (PADDED)  │ ← Fixed size │
│  └──────────────────────────────────────┘          │
│              ↓                                      │
│  ┌──────────────────────────────────────┐          │
│  │ Inner Envelope (Recipient decrypts) │          │
│  ├──────────────────────────────────────┤          │
│  │ from_user_id: UUID                  │ ← Hidden  │
│  │ from_convro_number: STRING          │          │
│  │ session_id: BYTEA                   │          │
│  │ actual_message_type: STRING         │          │
│  │ actual_created_at: TIMESTAMP        │ ← Real time │
│  │ encrypted_blob: BYTEA               │ ← C6P payload │
│  └──────────────────────────────────────┘          │
│                                                     │
└─────────────────────────────────────────────────────┘
```

#### Database Schema Changes

```sql
-- New table for sealed sender messages
CREATE TABLE messages_sealed (
    -- Primary key
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Routing (ONLY recipient visible to server)
    to_user_id UUID NOT NULL REFERENCES users(user_id),
    -- NO from_user_id! Sender identity encrypted in envelope

    -- Message type (server only sees "sealed_sender")
    message_type VARCHAR(30) NOT NULL DEFAULT 'sealed_sender',

    -- Encrypted envelope (contains sender + actual message)
    -- PADDED to fixed size (64KB) to hide message length
    encrypted_envelope BYTEA NOT NULL,

    -- Obfuscated timestamp (rounded to nearest 5 minutes)
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    -- Delivery tracking
    delivered_at TIMESTAMP WITH TIME ZONE,

    -- Status
    delivery_status VARCHAR(20) DEFAULT 'pending',

    -- Server-side expiration
    expires_at TIMESTAMP WITH TIME ZONE DEFAULT (NOW() + INTERVAL '30 days'),

    -- Constraints
    CHECK (message_type = 'sealed_sender'),
    CHECK (octet_length(encrypted_envelope) = 65536) -- Exactly 64KB
);

-- Indexes
CREATE INDEX idx_messages_sealed_recipient ON messages_sealed(to_user_id, delivery_status);
CREATE INDEX idx_messages_sealed_delivery ON messages_sealed(delivery_status, created_at);
CREATE INDEX idx_messages_sealed_expiration ON messages_sealed(expires_at) WHERE delivery_status = 'delivered';

-- Immutability trigger (like messages table)
CREATE TRIGGER trigger_immutable_sealed_envelope
    BEFORE UPDATE ON messages_sealed
    FOR EACH ROW
    EXECUTE FUNCTION prevent_encrypted_blob_modification();

-- Comments
COMMENT ON TABLE messages_sealed IS 'Sealed sender messages - sender identity hidden from server';
COMMENT ON COLUMN messages_sealed.encrypted_envelope IS 'Contains encrypted sender info + message (64KB padded)';
COMMENT ON COLUMN messages_sealed.created_at IS 'Rounded to 5min intervals for timing obfuscation';
```

#### Migration Strategy

**Phase 1: Dual Mode (v1.1)**
- Both `messages` and `messages_sealed` tables exist
- Clients can send via either table
- API accepts both formats
- Default: sealed sender (privacy by default)

**Phase 2: Sealed Only (v2.0)**
- Deprecate `messages` table
- All new messages use sealed sender
- Migrate old messages (anonymize sender)

#### Message Padding Implementation

```rust
// server/src/utils/padding.rs

const SEALED_MESSAGE_SIZE: usize = 65536; // 64 KB

/// Pad message to fixed size
pub fn pad_sealed_envelope(data: Vec<u8>) -> Result<Vec<u8>, PaddingError> {
    if data.len() > SEALED_MESSAGE_SIZE {
        return Err(PaddingError::TooLarge {
            size: data.len(),
            max: SEALED_MESSAGE_SIZE,
        });
    }

    let mut padded = data;
    padded.resize(SEALED_MESSAGE_SIZE, 0); // Zero padding
    Ok(padded)
}

/// Remove padding from message
pub fn unpad_sealed_envelope(padded: Vec<u8>) -> Result<Vec<u8>, PaddingError> {
    if padded.len() != SEALED_MESSAGE_SIZE {
        return Err(PaddingError::InvalidSize {
            size: padded.len(),
            expected: SEALED_MESSAGE_SIZE,
        });
    }

    // Find actual message length (first 4 bytes = length prefix)
    let length = u32::from_be_bytes([padded[0], padded[1], padded[2], padded[3]]) as usize;

    if length > SEALED_MESSAGE_SIZE - 4 {
        return Err(PaddingError::InvalidLength(length));
    }

    Ok(padded[4..4 + length].to_vec())
}
```

#### Timestamp Obfuscation

```rust
// server/src/utils/timing.rs

use chrono::{DateTime, Duration, Utc};

/// Round timestamp to nearest 5 minutes
pub fn obfuscate_timestamp(ts: DateTime<Utc>) -> DateTime<Utc> {
    const ROUND_TO_MINUTES: i64 = 5;

    let minutes = ts.timestamp() / 60;
    let rounded_minutes = (minutes / ROUND_TO_MINUTES) * ROUND_TO_MINUTES;

    DateTime::from_timestamp(rounded_minutes * 60, 0)
        .unwrap_or(ts)
}

/// Add random delay (0-5 seconds) before delivery
pub async fn apply_timing_jitter() {
    let jitter_ms = rand::thread_rng().gen_range(0..5000);
    tokio::time::sleep(Duration::milliseconds(jitter_ms).to_std().unwrap()).await;
}
```

#### API Endpoints

**Send Sealed Message:**

```
POST /v1/messages/sealed

Headers:
  Authorization: Bearer {access_token}

Request:
{
  "to_convro_number": "+99 654 321",
  "encrypted_envelope": "base64_encoded_64KB_blob"
}

Response: 201 Created
{
  "message_id": "880e8400-e29b-41d4-a716-446655440003",
  "delivery_status": "pending",
  "created_at": "2026-01-12T15:30:00Z"  // Rounded timestamp
}
```

**Fetch Sealed Inbox:**

```
GET /v1/messages/sealed/inbox

Headers:
  Authorization: Bearer {access_token}

Response: 200 OK
{
  "messages": [
    {
      "message_id": "880e8400-e29b-41d4-a716-446655440003",
      "encrypted_envelope": "base64_encoded_64KB_blob",
      "created_at": "2026-01-12T15:30:00Z",
      "delivered_at": null
    }
  ],
  "total": 5,
  "limit": 50,
  "offset": 0
}
```

---

## Part 3: Integration Between Features

### Conversations with Sealed Sender

**Challenge:** How to show conversations when sender is hidden?

**Solution:** Client-side decryption reveals sender, then builds conversation list locally.

```rust
// Client-side pseudocode

// 1. Fetch sealed inbox
let sealed_messages = api.fetch_sealed_inbox().await?;

// 2. Decrypt envelopes locally
for msg in sealed_messages {
    let envelope = decrypt_envelope(msg.encrypted_envelope)?;

    // 3. Extract sender from decrypted envelope
    let sender_id = envelope.from_user_id;
    let session_id = envelope.session_id;

    // 4. Update local conversation database
    local_db.upsert_conversation(
        sender_id,
        envelope.from_convro_number,
        session_id,
        envelope.actual_created_at,
    ).await?;
}

// 5. Display conversations list from local DB
let conversations = local_db.list_conversations().await?;
```

**Server-side:**
- Server provides `/v1/conversations` for NON-sealed messages (backward compatibility)
- For sealed sender users: conversations built client-side only
- Server never sees conversation list for sealed sender users

### Privacy Levels

Users can choose their privacy level:

```sql
-- Add to users table
ALTER TABLE users ADD COLUMN privacy_mode VARCHAR(20) DEFAULT 'standard';
-- Values: 'standard' (visible sender) or 'sealed' (hidden sender)
```

**API:**

```
PUT /v1/users/me/privacy

Request:
{
  "privacy_mode": "sealed"
}

Response: 200 OK
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "privacy_mode": "sealed",
  "updated_at": "2026-01-12T16:00:00Z"
}
```

---

## Part 4: Security Analysis

### Metadata Protection Comparison

| Metadata Type | Standard Mode | Sealed Mode | Signal |
|---------------|---------------|-------------|--------|
| **Sender identity** | ✅ Visible | ❌ Hidden | ❌ Hidden |
| **Recipient identity** | ✅ Visible | ✅ Visible | ✅ Visible |
| **Message content** | ❌ Encrypted (C6P) | ❌ Encrypted (C6P) | ❌ Encrypted |
| **Message size** | 🟡 Visible (variable) | ❌ Hidden (64KB fixed) | 🟡 Visible (padded) |
| **Exact timestamp** | ✅ Visible | 🟡 Obfuscated (5min) | ✅ Visible |
| **Social graph** | 🔴 Fully exposed | 🟢 Recipient-only | 🟢 Recipient-only |
| **Session linkage** | ✅ Visible | ❌ Hidden | 🟡 Visible (rotated) |

### Threat Model Updates

**New Mitigations:**

1. **Threat §7.1 - Metadata Minimization:**
   - ✅ Sealed sender hides social graph from server
   - ✅ Message padding hides content length
   - ✅ Timestamp rounding prevents precise correlation

2. **Threat §3.3 - Malicious Server:**
   - ✅ Compromised server cannot build sender social graph
   - ✅ Only recipient relationships exposed (necessary for routing)

**Residual Risks:**

1. **Traffic Analysis:** Server can still observe:
   - Message frequency to each recipient
   - Approximate message timing (5min resolution)
   - Recipient's social graph (who receives messages)

2. **Recipient Compromise:**
   - If recipient's device compromised, sender revealed after decryption
   - Mitigation: Client-side security (Keychain, secure enclave)

3. **Correlation Attacks:**
   - Attacker observing network traffic + sealed sender may correlate by timing
   - Mitigation: Timing jitter (0-5s), use Tor/VPN

---

## Part 5: Implementation Roadmap

### Phase 1: Conversations List (Week 1)

**Database:**
- [ ] Create materialized view `user_conversations`
- [ ] Add refresh trigger
- [ ] Create indexes

**Server:**
- [ ] Model: `Conversation` struct
- [ ] Repository: `ConversationRepository`
- [ ] Service: `ConversationService`
- [ ] API: `GET /v1/conversations`

**Testing:**
- [ ] Test conversation aggregation
- [ ] Test unread count accuracy
- [ ] Test sorting (last_activity DESC)
- [ ] Load test: 10,000 conversations

### Phase 2: Sealed Sender (Week 2)

**Database:**
- [ ] Create `messages_sealed` table
- [ ] Add immutability trigger
- [ ] Create indexes

**Server:**
- [ ] Utils: `padding.rs`, `timing.rs`
- [ ] Model: `SealedMessage` struct
- [ ] Repository: `SealedMessageRepository`
- [ ] Service: `SealedMessageService`
- [ ] API: `POST /v1/messages/sealed`, `GET /v1/messages/sealed/inbox`

**Testing:**
- [ ] Test message padding/unpadding
- [ ] Test timestamp obfuscation
- [ ] Test sealed delivery flow
- [ ] Security test: verify sender hidden

### Phase 3: Privacy Mode Toggle (Week 3)

**Database:**
- [ ] Add `privacy_mode` column to users

**Server:**
- [ ] API: `PUT /v1/users/me/privacy`
- [ ] Update message send logic (check sender's privacy_mode)

**Testing:**
- [ ] Test mode switching
- [ ] Test mixed mode (some users sealed, some standard)

### Phase 4: Documentation (Week 4)

**Updates:**
- [ ] `API_SPECIFICATION.md` - Add new endpoints
- [ ] `SECURITY_COMPLIANCE.md` - Update threat model compliance
- [ ] `database/schema.sql` - Add new tables/views
- [ ] `database/migrations/` - Create migration files
- [ ] `README.md` - Update feature list, status
- [ ] New: `SEALED_SENDER.md` - Complete design doc

---

## Part 6: Client Integration

### iOS Changes Required

**C6P Protocol:** No changes needed (sealed sender is transport-layer)

**App Changes:**

```swift
// ConvroAPI.swift

func sendSealedMessage(
    toConvroNumber: String,
    content: Data,
    sessionKeys: SessionKeys
) async throws -> SealedMessageResponse {
    // 1. Encrypt message content with C6P
    let encryptedBlob = try c6p.encrypt(content, with: sessionKeys)

    // 2. Build inner envelope
    let innerEnvelope = SealedEnvelope(
        fromUserId: currentUser.id,
        fromConvroNumber: currentUser.convroNumber,
        sessionId: sessionKeys.sessionId,
        messageType: "encrypted_message",
        createdAt: Date(),
        encryptedBlob: encryptedBlob
    )

    // 3. Encrypt envelope (with recipient's public key - future: use C6P session)
    let encryptedEnvelope = try encryptInnerEnvelope(innerEnvelope, for: toConvroNumber)

    // 4. Pad to 64KB
    let paddedEnvelope = padTo64KB(encryptedEnvelope)

    // 5. Send to server
    return try await api.post("/v1/messages/sealed", body: [
        "to_convro_number": toConvroNumber,
        "encrypted_envelope": paddedEnvelope.base64EncodedString()
    ])
}
```

---

## Part 7: Performance Considerations

### Conversations View Refresh

**Concern:** Refreshing materialized view on every message insert is expensive.

**Solutions:**

1. **Refresh frequency:** Only refresh every 10 seconds (acceptable delay)
   ```sql
   -- Use cron job instead of trigger
   SELECT cron.schedule('refresh-conversations', '*/10 * * * *',
       'REFRESH MATERIALIZED VIEW CONCURRENTLY user_conversations');
   ```

2. **Partial refresh:** Only update affected conversations
   ```sql
   -- Index allows CONCURRENTLY (non-blocking)
   REFRESH MATERIALIZED VIEW CONCURRENTLY user_conversations;
   ```

3. **Cache:** Add Redis cache for hot conversations
   ```rust
   // Cache conversation list for 10 seconds
   let cache_key = format!("conversations:{}", user_id);
   if let Some(cached) = redis.get(&cache_key).await? {
       return Ok(cached);
   }
   ```

### Sealed Message Overhead

**64KB padding impact:**

- Standard message: ~2-10 KB (text + C6P overhead)
- Sealed message: 64 KB (padded)
- **Overhead: ~6-32x larger**

**Mitigations:**

1. **Compression:** Apply before padding
   ```rust
   let compressed = zstd::compress(envelope, 3)?; // Level 3
   let padded = pad_to_64kb(compressed)?;
   ```

2. **Optional:** Let users choose (privacy vs bandwidth)
   - Mobile data: Standard mode (smaller)
   - WiFi: Sealed mode (privacy)

---

## Conclusion

This design provides:

✅ **Conversations list** - Essential UX feature
✅ **Sealed sender** - Signal-level metadata privacy
✅ **Message padding** - Hide content length
✅ **Timestamp obfuscation** - Reduce timing correlation
✅ **Backward compatibility** - Dual mode support
✅ **User choice** - Privacy vs convenience trade-off

**Differentiation:**
- WhatsApp: No sealed sender (poor privacy)
- Signal: Sealed sender optional (privacy-conscious)
- **Convro: Sealed sender default** (privacy-first, best-in-class)

**Next Steps:** Proceed with implementation (Phase 1 → Phase 4)

---

**Document maintained by:** Convro Server Team
**Last updated:** 2026-01-13
**Review date:** Before v1.1 release
