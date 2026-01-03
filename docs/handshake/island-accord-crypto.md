# IslandAccord v1 — Cryptographic Specification (Prekey Handshake + Key Confirmation) (island-accord-crypto.md)

**Status:** PRODUCTION / CANONICAL / NORMATIVE  
**Applies to:** Convro-6 Protocol (C6P) v1 DM sessions  
**Handshake name:** IslandAccord v1  
**Scope:** Prekey handshake cryptography (bundle verification, transcript, DH set, initiator authentication, key confirmation), plus exact linkage into **C6P v1 Key Schedule**.  
**Non-goal:** Server-side derivation of secrets (server MUST NOT compute any DH / KDF outputs).

**Depends on (normative):**
- `docs/handshake/island-accord-wire.md` (wire shapes + strict decoding rules)
- `docs/handshake/island-accord-state-machine.md` (server authority/state invariants)
- `docs/crypto/c6p-key-schedule.md` (root/chain/msg/nonce derivations)
- `docs/crypto/c6p-aead-and-aad.md` (AAD + session_binding definitions)
- `docs/crypto/c6p-error-codes.md` (canonical error codes)
- `docs/crypto/c6p-crypto-registry.md` (suite registry + message type registry)

---

## 0. Design Objectives (Normative)

IslandAccord v1 MUST provide:

1) **Confidentiality:** server never learns session secrets.  
2) **Initiator authentication:** responder verifies initiator identity via Ed25519 signature bound to the canonical transcript.  
3) **Strong binding:** transcript binds all key inputs (device IDs, session ID, suite, bundle keys) to prevent server splicing/mix&match.  
4) **Downgrade resistance:** `C6P_VERSION` and `suite_id` are transcript-bound and signature-bound.  
5) **Explicit key confirmation:** both sides prove they derived the same handshake secrets before activating the session.  
6) **Replay resistance:** server enforces `(initiatorDeviceId, responderDeviceId, sessionId)` uniqueness; clients enforce KC and local state.  
7) **OTP single-use:** server enforces OTP scarcity (reserve → pending consumption → consumed).

Fail-closed is non-negotiable: any mismatch or validation failure MUST abort.

---

## 1. Canonical Types & Encodings (Normative)

All parsing/validation rules are defined in `island-accord-wire.md` and are referenced here for cryptographic correctness.

### 1.1 Protocol version
- `C6P_VERSION` (u8): v1 = `0x01`
- `IA_VERSION` (u8): IslandAccord v1 = `0x01`  
  (This is the handshake-family version; it MUST equal C6P v1 in this release line.)

### 1.2 Canonical identifiers (wire-stable)
- `deviceId`: **16 bytes**, encoded as **hex32 lowercase**
- `sessionId`: **8 bytes**, encoded as **hex16 lowercase**
- `spkId`, `otpId`: **8 bytes**, encoded as **hex16 lowercase**

### 1.3 Key material encodings (wire-stable)
Binary fields are base64url (no padding) and MUST decode to exact length:
- X25519 public key: 32 bytes
- Ed25519 public key: 32 bytes
- Ed25519 signature: 64 bytes
- SHA-256 hash: 32 bytes
- HMAC-SHA256 tag: 32 bytes

---

## 2. Algorithms & Primitives (Normative)

IslandAccord v1 uses:
- X25519 (DH)
- Ed25519 (sign/verify)
- SHA-256
- HMAC-SHA256
- HKDF-SHA256 (RFC 5869)

**AEAD suites:** see `docs/crypto/c6p-crypto-registry.md`.  
**Production default policy:** ChaCha20-Poly1305 (`suite_id = 0x01`).  
Other suites MAY exist in the registry, but deployments MAY restrict them; unknown or disallowed suites MUST be rejected.

---

## 3. Prekey Bundle Requirements (Normative)

### 3.1 Responder bundle contents (server → initiator)
For responder device `B_deviceId`, server returns a bundle containing:

- `B_IK_sig_pub` (Ed25519 pub, 32)
- `B_IK_dh_pub`  (X25519 pub, 32)
- `SPK` (signed prekey):
  - `spkId` (hex16 → 8 bytes)
  - `spkPub` (X25519 pub, 32)
  - `spkSig` (Ed25519 signature, 64)
- Optional `OTP` (one-time prekey, server-reserved atomically):
  - `otpId` (hex16 → 8 bytes)
  - `otpPub` (X25519 pub, 32)

### 3.2 SPK signature verification (MUST)
Initiator MUST verify the SPK signature using `B_IK_sig_pub`:

**Label:**
- `LABEL_PREKEY = "C6P_PREKEY_V1"` (ASCII/UTF-8 bytes)

**Message to verify (canonical bytes):**
MSG = LABEL_PREKEY || spkId_bytes(8) || spkPub_bytes(32)



**Verification:**
VerifyEd25519(B_IK_sig_pub, spkSig, MSG) == true



If verification fails: abort (fail-closed) with `C6P.HANDSHAKE.SPK_SIGNATURE_INVALID`.

---

## 4. Actor Keys (Normative)

### 4.1 Initiator A keys
Long-term:
- `A_IK_sig` (Ed25519 identity signing keypair)
- `A_IK_dh`  (X25519 identity DH keypair)

Per-session:
- `A_EK` (fresh X25519 ephemeral keypair; MUST be newly generated for each session)

### 4.2 Responder B keys
Long-term:
- `B_IK_sig` (Ed25519 identity signing keypair)
- `B_IK_dh`  (X25519 identity DH keypair)

Rotating:
- `B_SPK` (X25519 signed prekey; rotated by policy)

One-time:
- `B_OTP` (X25519 one-time prekey; single-use; server-reserved)

---

## 5. DH Set (IslandAccord v1 = 3DH + optional OTP) (Normative)

Each DH output is 32 bytes.

### 5.1 Mandatory DHs
Initiator computes using bundle keys:

- `DH1 = X25519(A_IK_dh_priv,  B_SPK_pub)`
- `DH2 = X25519(A_EK_priv,     B_IK_dh_pub)`
- `DH3 = X25519(A_EK_priv,     B_SPK_pub)`

Responder computes the mirrored DHs:

- `DH1 = X25519(B_SPK_priv,    A_IK_dh_pub)`
- `DH2 = X25519(B_IK_dh_priv,  A_EK_pub)`
- `DH3 = X25519(B_SPK_priv,    A_EK_pub)`

### 5.2 Optional DH (only when OTP present)
If OTP is included and used:

- Initiator: `DH4 = X25519(A_EK_priv,  B_OTP_pub)`
- Responder: `DH4 = X25519(B_OTP_priv, A_EK_pub)`

### 5.3 Input Key Material (IKM) (canonical)
IKM = DH1 || DH2 || DH3 || [DH4]


Length:
- without OTP: 96 bytes
- with OTP: 128 bytes

No other DH computations exist in IslandAccord v1. Any change requires a version bump.

---

## 6. Canonical Transcript (Normative)

The transcript is the **single source of truth** for binding and downgrade protection.  
`transcript_hash = SHA256(T)` is consumed by C6P key schedule (§7).

### 6.1 Transcript label
- `LABEL_HANDSHAKE = "ISLAND_ACCORD_V1"` (ASCII/UTF-8 bytes)

### 6.2 Transcript fields (exact order, exact bytes)
Let `T` be the concatenation of the following in order:

1) `LABEL_HANDSHAKE` (bytes)  
2) `U8(IA_VERSION)`  
3) `U8(C6P_VERSION)`  
4) `U8(suite_id)`  
5) `sessionId_bytes` (8)  
6) `A_deviceId_bytes` (16)  
7) `B_deviceId_bytes` (16)  
8) `A_IK_dh_pub` (32)  
9) `A_IK_sig_pub` (32)  
10) `A_EK_pub` (32)  
11) `B_IK_dh_pub` (32)  
12) `B_IK_sig_pub` (32)  
13) `spkId_bytes` (8)  
14) `spkPub` (32)  
15) `spkSig` (64)  
16) `otpFlag` (1 byte: `0x01` if OTP is used else `0x00`)  
17) if `otpFlag == 0x01`:
   - `otpId_bytes` (8)
   - `otpPub` (32)

**Hard rules:**
- Field lengths MUST be validated before transcript hashing.
- Hex ids MUST be decoded to raw bytes in the transcript (not ASCII hex).
- `suite_id` in transcript MUST equal the wire `suiteId`.

### 6.3 Transcript hash
transcript_hash = SHA256(T) // 32 bytes



If a peer-provided `transcriptHash` does not match locally computed value: abort with `C6P.HANDSHAKE.TRANSCRIPT_MISMATCH`.

---

## 7. Linkage into C6P v1 Key Schedule (Normative)

IslandAccord v1 does **not** define its own independent root/chain derivation.  
It feeds **IKM** + **transcript_hash** + **session context** into **C6P v1 Key Schedule**.

### 7.1 Session context (CTX)
As defined by `docs/crypto/c6p-key-schedule.md`:

- `session_id` (8 bytes) = `sessionId_bytes`
- `initiator_device_id` (16 bytes) = `A_deviceId_bytes`
- `responder_device_id` (16 bytes) = `B_deviceId_bytes`

`CTX = session_id(8) || initiator_device_id(16) || responder_device_id(16)`

### 7.2 Root + KC key derivation
Implementations MUST derive:
- `root_key` (32)
- `kc_key` (32)

by executing `docs/crypto/c6p-key-schedule.md` **§4** exactly, using:
- `IKM = DH1||DH2||DH3||[DH4]`
- `transcript_hash = SHA256(T)`
- `CTX` as above
- `C6P_VERSION = 0x01`

Any deviation (labels, info layout, salts) is a protocol violation and MUST abort with:
- `C6P.KDF.DOMAIN_SEPARATION_VIOLATION` (recommended) or
- `C6P.KDF.INVALID_INFO`

### 7.3 Initial chain keys
Initial stream chain keys MUST be derived via `docs/crypto/c6p-key-schedule.md` **§5**, using:
- `root_key`
- `CTX`
- `transcript_hash`
- `suite_id` and `message_type = dm`

**Role mapping (normative):**
- Initiator: `send = CK_i2r`, `recv = CK_r2i`
- Responder: `send = CK_r2i`, `recv = CK_i2r`

Counters start at:
- `sendCounter = 0`
- `recvCounter = 0`

---

## 8. Initiator Authentication (Ed25519 Offer Signature) (Normative)

The initiator MUST authenticate the offer using Ed25519, bound to the transcript.

### 8.1 Signature label
- `LABEL_OFFER_SIG = "IA_OFFER_SIG_V1"` (ASCII/UTF-8 bytes)

### 8.2 Signature input (canonical)
To avoid ambiguity, the signature signs a hash of structured bytes:

sig_input = SHA256(
LABEL_OFFER_SIG ||
transcript_hash(32) ||
U8(C6P_VERSION) ||
U8(suite_id) ||
sessionId_bytes(8) ||
A_deviceId_bytes(16) ||
B_deviceId_bytes(16)
)



### 8.3 Signature
offer_signature = Ed25519.Sign(A_IK_sig_priv, sig_input) // 64 bytes



Responder MUST verify:
Ed25519.Verify(A_IK_sig_pub, sig_input, offer_signature) == true



Failure MUST abort with `C6P.HANDSHAKE.INITIATOR_SIGNATURE_INVALID`.

**Note:** `A_IK_sig_pub` is included in the transcript, so the signature is transcript-bound by construction.

---

## 9. Key Confirmation (KC1 + KC2) (Normative)

Key confirmation in IslandAccord v1 is **C6P Key Confirmation**, derived from `kc_key` and the transcript/session binding.

This section defines how wire fields `kc1` and `kc2` are computed.

### 9.1 KC payload (canonical)
Use `docs/crypto/c6p-key-schedule.md` §9.1:

kc_payload = SHA256(
"C6P_KC_V1" ||
U8(C6P_VERSION) ||
CTX ||
transcript_hash ||
U8(suite_id)
)



### 9.2 Directional KC tags (normative)
Use `docs/crypto/c6p-key-schedule.md` §9.3:

kc1 = HMAC-SHA256(kc_key, kc_payload || "INIT") // 32 bytes
kc2 = HMAC-SHA256(kc_key, kc_payload || "RESP") // 32 bytes



Where `"INIT"` and `"RESP"` are ASCII bytes.

### 9.3 State rule (normative)
- Responder MUST NOT mark local crypto session active until:
  - `kc1` verifies exactly.
- Initiator MUST NOT mark local crypto session active until:
  - `kc2` verifies exactly.

Mismatch MUST abort with:
- `C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED`

---

## 10. Wire Objects (Cryptographic Meaning) (Normative)

Wire shapes are defined in `island-accord-wire.md`. This section states cryptographic interpretation and required checks.

### 10.1 Offer (`dm.handshake.offer.v1`)
Offer MUST carry (minimum crypto-relevant fields):
- `version` (=1)
- `suiteId`
- `sessionId` (hex16)
- `initiatorDeviceId` (hex32)
- `responderDeviceId` (hex32)
- `initiatorIdentityDhPub` (b64url32)
- `initiatorIdentitySigPub` (b64url32)
- `initiatorEphemeralDhPub` (b64url32)
- `usedSignedPrekeyId` (hex16)
- `usedSignedPrekeyPublicKeyX25519` (b64url32)
- `usedOneTimePrekeyId` (hex16, nullable)
- `transcriptHash` (b64url32)
- `kc1` (b64url32)  // MUST equal directional INIT tag (§9.2)
- `offerSignatureEd25519` (b64url64)

Responder MUST:
1) validate encodings/lengths
2) validate `responderDeviceId` matches local device
3) load SPK/OTP private keys referenced by ids (respect rotation window policy)
4) recompute transcript_hash and compare
5) recompute DHs/IKM and derive `root_key/kc_key/chain keys` via C6P key schedule
6) verify initiator signature
7) verify `kc1`

### 10.2 Accept (`dm.handshake.accept.v1`)
Accept MUST carry:
- `sessionId` (hex16)
- `responderDeviceId` (hex32)
- `kc2` (b64url32) // MUST equal directional RESP tag (§9.2)

Initiator MUST:
1) locate local pending session by `(sessionId, responderDeviceId)`
2) verify `kc2`
3) only then mark session ACTIVE locally

---

## 11. Server Role (Normative, Non-Crypto Authority)

Server MUST:
- enforce state machine + routing + OTP scarcity (`island-accord-state-machine.md`)
- validate formats/lengths (fail-closed)
- enforce tuple uniqueness `(initiatorDeviceId, responderDeviceId, sessionId)`
- enforce suite policy allow/deny
- **MUST NOT** compute any DH or verify signatures/KC as a security boundary  
  (server MAY do superficial decoding checks only)

Server errors MUST use `docs/crypto/c6p-error-codes.md` mappings.

---

## 12. Failure Behavior (Fail-Closed) (Normative)

On any failure, implementation MUST:
- abort immediately
- not create an ACTIVE crypto session
- not advance counters/ratchet state
- zeroize ephemeral secrets when feasible

Common failure → canonical codes:
- invalid lengths/encoding: `C6P.ENC.*`
- SPK signature invalid: `C6P.HANDSHAKE.SPK_SIGNATURE_INVALID`
- transcript mismatch: `C6P.HANDSHAKE.TRANSCRIPT_MISMATCH`
- initiator signature invalid: `C6P.HANDSHAKE.INITIATOR_SIGNATURE_INVALID`
- kc mismatch: `C6P.HANDSHAKE.KEY_CONFIRMATION_FAILED`
- otp missing/unavailable: `C6P.HANDSHAKE.OTP_MISSING` / `C6P.KEYS.KEY_NOT_FOUND` (deployment must choose one mapping and keep stable)

---

## 13. Implementation Checklist (Normative)

Initiator MUST:
- [ ] fetch bundle and verify SPK signature (§3.2)
- [ ] generate fresh `A_EK` per session
- [ ] compute transcript_hash (§6)
- [ ] compute DHs and IKM (§5)
- [ ] derive `root_key`, `kc_key`, initial chains via `c6p-key-schedule.md`
- [ ] compute `kc1` (§9) and include in offer
- [ ] sign offer (§8) and include signature
- [ ] store local state as PENDING until `kc2` verifies

Responder MUST:
- [ ] validate device binding (`responderDeviceId` == local)
- [ ] load SPK private matching `usedSignedPrekeyId` (rotation policy explicit)
- [ ] load OTP private if `usedOneTimePrekeyId` present
- [ ] recompute transcript_hash and compare
- [ ] compute DHs/IKM and derive keys via `c6p-key-schedule.md`
- [ ] verify initiator signature
- [ ] verify `kc1`
- [ ] compute `kc2` and send accept
- [ ] only then mark ACTIVE locally

Server MUST:
- [ ] enforce state machine + OTP transitions atomically
- [ ] enforce tuple uniqueness and suite policy
- [ ] never derive secrets

---

## Appendix A — Pseudocode Summary (Normative)

### A.1 Initiator (A)
bundle = GET /v1/prekeys/bundle?device_id=B_deviceId
verify SPK signature with B_IK_sig_pub

A_EK = x25519_generate()

T = build_transcript( IA_VERSION, C6P_VERSION, suite_id, sessionId, A_deviceId, B_deviceId,
A_IK_dh_pub, A_IK_sig_pub, A_EK_pub,
B_IK_dh_pub, B_IK_sig_pub,
spkId, spkPub, spkSig,
otpFlag, [otpId, otpPub] )

transcript_hash = SHA256(T)

DH1 = X25519(A_IK_dh_priv, B_SPK_pub)
DH2 = X25519(A_EK_priv, B_IK_dh_pub)
DH3 = X25519(A_EK_priv, B_SPK_pub)
if otpFlag: DH4 = X25519(A_EK_priv, B_OTP_pub)

IKM = DH1||DH2||DH3||[DH4]

(root_key, kc_key) = C6P_KeySchedule_RootAndKC(IKM, transcript_hash, CTX)
(CK_i2r, CK_r2i) = C6P_KeySchedule_InitialChains(root_key, transcript_hash, CTX, suite_id, msg_type=dm)

kc1 = C6P_KC_INIT(kc_key, transcript_hash, CTX, suite_id)
sig = IA_OFFER_SIG(A_IK_sig_priv, transcript_hash, suite_id, sessionId, A_deviceId, B_deviceId)

POST /v1/dm/sessions/open with offer { transcriptHash, kc1, sig, ... }
store local session PENDING



### A.2 Responder (B)
receive offer
validate responderDeviceId == local device
load SPK_priv (and OTP_priv if referenced)

recompute transcript_hash and compare
compute mirrored DHs -> IKM
derive keys via C6P key schedule
verify initiator signature
verify kc1
kc2 = C6P_KC_RESP(kc_key, transcript_hash, CTX, suite_id)

POST /v1/dm/handshake/accept { kc2 }
store local session ACTIVE

---

## Appendix B — Suite Policy Note (Production)

For production deployments, the recommended default `suite_id` is:
- `0x01` ChaCha20-Poly1305

This document does not prohibit additional suites, but any suite enablement MUST be:
- registry-defined (`c6p-crypto-registry.md`)
- negotiated only by explicit policy (server/client)
- test-vector covered end-to-end

