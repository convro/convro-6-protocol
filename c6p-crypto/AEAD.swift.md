Purpose

AEAD.swift defines the protocol-level authenticated encryption interface for C6P.
It provides deterministic, context-bound encryption/decryption for message payloads, using AEAD with explicit AAD and strict failure semantics (fail-closed).

This module is protocol-facing. Concrete crypto backends (CryptoKit, third-party libs) are adapters.

Protocol assumptions

AEAD-first: All payloads are encrypted with AEAD. No plaintext content on the wire.

AEAD agility: C6P supports multiple AEAD suites via negotiation and versioning.

Deterministic nonces: Nonces are derived from protocol state and MUST be unique per (key, stream, counter).

Stream semantics are wire-stable: Any “direction/role” used in nonce/AAD MUST be computed identically by both peers (not “local perspective”).

Counter is canonical: The message counter used for nonce/AAD is a protocol field and MUST be the same for encryption and decryption.

Supported suites
C6P v1 crypto profile (protocol)

Preferred: AEGIS-128L

Fallback: XChaCha20-Poly1305

Note: The Swift reference implementation MAY temporarily use the best available platform primitives (e.g., XChaCha/ChaCha adapters), but protocol semantics must remain unchanged.

Inputs and outputs
Inputs (seal/open)

plaintext: Data (seal)

sealed: C6PSealedMessage (open)

messageKey: C6PMessageKey (suite-tagged)

nonce: C6PNonce (protocol-level nonce, length depends on suite)

context fields used to build AAD (see below)

extraAAD: Data? (optional)

Output

C6PSealedMessage (seal)

Data plaintext (open)

Wire representation

C6PSealedMessage is the wire-level ciphertext container:

ciphertext: Data — encrypted payload bytes (excluding tag)

tag: Data — AEAD authentication tag (fixed length per suite)

Nonce is not stored here by default because C6P uses deterministic nonce reconstruction.
If any mode requires transmitting a nonce (e.g., for compatibility), it must be added at the envelope layer as a versioned extension.

Nonce contract
Nonce uniqueness

Nonce reuse with the same AEAD key is catastrophic. C6P requires:

Nonce MUST be unique per (AEAD key, stream, counter).

Stream identifier (MUST)

C6P MUST use a wire-stable stream identifier, not local “sending/receiving”.

Ideal stream definition:

stream = I→R (initiator-to-responder)

stream = R→I (responder-to-initiator)

This stream id MUST be derivable identically by both peers and MUST be included in nonce and/or AAD consistently.

Nonce length

Nonce length is suite-defined:

AEGIS-128L: 16 bytes

XChaCha20-Poly1305: 24 bytes

(Legacy) ChaCha20-Poly1305: 12 bytes

C6PNonce MUST be protocol-level and MAY support multiple lengths. Adapters expose suite-specific nonce types.

AAD contract

C6P binds ciphertext to protocol context using AAD. AAD MUST be:

deterministic

canonical (same byte layout everywhere)

identical for seal/open

Canonical AAD layout (ideal, v1)

Big-endian, fixed order:

C6P_VERSION (1 byte)

suite_id (1 byte) — C6PEncryptionSuite.rawValue

session_id (8 bytes, big-endian) (ideal target; may be 4 bytes during migration)

stream_id (1 byte) — I→R or R→I

message_type (1 byte) — DM / group / channel / control

message_counter (8 bytes, big-endian)

extraAAD (optional) — appended as-is

Notes

AAD MUST NOT include fields that peers cannot deterministically reconstruct before decrypt.

If message_type is claimed to be “inside encryption”, then either:

(A) the envelope includes a minimal type/routing hint used for AAD, or

(B) message_type is removed from AAD and treated as encrypted-only.
This must be consistent across the wire layer and documented in c6p-wire/.

Failure semantics
Decrypt/auth failure

Any authentication failure MUST result in a hard failure of this message:

discard plaintext

do not attempt alternate suites

do not “repair” context

Implementations MUST NOT leak partial plaintext.

Suite mismatch

If the message key suite does not match the requested AEAD operation, it is a protocol error.

Silent suite fallback is forbidden outside handshake negotiation.

Security considerations

Context binding: Including protocol version/suite/session/stream/counter in AAD reduces cross-protocol and cross-session confusion.

Downgrade resistance: Version + suite in AAD prevents transparent downgrade after negotiation.

Replay resistance: Counter binding and replay policy (see c6p-replay/) prevents accepted replays.

Nonce discipline: Deterministic nonce generation is mandatory. Any RNG-based nonce is forbidden in C6P.

Non-goals

This module does not define:

key exchange / handshake

ratchet design

message parsing / schemas

storage encryption policy (handled separately)

push notification contents

Future extensions

Dual-track AEAD:

Transport: AEGIS-128L

Storage/offline/retries: AES-GCM-SIV or XChaCha20-Poly1305

Chunked AEAD for streaming/media with implicit counter nonce.

Hybrid PQ KEM as an opt-in enterprise extension (outside this module; affects handshake/key schedule).

Implementation status (Swift reference)

Current Swift reference may use CryptoKit-supported primitives (e.g., ChaChaPoly) for early development.

Protocol preferred suite is AEGIS-128L. If platform support is missing, the implementation must clearly declare:

which suite is active

that semantics (AAD/nonce/stream/counter contracts) remain unchanged.

Compliance checklist

 AAD layout matches spec byte-for-byte

 stream_id is wire-stable (not local)

 nonce uniqueness guaranteed per (key, stream, counter)

 no silent fallback on decrypt failure

 version/suite included in AAD

 counter overflow triggers session failure + rekey policy
