# Convro6Protocol – Crypto Layer (C6P-Crypto v1)

Status: `DRAFT-V1 (implementation-ready)`  
C6P Version: `1`  
Client runtime: Swift (iOS / iPadOS / macOS)  
Backend runtime: Node.js @ `https://api.convro.eu/bundler/v1`  
Primary DB: MariaDB 10.x

Ten dokument definiuje:

- prymitywy kryptograficzne C6P,
- format kluczy, fingerprintów i key IDs,
- harmonogram kluczy (root / chain / message),
- nonces i liczniki wiadomości,
- AEAD framing,
- **konkretny interfejs backendu** (endpointy HTTP),
- **konkretny schemat DB** dla warstwy crypto.

Cały dalszy protokół (Sessions, DMs, Groups, Channels, SecureRun) zakłada, że ta warstwa jest zaimplementowana w 100% zgodnie z tym dokumentem.

---

## 0. Global rules

1. **Treść wiadomości** i wrażliwe metadane są zawsze szyfrowane end-to-end.  
2. Backend `api.convro.eu/bundler/v1`:
   - widzi jedynie:
     - publiczne klucze,
     - jawne identyfikatory (`user_id`, `device_id`, `session_id`),
     - zakodowane AEAD blob (`nonce||ciphertext||tag` w Base64Url),
   - **nigdy** nie widzi kluczy prywatnych ani kluczy sesji.  
3. MariaDB jest wyłącznie magazynem:
   - publicznych kluczy,
   - prekeys,
   - zaszyfrowanych payloadów,
   - metadanych routingu (ale nie treści).  
4. Wszelkie błędy kryptograficzne są logowane **lokalnie na urządzeniu**, nigdy nie wysyłane na backend.

---

## 1. Cryptographic primitives (fixed for C6P_VERSION = 1)

### 1.1. Algorithms

- **Public-key / ECDH**  
  - `X25519` – key agreement (identity, prekeys, session ECDH).

- **Signatures**  
  - `Ed25519` – podpisy (identity announcement, future: key verification flows).

- **Hash & KDF**  
  - `SHA-256`  
  - `HKDF-SHA256` (Extract + Expand).

- **AEAD**  
  - `ChaCha20-Poly1305` (256-bit key, 96-bit nonce, 128-bit tag).

- **RNG**  
  - `SecRandomCopyBytes` / systemowy CSPRNG na iOS/macOS.  
  - ŻADNYCH `rand()`, `arc4random()` itd.

Zbiór algorytmów jest **sztywny** w v1. Zmiana któregokolwiek z nich = nowa wersja C6P.

### 1.2. Algorithm IDs (canonical)

W całym protokole używamy następujących ID:

- `C6P_DH_X25519_V1`
- `C6P_SIG_ED25519_V1`
- `C6P_HASH_SHA256_V1`
- `C6P_KDF_HKDFSHA256_V1`
- `C6P_AEAD_CHACHA20POLY1305_V1`

Backend i klient muszą zawsze używać tych ID w polach `algo_*` / `aead_scheme`.

---

## 2. Keys, IDs, fingerprints

### 2.1. Seeds & keypairs

Każdy keypair (identity, prekey) ma:

- **Seed** – 32 bajty z CSPRNG.
- **Private key** – trzymany lokalnie, wyprowadzony z seeda.
- **Public key** – 32 bajty.

**Encoding publicznego klucza dla backendu / API:**

```text
public_key_bytes (32 bytes)
-> Base64Url (no padding)
-> string, np. "r2Uf2iSkQmW6bJd0Q0u1bgWq8HPvM9tLtRmvE5Z1j54"
2.2. Key classes
Identity Device Key (IDK)

Typ: X25519 keypair per device.

Seed trzymany w secure storage (Keychain / Secure Enclave).

Publiczny IDK publikowany na backendzie.

Prekeys / One-time prekeys

Typ: X25519 keypair.

Publiczna część przechowywana na backendzie w c6p_prekeys.

Każdy prekey ma pole is_one_time (BOOLEAN).

One-time prekeys są zużywane przy pierwszym użyciu.

Session keys

wynik ECDH + HKDF (root/chain/message keys),

przechowywane TYLKO lokalnie.

2.3. Key IDs
Każdy klucz (IDK, prekey) posiada:

key_id – 8-bajtowy identyfikator (uint64, losowy, BE).

W JSON/API reprezentowany jako hex lowercase, np. "0f3a8b91d2c4e611".

Reguły:

key_id generujemy z RNG.

W DB jest PRIMARY KEY / UNIQUE.

W przypadku kolizji generujemy nowy.

2.4. Device IDs & User IDs
user_id – jawny identyfikator użytkownika w backendzie (np. uint64), mapowany do wirtualnego numeru +99.

device_id – 8-bajtowy uint64 per device (losowy), w JSON jako hex (np. "0012ffab9088a777").

convro_number – string w formacie +99 241 772 (canonical: bez spacji +99241772).

Zasada: identity = (user_id, device_id, IDK_public).

2.5. Fingerprint
Fingerprint IDK:

hash = SHA256(public_key_bytes) → 32 bajty.

fingerprint_bytes = hash[0..7] (pierwsze 8 bajtów).

Wyświetlanie:

text
Skopiuj kod
hex(fingerprint_bytes) UPPERCASE, grouped: A1F3-D9C0-4B7E-11D2
Pole w JSON: fingerprint (string A1F3-D9C0-4B7E-11D2).

3. HKDF & key schedule (logic & backend view)
3.1. HKDF conventions
HKDF-Extract(salt, IKM) → PRK

HKDF-Expand(PRK, info, L) → OKM

info zawsze ASCII:

text
Skopiuj kod
"c6p/<component>/<purpose>"
Przykłady:

"c6p/sessions/root-key"

"c6p/dm/sending-chain"

"c6p/group/msg-key"

"c6p/channel/msg-key"

Salt:

pierwsza transformacja – 32 bajty z RNG,

kolejne – poprzedni root_key lub chain_key.

Backend nie wykonuje HKDF – tylko klient.

3.2. Root, chain, message keys
Przykładowy flow dla DM (A ↔ B):

text
Skopiuj kod
shared_secret = X25519(a_priv, b_prekey_pub || b_idk_pub)
root_key      = HKDF-Extract(salt = root_salt, IKM = shared_secret)

sending_chain_key   = HKDF-Expand(root_key, info="c6p/dm/sending-chain",   L=32)
receiving_chain_key = HKDF-Expand(root_key, info="c6p/dm/receiving-chain", L=32)
Dla każdej wysłanej wiadomości:

text
Skopiuj kod
message_key = HKDF-Expand(
  PRK  = sending_chain_key,
  info = "c6p/dm/msg-key/" || encode_u64(counter),
  L    = 32
)

sending_chain_key_next = HKDF-Expand(
  PRK  = sending_chain_key,
  info = "c6p/dm/chain-next",
  L    = 32
)
Analogicznie dla grup i kanałów, ale z innymi prefixami info.

Backend widzi jedynie:

session_id,

direction (A→B / B→A / group / channel),

nie widzi żadnych kluczy.

4. Nonces & counters
4.1. Session nonce structure
Na poziomie sesji mamy:

session_id – 4-bajtowy uint32 (losowy lub hash z root_key).

message_counter – 8-bajtowy uint64 (monotonic, per direction).

Nonce (12 bajtów):

text
Skopiuj kod
nonce = encode_u32_be(session_id) || encode_u64_be(message_counter)
Backend nie musi rozumieć nonces – są tylko częścią blob.

4.2. Rules
message_counter start = 0.

Po każdej wysłanej wiadomości → counter += 1.

Jeśli counter zbliża się do 2^63, klient wymusza renegocjację sesji (nowy root_key, new session).

Backend może przechowywać session_message_counter_max w DB jako hint, ale nie może odtworzyć nonces.

5. AEAD
5.1. Scheme
AEAD: ChaCha20-Poly1305

key = message_key (32 bytes)

nonce = 12 bytes z sekcji 4.

AAD – opis kontekstu (poniżej).

5.2. AAD format
text
Skopiuj kod
AAD = concat(
  "c6p/aead/v1",             # ASCII
  C6P_VERSION (1 byte),      # np. 0x01
  msg_context_bytes
)
msg_context_bytes:

text
Skopiuj kod
msg_context_bytes = encode_u8(message_type)            # 0x01 DM, 0x02 GROUP, 0x03 CHANNEL, 0x10 CONTROL
                  || encode_u64_be(sender_device_id)   # 8 bytes
                  || encode_u32_be(session_id)         # 4 bytes
                  || encode_u64_be(message_counter)    # 8 bytes
Backend nie używa AAD, ale musi przechowywać message_type, sender_device_id, session_id, message_counter jako jawne kolumny w DB.

5.3. Frame layout
AEAD zwraca: ciphertext, tag.

Canonical FRAME:

text
Skopiuj kod
FRAME = nonce (12 bytes) || ciphertext (N bytes) || tag (16 bytes)
W DB i API przechowujemy:

json
Skopiuj kod
{
  "aead_scheme": "C6P_AEAD_CHACHA20POLY1305_V1",
  "blob": "base64url(FRAME)"
}
Backend nie ma prawa modyfikować blob.

6. Backend HTTP API (crypto-focused)
Base URL:

text
Skopiuj kod
https://api.convro.eu/bundler/v1
Każdy request wymaga autoryzacji (np. Authorization: Bearer <session_token>), która mapuje się do (user_id, device_id).

6.1. Identity keys API
6.1.1. Register / rotate device identity
POST /crypto/identity/register-device

Request body:

json
Skopiuj kod
{
  "user_id": 12345,
  "device_id": "0012ffab9088a777",
  "convro_number": "+99241772",
  "idk_public": "BASE64URL(X25519 public key)",
  "fingerprint": "A1F3-D9C0-4B7E-11D2",
  "algo_dh": "C6P_DH_X25519_V1",
  "platform": "ios",
  "client_version": "1.0.0-beta"
}
Semantyka:

Jeżeli (user_id, device_id) nie istnieje → tworzy rekord.

Jeżeli istnieje → traktujemy jako rotację IDK:

backend zapisuje nowy idk_public i fingerprint,

nie trzyma historii starych IDK (przynajmniej w v1).

Tabela DB (MariaDB): c6p_identity_keys

sql
Skopiuj kod
CREATE TABLE c6p_identity_keys (
  user_id           BIGINT UNSIGNED NOT NULL,
  device_id         BINARY(8)       NOT NULL, -- uint64 BE
  convro_number     VARCHAR(16)     NOT NULL, -- "+99241772" canonical
  idk_public        VARBINARY(32)   NOT NULL,
  fingerprint       CHAR(19)        NOT NULL, -- "A1F3-D9C0-4B7E-11D2"
  algo_dh           VARCHAR(64)     NOT NULL, -- "C6P_DH_X25519_V1"
  platform          VARCHAR(16)     NOT NULL,
  client_version    VARCHAR(32)     NOT NULL,
  created_at        DATETIME(6)     NOT NULL,
  updated_at        DATETIME(6)     NOT NULL,
  PRIMARY KEY (user_id, device_id),
  KEY idx_convro_number (convro_number)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
device_id w DB: zapisywany jako BINARY(8) (big-endian uint64).

6.1.2. Fetch identity keys for user / number
GET /crypto/identity/keys

Query params (jeden z):

convro_number=+99241772

albo user_id=12345

Response:

json
Skopiuj kod
{
  "user_id": 12345,
  "convro_number": "+99241772",
  "devices": [
    {
      "device_id": "0012ffab9088a777",
      "idk_public": "BASE64URL(...)",
      "fingerprint": "A1F3-D9C0-4B7E-11D2",
      "platform": "ios",
      "last_seen": "2025-12-10T22:15:34.123Z"
    }
  ]
}
Backend wykorzystuje dane z c6p_identity_keys + np. last_seen z tabel sessions.

6.2. Prekeys API
6.2.1. Publish prekeys
POST /crypto/prekeys/publish

Request:

json
Skopiuj kod
{
  "user_id": 12345,
  "device_id": "0012ffab9088a777",
  "prekeys": [
    {
      "key_id": "0f3a8b91d2c4e611",
      "public_key": "BASE64URL(X25519)",
      "is_one_time": true
    },
    {
      "key_id": "7a109db1000a7777",
      "public_key": "BASE64URL(X25519)",
      "is_one_time": false
    }
  ]
}
DB: c6p_prekeys

sql
Skopiuj kod
CREATE TABLE c6p_prekeys (
  user_id       BIGINT UNSIGNED NOT NULL,
  device_id     BINARY(8)       NOT NULL,
  key_id        BINARY(8)       NOT NULL, -- uint64 BE
  public_key    VARBINARY(32)   NOT NULL,
  is_one_time   TINYINT(1)      NOT NULL,
  used          TINYINT(1)      NOT NULL DEFAULT 0,
  created_at    DATETIME(6)     NOT NULL,
  used_at       DATETIME(6)     NULL,
  PRIMARY KEY (user_id, device_id, key_id),
  KEY idx_available (user_id, is_one_time, used)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
Zasady:

Po stronie klienta prekey private key jest trzymany lokalnie i powiązany z key_id.

Backend nie wie nic o private key.

6.2.2. Fetch & consume prekey (for handshake)
POST /crypto/prekeys/consume

Request:

json
Skopiuj kod
{
  "initiator_user_id": 555,               // A
  "initiator_device_id": "aa22bb3344ccdd11",
  "target_user_id": 12345,                // B
  "target_device_id": "0012ffab9088a777", // optional; null => any device
  "prefer_one_time": true
}
Response:

json
Skopiuj kod
{
  "target_user_id": 12345,
  "target_device_id": "0012ffab9088a777",
  "idk_public": "BASE64URL(...)",        // identity key B
  "prekey": {
    "key_id": "0f3a8b91d2c4e611",
    "public_key": "BASE64URL(...)",
    "is_one_time": true
  }
}
Zachowanie backendu:

Jeśli target_device_id podany → prekey dla tego device.

Jeśli nie → wybieramy device z ważnym IDK (np. najnowszy updated_at) i niezużytym prekey.

Jeżeli prefer_one_time = true:

najpierw szukamy is_one_time = 1 i used = 0,

jeśli brak, dopuszczamy is_one_time = 0.

Dla one-time prekey:

transakcyjnie ustawiamy used = 1, used_at = NOW(6).

6.3. AEAD storage API (generic)
Przechowywanie zaszyfrowanych wiadomości (DM/Group/Channel) opiera się o jedną tabelę c6p_aead_payloads, na którą nakładają się różne „warstwy logiczne” (DM, Group, Channel).

6.3.1. DB schema
sql
Skopiuj kod
CREATE TABLE c6p_aead_payloads (
  payload_id        BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  owner_user_id     BIGINT UNSIGNED NOT NULL,
  owner_device_id   BINARY(8)       NOT NULL, -- device, który wysłał
  session_id        BINARY(4)       NOT NULL,
  message_counter   BIGINT UNSIGNED NOT NULL, -- uint64
  message_type      TINYINT UNSIGNED NOT NULL, -- 1=DM,2=GROUP,3=CHANNEL,16=CONTROL
  direction         TINYINT UNSIGNED NOT NULL, -- 1=OUTBOUND,2=INBOUND (z perspektywy owner)
  aead_scheme       VARCHAR(64)     NOT NULL, -- "C6P_AEAD_CHACHA20POLY1305_V1"
  blob              LONGBLOB        NOT NULL, -- nonce||cipher||tag
  created_at        DATETIME(6)     NOT NULL,
  PRIMARY KEY (payload_id),
  KEY idx_owner_session (owner_user_id, session_id, message_counter),
  KEY idx_owner_type   (owner_user_id, message_type, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
Pole owner_user_id to użytkownik, do którego message logicznie należy (np. w DM – odbiorca, w group/channel – zależnie od designu warstwy wyżej).

6.3.2. Store AEAD payload
POST /crypto/aead/store

Request:

json
Skopiuj kod
{
  "owner_user_id": 12345,
  "owner_device_id": "0012ffab9088a777",
  "session_id": "01020304",                // hex (4 bytes BE)
  "message_counter": 42,
  "message_type": 1,                       // 1=DM,2=GROUP,3=CHANNEL,16=CONTROL
  "direction": 1,                          // 1=OUTBOUND,2=INBOUND
  "aead_scheme": "C6P_AEAD_CHACHA20POLY1305_V1",
  "blob": "BASE64URL(nonce||ciphertext||tag)"
}
Response:

json
Skopiuj kod
{
  "payload_id": 987654
}
Backend nie sprawdza poprawności blob, nie parsuje go.

Uwaga: wyższe warstwy (DMs, Groups, Channels) używają dodatkowych tabel do mapowania payload_id na:

dm_id / group_id / channel_id,

listę odbiorców,

pinned/flags itd.

Crypto layer nie musi o tym wiedzieć – wystarczy, że payload_id jest stabilny i indeksowalny.

6.3.3. Fetch AEAD payloads for session
GET /crypto/aead/fetch

Query params:

owner_user_id – wymagane,

session_id – hex 4-bajtowy,

opcjonalnie: since_counter, limit.

Example:

http
Skopiuj kod
GET /bundler/v1/crypto/aead/fetch?owner_user_id=12345&session_id=01020304&since_counter=0&limit=50
Response:

json
Skopiuj kod
{
  "items": [
    {
      "payload_id": 987654,
      "session_id": "01020304",
      "message_counter": 40,
      "message_type": 1,
      "direction": 2,
      "aead_scheme": "C6P_AEAD_CHACHA20POLY1305_V1",
      "blob": "BASE64URL(...)",
      "created_at": "2025-12-11T17:20:10.111Z"
    }
  ]
}
Backend sortuje rosnąco po message_counter i payload_id.

7. Error handling (client + backend)
7.1. Client-side decryption errors
Przy próbie deszyfracji:

jeśli AEAD tag się nie zgadza, nonce jest zły, albo klucz nie pasuje:

klient:

lokalnie loguje:

session_id,

message_counter,

payload_id (jeśli jest),

timestamp,

zwraca wewnętrzny błąd UI typu: „Could not decrypt message. Session may be out of sync.”

backend:

nie dostaje żadnej informacji o błędzie.

7.2. Backend errors
Jeżeli backend odrzuca request (np. brak autoryzacji, zły format JSON):

zwraca:

json
Skopiuj kod
{
  "error": "INVALID_REQUEST",
  "message": "description..."
}
Crypto layer NIE może wysyłać żadnych danych o kluczach prywatnych w treści błędu.

8. RNG & key storage (client)
Klient (Swift):

Do generowania:

seedów,

key_id,

session_id,

salts,

używa wyłącznie systemowego CSPRNG.

Klucze prywatne i seedy:

przechowywane w Keychain / Secure Enclave (zależnie od poziomu bezpieczeństwa),

nie są synchronizowane przez iCloud / backend.

Backupy:

v1: tylko manualny eksport seedów/keys (np. kodem QR / plikiem zaszyfrowanym),

brak „cloud backupów” na backendzie.

9. Versioning & compatibility
Stała protokołu:

text
Skopiuj kod
C6P_VERSION = 1
wchodzi do AAD,

powinna być przechowywana jako globalna stała we wszystkich warstwach.

Jakakolwiek zmiana:

format nonce,

HKDF info,

format AEAD frame,

wymaga zwiększenia C6P_VERSION i zdefiniowania nowych ID algorytmów, albo nowego profilu.

10. Implementacja w Swift (referencja)
Dalsze pliki Swift, które implementują ten dokument:

c6p-crypto/Primitives.swift

typy:

C6PKeyId,

C6PDeviceId,

C6PSessionId,

C6PMessageCounter,

helpery Base64Url / hex / SHA256 / HKDF.

c6p-crypto/KeySchedule.swift

C6PKeySchedule:

rootKey,

sendingChainKey,

receivingChainKey,

metody:

deriveForDM(...),

nextSendingMessageKey(),

nextReceivingMessageKey().

c6p-crypto/NonceSequencer.swift

C6PNonceSequencer:

sessionId,

currentCounter,

nextNonce().

c6p-crypto/AEAD.swift

C6PAEAD:

encrypt(messageKey, nonce, aad, plaintext) -> frame,

decrypt(messageKey, frame, aad) -> plaintext.

Te pliki muszą być spójne 1:1 z niniejszą specyfikacją
