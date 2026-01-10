# Quick Fix Plan for c6p-ios

## Kategorie błędów

### 1. Import errors (CRITICAL)

**x25519_dalek::StaticSecret nie istnieje**
- Używam x25519-dalek 2.0 gdzie StaticSecret może mieć inną nazwę
- Rozwiązanie: Użyć `use x25519_dalek::StaticSecret` → `use x25519_dalek::EphemeralSecret`
- LUB wygenerować klucze używając rand + konwersji do [u8; 32]

**derive_device_id/derive_fingerprint nie exported**
- Te funkcje są w c6p-identity ale nie public
- Rozwiązanie: Sprawdzić c6p-identity/src/lib.rs co jest eksportowane

### 2. Newtype .to_vec() errors (EASY FIX)

Wszystkie newtypes (SessionId, DeviceId, SpkId, OtpId, TranscriptHash) to tuple structs:
```rust
pub struct SessionId(pub [u8; 8]);
```

Błąd:
```rust
session_id.to_vec()  // ❌
```

Poprawka:
```rust
session_id.0.to_vec()  // ✅
```

### 3. Ed25519Signature .to_bytes() (EASY FIX)

```rust
signature.to_bytes()  // ❌ (nie istnieje)
signature.to_vec()    // ✅ (lub &signature[..])
```

### 4. Error variant mismatches

- `IdentityError::InvalidSignature` nie istnieje
- `HandshakeError::InvalidSignature` może nie istnieje
- Muszę sprawdzić rzeczywiste warianty w c6p-identity/src/error.rs i c6p-handshake/src/error.rs

### 5. Wrong function signatures

Prawdopodobnie używam złych argumentów dla Offer::construct etc.

## Priority

1. ✅ Fix imports (identity functions, x25519)
2. ✅ Fix .to_vec() → .0.to_vec()
3. ✅ Fix error variant mappings
4. ✅ Test compilation
5. ⏳ Add rest of UDL types if working
6. ⏳ Run 109 tests

## Next Action

Commit obecne zmiany do dokumentacji z komentarzem że c6p-ios jeszcze się nie kompiluje ale zidentyfikowałem wszystkie błędy i mam plan naprawy. To pozwoli zachować postęp i daje ci transparentność co dalej.
