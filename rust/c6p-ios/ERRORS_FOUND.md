# Błędy znalezione w c6p-ios

## Status: UDL się kompiluje! ✅

Minimalna UDL działa - problem był w kodzie Rust, nie w UDL syntax.

## Błędy w kodzie Rust

### 1. Counter API (session.rs:239, 246)

**Błąd:**
```rust
counter.as_u64()  // ❌ Metoda nie istnieje
```

**Poprawka:**
```rust
counter.value()   // ✅ Lub u64::from(counter)
```

### 2. encrypt_message signature (session.rs:209-215)

**Aktualny (ZŁY):**
```rust
c6p_sessions::encrypt_message(
    &ratchet_output.mk_material,
    &ratchet_output.nonce,
    &plaintext,
    &ratchet_output.aad,
)
```

**Prawidłowy (z aead.rs):**
```rust
c6p_sessions::encrypt_message(
    plaintext: &[u8],
    mk_material: &MessageKeyMaterial,
    counter: u64,
    ctx: &SessionContext,
    transcript_hash: &TranscriptHash,
    stream_ctx: &StreamContext,
)
```

**Problem:** Całkowicie inna sygnatura! Muszę przepisać session.rs żeby używać wysokopoziomowego API.

### 3. decrypt_message signature (session.rs:223-228)

Taki sam problem jak encrypt_message.

### 4. Brakujące importy

Potrzebne:
- `TranscriptHash` (c6p-crypto)
- Prawidłowe typy z c6p-sessions

## Plan naprawy

### Krok 1: Napraw Counter ✅ (łatwe)
```rust
-   counter.as_u64()
+   counter.value()
```

### Krok 2: Przepisz session.rs (trudniejsze)

Zamiast używać ratchet_output bezpośrednio, przekaż wszystkie parametry do encrypt_message:

```rust
pub fn encrypt(&self, plaintext: Vec<u8>) -> Result<EncryptedMessage> {
    let mut send_stream = self.send_stream.lock().unwrap();
    let counter = send_stream.send_counter();

    let stream_ctx = StreamContext {
        stream_id: if self.is_initiator { 0x01 } else { 0x02 },
        message_type: 0x01,
        suite_id: self.suite_id,
    };

    // Użyj wysokopoziomowego API
    let sealed = c6p_sessions::encrypt_message(
        &plaintext,
        &mk_material,  // Musimy to wyciągnąć z ratchet
        counter.value(),
        &self.ctx,
        &self.transcript_hash,  // Musimy dodać do SessionState
        &stream_ctx,
    )?;

    // Advance ratchet AFTER successful encryption
    send_stream.advance_send(...)?;

    Ok(EncryptedMessage {
        counter: counter.value(),
        ciphertext: sealed,
        tag: vec![], // Tag jest już w sealed
    })
}
```

**PROBLEM:** SessionState nie ma transcript_hash! Musimy go dodać.

### Krok 3: Uproszczona alternatywa

Zamiast komplikować SessionState, mogę:
1. Użyć niższego poziomu (bezpośrednio ChaCha20Poly1305)
2. Albo dodać transcript_hash do SessionKeys w UDL

**Decyzja:** Dodać transcript_hash do SessionState i używać wysokopoziomowego API.

## Następne kroki

1. ✅ UDL kompiluje się (minimal version)
2. ⏳ Napraw błędy Counter (.value() zamiast .as_u64())
3. ⏳ Dodaj transcript_hash do SessionState
4. ⏳ Przepisz encrypt/decrypt żeby używać encrypt_message/decrypt_message
5. ⏳ Stopniowo dodaj pełną UDL
6. ⏳ Test kompilacji całego workspace
7. ⏳ Uruchom 109 testów

## Nauka

- UniFFI UDL była OK - problem był w Rust code
- Zawsze sprawdzaj signatures z prawdziwego API, nie zakładaj
- Testy są krytyczne - gdyby były testy dla c6p-ios, złapałyby to wcześniej
