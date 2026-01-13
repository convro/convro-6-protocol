# Convro API Specification v1.1

**Version:** 1.1.0
**Base URL:** `https://api.convro.app/v1`
**Protocol:** REST + WebSocket
**Authentication:** JWT (Bearer token)
**Format:** JSON

---

## Table of Contents

1. [Authentication](#1-authentication)
2. [User Management](#2-user-management)
3. [Device Management](#3-device-management)
4. [Prekey Operations](#4-prekey-operations)
5. [Messaging](#5-messaging)
6. [Conversations](#6-conversations)
7. [Sealed Sender Messages](#7-sealed-sender-messages)
8. [Contacts](#8-contacts)
9. [Presence](#9-presence)
10. [WebSocket Protocol](#10-websocket-protocol)
11. [Error Codes](#11-error-codes)
12. [Rate Limiting](#12-rate-limiting)
13. [Security](#13-security)

---

## 1. Authentication

### 1.1 Register User

Creates a new user account and assigns a Convro Number.

**Endpoint:** `POST /auth/register`

**Request:**
```json
{
  "username": "alice_smith",
  "password": "SecurePassword123!",
  "display_name": "Alice Smith"
}
```

**Response:** `201 Created`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice_smith",
  "convro_number": "+99 123 456",
  "display_name": "Alice Smith",
  "created_at": "2026-01-12T10:30:00Z",
  "tokens": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 3600,
    "token_type": "Bearer"
  }
}
```

**Errors:**
- `400` - Invalid username/password format
- `409` - Username already exists
- `503` - Convro Number pool exhausted

---

### 1.2 Login

Authenticates existing user and returns JWT tokens.

**Endpoint:** `POST /auth/login`

**Request:**
```json
{
  "username": "alice_smith",
  "password": "SecurePassword123!"
}
```

**Response:** `200 OK`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice_smith",
  "convro_number": "+99 123 456",
  "display_name": "Alice Smith",
  "tokens": {
    "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
    "expires_in": 3600,
    "token_type": "Bearer"
  }
}
```

**Errors:**
- `401` - Invalid credentials
- `429` - Too many login attempts (rate limit)

---

### 1.3 Refresh Token

Obtains new access token using refresh token.

**Endpoint:** `POST /auth/refresh`

**Request:**
```json
{
  "refresh_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response:** `200 OK`
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "expires_in": 3600,
  "token_type": "Bearer"
}
```

**Errors:**
- `401` - Invalid or expired refresh token

---

### 1.4 Logout

Invalidates current tokens.

**Endpoint:** `POST /auth/logout`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `204 No Content`

---

## 2. User Management

### 2.1 Get Current User Profile

Returns authenticated user's profile.

**Endpoint:** `GET /users/me`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `200 OK`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice_smith",
  "convro_number": "+99 123 456",
  "display_name": "Alice Smith",
  "created_at": "2026-01-10T08:00:00Z",
  "last_login": "2026-01-12T10:30:00Z",
  "account_status": "active"
}
```

---

### 2.2 Search User by Convro Number

Looks up user by their Convro Number (for adding contacts).

**Endpoint:** `GET /users/search?convro_number={number}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `convro_number` (required): Convro Number to search (e.g., `+99123456`)

**Response:** `200 OK`
```json
{
  "user_id": "660e8400-e29b-41d4-a716-446655440001",
  "convro_number": "+99 654 321",
  "display_name": "Bob Jones",
  "identity_fingerprint": "A1B2C3D4E5F67890...",
  "created_at": "2026-01-11T12:00:00Z"
}
```

**Errors:**
- `404` - User not found

---

### 2.3 Update Profile

Updates user's display name.

**Endpoint:** `PATCH /users/me`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "display_name": "Alice Marie Smith"
}
```

**Response:** `200 OK`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "username": "alice_smith",
  "convro_number": "+99 123 456",
  "display_name": "Alice Marie Smith",
  "updated_at": "2026-01-12T11:00:00Z"
}
```

---

## 3. Device Management

### 3.1 Register Device

Registers a new device identity for multi-device support.

**Endpoint:** `POST /devices`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "device_id": "a1b2c3d4e5f6...",
  "identity_key": "1234567890abcdef...",
  "device_name": "Alice's iPhone 14 Pro",
  "device_platform": "ios",
  "device_os_version": "17.2",
  "app_version": "1.0.0"
}
```

**Response:** `201 Created`
```json
{
  "device_identity_id": "770e8400-e29b-41d4-a716-446655440002",
  "device_id": "a1b2c3d4e5f6...",
  "identity_key": "1234567890abcdef...",
  "device_name": "Alice's iPhone 14 Pro",
  "registered_at": "2026-01-12T10:35:00Z",
  "is_active": true
}
```

**Errors:**
- `409` - Device already registered

---

### 3.2 List User Devices

Returns all devices for authenticated user.

**Endpoint:** `GET /devices`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `200 OK`
```json
{
  "devices": [
    {
      "device_identity_id": "770e8400-e29b-41d4-a716-446655440002",
      "device_id": "a1b2c3d4e5f6...",
      "device_name": "Alice's iPhone 14 Pro",
      "device_platform": "ios",
      "registered_at": "2026-01-12T10:35:00Z",
      "last_seen": "2026-01-12T11:00:00Z",
      "is_active": true
    },
    {
      "device_identity_id": "770e8400-e29b-41d4-a716-446655440003",
      "device_id": "f6e5d4c3b2a1...",
      "device_name": "Alice's iPad Pro",
      "device_platform": "ios",
      "registered_at": "2026-01-10T14:00:00Z",
      "last_seen": "2026-01-11T18:30:00Z",
      "is_active": true
    }
  ]
}
```

---

### 3.3 Deactivate Device

Deactivates a device (revokes access).

**Endpoint:** `DELETE /devices/{device_identity_id}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `204 No Content`

**Errors:**
- `404` - Device not found
- `403` - Cannot deactivate last device

---

## 4. Prekey Operations

### 4.1 Upload Prekeys

Uploads signed prekey + one-time prekeys for a device.

**Endpoint:** `POST /prekeys`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "device_identity_id": "770e8400-e29b-41d4-a716-446655440002",
  "signed_prekey": {
    "spk_id": 1,
    "public_key": "abcdef1234567890...",
    "signature": "fedcba0987654321...",
    "expires_at": "2026-01-19T10:35:00Z"
  },
  "one_time_prekeys": [
    {
      "otp_id": 1,
      "public_key": "11111111aaaaaaaa..."
    },
    {
      "otp_id": 2,
      "public_key": "22222222bbbbbbbb..."
    }
    // ... up to 100 OTPs
  ]
}
```

**Response:** `201 Created`
```json
{
  "bundle_id": "880e8400-e29b-41d4-a716-446655440004",
  "device_identity_id": "770e8400-e29b-41d4-a716-446655440002",
  "spk_id": 1,
  "otps_uploaded": 25,
  "uploaded_at": "2026-01-12T10:40:00Z"
}
```

**Errors:**
- `400` - Invalid prekey format
- `409` - SPK ID already exists (must increment)

---

### 4.2 Fetch Prekey Bundle

Retrieves prekey bundle for initiating handshake.

**Endpoint:** `GET /prekeys/{convro_number}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Path Parameters:**
- `convro_number`: Target user's Convro Number (e.g., `+99654321`)

**Response:** `200 OK`
```json
{
  "user_id": "660e8400-e29b-41d4-a716-446655440001",
  "convro_number": "+99 654 321",
  "device_identity_id": "770e8400-e29b-41d4-a716-446655440005",
  "device_id": "f6e5d4c3b2a1...",
  "identity_key": "9876543210fedcba...",
  "signed_prekey": {
    "spk_id": 1,
    "public_key": "abcdef1234567890...",
    "signature": "fedcba0987654321..."
  },
  "one_time_prekey": {
    "otp_id": "990e8400-e29b-41d4-a716-446655440006",
    "public_key": "11111111aaaaaaaa..."
  }
}
```

**Notes:**
- `one_time_prekey` is **reserved** for 5 minutes (not consumed yet)
- If no OTPs available, field is `null` (fallback to 3DH)

**Errors:**
- `404` - User not found or no active devices
- `503` - No prekeys available (user needs to upload)

---

### 4.3 Get Prekey Health Status

Returns prekey pool status for user's devices.

**Endpoint:** `GET /prekeys/health`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `200 OK`
```json
{
  "devices": [
    {
      "device_identity_id": "770e8400-e29b-41d4-a716-446655440002",
      "device_name": "Alice's iPhone 14 Pro",
      "has_signed_prekey": true,
      "spk_expires_at": "2026-01-19T10:35:00Z",
      "available_otps": 18,
      "consumed_otps": 7,
      "status": "healthy"
    }
  ]
}
```

**Status Values:**
- `healthy`: >= 10 OTPs available
- `low`: 1-9 OTPs available
- `critical`: 0 OTPs available
- `expired`: SPK expired

---

## 5. Messaging

### 5.1 Send Message

Sends encrypted message (handshake offer, accept, or encrypted message).

**Endpoint:** `POST /messages`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "to_convro_number": "+99 654 321",
  "message_type": "encrypted_message",
  "session_id": "abcdef1234567890...",
  "encrypted_blob": "base64_encrypted_data_here...",
  "metadata": {
    "content_type": "text",
    "size_bytes": 1024
  }
}
```

**Message Types:**
- `handshake_offer`: Initial handshake offer
- `handshake_accept`: Handshake accept response
- `encrypted_message`: Regular encrypted message

**Response:** `201 Created`
```json
{
  "message_id": "aa0e8400-e29b-41d4-a716-446655440007",
  "from_convro_number": "+99 123 456",
  "to_convro_number": "+99 654 321",
  "message_type": "encrypted_message",
  "created_at": "2026-01-12T11:05:00Z",
  "delivery_status": "pending"
}
```

**Errors:**
- `404` - Recipient not found
- `413` - Message too large (max 10MB)
- `429` - Rate limit exceeded

---

### 5.2 Fetch Inbox

Retrieves undelivered messages for authenticated user.

**Endpoint:** `GET /messages/inbox`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `limit` (optional): Max messages to return (default: 50, max: 100)
- `offset` (optional): Pagination offset (default: 0)

**Response:** `200 OK`
```json
{
  "messages": [
    {
      "message_id": "aa0e8400-e29b-41d4-a716-446655440007",
      "from_convro_number": "+99 654 321",
      "to_convro_number": "+99 123 456",
      "message_type": "encrypted_message",
      "session_id": "abcdef1234567890...",
      "encrypted_blob": "base64_encrypted_data...",
      "created_at": "2026-01-12T11:05:00Z"
    }
  ],
  "total": 1,
  "limit": 50,
  "offset": 0
}
```

---

### 5.3 Mark Message as Delivered

Acknowledges message delivery (removes from inbox).

**Endpoint:** `POST /messages/{message_id}/delivered`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `204 No Content`

**Errors:**
- `404` - Message not found or already delivered

---

### 5.4 Get Message History

Retrieves message history for a session (for debugging/admin).

**Endpoint:** `GET /messages/history?session_id={session_id}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `session_id` (required): Session ID (hex string)
- `limit` (optional): Max messages (default: 50)
- `offset` (optional): Pagination offset

**Response:** `200 OK`
```json
{
  "session_id": "abcdef1234567890...",
  "messages": [
    {
      "message_id": "aa0e8400-e29b-41d4-a716-446655440007",
      "from_convro_number": "+99 123 456",
      "to_convro_number": "+99 654 321",
      "message_type": "encrypted_message",
      "created_at": "2026-01-12T11:05:00Z",
      "delivered_at": "2026-01-12T11:05:30Z"
    }
  ],
  "total": 15,
  "limit": 50,
  "offset": 0
}
```

---

## 6. Conversations

### 6.1 List Conversations

Returns authenticated user's conversation list with unread counts and last message info.

**Endpoint:** `GET /conversations`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `limit` (optional): Max conversations to return (default: 50, max: 100)
- `offset` (optional): Pagination offset (default: 0)

**Response:** `200 OK`
```json
{
  "conversations": [
    {
      "conversation_id": "550e8400_660e8400",
      "participant": {
        "user_id": "660e8400-e29b-41d4-a716-446655440001",
        "convro_number": "+99 654 321",
        "display_name": "Bob Jones"
      },
      "last_message": {
        "message_id": "aa0e8400-e29b-41d4-a716-446655440007",
        "message_type": "encrypted_message",
        "timestamp": "2026-01-12T11:05:00Z"
      },
      "unread_count": 3,
      "last_activity": "2026-01-12T11:05:00Z"
    },
    {
      "conversation_id": "550e8400_770e8400",
      "participant": {
        "user_id": "770e8400-e29b-41d4-a716-446655440003",
        "convro_number": "+99 111 222",
        "display_name": "Carol Smith"
      },
      "last_message": null,
      "unread_count": 0,
      "last_activity": "2026-01-11T18:30:00Z"
    }
  ],
  "total": 12,
  "limit": 50,
  "offset": 0
}
```

**Notes:**
- Conversations are aggregated from `sessions` and `messages` tables
- Sorted by `last_activity` DESC (most recent first)
- Only includes active sessions
- `unread_count` reflects pending messages for the user
- `last_message` is `null` if conversation has no messages yet

**Errors:**
- `401` - Unauthorized (invalid/expired token)

---

## 7. Sealed Sender Messages

**Privacy Mode:** Sealed sender messages hide sender identity from the server for maximum privacy.

**Key Features:**
- ✅ Sender identity encrypted inside envelope (server only sees recipient)
- ✅ Fixed 64KB message size (hides actual content length)
- ✅ Timestamp obfuscation (rounded to 5-minute intervals)
- ✅ Timing jitter (random 0-5 second delivery delay)

**Comparison:**

| Feature | Standard Messages | Sealed Sender | Signal |
|---------|------------------|---------------|--------|
| Server sees sender | ✅ Yes | ❌ No | ❌ No (optional) |
| Server sees recipient | ✅ Yes | ✅ Yes (routing only) | ✅ Yes |
| Message size visible | ✅ Yes | ❌ No (64KB padding) | ✅ Yes |
| Timestamp precision | ✅ Millisecond | ❌ 5-minute intervals | ✅ Millisecond |

---

### 7.1 Send Sealed Message

Sends a sealed sender message where the sender identity is hidden from the server.

**Endpoint:** `POST /messages/sealed`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "to_convro_number": "+99 654 321",
  "encrypted_envelope": "base64_encoded_64kb_envelope_here..."
}
```

**Envelope Format:**
- Total size: **Exactly 64KB (65536 bytes)**
- Structure: `[4-byte length prefix][actual encrypted data][zero padding]`
- Encryption: AEAD (AES-256-GCM or ChaCha20-Poly1305)
- Contains: `from_user_id` + `message_content` + `timestamp` (all encrypted)

**Response:** `201 Created`
```json
{
  "message_id": "bb0e8400-e29b-41d4-a716-446655440009",
  "delivery_status": "pending",
  "created_at": "2026-01-12T11:05:00Z"
}
```

**Notes:**
- `created_at` is **obfuscated** (rounded to 5-minute intervals)
- Server applies **timing jitter** (0-5 second delay) before delivery
- Sender identity is **NOT** stored in database
- Message is routed to recipient's sealed inbox

**Errors:**
- `400` - Invalid base64 encoding or envelope not exactly 64KB
- `404` - Recipient Convro Number not found
- `413` - Payload exceeds 64KB limit
- `429` - Rate limit exceeded

---

### 7.2 Fetch Sealed Inbox

Retrieves pending sealed sender messages for authenticated user.

**Endpoint:** `GET /messages/sealed/inbox`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `limit` (optional): Max messages to return (default: 50, max: 100)
- `offset` (optional): Pagination offset (default: 0)

**Response:** `200 OK`
```json
{
  "messages": [
    {
      "message_id": "bb0e8400-e29b-41d4-a716-446655440009",
      "encrypted_envelope": "base64_encoded_64kb_envelope...",
      "created_at": "2026-01-12T11:05:00Z",
      "delivery_status": "pending"
    },
    {
      "message_id": "cc0e8400-e29b-41d4-a716-446655440010",
      "encrypted_envelope": "base64_encoded_64kb_envelope...",
      "created_at": "2026-01-12T11:00:00Z",
      "delivery_status": "pending"
    }
  ],
  "total": 2,
  "limit": 50,
  "offset": 0
}
```

**Client-Side Processing:**
1. Download encrypted envelopes
2. Try decrypting with all active session keys
3. Extract sender identity from decrypted envelope
4. Verify AEAD authentication tag
5. Mark as delivered after successful decryption

**Notes:**
- Server has **no knowledge** of message sender
- Client must try multiple session keys to find correct one
- Failed decryption = message not for this user (or corrupted)
- Only `pending` messages are returned

---

### 7.3 Mark Sealed Message as Delivered

Acknowledges receipt of sealed message (removes from inbox).

**Endpoint:** `POST /messages/sealed/{message_id}/delivered`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Path Parameters:**
- `message_id`: UUID of the sealed message

**Response:** `204 No Content`

**Errors:**
- `404` - Message not found or already delivered
- `403` - Message does not belong to authenticated user

**Notes:**
- Once marked as delivered, message cannot be re-fetched
- Server automatically deletes delivered messages after 30 days
- Undelivered messages expire after 30 days and are deleted

---

### 7.4 Privacy Guarantees

**What the Server Knows (Sealed Sender):**
- ✅ Recipient Convro Number (for routing)
- ✅ Approximate timestamp (5-minute intervals)
- ✅ Message count per recipient

**What the Server Does NOT Know:**
- ❌ Sender identity
- ❌ Actual message size (always 64KB)
- ❌ Precise timestamp (obfuscated)
- ❌ Message content (encrypted)
- ❌ Relationship between sender and recipient

**Threat Model:**
- **Malicious Server:** Cannot build social graph from sealed sender messages
- **Network Observer:** Cannot infer message size (all messages are 64KB)
- **Timing Attacks:** Mitigated by 5-minute timestamp rounding + random jitter
- **Traffic Analysis:** Partially mitigated (size hidden, timing obfuscated)

**Limitations:**
- Recipient identity must be visible for routing
- Global passive adversary can still perform traffic correlation
- Recommend using Tor/VPN for network-level anonymity

---

## 8. Contacts

### 8.1 Add Contact

Adds user to contact list (by Convro Number).

**Endpoint:** `POST /contacts`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "convro_number": "+99 654 321",
  "display_name": "Bob Jones"
}
```

**Response:** `201 Created`
```json
{
  "contact_id": "bb0e8400-e29b-41d4-a716-446655440008",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "contact_convro_number": "+99 654 321",
  "contact_user_id": "660e8400-e29b-41d4-a716-446655440001",
  "display_name": "Bob Jones",
  "is_verified": false,
  "added_at": "2026-01-12T11:10:00Z"
}
```

**Errors:**
- `404` - Convro Number not found
- `409` - Contact already exists

---

### 8.2 List Contacts

Returns user's contact list.

**Endpoint:** `GET /contacts`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `200 OK`
```json
{
  "contacts": [
    {
      "contact_id": "bb0e8400-e29b-41d4-a716-446655440008",
      "convro_number": "+99 654 321",
      "display_name": "Bob Jones",
      "is_verified": true,
      "verified_at": "2026-01-12T12:00:00Z",
      "added_at": "2026-01-12T11:10:00Z"
    }
  ]
}
```

---

### 8.3 Verify Contact

Marks contact as verified (after out-of-band fingerprint check).

**Endpoint:** `POST /contacts/{contact_id}/verify`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `200 OK`
```json
{
  "contact_id": "bb0e8400-e29b-41d4-a716-446655440008",
  "is_verified": true,
  "verified_at": "2026-01-12T12:00:00Z"
}
```

---

### 8.4 Remove Contact

Removes contact from list.

**Endpoint:** `DELETE /contacts/{contact_id}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Response:** `204 No Content`

---

## 9. Presence

### 9.1 Update Presence

Updates user's online/offline status.

**Endpoint:** `POST /presence`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Request:**
```json
{
  "status": "online",
  "ws_connection_id": "conn_abc123"
}
```

**Status Values:**
- `online`: User is active
- `away`: User inactive for > 5 minutes
- `offline`: User disconnected

**Response:** `200 OK`
```json
{
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "status": "online",
  "updated_at": "2026-01-12T12:05:00Z"
}
```

---

### 9.2 Get Contact Presence

Returns presence status for contacts.

**Endpoint:** `GET /presence?convro_numbers={numbers}`

**Headers:**
```
Authorization: Bearer {access_token}
```

**Query Parameters:**
- `convro_numbers`: Comma-separated list (e.g., `+99654321,+99111222`)

**Response:** `200 OK`
```json
{
  "presence": [
    {
      "convro_number": "+99 654 321",
      "status": "online",
      "last_seen": "2026-01-12T12:05:00Z"
    },
    {
      "convro_number": "+99 111 222",
      "status": "offline",
      "last_seen": "2026-01-12T10:00:00Z"
    }
  ]
}
```

---

## 10. WebSocket Protocol

### 10.1 Connection

**URL:** `wss://ws.convro.app/v1/stream`

**Connection Flow:**
1. Client connects to WebSocket URL
2. Server sends `hello` message
3. Client sends `authenticate` message with JWT
4. Server responds with `authenticated` or `error`
5. Connection established

**Authentication:**
```json
{
  "type": "authenticate",
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
}
```

**Response:**
```json
{
  "type": "authenticated",
  "user_id": "550e8400-e29b-41d4-a716-446655440000",
  "convro_number": "+99 123 456",
  "connection_id": "conn_abc123"
}
```

---

### 10.2 Heartbeat

Client must send heartbeat every 30 seconds to keep connection alive.

**Client → Server:**
```json
{
  "type": "ping",
  "timestamp": "2026-01-12T12:10:00Z"
}
```

**Server → Client:**
```json
{
  "type": "pong",
  "timestamp": "2026-01-12T12:10:00Z"
}
```

**Timeout:** If no heartbeat for 60 seconds, server closes connection.

---

### 10.3 Message Delivery

**Server → Client** (new message):
```json
{
  "type": "message",
  "message_id": "aa0e8400-e29b-41d4-a716-446655440007",
  "from_convro_number": "+99 654 321",
  "to_convro_number": "+99 123 456",
  "message_type": "encrypted_message",
  "session_id": "abcdef1234567890...",
  "encrypted_blob": "base64_encrypted_data...",
  "created_at": "2026-01-12T11:05:00Z"
}
```

**Client → Server** (ACK):
```json
{
  "type": "ack",
  "message_id": "aa0e8400-e29b-41d4-a716-446655440007"
}
```

---

### 10.4 Typing Indicator

**Client → Server:**
```json
{
  "type": "typing",
  "to_convro_number": "+99 654 321",
  "session_id": "abcdef1234567890...",
  "is_typing": true
}
```

**Server → Recipient:**
```json
{
  "type": "typing",
  "from_convro_number": "+99 123 456",
  "session_id": "abcdef1234567890...",
  "is_typing": true
}
```

---

### 10.5 Presence Updates

**Server → Client** (contact came online):
```json
{
  "type": "presence",
  "convro_number": "+99 654 321",
  "status": "online",
  "timestamp": "2026-01-12T12:00:00Z"
}
```

---

### 10.6 Error Handling

**Server → Client:**
```json
{
  "type": "error",
  "error_code": "INVALID_MESSAGE_FORMAT",
  "message": "Message payload exceeds 10MB limit",
  "timestamp": "2026-01-12T12:00:00Z"
}
```

---

### 10.7 Disconnection

**Client → Server:**
```json
{
  "type": "disconnect",
  "reason": "client_initiated"
}
```

**Server Response:**
```json
{
  "type": "goodbye",
  "message": "Connection closed gracefully"
}
```

Server then closes WebSocket connection.

---

## 11. Error Codes

### HTTP Status Codes

| Code | Meaning | Usage |
|------|---------|-------|
| `200` | OK | Successful GET/PATCH/POST |
| `201` | Created | Resource created (POST) |
| `204` | No Content | Successful DELETE |
| `400` | Bad Request | Invalid request format |
| `401` | Unauthorized | Missing/invalid auth token |
| `403` | Forbidden | Insufficient permissions |
| `404` | Not Found | Resource not found |
| `409` | Conflict | Resource already exists |
| `413` | Payload Too Large | Message/file too large |
| `429` | Too Many Requests | Rate limit exceeded |
| `500` | Internal Server Error | Server error |
| `503` | Service Unavailable | Temporary unavailability |

---

### Application Error Codes

**Error Response Format:**
```json
{
  "error": {
    "code": "INVALID_CREDENTIALS",
    "message": "Username or password is incorrect",
    "details": {
      "field": "password",
      "reason": "incorrect_password"
    },
    "timestamp": "2026-01-12T12:00:00Z",
    "request_id": "req_abc123"
  }
}
```

**Error Codes:**

| Code | HTTP Status | Description |
|------|-------------|-------------|
| `INVALID_CREDENTIALS` | 401 | Login failed (wrong username/password) |
| `TOKEN_EXPIRED` | 401 | Access token expired (use refresh token) |
| `TOKEN_INVALID` | 401 | Token malformed or invalid signature |
| `USER_NOT_FOUND` | 404 | User with Convro Number not found |
| `DEVICE_NOT_FOUND` | 404 | Device identity not found |
| `MESSAGE_NOT_FOUND` | 404 | Message ID not found |
| `USERNAME_TAKEN` | 409 | Username already registered |
| `DEVICE_ALREADY_REGISTERED` | 409 | Device already registered |
| `CONTACT_ALREADY_EXISTS` | 409 | Contact already in list |
| `PREKEY_POOL_EXHAUSTED` | 503 | User has no OTPs available |
| `CONVRO_NUMBER_EXHAUSTED` | 503 | No Convro Numbers available |
| `RATE_LIMIT_EXCEEDED` | 429 | Too many requests |
| `INVALID_PREKEY_FORMAT` | 400 | Prekey signature verification failed |
| `MESSAGE_TOO_LARGE` | 413 | Message exceeds 10MB limit |
| `INVALID_SESSION_ID` | 400 | Session ID format invalid |
| `WEBSOCKET_AUTH_FAILED` | 401 | WebSocket authentication failed |
| `INTERNAL_ERROR` | 500 | Unexpected server error |

---

## 12. Rate Limiting

### 12.1 Rate Limit Rules

| Endpoint | Limit | Window | Scope |
|----------|-------|--------|-------|
| `POST /auth/login` | 5 requests | 15 minutes | Per IP |
| `POST /auth/register` | 3 requests | 1 hour | Per IP |
| `POST /messages` | 100 requests | 1 minute | Per user |
| `GET /messages/inbox` | 30 requests | 1 minute | Per user |
| `GET /prekeys/{convro_number}` | 10 requests | 1 minute | Per user |
| `POST /prekeys` | 5 requests | 1 hour | Per device |
| `GET /contacts` | 60 requests | 1 minute | Per user |
| `WebSocket messages` | 200 messages | 1 minute | Per connection |

---

### 12.2 Rate Limit Headers

**Response Headers:**
```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1705067400
```

**When Exceeded:**
```
HTTP/1.1 429 Too Many Requests
Retry-After: 45
```

```json
{
  "error": {
    "code": "RATE_LIMIT_EXCEEDED",
    "message": "Too many requests. Retry after 45 seconds.",
    "retry_after": 45
  }
}
```

---

## 13. Security

### 13.1 TLS Requirements

- **Minimum TLS version:** TLS 1.3
- **Cipher suites:** Only AEAD ciphers (ChaCha20-Poly1305, AES-256-GCM)
- **Certificate pinning:** Recommended for mobile apps

---

### 13.2 JWT Token Format

**Access Token Payload:**
```json
{
  "sub": "550e8400-e29b-41d4-a716-446655440000",
  "convro_number": "+99 123 456",
  "username": "alice_smith",
  "type": "access",
  "iat": 1705067400,
  "exp": 1705071000,
  "jti": "token_abc123"
}
```

**Expiration:**
- Access token: 1 hour
- Refresh token: 30 days

---

### 13.3 Request Signing (Optional)

For high-security endpoints, requests can be signed with HMAC-SHA256.

**Header:**
```
X-Signature: sha256=abcdef1234567890...
X-Timestamp: 2026-01-12T12:00:00Z
```

**Signature Computation:**
```
signature = HMAC-SHA256(
    key = user_api_secret,
    message = method + "|" + path + "|" + timestamp + "|" + body_hash
)
```

---

### 13.4 CORS Policy

**Allowed Origins:**
- `https://app.convro.app` (web app)
- `https://convro.app` (landing page)

**Allowed Methods:**
- `GET`, `POST`, `PATCH`, `DELETE`, `OPTIONS`

**Allowed Headers:**
- `Authorization`, `Content-Type`, `X-Request-ID`

**Preflight Cache:**
- `Access-Control-Max-Age: 86400` (24 hours)

---

### 13.5 Content Security Policy

**Recommended CSP Header:**
```
Content-Security-Policy: default-src 'self';
  connect-src 'self' wss://ws.convro.app;
  img-src 'self' data:;
  script-src 'self';
  style-src 'self' 'unsafe-inline';
```

---

## 12. Examples

### 12.1 Complete Handshake Flow

**Alice initiates handshake with Bob:**

**Step 1:** Alice fetches Bob's prekey bundle
```bash
GET /prekeys/+99654321
Authorization: Bearer alice_access_token
```

**Response:**
```json
{
  "convro_number": "+99 654 321",
  "device_id": "bob_device_id_hex",
  "identity_key": "bob_ik_dh_hex",
  "signed_prekey": {
    "spk_id": 1,
    "public_key": "bob_spk_hex",
    "signature": "bob_spk_sig_hex"
  },
  "one_time_prekey": {
    "otp_id": "otp_uuid",
    "public_key": "bob_otp_hex"
  }
}
```

**Step 2:** Alice creates offer (client-side C6P FFI call)
```swift
let offer = try handshake_create_offer(
    initiator_identity: alice_identity,
    responder_bundle: bob_bundle
)
```

**Step 3:** Alice sends offer to Bob
```bash
POST /messages
Authorization: Bearer alice_access_token
```

```json
{
  "to_convro_number": "+99 654 321",
  "message_type": "handshake_offer",
  "encrypted_blob": "base64_offer_blob"
}
```

**Step 4:** Bob receives offer (WebSocket)
```json
{
  "type": "message",
  "message_id": "msg_uuid",
  "from_convro_number": "+99 123 456",
  "message_type": "handshake_offer",
  "encrypted_blob": "base64_offer_blob"
}
```

**Step 5:** Bob accepts offer (client-side)
```swift
let accept = try handshake_accept_offer(
    responder_identity: bob_identity,
    offer: offer_blob
)
```

**Step 6:** Bob sends accept to Alice
```bash
POST /messages
Authorization: Bearer bob_access_token
```

```json
{
  "to_convro_number": "+99 123 456",
  "message_type": "handshake_accept",
  "encrypted_blob": "base64_accept_blob"
}
```

**Step 7:** Alice receives accept (WebSocket)
```json
{
  "type": "message",
  "message_id": "msg_uuid2",
  "from_convro_number": "+99 654 321",
  "message_type": "handshake_accept",
  "encrypted_blob": "base64_accept_blob"
}
```

**Step 8:** Alice verifies KC2 (client-side)
```swift
let verified = try handshake_verify_accept(
    accept: accept_blob,
    expected_kc2: stored_kc2
)
```

✅ **Session ACTIVE** on both sides!

---

### 12.2 Sending Encrypted Message

**Alice sends message to Bob:**

**Step 1:** Encrypt message (client-side)
```swift
let encrypted = try session_state.encrypt(plaintext: "Hello Bob!")
```

**Step 2:** Send via WebSocket (if online) or REST (if offline)
```json
{
  "type": "send",
  "to_convro_number": "+99 654 321",
  "message_type": "encrypted_message",
  "session_id": "session_id_hex",
  "encrypted_blob": "base64_encrypted_message"
}
```

**Step 3:** Bob receives (WebSocket)
```json
{
  "type": "message",
  "message_id": "msg_uuid3",
  "from_convro_number": "+99 123 456",
  "message_type": "encrypted_message",
  "session_id": "session_id_hex",
  "encrypted_blob": "base64_encrypted_message"
}
```

**Step 4:** Bob decrypts (client-side)
```swift
let plaintext = try session_state.decrypt(ciphertext: encrypted_blob)
// plaintext = "Hello Bob!"
```

**Step 5:** Bob sends ACK
```json
{
  "type": "ack",
  "message_id": "msg_uuid3"
}
```

---

## 13. OpenAPI 3.0 Specification

Full OpenAPI spec available at:
**`docs/api/openapi.yaml`**

Interactive docs:
**`https://api.convro.app/v1/docs`** (Swagger UI)

---

## Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-12 | Initial API specification |
| 1.1.0 | 2026-01-13 | Added Conversations (§6) + Sealed Sender Messages (§7) |

---

**Last Updated:** 2026-01-13
**Maintained by:** Convro Engineering Team
**Contact:** api@convro.app
