# C6P Protocol - Complete System Architecture Plan

**Status:** 🚧 DRAFT - Awaiting Approval

This document outlines the complete architecture for a production-ready E2EE messaging system using C6P Protocol.

---

## Table of Contents

- [System Overview](#system-overview)
- [Convro Numbers System](#convro-numbers-system)
- [Server Architecture](#server-architecture)
- [Database Schema (PostgreSQL)](#database-schema-postgresql)
- [Authentication Flow](#authentication-flow)
- [Handshake Flow (Device-to-Device)](#handshake-flow-device-to-device)
- [Realtime Messaging](#realtime-messaging)
- [Example iOS App](#example-ios-app)
- [Security Considerations](#security-considerations)
- [Implementation Phases](#implementation-phases)

---

## System Overview

### High-Level Architecture

```
┌─────────────────┐         ┌─────────────────┐
│   iOS Device A  │         │   iOS Device B  │
│                 │         │                 │
│  ┌───────────┐  │         │  ┌───────────┐  │
│  │ C6P App   │  │         │  │ C6P App   │  │
│  │           │  │         │  │           │  │
│  │ Keychain  │  │         │  │ Keychain  │  │
│  └─────┬─────┘  │         │  └─────┬─────┘  │
│        │        │         │        │        │
└────────┼────────┘         └────────┼────────┘
         │                           │
         │  HTTPS + WebSocket        │
         │                           │
         └──────────┬────────────────┘
                    │
         ┌──────────▼──────────┐
         │                     │
         │   Convro Server     │
         │   (Rust + Axum)     │
         │                     │
         │  ┌──────────────┐   │
         │  │ Auth Service │   │
         │  ├──────────────┤   │
         │  │ Prekey Store │   │
         │  ├──────────────┤   │
         │  │ Message Relay│   │
         │  ├──────────────┤   │
         │  │ WebSocket Hub│   │
         │  └──────────────┘   │
         │                     │
         └──────────┬──────────┘
                    │
         ┌──────────▼──────────┐
         │                     │
         │   PostgreSQL DB     │
         │                     │
         │  • users            │
         │  • convro_numbers   │
         │  • device_identities│
         │  • prekey_bundles   │
         │  • sessions         │
         │  • messages         │
         │                     │
         └─────────────────────┘
```

### Key Design Decisions

1. **PostgreSQL over MariaDB/MySQL**
   - ✅ Better JSON support (for storing encrypted message blobs)
   - ✅ Advanced indexing (for message queues)
   - ✅ Full-text search (for Convro Number lookups)
   - ✅ Strong ACID guarantees
   - ✅ Better support for concurrent writes
   - ✅ Native UUID type

2. **Stateless C6P Design**
   - ✅ Server NEVER sees encryption keys
   - ✅ Server only relays encrypted messages
   - ✅ All keys stored in iOS Keychain
   - ✅ Zero-knowledge architecture

3. **Convro Numbers as Universal IDs**
   - ✅ Easy to remember: `+99 123 456`
   - ✅ Phone-like format (familiar UX)
   - ✅ Globally unique across system
   - ✅ No PII exposure (not real phone numbers)

---

## Convro Numbers System

### What is a Convro Number?

A **Convro Number** is a unique identifier for each user, similar to a phone number but completely synthetic.

**Format:** `+99 XXX XXX` (or `+99 XXX XXX XXX` for scaling)

**Example:**
- User A: `+99 123 456`
- User B: `+99 789 012`

### Why Convro Numbers?

| Feature | Convro Number | Phone Number | Username |
|---------|---------------|--------------|----------|
| **Privacy** | ✅ No PII | ❌ Personal data | ⚠️ May reveal identity |
| **Portability** | ✅ Device-independent | ❌ SIM-locked | ✅ Portable |
| **Memorability** | ✅ Numeric, short | ✅ Familiar | ⚠️ May be taken |
| **Global Uniqueness** | ✅ Guaranteed | ⚠️ Country codes | ❌ Collisions possible |
| **No Auth Required** | ✅ Self-generated | ❌ SMS verification | ⚠️ Email verification |

### Number Generation

#### Strategy 1: Sequential Allocation
```sql
-- Simple, predictable
SELECT nextval('convro_number_seq');
-- Returns: 123456, 123457, 123458, ...
```

**Pros:**
- ✅ Guaranteed unique
- ✅ No collisions
- ✅ Simple to implement

**Cons:**
- ⚠️ Reveals registration order
- ⚠️ Predictable (easy to enumerate users)

#### Strategy 2: Random with Collision Detection (Recommended)
```rust
fn generate_convro_number() -> String {
    loop {
        // Generate random 6-digit number: 100000-999999
        let number = rand::thread_rng().gen_range(100_000..1_000_000);
        let convro_number = format!("+99 {} {}",
            number / 1000,
            number % 1000
        );

        // Check if available in database
        if is_convro_number_available(&convro_number).await {
            return convro_number;
        }
    }
}
```

**Pros:**
- ✅ Non-predictable
- ✅ Privacy-friendly
- ✅ No enumeration attacks

**Cons:**
- ⚠️ Requires collision check
- ⚠️ Eventually exhausts namespace (999,000 numbers)

#### Strategy 3: Hybrid (Best for Production)
```rust
// Start with random allocation
// When utilization > 80%, switch to sequential
fn generate_convro_number(utilization: f64) -> String {
    if utilization < 0.8 {
        generate_random_convro_number() // Strategy 2
    } else {
        generate_sequential_convro_number() // Strategy 1
    }
}
```

### Formatting and Display

**Database:** `+99123456` (no spaces, for indexing)
**Display:** `+99 123 456` (with spaces, for UX)

```swift
// Swift formatting
extension String {
    func formatAsConvroNumber() -> String {
        // "+99123456" -> "+99 123 456"
        let digits = self.replacingOccurrences(of: "+99", with: "")
        guard digits.count == 6 else { return self }

        let part1 = String(digits.prefix(3))
        let part2 = String(digits.suffix(3))
        return "+99 \(part1) \(part2)"
    }
}
```

### Scaling Beyond 1 Million Users

**Option 1:** Add another digit: `+99 XXXX XXX` (10M users)
**Option 2:** Add country-like prefix: `+991 XXX XXX` (multiple realms)
**Option 3:** Vanity numbers: `+99 LOVE YOU` (premium feature)

---

## Server Architecture

### Technology Stack

**Language:** Rust 🦀
**Web Framework:** Axum (async, fast, type-safe)
**Database:** PostgreSQL 15+
**Realtime:** WebSockets (Tokio-Tungstenite)
**Auth:** JWT (JSON Web Tokens)
**Deployment:** Docker + docker-compose

### Server Components

#### 1. Auth Service
**Responsibilities:**
- User registration (create account + assign Convro Number)
- Login (username/password → JWT)
- JWT validation
- Device registration (store device identity)

**Endpoints:**
```
POST /api/v1/auth/register
  Body: { username, password }
  Returns: { user_id, convro_number, jwt_token }

POST /api/v1/auth/login
  Body: { convro_number, password }
  Returns: { jwt_token }

POST /api/v1/auth/register-device
  Headers: { Authorization: Bearer <jwt> }
  Body: { device_id, device_public_key, signed_prekey, one_time_prekeys[] }
  Returns: { success: true }
```

#### 2. Prekey Store Service
**Responsibilities:**
- Store signed prekeys for users
- Store one-time prekeys (OTP pool)
- Distribute prekeys for handshake initiation
- Track OTP consumption

**Endpoints:**
```
POST /api/v1/prekeys/upload
  Headers: { Authorization: Bearer <jwt> }
  Body: { signed_prekey, one_time_prekeys: [otp1, otp2, ...] }
  Returns: { uploaded: 25 }

GET /api/v1/prekeys/{convro_number}
  Headers: { Authorization: Bearer <jwt> }
  Returns: {
    device_id,
    identity_key,
    signed_prekey,
    one_time_prekey (optional)
  }
```

#### 3. Message Relay Service
**Responsibilities:**
- Accept encrypted messages from sender
- Queue messages for recipient
- Deliver when recipient is online (WebSocket)
- Store offline messages (PostgreSQL)

**Endpoints:**
```
POST /api/v1/messages/send
  Headers: { Authorization: Bearer <jwt> }
  Body: {
    to_convro_number,
    encrypted_message_blob,
    message_type: "handshake_offer" | "handshake_accept" | "encrypted_message"
  }
  Returns: { message_id, delivered: true/false }

GET /api/v1/messages/inbox
  Headers: { Authorization: Bearer <jwt> }
  Returns: { messages: [...] }
```

#### 4. WebSocket Hub
**Responsibilities:**
- Maintain persistent connections to online clients
- Push messages in realtime
- Presence tracking (online/offline status)
- Typing indicators (future)

**WebSocket Protocol:**
```json
// Client → Server
{
  "type": "authenticate",
  "token": "jwt_token_here"
}

// Server → Client (on new message)
{
  "type": "new_message",
  "from_convro_number": "+99 123 456",
  "message_id": "msg_abc123",
  "encrypted_blob": "base64_encrypted_data"
}

// Client → Server (mark delivered)
{
  "type": "ack",
  "message_id": "msg_abc123"
}
```

---

## Database Schema (PostgreSQL)

### Table: `users`
```sql
CREATE TABLE users (
    user_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    convro_number VARCHAR(15) UNIQUE NOT NULL,  -- "+99123456"
    username VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,  -- Argon2id hash
    created_at TIMESTAMP DEFAULT NOW(),
    last_login TIMESTAMP,

    -- Indexes
    INDEX idx_convro_number (convro_number),
    INDEX idx_username (username)
);
```

### Table: `device_identities`
Each user can have multiple devices (multi-device support).

```sql
CREATE TABLE device_identities (
    device_identity_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    device_id BYTEA NOT NULL,  -- Ed25519 public key (32 bytes)
    device_name VARCHAR(100),  -- "John's iPhone 14"
    identity_key BYTEA NOT NULL,  -- Long-term identity key
    registered_at TIMESTAMP DEFAULT NOW(),
    last_seen TIMESTAMP,

    UNIQUE(device_id),
    INDEX idx_user_devices (user_id)
);
```

### Table: `prekey_bundles`
Stores signed prekeys and one-time prekeys for handshake.

```sql
CREATE TABLE prekey_bundles (
    bundle_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_identity_id UUID REFERENCES device_identities(device_identity_id) ON DELETE CASCADE,

    -- Signed Prekey (long-lived, rotates weekly)
    signed_prekey BYTEA NOT NULL,
    signed_prekey_signature BYTEA NOT NULL,
    signed_prekey_id INTEGER NOT NULL,

    uploaded_at TIMESTAMP DEFAULT NOW(),

    INDEX idx_device_prekeys (device_identity_id)
);
```

### Table: `one_time_prekeys`
Pool of single-use prekeys.

```sql
CREATE TABLE one_time_prekeys (
    otp_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_identity_id UUID REFERENCES device_identities(device_identity_id) ON DELETE CASCADE,

    one_time_prekey BYTEA NOT NULL,
    otp_key_id INTEGER NOT NULL,

    -- Lifecycle
    uploaded_at TIMESTAMP DEFAULT NOW(),
    consumed_at TIMESTAMP NULL,
    consumed_by UUID REFERENCES users(user_id) NULL,

    INDEX idx_device_available_otps (device_identity_id, consumed_at)
);
```

**Query for handshake:**
```sql
-- Get prekey bundle for user
SELECT
    di.device_id,
    di.identity_key,
    pb.signed_prekey,
    pb.signed_prekey_signature,
    otp.one_time_prekey
FROM users u
JOIN device_identities di ON u.user_id = di.user_id
JOIN prekey_bundles pb ON di.device_identity_id = pb.device_identity_id
LEFT JOIN one_time_prekeys otp ON di.device_identity_id = otp.device_identity_id
    AND otp.consumed_at IS NULL
WHERE u.convro_number = '+99123456'
ORDER BY otp.uploaded_at ASC
LIMIT 1;

-- Mark OTP as consumed
UPDATE one_time_prekeys
SET consumed_at = NOW(), consumed_by = :initiator_user_id
WHERE otp_id = :otp_id;
```

### Table: `sessions`
Tracks E2EE sessions between devices.

```sql
CREATE TABLE sessions (
    session_id BYTEA PRIMARY KEY,  -- C6P session ID (32 bytes)

    -- Participants
    initiator_device_id UUID REFERENCES device_identities(device_identity_id),
    responder_device_id UUID REFERENCES device_identities(device_identity_id),

    -- Session metadata (NOT keys - keys never touch server)
    created_at TIMESTAMP DEFAULT NOW(),
    last_activity TIMESTAMP,
    message_count INTEGER DEFAULT 0,

    INDEX idx_initiator (initiator_device_id),
    INDEX idx_responder (responder_device_id)
);
```

### Table: `messages`
Stores encrypted messages (server can't read them).

```sql
CREATE TABLE messages (
    message_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Routing
    from_convro_number VARCHAR(15) NOT NULL,
    to_convro_number VARCHAR(15) NOT NULL,

    -- Message type
    message_type VARCHAR(20) NOT NULL,  -- 'handshake_offer', 'handshake_accept', 'encrypted_message'

    -- Encrypted payload (server-opaque blob)
    encrypted_blob BYTEA NOT NULL,

    -- Delivery tracking
    created_at TIMESTAMP DEFAULT NOW(),
    delivered_at TIMESTAMP NULL,
    read_at TIMESTAMP NULL,

    INDEX idx_recipient_undelivered (to_convro_number, delivered_at),
    INDEX idx_created_at (created_at)
);
```

### Table: `contacts`
User's contact list (optional - for UX).

```sql
CREATE TABLE contacts (
    contact_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(user_id) ON DELETE CASCADE,
    contact_convro_number VARCHAR(15) NOT NULL,
    display_name VARCHAR(100),  -- User-chosen name
    added_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(user_id, contact_convro_number),
    INDEX idx_user_contacts (user_id)
);
```

---

## Authentication Flow

### Registration Flow

```
┌─────────┐                          ┌─────────┐
│  iOS    │                          │ Server  │
│  App    │                          │         │
└────┬────┘                          └────┬────┘
     │                                    │
     │  1. User enters username/password  │
     ├────────────────────────────────────▶
     │  POST /api/v1/auth/register        │
     │  { username, password }            │
     │                                    │
     │                                    │  2. Server validates
     │                                    │     - Check username unique
     │                                    │     - Hash password (Argon2id)
     │                                    │     - Generate Convro Number
     │                                    │     - Create user in DB
     │                                    │
     │  3. Return credentials             │
     │◀────────────────────────────────────
     │  { user_id, convro_number, jwt }   │
     │                                    │
     │  4. App generates device identity  │
     │     identity_generate_identity()   │
     │                                    │
     │  5. App generates prekeys          │
     │     - 1 signed prekey              │
     │     - 25 one-time prekeys          │
     │                                    │
     │  6. Upload device + prekeys        │
     ├────────────────────────────────────▶
     │  POST /api/v1/auth/register-device │
     │  {                                 │
     │    device_id,                      │
     │    identity_key,                   │
     │    signed_prekey,                  │
     │    one_time_prekeys: [...]         │
     │  }                                 │
     │                                    │
     │  7. Success                        │
     │◀────────────────────────────────────
     │  { success: true }                 │
     │                                    │
     │  8. Store identity in Keychain     │
     │     KeychainManager.store()        │
     │                                    │
```

### Login Flow

```
┌─────────┐                          ┌─────────┐
│  iOS    │                          │ Server  │
│  App    │                          │         │
└────┬────┘                          └────┬────┘
     │                                    │
     │  1. User enters Convro # + password│
     ├────────────────────────────────────▶
     │  POST /api/v1/auth/login           │
     │  { convro_number, password }       │
     │                                    │
     │                                    │  2. Validate credentials
     │                                    │     - Lookup user by number
     │                                    │     - Verify password hash
     │                                    │     - Generate JWT token
     │                                    │
     │  3. Return JWT                     │
     │◀────────────────────────────────────
     │  { jwt_token, user_id }            │
     │                                    │
     │  4. Load device identity from      │
     │     Keychain                       │
     │                                    │
     │  5. Connect WebSocket              │
     ├────────────────────────────────────▶
     │  WS /api/v1/ws                     │
     │  { type: "auth", token: jwt }      │
     │                                    │
     │  6. Receive pending messages       │
     │◀────────────────────────────────────
     │  { type: "inbox", messages: [...] }│
     │                                    │
```

---

## Handshake Flow (Device-to-Device)

This is the **core E2EE establishment** between two users.

### Scenario: Alice wants to message Bob

**Alice's Convro Number:** `+99 123 456`
**Bob's Convro Number:** `+99 789 012`

### Step-by-Step Flow

```
┌──────────┐         ┌─────────┐         ┌──────────┐
│  Alice   │         │ Server  │         │   Bob    │
│ (iPhone) │         │         │         │ (iPhone) │
└────┬─────┘         └────┬────┘         └────┬─────┘
     │                    │                   │
     │ 1. Alice enters    │                   │
     │    Bob's number:   │                   │
     │    "+99 789 012"   │                   │
     │                    │                   │
     │ 2. Fetch Bob's     │                   │
     │    prekey bundle   │                   │
     ├────────────────────▶                   │
     │ GET /prekeys/      │                   │
     │     +99789012      │                   │
     │                    │                   │
     │ 3. Return bundle   │                   │
     │◀────────────────────                   │
     │ {                  │                   │
     │   device_id,       │                   │
     │   identity_key,    │                   │
     │   signed_prekey,   │                   │
     │   one_time_prekey  │                   │
     │ }                  │                   │
     │                    │                   │
     │ 4. Create handshake│                   │
     │    offer (C6P)     │                   │
     │    - 3DH/4DH key   │                   │
     │      agreement     │                   │
     │    - Derive session│                   │
     │      keys          │                   │
     │                    │                   │
     │ let (offer, keys)  │                   │
     │   = handshake_     │                   │
     │     create_offer() │                   │
     │                    │                   │
     │ 5. Store keys in   │                   │
     │    Keychain        │                   │
     │                    │                   │
     │ 6. Send offer to   │                   │
     │    server          │                   │
     ├────────────────────▶                   │
     │ POST /messages/send│                   │
     │ {                  │                   │
     │   to: +99789012,   │                   │
     │   type: handshake_ │                   │
     │         offer,     │                   │
     │   blob: <encrypted>│                   │
     │ }                  │                   │
     │                    │                   │
     │                    │ 7. Server relays  │
     │                    │    to Bob (WS)    │
     │                    ├──────────────────▶│
     │                    │ {                 │
     │                    │   type: new_msg,  │
     │                    │   from: +99123456,│
     │                    │   blob: <offer>   │
     │                    │ }                 │
     │                    │                   │
     │                    │ 8. Bob accepts    │
     │                    │    handshake      │
     │                    │                   │
     │                    │ let (accept, keys)│
     │                    │   = handshake_    │
     │                    │     accept_offer()│
     │                    │                   │
     │                    │ 9. Store keys     │
     │                    │    in Keychain    │
     │                    │                   │
     │                    │ 10. Send accept   │
     │                    │◀──────────────────│
     │                    │ POST /messages/   │
     │                    │      send         │
     │                    │ {                 │
     │                    │   to: +99123456,  │
     │                    │   type: handshake_│
     │                    │         accept,   │
     │                    │   blob: <accept>  │
     │                    │ }                 │
     │                    │                   │
     │ 11. Alice receives │                   │
     │     accept (WS)    │                   │
     │◀────────────────────                   │
     │ { blob: <accept> } │                   │
     │                    │                   │
     │ 12. Verify accept  │                   │
     │     (KC2 check)    │                   │
     │                    │                   │
     │ handshake_verify_  │                   │
     │   accept()         │                   │
     │                    │                   │
     │ ✅ Session         │                   │ ✅ Session
     │    ESTABLISHED     │                   │    ESTABLISHED
     │                    │                   │
     │ 13. Now both can encrypt/decrypt      │
     │     messages with session keys!       │
     │                    │                   │
```

### Code Example (Alice's Side)

```swift
// Alice initiates handshake with Bob

// 1. Fetch Bob's prekey bundle
let response = try await api.getPrekeyBundle(convroNumber: "+99 789 012")
let bobBundle = PrekeyBundle(
    deviceId: response.device_id,
    identityKey: response.identity_key,
    signedPrekey: response.signed_prekey,
    oneTimePrekey: response.one_time_prekey
)

// 2. Load Alice's identity from Keychain
let aliceIdentity = try KeychainManager.loadDeviceIdentity()

// 3. Create handshake offer
let result = try handshake_create_offer(
    initiator_identity: aliceIdentity,
    responder_bundle: bobBundle
)

// 4. Store session keys in Keychain (CRITICAL!)
try KeychainManager.storeSessionKeys(
    result.session_keys,
    for: result.offer.session_id
)

// 5. Send offer to server
try await api.sendMessage(
    to: "+99 789 012",
    type: .handshakeOffer,
    blob: result.offer.serialized
)

// 6. Wait for accept message (via WebSocket)
// ... handled by WebSocketManager
```

### Code Example (Bob's Side)

```swift
// Bob receives handshake offer via WebSocket

func handleIncomingMessage(_ message: IncomingMessage) async throws {
    guard message.type == .handshakeOffer else { return }

    // 1. Load Bob's identity from Keychain
    let bobIdentity = try KeychainManager.loadDeviceIdentity()

    // 2. Load Bob's signed prekey
    let signedPrekey = try KeychainManager.loadSignedPrekey()

    // 3. Accept handshake
    let result = try handshake_accept_offer(
        responder_identity: bobIdentity,
        responder_spk: signedPrekey,
        responder_otp: nil, // OTP already consumed by Alice
        offer_bytes: message.blob
    )

    // 4. Store session keys in Keychain
    try KeychainManager.storeSessionKeys(
        result.session_keys,
        for: result.accept.session_id
    )

    // 5. Send accept to Alice
    try await api.sendMessage(
        to: message.from_convro_number,
        type: .handshakeAccept,
        blob: result.accept.serialized
    )

    // ✅ Session established!
}
```

---

## Realtime Messaging

### WebSocket Protocol

**Connection:**
```
wss://api.convro.io/api/v1/ws
```

**Client Authentication:**
```json
{
  "type": "authenticate",
  "token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Server Response:**
```json
{
  "type": "auth_success",
  "user_id": "uuid-here",
  "convro_number": "+99 123 456"
}
```

### Message Types

#### 1. New Encrypted Message
```json
// Server → Client
{
  "type": "new_message",
  "message_id": "msg_abc123",
  "from_convro_number": "+99 789 012",
  "message_type": "encrypted_message",
  "encrypted_blob": "base64_encoded_encrypted_data_here",
  "timestamp": "2026-01-12T00:30:00Z"
}
```

#### 2. Delivery Acknowledgment
```json
// Client → Server
{
  "type": "ack",
  "message_id": "msg_abc123"
}
```

#### 3. Typing Indicator (Future)
```json
// Client → Server
{
  "type": "typing",
  "to_convro_number": "+99 789 012",
  "is_typing": true
}
```

#### 4. Presence Update (Future)
```json
// Server → Client
{
  "type": "presence",
  "convro_number": "+99 789 012",
  "status": "online" | "offline" | "away"
}
```

### Message Encryption Flow

```
┌──────────┐         ┌─────────┐         ┌──────────┐
│  Alice   │         │ Server  │         │   Bob    │
└────┬─────┘         └────┬────┘         └────┬─────┘
     │                    │                   │
     │ 1. Alice types     │                   │
     │    "Hello Bob!"    │                   │
     │                    │                   │
     │ 2. Load session    │                   │
     │    keys from       │                   │
     │    Keychain        │                   │
     │                    │                   │
     │ 3. Encrypt with    │                   │
     │    C6P session     │                   │
     │                    │                   │
     │ let encrypted =    │                   │
     │   session_encrypt( │                   │
     │     plaintext,     │                   │
     │     session_keys   │                   │
     │   )                │                   │
     │                    │                   │
     │ 4. Send encrypted  │                   │
     │    blob to server  │                   │
     ├────────────────────▶                   │
     │ POST /messages/send│                   │
     │ (or via WebSocket) │                   │
     │                    │                   │
     │                    │ 5. Server relays  │
     │                    │    (no decryption)│
     │                    ├──────────────────▶│
     │                    │ WS: new_message   │
     │                    │                   │
     │                    │ 6. Bob loads keys │
     │                    │    from Keychain  │
     │                    │                   │
     │                    │ 7. Decrypt with   │
     │                    │    C6P session    │
     │                    │                   │
     │                    │ let plaintext =   │
     │                    │   session_decrypt(│
     │                    │     encrypted,    │
     │                    │     session_keys  │
     │                    │   )               │
     │                    │                   │
     │                    │ 8. Display:       │
     │                    │    "Hello Bob!"   │
     │                    │                   │
```

---

## Example iOS App

### App Structure

```
ConvroApp/
├── App/
│   ├── ConvroApp.swift              # App entry point
│   └── AppDelegate.swift            # App lifecycle
│
├── Core/
│   ├── Managers/
│   │   ├── C6PManager.swift         # C6P protocol wrapper
│   │   ├── KeychainManager.swift   # Secure storage
│   │   ├── APIManager.swift        # Server API client
│   │   └── WebSocketManager.swift  # Realtime connection
│   │
│   ├── Models/
│   │   ├── User.swift              # User model
│   │   ├── Contact.swift           # Contact model
│   │   ├── Message.swift           # Message model
│   │   └── Session.swift           # E2EE session model
│   │
│   └── Services/
│       ├── AuthService.swift       # Authentication
│       └── MessageService.swift    # Message handling
│
├── Features/
│   ├── Authentication/
│   │   ├── Views/
│   │   │   ├── LoginView.swift
│   │   │   └── RegisterView.swift
│   │   └── ViewModels/
│   │       └── AuthViewModel.swift
│   │
│   ├── Contacts/
│   │   ├── Views/
│   │   │   ├── ContactListView.swift
│   │   │   └── AddContactView.swift
│   │   └── ViewModels/
│   │       └── ContactsViewModel.swift
│   │
│   ├── Chat/
│   │   ├── Views/
│   │   │   ├── ConversationListView.swift
│   │   │   ├── ChatView.swift
│   │   │   └── MessageBubble.swift
│   │   └── ViewModels/
│   │       └── ChatViewModel.swift
│   │
│   └── Settings/
│       ├── Views/
│       │   └── SettingsView.swift
│       └── ViewModels/
│           └── SettingsViewModel.swift
│
└── Resources/
    ├── Assets.xcassets/
    └── Localizable.strings
```

### Key Screens

#### 1. Registration Screen
```
┌─────────────────────────────────┐
│  Create Your Convro Account     │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Username                  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Password                  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Confirm Password          │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │   Create Account          │  │
│  └───────────────────────────┘  │
│                                 │
│  After registration, you'll     │
│  receive your unique Convro     │
│  Number: +99 XXX XXX            │
└─────────────────────────────────┘
```

#### 2. Login Screen
```
┌─────────────────────────────────┐
│  Welcome Back!                  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Convro Number             │  │
│  │ +99 123 456               │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Password                  │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │   Sign In                 │  │
│  └───────────────────────────┘  │
│                                 │
│  Don't have an account?         │
│  Create one                     │
└─────────────────────────────────┘
```

#### 3. Home Screen (Conversation List)
```
┌─────────────────────────────────┐
│  Convro        🔔  ⚙️            │
│  +99 123 456 (Your Number)      │
├─────────────────────────────────┤
│                                 │
│  🔍 Search contacts...          │
│                                 │
│  ┌─────────────────────────┐   │
│  │ 👤 Alice                │   │
│  │ +99 456 789             │   │
│  │ Hey! How are you? 🔒    │   │
│  │                    2:30p│   │
│  └─────────────────────────┘   │
│                                 │
│  ┌─────────────────────────┐   │
│  │ 👤 Bob                  │   │
│  │ +99 789 012             │   │
│  │ See you tomorrow 🔒     │   │
│  │                 Yesterday│   │
│  └─────────────────────────┘   │
│                                 │
│  [+] New Chat                   │
└─────────────────────────────────┘
```

#### 4. Chat Screen
```
┌─────────────────────────────────┐
│ < Back                          │
│  👤 Alice (+99 456 789)         │
│  🔒 End-to-End Encrypted        │
├─────────────────────────────────┤
│                                 │
│           ┌─────────────────┐   │
│           │ Hey! How are    │   │
│           │ you?            │   │
│           │          2:30p  │   │
│           └─────────────────┘   │
│                                 │
│  ┌─────────────────┐            │
│  │ I'm great! You? │            │
│  │ 2:31p           │            │
│  └─────────────────┘            │
│                                 │
│           ┌─────────────────┐   │
│           │ Same here! Want │   │
│           │ to grab coffee? │   │
│           │          2:32p  │   │
│           └─────────────────┘   │
│                                 │
├─────────────────────────────────┤
│  ┌───────────────────────┐ 🎤  │
│  │ Type a message...     │     │
│  └───────────────────────┘     │
└─────────────────────────────────┘
```

#### 5. Add Contact Screen
```
┌─────────────────────────────────┐
│  Add New Contact                │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Convro Number             │  │
│  │ +99 789 012               │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │ Display Name (optional)   │  │
│  │ Bob Smith                 │  │
│  └───────────────────────────┘  │
│                                 │
│  ┌───────────────────────────┐  │
│  │   Add Contact             │  │
│  └───────────────────────────┘  │
│                                 │
│  💡 Tip: Ask your friend for    │
│     their Convro Number to      │
│     start chatting securely!    │
└─────────────────────────────────┘
```

### Features

**Must Have (v1.0):**
- ✅ User registration + login
- ✅ Convro Number assignment
- ✅ Contact management (add by Convro Number)
- ✅ E2EE handshake flow
- ✅ Send/receive encrypted messages
- ✅ Realtime delivery (WebSocket)
- ✅ Offline message queue
- ✅ Message persistence (local SQLite)
- ✅ Keychain integration for keys
- ✅ Session management

**Nice to Have (v1.1+):**
- ⏳ Typing indicators
- ⏳ Read receipts
- ⏳ Profile pictures
- ⏳ QR code sharing (for Convro Number)
- ⏳ Push notifications
- ⏳ Group chats (future)
- ⏳ Voice messages (future)

---

## Security Considerations

### 1. Server Trust Model

**What the server NEVER sees:**
- ❌ Encryption keys (all keys in iOS Keychain)
- ❌ Message plaintext (only encrypted blobs)
- ❌ Session keys (derived on-device)

**What the server DOES see:**
- ✅ Metadata (who sends to whom, when)
- ✅ Convro Numbers (for routing)
- ✅ Message sizes (ciphertext length)
- ✅ Online status (WebSocket connections)

**Mitigation:**
- Future: Sealed sender (hide sender metadata)
- Future: Padding (hide message sizes)
- Future: Onion routing (hide IP addresses)

### 2. Key Rotation

**Signed Prekeys:**
- Rotate every 7 days
- Server notifies app when SPK is old

**One-Time Prekeys:**
- Upload 25 OTPs on registration
- Refill when < 5 remaining
- Server sends push notification

**Session Keys:**
- Ratchet forward after each message
- Old keys destroyed immediately

### 3. Database Security

**PostgreSQL Encryption:**
```sql
-- Enable at-rest encryption (PostgreSQL 12+)
ALTER SYSTEM SET ssl = on;

-- Encrypt specific columns (for extra paranoia)
CREATE EXTENSION pgcrypto;

-- Though not needed - messages already encrypted by C6P!
```

**Access Control:**
```sql
-- Server app user (limited permissions)
CREATE USER convro_app WITH PASSWORD 'strong_password';
GRANT SELECT, INSERT, UPDATE ON users TO convro_app;
GRANT SELECT, INSERT, UPDATE ON messages TO convro_app;
-- No DELETE or DROP permissions!

-- Admin user (for migrations only)
CREATE USER convro_admin WITH PASSWORD 'admin_password';
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO convro_admin;
```

### 4. JWT Security

**Token Structure:**
```json
{
  "user_id": "uuid",
  "convro_number": "+99123456",
  "exp": 1705104000,  // 7 days expiration
  "iat": 1704499200
}
```

**Validation:**
- ✅ Verify signature (HMAC-SHA256 or RS256)
- ✅ Check expiration
- ✅ Validate issuer
- ✅ Check not-before (nbf)

**Storage:**
- Store in iOS Keychain (not UserDefaults!)

---

## Implementation Phases

### Phase 1: Foundation (Weeks 1-2)
**Goal:** Basic infrastructure

- [ ] PostgreSQL schema setup
- [ ] Rust server skeleton (Axum)
- [ ] JWT authentication
- [ ] User registration endpoint
- [ ] Login endpoint
- [ ] Convro Number generation

**Deliverables:**
- Users can register and get a Convro Number
- Users can log in and receive JWT
- Database schema deployed

### Phase 2: Prekey Infrastructure (Week 3)
**Goal:** Enable handshakes

- [ ] Prekey upload endpoint
- [ ] Prekey fetch endpoint
- [ ] OTP consumption logic
- [ ] Prekey rotation reminders

**Deliverables:**
- Devices can upload prekeys
- Devices can fetch prekey bundles
- OTPs marked as consumed

### Phase 3: Message Relay (Week 4)
**Goal:** Server can relay encrypted messages

- [ ] Send message endpoint
- [ ] Inbox fetch endpoint
- [ ] Message persistence
- [ ] Delivery tracking

**Deliverables:**
- Messages stored in database
- Users can send encrypted blobs
- Users can fetch inbox

### Phase 4: WebSocket Realtime (Week 5)
**Goal:** Live message delivery

- [ ] WebSocket connection handler
- [ ] Client authentication (JWT over WS)
- [ ] Message push to online clients
- [ ] Presence tracking

**Deliverables:**
- Clients connect via WebSocket
- Messages delivered in realtime
- Fallback to inbox for offline users

### Phase 5: iOS App - Auth (Week 6)
**Goal:** Users can register and log in

- [ ] Registration UI
- [ ] Login UI
- [ ] API client integration
- [ ] Keychain storage for JWT

**Deliverables:**
- Working registration flow
- Working login flow
- Convro Number displayed

### Phase 6: iOS App - Handshake (Week 7)
**Goal:** E2EE session establishment

- [ ] Device identity generation on first launch
- [ ] Prekey upload on registration
- [ ] Fetch prekey bundle for contact
- [ ] Handshake UI (loading states)
- [ ] Session key storage

**Deliverables:**
- Two devices can complete handshake
- Session keys stored in Keychain

### Phase 7: iOS App - Messaging (Week 8)
**Goal:** Send/receive encrypted messages

- [ ] Chat UI (SwiftUI)
- [ ] Message encryption (C6P)
- [ ] Message decryption (C6P)
- [ ] Local message persistence (SQLite)
- [ ] WebSocket integration

**Deliverables:**
- Users can send encrypted messages
- Users can receive and decrypt messages
- Messages display in chat UI

### Phase 8: Polish & Testing (Week 9-10)
**Goal:** Production-ready

- [ ] Error handling (network, crypto, server)
- [ ] Offline mode (queue messages)
- [ ] UI polish (animations, loading states)
- [ ] Integration tests
- [ ] Security audit of app flow

**Deliverables:**
- Robust error handling
- Smooth UX
- No crashes

---

## Technology Choices Summary

| Component | Technology | Why? |
|-----------|-----------|------|
| **Server Language** | Rust | Memory-safe, fast, async |
| **Web Framework** | Axum | Type-safe, ergonomic, Tokio-native |
| **Database** | PostgreSQL 15+ | JSON support, ACID, performance |
| **Auth** | JWT (HMAC-SHA256) | Stateless, standard, secure |
| **Realtime** | WebSockets (Tokio-Tungstenite) | Low latency, bidirectional |
| **iOS App** | Swift + SwiftUI | Native performance, modern UI |
| **iOS Storage** | Keychain + SQLite | Secure keys + local message cache |
| **C6P Integration** | XCFramework + SPM | Native Rust crypto via UniFFI |

---

## Open Questions for Approval

1. **Convro Number Generation:**
   - Random with collision detection? ✅ (Recommended)
   - Sequential? (Simple but predictable)
   - Hybrid? (Random until 80% full)

2. **Multi-Device Support:**
   - v1.0: Single device per user
   - v1.1: Multiple devices (requires linked devices)

3. **Message Retention:**
   - Server deletes delivered messages? (Privacy-first)
   - Server keeps messages for X days? (Reliability-first)

4. **Push Notifications:**
   - v1.0: Poll when app is in foreground
   - v1.1: APNs integration for background delivery

5. **Server Deployment:**
   - Docker Compose (for prototype)
   - Kubernetes (for production scale)

---

## Next Steps

**Awaiting your approval on:**
1. ✅ PostgreSQL as database (vs MariaDB)
2. ✅ Convro Numbers format (`+99 XXX XXX`)
3. ✅ Rust + Axum for server
4. ✅ WebSockets for realtime
5. ⏳ Random Convro Number generation strategy
6. ⏳ Message retention policy
7. ⏳ Multi-device support timeline

**Once approved, I will:**
1. Create detailed PostgreSQL migration files
2. Implement Rust server skeleton
3. Build iOS app prototype
4. Write integration tests

---

**Ready to build the future of private messaging! 🚀🔐**

Let me know what you think and what needs adjustment!
