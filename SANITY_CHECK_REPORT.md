# Convro Server - Sanity Check Report

**Date:** 2026-01-12
**Status:** ⚠️ **CRITICAL GAPS IDENTIFIED**

---

## ❌ Problem 1: MISSING CONVERSATIONS LIST

### What's Missing:
The API has **NO endpoint for listing conversations** - a fundamental feature for any messaging app!

**Current API has:**
- ✅ `POST /messages` - Send message
- ✅ `GET /messages/inbox` - Fetch undelivered messages
- ✅ `POST /messages/{id}/delivered` - Mark delivered
- ✅ `GET /messages/history` - Get history by session_id

**What's MISSING:**
- ❌ `GET /conversations` - **List all conversations for user**

### Why This is Critical:
Users need to see:
- All their active conversations (like WhatsApp/Signal conversation list)
- Last message in each conversation
- Timestamp of last activity
- Unread message count
- Participant info (Convro Number, display name)

### Current State:
- Database has `sessions` table tracking device-to-device sessions
- Database has `messages` table with all messages
- **But NO way to aggregate into user-facing conversations list!**

### What Needs to be Added:

#### Option A: Database View
```sql
CREATE VIEW user_conversations AS
SELECT
    s.session_id,
    s.initiator_user_id,
    s.responder_user_id,
    s.last_activity,
    s.message_count,
    m.last_message_id,
    m.last_message_type,
    m.last_message_at,
    -- Count undelivered messages
    (SELECT COUNT(*) FROM messages
     WHERE session_id = s.session_id
     AND delivery_status = 'pending') as unread_count
FROM sessions s
LEFT JOIN LATERAL (
    SELECT message_id, message_type, created_at as last_message_at
    FROM messages
    WHERE session_id = s.session_id
    ORDER BY created_at DESC
    LIMIT 1
) m ON TRUE
WHERE s.is_active = TRUE;
```

#### Option B: New Table
```sql
CREATE TABLE conversations (
    conversation_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(user_id),
    other_user_id UUID NOT NULL REFERENCES users(user_id),
    session_id BYTEA REFERENCES sessions(session_id),
    last_message_id UUID REFERENCES messages(message_id),
    last_message_at TIMESTAMP WITH TIME ZONE,
    unread_count INTEGER DEFAULT 0,
    is_archived BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

    UNIQUE(user_id, other_user_id)
);
```

#### Required API Endpoint:
```
GET /v1/conversations

Response:
{
  "conversations": [
    {
      "conversation_id": "...",
      "participant": {
        "user_id": "...",
        "convro_number": "+99 654 321",
        "display_name": "Bob Jones"
      },
      "last_message": {
        "message_id": "...",
        "message_type": "encrypted_message",
        "created_at": "2026-01-12T15:30:00Z"
      },
      "unread_count": 3,
      "last_activity": "2026-01-12T15:30:00Z"
    }
  ]
}
```

---

## ❌ Problem 2: SEVERE METADATA LEAKAGE

### Current Metadata Exposure:

The `messages` table stores:

```sql
-- ⚠️ METADATA LEAKED TO SERVER:
from_user_id UUID          -- Server knows WHO sent
to_user_id UUID            -- Server knows WHO received
from_convro_number VARCHAR -- Redundant sender info
to_convro_number VARCHAR   -- Redundant recipient info
session_id BYTEA           -- Links messages into conversations
message_type VARCHAR       -- Server knows message TYPE
created_at TIMESTAMP       -- Server knows WHEN
delivered_at TIMESTAMP     -- Server knows WHEN delivered
read_at TIMESTAMP          -- Server knows WHEN read
```

### What This Means:

**If server is compromised, attacker learns:**
1. **Social graph**: Complete map of who talks to whom
2. **Communication patterns**: Frequency, timing, volume
3. **Message types**: Handshakes vs normal messages
4. **Behavioral patterns**: Sleep schedules, response times
5. **Relationship strength**: Message counts per session

### Security Doc Claims:

From `SECURITY_COMPLIANCE.md`:
> "**§7 Metadata Minimization** | Automatic message expiration | ✅"

**Reality:** Only message expiration (30 days) is implemented. The server **STILL SEES ALL METADATA**.

### What Should Be Done (Privacy Best Practices):

#### 1. **Sealed Sender** (Signal Protocol)
- Sender identity encrypted in message payload
- Server only knows recipient (for routing)
- `from_user_id` removed from database
- Sender revealed only to recipient after decryption

```sql
-- Sealed sender schema:
CREATE TABLE messages_sealed (
    message_id UUID PRIMARY KEY,
    to_user_id UUID NOT NULL,           -- ONLY recipient
    -- NO from_user_id!                 -- Sender hidden
    encrypted_envelope BYTEA NOT NULL,  -- Contains sender + message
    created_at TIMESTAMP,
    ...
);
```

#### 2. **Message Padding**
- All messages same size (e.g., 64KB)
- Prevents size-based traffic analysis

```rust
// In message_service.rs
fn pad_message(blob: Vec<u8>) -> Vec<u8> {
    const TARGET_SIZE: usize = 65536; // 64 KB
    let mut padded = blob;
    padded.resize(TARGET_SIZE, 0);
    padded
}
```

#### 3. **Timing Obfuscation**
- Random delays before delivery (0-5 seconds)
- Batching: Send multiple messages at fixed intervals
- Prevents real-time correlation attacks

#### 4. **Ephemeral Session IDs**
- Rotate `session_id` periodically (e.g., every 1000 messages)
- Breaks long-term conversation linkage

#### 5. **Remove Redundant Fields**
- `from_convro_number` / `to_convro_number` - can be looked up from user_id
- Reduces metadata footprint

### Threat Model Gaps:

The current implementation protects:
- ✅ Message **content** (encrypted_blob is E2EE)
- ✅ Message **integrity** (immutability trigger)
- ✅ **OTP race conditions** (SELECT FOR UPDATE)

But **DOES NOT** protect:
- ❌ **Who talks to whom** (social graph exposed)
- ❌ **Communication patterns** (timestamps exposed)
- ❌ **Message size** (encrypted_blob length visible)
- ❌ **Sender anonymity** (from_user_id in plaintext)

### Comparison to Signal:

**Signal's Sealed Sender:**
- Server only knows recipient
- Sender identity in encrypted envelope
- Requires trust token (to prevent spam)

**Convro current state:**
- Server knows both sender and recipient
- No sealed sender implementation
- Social graph fully exposed

---

## 📊 Metadata Risk Assessment

| Metadata Type | Exposed to Server? | Risk Level | Signal Equivalent |
|---------------|-------------------|------------|-------------------|
| Sender identity | ✅ YES | 🔴 HIGH | ❌ Hidden (sealed) |
| Recipient identity | ✅ YES | 🟡 MEDIUM | ✅ Visible (routing) |
| Message content | ❌ NO (encrypted) | 🟢 LOW | ❌ Hidden (E2EE) |
| Message size | ✅ YES | 🟡 MEDIUM | 🟡 Visible (padded) |
| Timestamps | ✅ YES | 🟡 MEDIUM | ✅ Visible |
| Session linkage | ✅ YES | 🔴 HIGH | 🟡 Rotated |
| Message type | ✅ YES | 🟢 LOW | ❌ Hidden |

---

## 🎯 Recommendations

### Priority 1: URGENT (Functionality)
1. **Add conversations list endpoint**
   - Create database view or table
   - Implement `GET /v1/conversations` API
   - Add repository/service/API layers
   - Include unread count, last message preview

### Priority 2: HIGH (Privacy)
2. **Sealed sender implementation**
   - Research Signal's sealed sender protocol
   - Modify message schema (remove from_user_id)
   - Add sender to encrypted envelope
   - Update iOS/Rust clients

3. **Message padding**
   - Pad all encrypted_blob to fixed size
   - Add padding/unpadding to C6P protocol

### Priority 3: MEDIUM (Privacy Enhancements)
4. **Timing obfuscation**
   - Add random delays (configurable)
   - Implement message batching

5. **Session rotation**
   - Auto-rotate session_id periodically
   - Update clients to handle rotation

### Priority 4: LOW (Cleanup)
6. **Remove redundant metadata**
   - Drop `from_convro_number`, `to_convro_number` columns
   - Use JOINs to users table instead

---

## 🚦 Current Status Summary

| Component | Status | Notes |
|-----------|--------|-------|
| Authentication | ✅ Complete | 4 endpoints working |
| Devices | ✅ Complete | 3 endpoints working |
| Prekeys | ✅ Complete | 3 endpoints working |
| Messages | ⚠️ Partial | Send/inbox work, **conversations missing** |
| **Conversations** | ❌ **MISSING** | **CRITICAL GAP** |
| Contacts | ❌ Not implemented | Planned but not built |
| Presence | ❌ Not implemented | Planned but not built |
| WebSocket | 🟡 Partial | Hub exists, no endpoint handler |
| **Metadata privacy** | ❌ **WEAK** | **Social graph exposed** |

---

## 📝 Action Items

### Immediate (Before Production):
- [ ] Design and implement conversations list (database + API)
- [ ] Document current metadata exposure clearly
- [ ] Add warnings about social graph visibility
- [ ] Consider sealed sender roadmap

### Short-term (v1.1):
- [ ] Implement sealed sender
- [ ] Add message padding
- [ ] Implement contacts API (referenced but not built)
- [ ] Implement presence API (referenced but not built)

### Long-term (v2.0):
- [ ] Timing obfuscation
- [ ] Session rotation
- [ ] Optional Tor integration
- [ ] Private group messaging

---

## ⚖️ Trade-offs Discussion

### Why Metadata Leakage Exists:

**Practical reasons:**
1. **Routing**: Server needs to know recipient to deliver message
2. **Offline delivery**: Need to queue messages for offline users
3. **Multi-device**: Need to track sessions per device
4. **Abuse prevention**: Need sender info for spam/block features

**Privacy vs Usability:**
- Signal: Sealed sender is **optional** (can be disabled for verified contacts)
- WhatsApp: No sealed sender (full metadata visible to server)
- Convro: Currently like WhatsApp (full visibility)

### Recommendation:

**For Convro v1.0:**
1. Ship with current metadata model (document clearly)
2. Add sealed sender as **optional privacy mode** in v1.1
3. Let users choose: convenience vs maximum privacy

**For differentiation:**
- Make sealed sender **default** (unlike Signal where it's opt-in)
- Add UI toggle: "Maximum Privacy Mode" with clear explanation

---

## 📋 Testing Checklist (Remaining)

- [ ] Test conversations list endpoint
- [ ] Verify unread count accuracy
- [ ] Test conversation sorting (by last_activity)
- [ ] Load test: 10,000 conversations per user
- [ ] Verify metadata exposure documentation
- [ ] Security audit: Review all stored metadata

---

**Report prepared by:** Claude (Session: claude/analyze-convro6-docs-eV0ZQ)
**Next steps:** Awaiting user decision on priorities
