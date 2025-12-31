# C6P Crypto Core (v1) — Documentation Capsule

This directory defines the **canonical, audit-grade** cryptographic core used by Convro-6-Protocol (C6P) and by the IslandAccord v1 handshake.

**Scope:** primitives, encoding rules, domain separation, KDF/key schedule, AEAD/AAD/nonce derivation, ratchet semantics (including skip-window), implementation requirements, and test vectors.

**Non-scope:** app UI/UX, transport UI logic, product features, backend business logic.  
**Security boundary:** the backend/server **never** computes session secrets.

---

## Normative language

This documentation uses **RFC-style keywords**:

- **MUST / MUST NOT**: mandatory for compliance
- **SHOULD / SHOULD NOT**: recommended; deviation requires documented rationale
- **MAY**: optional

Any implementation claiming compatibility with **C6P v1** MUST follow all normative requirements in this directory.

---

## Canonical authority & Rust boundary

The **authoritative reference implementation** of the Crypto Core is the **Rust crypto-core** (normative behavior and edge-cases are defined there).  
Swift/Node/other languages are treated as **bindings / ports** and MUST match Rust outputs bit-for-bit (validated via test vectors).

This is intentional for auditability, determinism, and hardening (memory safety + explicit zeroization).

---

## Relationship to IslandAccord v1 handshake

IslandAccord v1 is the **handshake layer** that:
- binds parties, device IDs, and transcript inputs,
- derives the initial handshake secret material,
- performs initiator authenticity checks (Ed25519) and key confirmation,
- produces **seed inputs** for Crypto Core.

Crypto Core then defines:
- root key derivation,
- chain key derivation (i2r/r2i),
- message key ratchet behavior and state transitions,
- AEAD encryption/decryption rules,
- deterministic nonce derivation and AAD canonical layout,
- skip-window and replay protection semantics.

**Hard invariant:** Crypto Core outputs MUST be identical across all implementations given the same inputs.

---

## Directory contents (read order)

### 0) Start here
1. **`c6p-crypto-core.md`**  
   High-level crypto system view, key lifecycle, failure semantics, and what “Crypto Core” guarantees.

2. **`c6p-crypto-registry.md`**  
   Canonical registries: protocol/version IDs, suite IDs, message types, stream IDs, and **domain-separation labels**.  
   **No undeclared label is allowed.**

3. **`c6p-encoding-and-types.md`**  
   Canonical encodings and fixed-length types (base64url/hex, endianness, device/session/key IDs).

### 1) KDF + schedule
4. **`c6p-kdf-and-domain-separation.md`**  
   HKDF-SHA256 usage rules + how context binding works.

5. **`c6p-key-schedule.md`**  
   The canonical derivation graph: root key → chain keys → message keys.  
   Includes required bindings to IslandAccord v1 transcript/session inputs.

### 2) Ratchet + transport reality
6. **`c6p-ratchet-and-skip-window.md`**  
   DM ratchet semantics including **mandatory skip-window**, replay cache rules, and crash-safety expectations.

### 3) Encryption details
7. **`c6p-aead-and-aad.md`**  
   Allowed suites, AEAD failure behavior, canonical AAD layout, and parse-after-auth rules.

8. **`c6p-nonce-derivation.md`**  
   Deterministic nonce derivation function, lengths (12B/24B), and non-reuse invariants.

### 4) Hardening
9. **`c6p-implementation-requirements.md`**  
   Constant-time rules, zeroization requirements, RNG constraints, logging policy, and error handling boundaries.

### 5) Verification
10. **`c6p-test-vectors.md`** + **`vectors/`**  
    Interop validation set for auditors and CI: handshake seeds → root/chain, ratchet steps, AAD/nonce vectors.

---

## Security invariants (non-negotiable)

Implementations MUST satisfy all of the following:

1. **Fail-closed.** Any decode/length/verification failure MUST abort the operation.
2. **Canonical encoding only.** Non-canonical base64url/hex MUST be rejected (or normalized strictly where specified).
3. **Domain separation everywhere.** Every KDF derivation MUST use a declared label and correct context binding.
4. **Authenticated before parsed.** Ciphertexts MUST be authenticated (AEAD open) before any structured parsing.
5. **No secret leakage.** Logs MUST NOT contain secrets, raw keys, plaintext, or raw ECDH outputs.
6. **State transitions are atomic.** Counter and chain state MUST persist safely to prevent nonce reuse or rollback.
7. **Skip-window is mandatory.** DM receives MUST support controlled out-of-order delivery with replay protection.

---

## Cross-references

- Handshake (IslandAccord v1): `docs/handshake/*`
- Wire format envelopes/AAD: `docs/wire/*` (if present) and handshake wire doc
- Threat model: maintained separately (not in this directory)

---

## CI / audit expectations

This repository is expected to provide:
- deterministic test vectors (`docs/crypto/vectors/*`),
- a “Rust crypto-core” test harness that verifies vectors,
- optional language ports that must match vectors bit-for-bit.

Auditors should be able to:
- reproduce derivations from vectors,
- verify edge-case behavior (skip-window, replay, malformed encodings),
- confirm that server-side components never access secret material.

---

## Versioning & stability policy

- **Wire IDs and registries are stable forever** once published.
- New versions MUST:
  - bump protocol version explicitly,
  - extend registries without breaking old IDs,
  - ship a new vector set and compatibility notes.

---

## Contact / reporting

Security issues and protocol concerns should be reported privately to maintainers until a coordinated disclosure plan is agreed.

(Details and channels are defined outside this directory.)
