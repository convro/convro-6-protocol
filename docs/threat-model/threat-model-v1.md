# C6P Threat Model (v1)

**Status:** PRODUCTION / NORMATIVE
**Scope:** Security analysis, attack surface, mitigations for C6P protocol
**Applies to:** All C6P v1 implementations

---

## 0. Purpose

This document provides a comprehensive **threat model** for the Convro 6 Protocol (C6P) v1. It identifies:
- **Assets** to protect (keys, messages, metadata)
- **Threat actors** and capabilities (network attackers, malicious servers, compromised devices)
- **Attack vectors** (interception, replay, impersonation, denial of service)
- **Mitigations** (protocol features, implementation requirements)
- **Residual risks** (out-of-scope threats, assumptions)

---

## 1. Security Goals

### 1.1 Primary Goals

1. **Confidentiality**: Messages can only be read by intended recipients
2. **Authenticity**: Recipients can verify sender identity
3. **Integrity**: Tampering with messages is detectable
4. **Forward Secrecy**: Compromise of current keys does not reveal past messages
5. **Future Secrecy** (partial): Compromise recovery via key rotation

### 1.2 Secondary Goals

6. **Replay Resistance**: Duplicate messages are rejected
7. **Metadata Minimization**: Limit exposure of metadata (who, when, frequency)
8. **Downgrade Resistance**: Protocol version and suite cannot be downgraded
9. **Deniability** (future): Cryptographic deniability for message authorship

---

## 2. Assets

### 2.1 High-Value Assets (Critical)

| Asset | Description | Compromise Impact |
|-------|-------------|-------------------|
| **IK_sig** (Identity Key - Signature) | Ed25519 long-term signing key | Full identity compromise; attacker can impersonate user |
| **IK_dh** (Identity Key - DH) | X25519 long-term DH key | Handshake compromise; attacker can complete handshakes as user |
| **Root Key** | Master secret from handshake | Session compromise; all messages in session decryptable |
| **Chain Keys** | Per-stream symmetric ratchet keys | Compromise of future messages in stream |

### 2.2 Medium-Value Assets

| Asset | Description | Compromise Impact |
|-------|-------------|-------------------|
| **SPK** (Signed Prekey) | Medium-term DH prekey (30-day rotation) | Limited-time handshake compromise |
| **OTP** (One-Time Prekey) | Single-use DH prekey | Single-session compromise if used before rotation |
| **Message Keys** | Per-message AEAD keys | Single message compromise (minimal impact due to per-message keys) |
| **Session Metadata** | Session ID, timestamps, message counts | Metadata leakage (who talks to whom, frequency) |

### 2.3 Low-Value Assets

| Asset | Description | Compromise Impact |
|-------|-------------|-------------------|
| **Device ID** | Derived from IK_sig public key | Public information; no direct compromise |
| **Fingerprints** | Public key hashes for verification | Public information; useful for social engineering |

---

## 3. Threat Actors

### 3.1 Network Attacker (Passive)

**Capabilities:**
- Observe encrypted traffic (ciphertext, AAD, metadata)
- Record traffic for later analysis (harvest-now-decrypt-later)

**Goals:**
- Decrypt messages
- Identify communication patterns (metadata analysis)

**Mitigations:**
- End-to-end encryption (AEAD)
- Metadata minimization (see §7)
- Forward secrecy (key rotation)

---

### 3.2 Network Attacker (Active)

**Capabilities:**
- Intercept, modify, replay, drop, or delay messages
- Inject fake messages
- Downgrade protocol version (if not protected)

**Goals:**
- Impersonate users
- Decrypt messages via downgrade attacks
- Cause denial of service

**Mitigations:**
- Message authentication (AEAD)
- Replay detection (consumed counters)
- Downgrade resistance (version/suite binding in AAD)
- Key confirmation (KC tags)

---

### 3.3 Malicious Server

**Capabilities:**
- Control prekey bundles (serve stale/malicious SPKs)
- Deny service (refuse to deliver messages)
- Metadata analysis (session IDs, timestamps, message sizes)

**Goals:**
- Enable man-in-the-middle attacks (serve attacker's SPK)
- Harvest metadata
- Cause denial of service

**Mitigations:**
- SPK signatures (bind SPK to IK_sig)
- Key confirmation (detect MITM before first message)
- Transparency logs (future: auditable prekey publication)
- Out-of-band fingerprint verification

**Residual Risk:** Server can still deny service (out of scope for C6P)

---

### 3.4 Compromised Device (Peer)

**Capabilities:**
- Access to all keys on compromised device
- Decrypt past and future messages from that device

**Goals:**
- Read user's messages
- Impersonate user

**Mitigations:**
- Forward secrecy (past messages protected if keys rotated)
- Per-device identities (compromise of one device does not affect others)
- Platform security (Keychain/KeyStore, biometric locks)

**Residual Risk:** Device compromise is severe; C6P cannot fully mitigate

---

### 3.5 Quantum Adversary (Future)

**Capabilities:**
- Break X25519 ECDH (Shor's algorithm)
- Harvest encrypted traffic now, decrypt later with quantum computer

**Goals:**
- Decrypt past messages (break forward secrecy)

**Mitigations:**
- Post-quantum prekeys (future: hybrid X25519 + Kyber)
- Key rotation (limit exposure window)

**Residual Risk:** C6P v1 is NOT quantum-safe; v2+ will address

---

## 4. Attack Vectors and Mitigations

### 4.1 Interception Attacks

#### 4.1.1 Passive Eavesdropping

**Attack:** Network attacker records encrypted traffic

**Mitigation:**
- AEAD encryption (ChaCha20-Poly1305)
- Unique per-message keys (from ratchet)
- No plaintext metadata in wire protocol

**Residual Risk:** Metadata (session ID, message size, timestamps) visible

---

#### 4.1.2 Man-in-the-Middle (MITM) During Handshake

**Attack:** Malicious server replaces initiator's SPK with attacker's SPK

**Mitigation:**
- SPK signature (bind SPK to IK_sig)
- Key confirmation (KC1/KC2 exchange)
- Out-of-band fingerprint verification

**Protocol Flow:**
1. Initiator fetches responder's bundle (SPK + signature)
2. Verify `SPK_sig` against responder's `IK_sig_pub`
3. Complete handshake
4. Exchange KC tags (HMAC of transcript)
5. If KC1/KC2 mismatch → abort (MITM detected)

**Residual Risk:** If server replaces BOTH SPK and IK_sig_pub, MITM succeeds until out-of-band fingerprint check

---

### 4.2 Replay Attacks

#### 4.2.1 Message Replay

**Attack:** Attacker captures encrypted message, replays it to recipient

**Mitigation:**
- Consumed counter set (reject duplicate counters)
- Session binding in AAD (prevents cross-session replay)

**Protocol Check:**
```rust
if consumed.contains(counter) {
    return Err(ReplayDetected);
}
```

**Residual Risk:** None (replay prevented by design)

---

#### 4.2.2 Prekey Bundle Replay

**Attack:** Server serves stale SPK after it's been rotated

**Mitigation:**
- SPK rotation policy (30 days)
- Migration window (7 days to accept both old and new SPK)
- After migration, reject old SPK signatures

**Residual Risk:** During migration window, old SPK is valid (acceptable tradeoff)

---

### 4.3 Impersonation Attacks

#### 4.3.1 Identity Key Substitution

**Attack:** Attacker generates new IK and registers as victim

**Mitigation:**
- Out-of-band identity verification (fingerprint exchange via QR code, voice call)
- Trust-on-first-use (TOFU) model
- Key transparency logs (future: auditable IK publication)

**Residual Risk:** TOFU vulnerable to MITM on first contact; users MUST verify fingerprints

---

#### 4.3.2 Device Impersonation

**Attack:** Stolen device used to impersonate user

**Mitigation:**
- Platform security (biometric locks, device passcodes)
- Key storage hardening (Keychain `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Remote revocation (future: device revocation via server API)

**Residual Risk:** If device unlocked and stolen, attacker has full access

---

### 4.4 Downgrade Attacks

#### 4.4.1 Protocol Version Downgrade

**Attack:** Attacker forces use of older, weaker protocol version

**Mitigation:**
- Protocol version bound in AAD (`aad[0] = 0x01`)
- Version negotiation during handshake
- No fallback to insecure versions

**Protocol Rule:** If version mismatch, abort handshake with `C6P.HANDSHAKE.VERSION_MISMATCH`

**Residual Risk:** None (downgrade prevented by design)

---

#### 4.4.2 Suite Downgrade

**Attack:** Attacker forces use of weaker crypto suite (e.g., replace ChaCha20 with broken cipher)

**Mitigation:**
- Suite ID bound in AAD (`aad[1..3] = suite_id_be16`)
- Suite bound to session at handshake
- No dynamic suite switching

**Residual Risk:** None (suite fixed at handshake)

---

### 4.5 Denial of Service (DoS)

#### 4.5.1 Message Flooding

**Attack:** Attacker sends thousands of fake messages

**Mitigation:**
- Rate limiting (server-side)
- AEAD validation (reject invalid messages early)
- Skip-window limit (2048) prevents resource exhaustion

**Residual Risk:** DoS is out of scope for E2E protocol; rely on server/network defenses

---

#### 4.5.2 OTP Exhaustion

**Attack:** Attacker consumes all OTPs for a user

**Mitigation:**
- OTP reservation TTL (5 minutes)
- Server-side rate limiting on `/fetch-bundle`
- OTP replenishment strategy (upload new OTPs periodically)

**Residual Risk:** Server can be DoS'd; mitigate with network-level defenses

---

### 4.6 Key Compromise

#### 4.6.1 Long-Term Key Compromise (IK)

**Attack:** Attacker steals `IK_sig_priv` or `IK_dh_priv`

**Impact:**
- Can impersonate user in new handshakes
- Cannot decrypt past sessions (forward secrecy protects)

**Mitigation:**
- Platform security (Keychain/KeyStore with biometric locks)
- Key rotation (user-initiated or policy-driven)
- Revocation API (mark compromised IK as revoked)

**Recovery:**
1. Detect compromise (user reports suspicious activity)
2. Rotate IK (generate new identity)
3. Notify contacts (out-of-band)
4. Revoke old IK on server

---

#### 4.6.2 Session Key Compromise (Root/Chain Key)

**Attack:** Attacker gains access to current `root_key` or `chain_key`

**Impact:**
- Can decrypt future messages in session
- Past messages protected (forward secrecy)

**Mitigation:**
- Per-message keys (limit scope of compromise)
- Session expiration (90-day TTL)
- New session negotiation (force key refresh)

**Residual Risk:** Future messages in session compromised until new session created

---

### 4.7 Metadata Leakage

#### 4.7.1 Traffic Analysis

**Attack:** Observe message sizes, timestamps, frequency to infer communication patterns

**Mitigations:**
- Padding (future: uniform message sizes)
- Dummy traffic (future: cover traffic)
- Batching (reduce timing correlation)

**Residual Risk:** C6P v1 does NOT implement padding; metadata partially exposed

---

#### 4.7.2 Session Linkability

**Attack:** Correlate session IDs across network to track users

**Mitigations:**
- Session IDs are random (not derived from user identities)
- Short-lived sessions (force rotation)

**Residual Risk:** Session IDs visible to network; cannot hide communication graph

---

## 5. Implementation Vulnerabilities

### 5.1 Timing Attacks

**Risk:** Variable-time cryptographic operations leak secret bits

**Mitigations:**
- Use constant-time crypto libraries (ring, libsodium)
- Constant-time comparisons for tags/MACs

**Test:** Run `dudect` or similar timing analysis tools

---

### 5.2 Memory Safety

**Risk:** Buffer overflows, use-after-free expose keys

**Mitigations:**
- Memory-safe languages (Rust, Swift, Kotlin)
- Bounds checking (reject oversized inputs)
- Zeroization (`zeroize` crate, `SecureBytes`)

**Test:** Use sanitizers (ASan, MSan) in CI

---

### 5.3 Side Channels

**Risk:** Cache timing, power analysis leak keys

**Mitigations:**
- Use hardware-backed keystores (Secure Enclave, StrongBox)
- Avoid secret-dependent branches (constant-time code)

**Residual Risk:** Advanced side-channel attacks (power analysis) out of scope for software-only defenses

---

### 5.4 Random Number Generation (RNG)

**Risk:** Weak RNG leads to predictable keys/nonces

**Mitigations:**
- Use platform CSPRNGs (SecRandomCopyBytes, /dev/urandom)
- NEVER use predictable seeds (timestamp, PID)

**Test:** NIST SP 800-90B statistical tests

---

## 6. Protocol-Specific Security Analysis

### 6.1 IslandAccord Handshake

**Security Properties:**
- **Authenticated key exchange**: Both parties authenticated via signatures
- **Forward secrecy**: DH ratchet provides per-session keys
- **Deniability (partial)**: Signatures prevent full deniability

**Attack Surface:**
- SPK signature verification (MUST reject invalid signatures)
- OTP replay (mitigated by consumption tracking)
- Transcript tampering (mitigated by KC tags)

**Test Vectors:** `docs/handshake/test-vectors/v1/negative_vectors.json`

---

### 6.2 DM Ratchet

**Security Properties:**
- **Forward secrecy**: Per-message keys deleted after use
- **Out-of-order tolerance**: Skip-window allows reordering
- **Replay resistance**: Consumed set prevents duplicates

**Attack Surface:**
- Counter overflow (u64 max = 2^64-1; practically unreachable)
- Skip-window exhaustion (bounded at 2048)
- State corruption (mitigated by atomic persistence)

**Test Vectors:** `docs/Sessions/test-vectors/v1/negative_vectors.json`

---

## 7. Metadata Protection

### 7.1 What is Protected

- **Message content**: Encrypted with per-message AEAD keys
- **AAD binding**: Session/stream/counter bound to ciphertext

### 7.2 What is NOT Protected (Metadata Leakage)

| Metadata | Visibility | Mitigation |
|----------|-----------|------------|
| **Session ID** | Visible to network | Random (not user-linked) |
| **Message size** | Visible to network | Padding (future) |
| **Timestamp** | Visible to network | Dummy traffic (future) |
| **Sender/recipient IPs** | Visible to network | Use Tor/VPN (out of scope) |
| **Message frequency** | Visible to network | Cover traffic (future) |

**Recommendation:** For high-threat users, combine C6P with Tor or similar anonymity networks.

---

## 8. Compliance and Audits

### 8.1 External Audits

**Recommended:** Third-party cryptographic review before v1 production release

**Focus areas:**
- Handshake protocol (IslandAccord)
- Key derivation (HKDF usage)
- AEAD construction (nonce uniqueness)
- Implementation review (timing attacks, memory safety)

---

### 8.2 Cryptographic Agility

**Current:** C6P v1 defaults to ChaCha20-Poly1305 (suite 0x01)

**Future:** Support suite negotiation (AEGIS-256, XChaCha20-Poly1305)

**Downgrade Protection:** Suite bound in AAD; cannot switch mid-session

---

## 9. Residual Risks (Out of Scope)

### 9.1 Endpoint Security

**Risk:** Compromised OS, malware on device

**Mitigation:** Out of scope; rely on platform security

---

### 9.2 Social Engineering

**Risk:** User tricked into accepting fake fingerprint

**Mitigation:** User education; protocol cannot prevent

---

### 9.3 Legal/Coercion

**Risk:** Government forces user to reveal keys

**Mitigation:** Out of scope; consider plausible deniability in future versions

---

### 9.4 Quantum Computers

**Risk:** Shor's algorithm breaks X25519

**Mitigation:** C6P v2+ will support post-quantum prekeys (Kyber)

---

## 10. Threat Summary Table

| Threat | Likelihood | Impact | Mitigation | Residual Risk |
|--------|-----------|--------|------------|---------------|
| Passive eavesdropping | High | High | AEAD encryption | Metadata visible |
| MITM (handshake) | Medium | Critical | SPK signature + KC | Server can serve fake IK |
| Replay attack | Medium | Low | Consumed set | None |
| Downgrade attack | Low | High | Version/suite in AAD | None |
| Key compromise (device) | Low | Critical | Platform security | User data exposed |
| DoS (flooding) | High | Medium | Rate limiting | Server DoS possible |
| Metadata analysis | High | Medium | None in v1 | Timing/size visible |
| Quantum attack | Low (future) | Critical | None in v1 | Harvest-now-decrypt-later |

---

## 11. Compliance Checklist

- [ ] All critical assets stored in platform secure storage (Keychain/KeyStore)
- [ ] Replay attacks prevented (consumed counter set)
- [ ] MITM prevented (SPK signature + KC)
- [ ] Downgrade attacks prevented (version/suite in AAD)
- [ ] Forward secrecy achieved (per-message keys)
- [ ] Constant-time crypto (no timing leaks)
- [ ] Memory zeroization (keys deleted after use)
- [ ] External cryptographic audit completed

---

## 12. References

- **IslandAccord Security:** `docs/handshake/island-accord-crypto.md`
- **Session Security:** `docs/Sessions/sessions-overview.md`
- **Key Storage:** `docs/identity/key-storage-and-hardening.md`
- **Error Handling:** `docs/Sessions/sessions-error-codes.md`

---

## 13. Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | TBD | Initial threat model for C6P v1 |

---
