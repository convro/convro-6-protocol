FINAL PLAN REPO (CANONICAL / AUDIT-GRADE)
/docs/ (JEST W REPO W TYM MOMENCIE GOTOWY!!)
README.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)
/docs/crypto/ (JEST W REPO W TYM MOMENCIE GOTOWY!!)

README.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-crypto-registry.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-encoding-and-canonicalization.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-error-codes.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-key-schedule.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-nonce-policy.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-aead-and-aad.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

c6p-replay-and-skip-window.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

/docs/crypto/test-vectors/ (DO DODANIA)

README.md (DO DODANIA)

v1/

key_schedule_vectors.json (DO DODANIA)

nonce_vectors.json (DO DODANIA)

aad_vectors.json (DO DODANIA)

aead_vectors_chacha20poly1305.json (DO DODANIA)

aead_vectors_xchacha20poly1305.json (DO DODANIA)

replay_skipwindow_vectors.json (DO DODANIA)

/docs/handshake/ (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-crypto.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-wire.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-state-machine.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-test-matrix.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-error-codes.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

island-accord-observability.md (JEST W REPO W TYM MOMENCIE GOTOWY!!)

/docs/handshake/test-vectors/ (DO DODANIA)

README.md (DO DODANIA)

v1/

island_accord_offer_vectors.json (DO DODANIA)

initiator_derive_vectors.json (DO DODANIA)

responder_derive_vectors.json (DO DODANIA)

key_confirmation_vectors.json (DO DODANIA)

negative_vectors.json (DO DODANIA)

/docs/identity/ (JEST W REPO W TYM MOMENCIE GOTOWY!!)

(tu dopinamy kanon plików — wymagane pod audyt)

identity-registry.md (DO DODANIA)

device-identity.md (DO DODANIA)

key-rotation-policy.md (DO DODANIA)

prekeys-lifecycle.md (DO DODANIA)

key-storage-and-hardening.md (DO DODANIA)

identity-error-codes.md (DO DODANIA)

identity-test-matrix.md (DO DODANIA)

identity-observability.md (DO DODANIA)

/docs/identity/test-vectors/ (DO DODANIA)

README.md (DO DODANIA)

v1/

device_id_vectors.json (DO DODANIA)

identity_key_vectors.json (DO DODANIA)

fingerprint_vectors.json (DO DODANIA)

signed_prekey_sig_vectors.json (DO DODANIA)

prekeys_payload_vectors.json (DO DODANIA)

/docs/Sessions/ (JEST W REPO W TYM MOMENCIE GOTOWY!!)

(tu dopinamy kanon plików — wymagane pod audyt)

sessions-overview.md (DO DODANIA)

dm-ratchet-state-machine.md (DO DODANIA)

session-storage-contract.md (DO DODANIA)

concurrency-and-ordering.md (DO DODANIA)

sessions-error-codes.md (DO DODANIA)

sessions-test-matrix.md (DO DODANIA)

sessions-observability.md (DO DODANIA)

/docs/Sessions/test-vectors/ (DO DODANIA)

README.md (DO DODANIA)

v1/

dm_encrypt_vectors.json (DO DODANIA)

dm_decrypt_vectors.json (DO DODANIA)

ratchet_step_vectors.json (DO DODANIA)

skip_window_vectors.json (DO DODANIA)

replay_reject_vectors.json (DO DODANIA)

/docs/threat-model/ (DO DODANIA — osobny “9 stron A4 PDF”)

threat-model-v1.md (DO DODANIA)

assets/ (DO DODANIA)

diagrams/ (DO DODANIA)

tables/ (DO DODANIA)

/rust/ (DO DODANIA — CANONICAL “ONE TRUE CRYPTO”)
/rust/c6p-crypto/ (DO DODANIA)

Cargo.toml

src/lib.rs

src/encoding.rs (base64url/hex/canonicalize)

src/ids.rs (DeviceId/KeyId/SessionId/Counter)

src/hkdf.rs

src/kdf.rs (key schedule)

src/nonce.rs (deterministic nonce policy)

src/aad.rs (AAD builder, strict 1 format)

src/aead/

mod.rs

chacha20poly1305.rs

xchacha20poly1305.rs

aegis128l.rs (opcjonalnie: gated feature “experimental” jeśli brak top-impl)

src/errors.rs

tests/vectors_v1.rs

/rust/c6p-handshake/ (DO DODANIA)

Cargo.toml

src/lib.rs

src/island_accord.rs (initiator/responder derive, verify SPK, OTP binding)

src/key_confirmation.rs (KC tag, transcript binding)

src/transcript.rs (canonical transcript bytes)

src/wire.rs (offer/confirm structs + strict parsing)

src/errors.rs

tests/vectors_v1.rs

/rust/c6p-identity/ (DO DODANIA)

Cargo.toml

src/lib.rs

src/device_identity.rs (ed25519/x25519, fingerprints)

src/prekeys.rs (SPK/OTP lifecycle helpers — local side)

src/signatures.rs (label||spk_pub signing/verify)

src/errors.rs

tests/vectors_v1.rs

/rust/c6p-sessions/ (DO DODANIA)

Cargo.toml

src/lib.rs

src/session_state.rs (canonical C6PDMSessionState + invariants)

src/ratchet.rs (derive/advance keys using c6p-crypto)

src/skip_window.rs (cache+replay reject policy)

src/storage_contract.rs (atomic persistence format/versioning)

src/errors.rs

tests/vectors_v1.rs

/rust/c6p-testgen/ (DO DODANIA — generator wektorów)

Cargo.toml

src/main.rs (generuje JSON do docs/**/test-vectors/v1/)*

/swift/ (PLACEHOLDERY — UI OUT, ale integration IN)
/swift/C6PCoreBridge/ (DO DODANIA)

Package.swift

Sources/C6PCoreBridge/

BridgeTypes.swift (mapowanie structów/wire)

CryptoBridge.swift (wołanie Rust core / lub fallback)

StorageBridge.swift (Keychain wrapper, zero crypto logiki)

Tests/…

/swift/ConvroApp/ (POMIJAMY NA GRANTY — UI)

(celowo poza scope audytu protokołu)

/node/ (BACKEND — ROUTING + STATE AUTHORITY, ZERO SECRETS)
/node/backend/ (PLACEHOLDERY / lub istniejące)

src/

api/

v1/

prekeys.routes.js (status/upload/bundle; server reserve OTP)

dm_sessions.routes.js (open/accept; state authority)

validators/

prekeys.validator.js (strict lengths, base64url, hex)

island_accord.validator.js (offer/confirm contract)

envelopes.validator.js

db/

schema.sql

prekeys.store.js

sessions.store.js

observability/

metrics.js

audit_log.js

test/

contract_tests.spec.js (mirror test vectors from docs)

/scripts/ (DO DODANIA)

verify_vectors.sh (porównuje outputs Rust vs expected JSON)

lint_docs.sh

release_checklist.md

/LICENSE, /SECURITY, /CONTRIBUTING (DO DODANIA)

SECURITY.md (reporting policy, crypto disclosure rules)

CONTRIBUTING.md

LICENSE
