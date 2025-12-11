# Convro6Protocol (C6P) – Version 1

> **Status:** draft, production-oriented  
> **Version:** `C6P_VERSION = 1`  
> **Scope:** identity, sessions, direct messages, groups, channels, metadata, versioning.

C6P (Convro6Protocol) is the end-to-end encryption protocol used by **convro** for:

- **1:1 direct messages** (DMs),
- **groups** with roles and permissions,
- **broadcast channels**,
- **multi-device** usage of a single account,
- **minimal-metadata, no-cloud-backup** model in v1.

All cryptography is built directly on **well-known primitives** (no libsignal), with:

- X25519 for ECDH,
- Ed25519 for signatures,
- HKDF-SHA256 as KDF,
- ChaCha20-Poly1305 as AEAD.

---

## 1. Threat Model

### 1.1 Adversaries

C6P v1 protects against:

- **Malicious or compromised backend**  
  The backend may attempt to:
  - read, modify or replay messages,
  - inject or replace keys,
  - attempt downgrade attacks.

- **Network adversaries (full MITM)**  
  Any entity between client and backend can:
  - observe all traffic,
  - delay, replay, drop or reorder messages,
  - attempt to modify packets.

- **Passive observers of storage**  
  Access to backend DB or backups must not reveal message contents, group contents, or channel contents.

### 1.2 Out-of-scope

C6P v1 explicitly does **not** attempt to protect against:

- **Fully compromised client devices**  
  If the OS or the device is rooted / jailbroken / malware-infected, all bets are off.

- **Malicious contacts as a cryptographic adversary**  
  We do **not** model the case where a contact tries to manipulate the protocol itself (e.g. injecting fake keys into other users). Contacts can of course leak plaintext after decrypting messages – this is a social, not cryptographic, problem.

- **Physical access to an unlocked device**  
  C6P assumes the user protects their device with PIN / FaceID / TouchID and does not share it.

---

## 2. Identity Model

### 2.1 Account identity: virtual +99 number

Every convro account has a **primary identity**:

- A **virtual number** in the `+99 xxx xxx` namespace, e.g. `+99 241 772`.
- This number:
  - is generated once during registration,
  - is **permanent for the lifetime of the account**,
  - cannot be rotated or reassigned,
  - is the **canonical identifier** used by the protocol and backend.

There is **no dependency on SIM card numbers or provider-owned phone numbers**.

Deletion of an account (including a "panic" mode that wipes local keys and turns the app into a calculator UI) is considered a **separate operation** at the app level. After deletion:

- the +99 number becomes permanently invalid for that account,
- server and protocol MUST treat it as retired (no new sessions allowed),
- re-registration MUST create a fresh identity.

### 2.2 Usernames

Each account may optionally have a **username**:

- format: `@username`,
- unique within the convro namespace,
- mapped internally to the account identity.

Properties:

- Usernames are **aliases** to the primary +99 identity.
- Protocol and backend may accept username strings as input, but **all cryptographic binding** is done to internal `user_id` / +99 identity and keys, not to the username string.
- Username changes do **not** affect cryptographic identity.

### 2.3 Identity keys (account vs device)

C6P distinguishes:

- **Account identity** – bound to the +99 number and used for addressing.
- **Device identity** – bound to a specific installation of the app on a device.

Each **device** has:

- a long-term X25519 key pair: `device_identity_key`,
- a long-term Ed25519 key pair: `device_signature_key`,
- a stable `device_id` (opaque identifier managed by the backend).

Multi-device is supported **from v1**:

- An account (a +99 number) may have multiple devices.
- Each device maintains its **own sessions** with other devices.
- History is **per-device**: new devices do not automatically get old history.

---

## 3. Cryptographic Primitives

C6P v1 uses only the following primitives:

- **Key agreement**
  - X25519 (ECDH over Curve25519) for all ECDH operations.

- **Signatures**
  - Ed25519 for:
    - device identity attestation,
    - server-signed events that must be verifiable client-side.

- **Key derivation**
  - HKDF with SHA-256 for:
    - deriving root keys, chain keys,
    - per-message keys,
    - sender keys in groups.

- **Authenticated encryption**
  - ChaCha20-Poly1305 (256-bit) in AEAD mode for:
    - messages,
    - group and channel payloads,
    - any encrypted metadata fields.

Non-goals:

- No custom / experimental crypto.
- No home-made MACs or ad-hoc constructions.

---

## 4. High-level Architecture

### 4.1 Roles

- **Client (iOS app)**  
  - Holds identity keys, device keys, and session state.
  - Encrypts / decrypts payloads end-to-end.
  - Initiates and maintains sessions with other devices.
  - Manages group and channel keys locally.

- **Backend server** (Node.js, MariaDB – described in a separate server spec)  
  - Routes encrypted payloads between devices.
  - Manages account metadata (mapping +99 → user_id → devices).
  - Stores *only* minimal metadata needed for routing and delivery.
  - Does **not** have access to plaintext messages or group/channel keys.

### 4.2 Message flow overview (v1)

1. **Account creation**
   - Client generates account and device keys.
   - Backend registers:
     - `user_id`,
     - `+99` number,
     - initial `device_id` + associated public keys.

2. **Session setup**
   - When device A wants to send a message to device B (or multiple devices in group/channel context), it:
     - obtains the recipient device public keys through the backend,
     - performs a session handshake (C6P-Sessions),
     - derives a shared session state (root keys, chain keys).

3. **Message sending**
   - For each message:
     - derive a message key from current chain key (HKDF),
     - encrypt payload via ChaCha20-Poly1305,
     - send ciphertext and minimal routing metadata to the backend.

4. **Delivery**
   - Backend:
     - uses routing metadata to identify recipient devices,
     - stores ciphertext in per-device queues,
     - delivers to online devices; persists for offline ones.

5. **Receiving**
   - Device receives envelope,
   - locates appropriate session state,
   - derives message key and decrypts,
   - processes message type (DM, group, channel).

---

## 5. Sessions (overview)

> Details are defined in: `c6p-sessions/C6P-Sessions.sys.md`, `Session.swift`, `SecureMySession.swift`.

### 5.1 Session goals

- Multi-device support for both sender and recipient.
- Perfect forward secrecy (PFS) and future secrecy (PCS):
  - compromise of long-term keys must not reveal past messages,
  - compromise of current session keys should not reveal future messages.
- Stateless / minimal-state server:
  - server stores only what’s necessary to route messages and sync prekeys,
  - no requirement for server to maintain per-session cryptographic state.

### 5.2 Session building blocks

Each device maintains:

- **Long-term device_identity_key (X25519)**,
- **Prekeys and one-time prekeys**:
  - uploaded to server for other devices to fetch and start sessions,
  - consumed once when possible.

Session establishment is based on:

- ECDH combinations (like `IK ⋅ SPK`, `EK ⋅ IK`, etc.),
- HKDF-SHA256 to derive:
  - **root key (RK)**,
  - **sending / receiving chain keys (CKs)**,
  - **per-message keys (MKs)**.

Each plaintext message is encrypted with a unique MK, never reused.

---

## 6. Direct Messages (DMs)

> Details in: `c6p-dms/C6P-DMs.sys.md`, `Messages.swift`.

### 6.1 DM model

A **DM session** is conceptually between:

- Account A (+99 number) and account B (+99 number),
- but technically implemented as sessions between **devices of A** and **devices of B**.

For each pair of devices (A.x, B.y), there is a logical session:

- A.x may have separate sending and receiving chains for B.y,
- likewise for B.y towards A.x.

### 6.2 Message types (DM)

Minimum required DM types in v1:

- `text` – UTF-8 text payload,
- `media` – reference to encrypted media (image / video / file),
- `reaction` – reaction to a previous message,
- `edit` – edited content of a previous message,
- `delete` – deletion marker (local + remote semantics defined in DM spec),
- `control` – typing indicators, read receipts, etc.

Each DM message is represented as:

- **Encrypted payload** (AEAD):
  - includes message body, type, timestamps and flags,
- **Minimal routing metadata**:
  - sender device_id, recipient device_id(s),
  - conversation_id (server-side DM identifier),
  - message sequence / ordering hints (if required).

---

## 7. Groups

> Details in: `c6p-groups/C6P-Groups.sys.md`, `Group.swift`, `GroupProperties.swift`.

### 7.1 Group model

A **group** is:

- identified by a server-side `group_id`,
- belongs to a single creator account,
- has a set of **members** (accounts) with roles:
  - owner,
  - admin,
  - member,
  - optionally muted / restricted roles.

Roles and permissions include (non-exhaustive):

- add/remove members (owner/admin),
- promote/demote admins,
- change group name, avatar, description,
- pin messages,
- toggle join permissions,
- configure auto-delete timers for messages in the group.

### 7.2 Group keys

Groups use a **Group Master Key (GMK)**:

- GMK is known to all current members’ devices.
- Each member device derives a **sender key** from GMK via HKDF.
- Messages are sent using sender keys, not per-recipient sessions:
  - this allows efficient fan-out to many members,
  - but requires correct membership and key management.

Key operations:

- adding a member → device of owner/admin re-encrypts GMK to that member’s devices,
- removing a member → GMK rotation is scheduled; new GMK distributed to remaining members,
- auto-delete / retention policies are enforced locally by clients.

Groups aim for:

- PFS within reasonable constraints,
- removal of ex-members from future access by GMK rotation.

---

## 8. Channels

> Details in: `c6p-channels/C6P-Channels.sys.md`, `Channel.swift`, `ChannelProperties.swift`.

### 8.1 Channel model

A **channel** is a:

- broadcast-oriented structure,
- with one or more **publishers** (owners/admins),
- and many **subscribers** (read-only followers by default).

Properties:

- identified by `channel_id`,
- may have categories / tags for discovery,
- can be public (visible) or private (invite-only).

### 8.2 Channel encryption

Channels are **partially E2E**:

- Publisher devices hold a channel **Publisher Key**, derived similarly to group GMKs.
- Subscribers receive keys that allow:
  - decrypting channel messages,
  - but not publishing.

For v1:

- default model: **one-way broadcast** (publishers → subscribers),
- future extensions may allow:
  - controlled feedback (reactions, limited replies),
  - Q&A segments as separate threads.

Channel history is **per-device**:

- new devices will only receive channel history as allowed by protocol policy (e.g. from join-time onward).

---

## 9. Message Model (Common Layer)

The message model is shared by DMs, groups and channels, with context-specific rules.

### 9.1 Core fields (inside AEAD payload)

Each encrypted payload contains at minimum:

- `message_id` (client-side UUID),
- `conversation_context` (DM / group / channel),
- `sender_device_id`,
- `sent_at` timestamp (client time),
- `message_type`:
  - `text`, `media`, `reaction`, `edit`, `delete`, `control`, etc.
- `body` (type-specific content),
- optional flags:
  - `is_pinned`,
  - `auto_delete_after` (per message),
  - `is_silent` (for muted notifications).

### 9.2 Features required in v1

For **DMs, groups and/or channels**:

- **Media**: image, video, generic files:
  - content is stored encrypted with per-object keys,
  - message references media via encrypted descriptors.

- **Reactions**:
  - attached to message IDs,
  - implemented as separate small messages targeting the original message.

- **Pinned messages**:
  - pinned state is represented by control messages and/or group/channel metadata,
  - clients must show pinned messages at top of conversation.

- **Mute conversation**:
  - a per-conversation flag stored locally on the device,
  - may be mirrored in encrypted account settings.

- **Pin chat** (at list level):
  - local setting controlling chat order in UI (pinned at top).

- **Block user**:
  - local rule: do not accept messages from that identity,
  - server may optionally enforce routing filters if blocking is synced.

- **Auto-delete**:
  - per-conversation or per-message timers,
  - when timer expires, clients delete local ciphertext and forget keys (if applicable).

Exact encoding and wire format of these affordances are defined in `C6P-DMs`, `C6P-Groups`, and `C6P-Channels` specs.

---

## 10. Metadata & Privacy

C6P sharp line:

- **Content**: always end-to-end encrypted.
- **Metadata**: minimized and clearly enumerated.

### 10.1 Metadata the server sees

For each message envelope, the backend SHOULD only see:

- `sender_user_id`,
- `sender_device_id`,
- recipient entity:
  - `conversation_id` for DMs,
  - `group_id` for groups,
  - `channel_id` for channels,
- target `device_id`s for fan-out (derived from memberships),
- `server_timestamp` (when the backend processed message),
- delivery status flags (queued, delivered, read – if implemented).

The backend MUST NOT see:

- plaintext message content,
- group/channel keys,
- internal message flags that would leak structure beyond what’s strictly necessary.

The protocol spec and backend spec will list **all** metadata fields explicitly. There MUST be no hidden analytics fields.

---

## 11. Push Notifications

In v1, C6P defines a **privacy-first push model**:

- Push payloads sent through OS push services (APNs, FCM, etc.) **contain no plaintext message content**.
- Minimal form in v1:
  - “You have a new message in convro.”
  - Optionally: generic count of unread items.

Binding sender or conversation to push content is considered an **extension**:

- Possible future extension: show “New message” + hint which conversation (e.g. “1 new message”), but without sender name.
- Showing sender name or part of body is possible only under an explicit user opt-in and must be handled by a separate extension spec (`C6P-Notifications`), as it leaks metadata to the OS.

All actual content and sender identity are resolved **after** app wakeup and E2E decryption.

---

## 12. Backups & Recovery

C6P v1 takes a conservative stance:

- **No cloud backups** of E2E keys or message history specified in the protocol.
- Clients MAY offer:
  - local export of identity / device seeds,
  - local encrypted backups under user-chosen passphrases.

In case of device loss and no local backup:

- The user performs a **hard reset**:
  - new device keys,
  - new sessions,
  - old messages and sessions permanently unrecoverable.

Future versions may define `C6P-Backup` as an extension, but v1 treats it as out-of-scope.

---

## 13. Versioning & Downgrade Protection

### 13.1 Global version

C6P v1 uses a single global version constant:


C6P_VERSION = 1
Every C6P message MUST carry:

a version field in its envelope and/or encrypted payload, allowing clients to:

refuse unknown future versions,

detect downgrade attempts.

13.2 Downgrade protection

Clients MUST:

refuse to establish or continue sessions that attempt to use a protocol version lower than the one the client is compiled against, if this implies weaker security,

treat inconsistent versioning (e.g. server claiming v1 while peers claim v0) as a potential attack and fail closed (showing clear errors to the user).

Session state encodes the protocol version; all session derivations and message formats are version-tagged.

14. Extensibility & Directory Layout

The C6P spec is split into thematic modules, each with:

a *.sys.md (system-level spec),

one or more Swift reference implementations.

14.1 Modules

Sessions

c6p-sessions/C6P-Sessions.sys.md

c6p-sessions/Session.swift

c6p-sessions/SecureMySession.swift

Direct Messages

c6p-dms/C6P-DMs.sys.md

c6p-dms/Messages.swift

Groups

c6p-groups/C6P-Groups.sys.md

c6p-groups/Group.swift

c6p-groups/GroupProperties.swift

Channels

c6p-channels/C6P-Channels.sys.md

c6p-channels/Channel.swift

c6p-channels/ChannelProperties.swift

Calls

c6p-calls/C6P-Calls.sys.md

c6p-calls/Call.swift

c6p-calls/VideoCall.swift

Settings / Identity

c6p-settings/C6P-Settings.sys.md

c6p-settings/MyProfile.swift

Secure Run / Handshake

c6p-secure-run/C6P-SecureRun.sys.md

c6p-secure-run/StartDM.swift

c6p-secure-run/StartGroup.swift

c6p-secure-run/StartChannel.swift

Each *.sys.md:

refines the global rules from this Convro-6-Protocol.md,

must not contradict this core spec,

may only narrow or extend behaviour in a compatible way.

15. Server Assumptions (for backend spec)

While this document focuses on the client-side protocol, it assumes:

A Node.js backend implementing:

registration endpoints,

device registration and key upload endpoints,

prekey distribution endpoints,

messaging endpoints for DMs, groups, channels,

minimal metadata storage on MariaDB.

The full backend API (URLs, request/response JSON, DB schema) will be defined in a separate Server Specification, but:

all endpoints MUST treat message content as opaque ciphertext,

all decisions about message confidentiality, authenticity and integrity are enforced by C6P, not by the server.

16. Summary

C6P v1 defines:

a virtual +99-based identity model,

multi-device accounts with per-device keys and history,

modern cryptography (X25519, Ed25519, HKDF-SHA256, ChaCha20-Poly1305),

E2E-encrypted DMs, groups and broadcast channels,

a minimal-metadata, no-cloud-backup approach,

a versioned, extensible spec compatible with future modules (Calls, Backup, Notifications, etc.).

All further documents in the c6p-* directories MUST be read as refinements of this contract.
