# IslandAccord v1 — Cryptographic Specification (Prekey Handshake + Key Confirmation)

**Status:** Production / Canonical  
**Applies to:** Convro-6 Protocol (C6P) DM sessions  
**Handshake name:** IslandAccord v1  
**Goal:** Establish DM session root + double-ratchet chain keys using prekey bundle, with strong binding, initiator authentication, downgrade resistance, and explicit key confirmation.  
**Non-goal:** Server-side computation of secrets (server MUST NOT compute any shared secrets).

---

## 1. Actors and Notation

- **A** = Initiator (client starting DM)
- **B** = Responder (client receiving DM invite)
- **Server** = untrusted relay/storage for offers + state. Server is allowed to reserve/consume OTP but MUST NOT know session secrets.

Identifiers:
- `deviceId` = 8 bytes, hex16 lowercase on wire
- `sessionId` = 4 bytes, hex8 lowercase on wire

Key types:
- `IK_sig` = Ed25519 identity signing keypair
- `IK_dh`  = X25519 identity DH keypair
- `SPK`    = X25519 signed prekey keypair (longer-lived, rotated)
- `OTP`    = X25519 one-time prekey keypair (single-use, server-reserved)

Encoding:
- All binary fields are base64url (no padding) unless explicitly stated (hex IDs).

---

## 2. Security Objectives (what auditors will look for)

IslandAccord v1 MUST provide:

1) **Confidentiality** of session root and message keys (server never learns secrets).  
2) **Authentication of initiator** using Ed25519 signature bound to the offer/transcript.  
3) **Strong binding** to responder prekey material (prevents server splicing / mix&match).  
4) **Downgrade protection** (version + suiteId included in transcript and signature).  
5) **Key confirmation** (both parties prove they derived the same secrets).  
6) **Replay protection** (sessionId uniqueness + transcript uniqueness + server-side duplication rejection).  
7) **OTP single-use** enforced by server reservation + responder consumption.

---

## 3. Preconditions (MUST)

### 3.1 Responder prekey bundle validity
Server MUST provide to A a bundle for device `B_deviceId` containing:
- `B_IK_sig_pub` (Ed25519 pub, 32 bytes)
- `B_IK_dh_pub` (X25519 pub, 32 bytes)
- `B_SPK` tuple:
  - `spkId` (hex16)
  - `spkPub` (X25519 pub, 32 bytes)
  - `spkSig` (Ed25519 signature, 64 bytes)
- Optional `B_OTP` tuple (reserved atomically):
  - `otpId` (hex16)
  - `otpPub` (X25519 pub, 32 bytes)

### 3.2 Signed prekey signature (MUST)
Responder’s signed prekey signature MUST verify:

`VerifyEd25519(B_IK_sig_pub, Sig = spkSig, Msg = LABEL_PREKEY || spkId || spkPub)`

Where:
- `LABEL_PREKEY = "C6P_PREKEY_V1"` (ASCII bytes)
- `spkId` is the raw 8 bytes decoded from hex16
- `spkPub` is 32 bytes

If verification fails, handshake MUST abort (fail-closed).

---

## 4. ECDH Set (3DH + OTP)

IslandAccord v1 uses the following DH computations:

Initiator A generates:
- `A_EK` fresh X25519 ephemeral keypair per session
- A already has `A_IK_dh_priv` (identity DH)

Responder B uses:
- `B_IK_dh_pub` from bundle
- `B_SPK_pub` from bundle
- `B_OTP_pub` from bundle if present

### 4.1 Mandatory DHs
Compute (each result is 32 bytes):
- `DH1 = X25519(A_IK_dh_priv,  B_SPK_pub)`
- `DH2 = X25519(A_EK_priv,     B_IK_dh_pub)`
- `DH3 = X25519(A_EK_priv,     B_SPK_pub)`

### 4.2 Optional DH (only when OTP is present in bundle)
- `DH4 = X25519(A_EK_priv, B_OTP_pub)`

### 4.3 Input Key Material (IKM)
`IKM = DH1 || DH2 || DH3 || [DH4]`

**No other DHs exist in IslandAccord v1.**  
(“More DHs” are not added ad-hoc; any evolution is a version bump.)

---

## 5. Transcript (canonical binding)

IslandAccord v1 uses a **canonical transcript** for binding and downgrade protection.

### 5.1 Transcript fields (MUST, in this exact order)
Let bytes be appended in order:

1. `LABEL_HANDSHAKE = "ISLAND_ACCORD_V1"` (ASCII bytes)
2. `version` (1 byte)
3. `suiteId` (1 byte)  
4. `sessionId` (4 bytes)
5. `A_deviceId` (8 bytes)
6. `B_deviceId` (8 bytes)
7. `A_IK_dh_pub` (32 bytes)
8. `A_IK_sig_pub` (32 bytes)
9. `A_EK_pub` (32 bytes)
10. `B_IK_dh_pub` (32 bytes)
11. `B_IK_sig_pub` (32 bytes)
12. `spkId` (8 bytes)
13. `spkPub` (32 bytes)
14. `spkSig` (64 bytes)
15. `otpFlag` (1 byte: 0x01 if OTP used else 0x00)
16. if `otpFlag == 0x01`: `otpId` (8 bytes) and `otpPub` (32 bytes)

### 5.2 Transcript hash
`transcriptHash = SHA256(transcriptBytes)` (32 bytes)

The `transcriptHash` MUST be included in:
- KDF salt
- offer signature input
- both key confirmations

---

## 6. KDF and Key Schedule

### 6.1 PRK
`PRK = HKDF-Extract(salt = transcriptHash, IKM)`

HKDF is HKDF-SHA256 (RFC 5869).

### 6.2 Root seed
`rootSeed = HKDF-Expand(PRK, info = "IA_ROOT_SEED_V1", len = 32)`

This becomes:
- `RootKey` (32 bytes)

### 6.3 Chain keys (double ratchet initialization)
Derive two chain keys, wire-stable streams:
- `CK_i2r` for Initiator -> Responder
- `CK_r2i` for Responder -> Initiator

Derivation MUST be deterministic from `RootKey` using `C6PKeySchedule` and MUST bind:
- `sessionId`
- `A_deviceId`, `B_deviceId`
- streamId (`i2r` or `r2i`)
- suiteId

Mapping:
- Initiator: `send = CK_i2r`, `recv = CK_r2i`
- Responder: `send = CK_r2i`, `recv = CK_i2r`

Counters:
- `sendCounter = 0`
- `recvCounter = 0`

---

## 7. Initiator Signature (Ed25519)

IslandAccord v1 authenticates the initiator at the handshake layer.

### 7.1 Signature input (canonical)
Initiator MUST compute:

`sigInput = SHA256( "IA_OFFER_SIG_V1" || transcriptHash || sessionId || A_deviceId || B_deviceId || suiteId )`

Where:
- `"IA_OFFER_SIG_V1"` is ASCII bytes
- `sessionId` is raw 4 bytes
- `A_deviceId`, `B_deviceId` are raw 8 bytes
- `suiteId` is 1 byte

### 7.2 Signature
`offerSignature = Ed25519.Sign(A_IK_sig_priv, sigInput)` (64 bytes)

Responder MUST verify the signature using `A_IK_sig_pub` supplied in the offer and bound in transcript.

If signature verification fails, handshake MUST abort.

---

## 8. Key Confirmation (explicit)

Key confirmation is REQUIRED and consists of **two one-way confirmations**:
- `KC1` from Initiator included in the offer
- `KC2` from Responder returned in accept/ack

### 8.1 Confirmation keys
Derive distinct confirmation keys from PRK:

- `KCk1 = HKDF-Expand(PRK, info="IA_KC1_KEY_V1", len=32)`
- `KCk2 = HKDF-Expand(PRK, info="IA_KC2_KEY_V1", len=32)`

### 8.2 KC1 (Initiator -> Responder)
Initiator computes:

`kc1Input = SHA256( "IA_KC1_V1" || transcriptHash || sessionId )`

`kc1 = HMAC-SHA256(key=KCk1, msg=kc1Input)` (32 bytes)

Responder MUST recompute and compare `kc1`.  
Mismatch MUST abort.

### 8.3 KC2 (Responder -> Initiator)
Responder computes:

`kc2Input = SHA256( "IA_KC2_V1" || transcriptHash || sessionId )`

`kc2 = HMAC-SHA256(key=KCk2, msg=kc2Input)` (32 bytes)

Initiator MUST verify `kc2` before marking session ACTIVE.

---

## 9. Wire Contracts

All wire structs MUST be strictly validated:
- exact lengths
- lowercase hex for ids
- base64url no padding for binary

### 9.1 IslandAccordOfferV1 (sent in POST /v1/dm/sessions/open)
Fields (JSON):
- `version` (int, MUST be 1)
- `suiteId` (int, 1 byte semantics)
- `sessionId` (hex8)
- `initiatorDeviceId` (hex16)
- `responderDeviceId` (hex16)
- `initiatorIdentityDhPub` (b64url 32)
- `initiatorIdentitySigPub` (b64url 32)
- `initiatorEphemeralDhPub` (b64url 32)
- `usedSignedPrekeyId` (hex16)
- `usedSignedPrekeyPublicKeyX25519` (b64url 32)
- `usedOneTimePrekeyId` (hex16, nullable)
- `transcriptHash` (b64url 32)
- `kc1` (b64url 32)
- `offerSignatureEd25519` (b64url 64)

Server MUST treat offer as opaque, except:
- validate formatting/length
- enforce session uniqueness policy
- persist and deliver to responder

### 9.2 IslandAccordAcceptV1 (sent in POST /v1/dm/handshake/accept)
Fields:
- `sessionId` (hex8)
- `responderDeviceId` (hex16)
- `kc2` (b64url 32)

Server MUST:
- allow responder to attach accept to existing session
- deliver accept to initiator
- mark state as `ACTIVE` only after accept stored (client-side verification still required)

---

## 10. State Machine (client-side)

### 10.1 Initiator (A)
1) Fetch bundle for `(B_deviceId)` (server reserves OTP if available).  
2) Verify SPK signature with `B_IK_sig_pub`.  
3) Generate `A_EK`.  
4) Compute DHs -> IKM -> transcriptHash -> PRK -> RootKey -> chain keys.  
5) Compute `kc1` and `offerSignature`.  
6) POST `/v1/dm/sessions/open` with `IslandAccordOfferV1`.  
7) Store local session as `PENDING` (do not treat as ACTIVE).  
8) Await accept containing `kc2`.  
9) Verify `kc2`. If OK -> mark session `ACTIVE`. If fail -> delete session state and warn.

### 10.2 Responder (B)
1) Receive offer.  
2) Validate device binding: offer.responderDeviceId MUST equal local deviceId.  
3) Validate used SPK binding:
   - `offer.usedSignedPrekeyId` MUST match current SPK id, OR the client MUST have a rotation window that can still load that SPK private.
   - `offer.usedSignedPrekeyPublicKeyX25519` MUST equal actual SPK pub derived from loaded private.
4) Load OTP private if `usedOneTimePrekeyId` present; if missing -> abort.  
5) Recompute transcriptHash (including otpPub derived from otpPriv if used). Compare with offer.transcriptHash.  
6) Compute DHs (mirrored) -> PRK -> RootKey -> chain keys.  
7) Verify `offerSignatureEd25519`.  
8) Verify `kc1`.  
9) Derive `kc2`, POST `/v1/dm/handshake/accept`.  
10) Consume OTP locally AFTER successful session creation + accept persisted.  
11) Store local session as `ACTIVE`.

---

## 11. Server Rules (MUST)

1) Server MUST NOT compute any DH, PRK, root, chain keys, message keys.  
2) Bundle endpoint MUST reserve OTP atomically:
   - If OTP is present, it is assigned to the returned bundle and cannot be returned to other initiators.
3) If responder never accepts, server MAY recycle the reserved OTP only after expiry window (documented retention policy).  
4) Server MUST prevent duplicate sessionId collisions per initiator/responder tuple.  
5) Server MUST be able to deliver offer + accept to correct parties without requiring storing identity keys in plaintext beyond what is already in prekey store.

---

## 12. Metadata Minimization (design commitments)

IslandAccord v1 minimizes metadata by:
- Using `sessionId` and `deviceId` as primary correlation, not phone/email identifiers.
- Keeping offer payload free of message content and free of extra identity fields beyond required keys.
- Avoiding sending peer contact lists / group membership at handshake time.
- Enforcing deterministic nonce strategies only inside AEAD layer, not in handshake.

Note: handshake necessarily discloses that A wants to talk to B’s deviceId; this is the irreducible minimum for DM establishment.

---

## 13. Failure Behavior (fail-closed)

Any verification failure MUST:
- abort immediately
- not create ACTIVE session
- wipe ephemeral secret material from memory
- keep a minimal forensic log locally (non-sensitive, no keys)

Failures include:
- invalid lengths / encoding
- SPK signature invalid
- transcript hash mismatch
- offer signature invalid
- kc1/kc2 mismatch
- OTP referenced but missing

---

## 14. Compatibility and Versioning

- `version` is strict. Any unknown version MUST be rejected.
- Any future changes (new DH set, new transcript fields, new KC mechanism) MUST bump `version`.

---

## 15. Summary (auditor-facing)

IslandAccord v1 is a prekey handshake that:
- uses a 3DH core + optional OTP DH
- binds all critical inputs via transcript hash
- authenticates initiator with Ed25519 signature
- performs explicit two-way key confirmation (kc1 + kc2)
- keeps server ignorant of session secrets by design



