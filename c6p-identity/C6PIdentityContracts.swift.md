# C6PIdentityContracts.swift

## Rola pliku
Ten plik definiuje **kontrakty wire-level** (request/response) dla warstwy `c6p-identity`:

- sprawdzanie dostępności `@username`
- rezerwacja `@username` (opcjonalnie, ale zalecane przeciw wyścigom)
- przydział Virtual Number w przestrzeni `+99`
- utworzenie konta (finalizacja rejestracji)
- rejestracja urządzenia (multi-device)
- aktualizacje profilu (opcjonalnie)

Plik nie zawiera networku — to świadoma decyzja:
- kontrakty mają być stabilne, łatwe do audytu i testów
- transport (HTTP/gRPC/WebSocket) jest osobną warstwą

---

## Najważniejsze założenia (v1)

### 1) Virtual Number (VN) = konto
Konto jest adresowane przez Virtual Number (VN) w przestrzeni `+99`.

**Canonical form (payload):**
- `"+99" + 6 cyfr`, bez spacji
- przykład: `+99123456`

**UI display:**
- może formatować: `+99 123 456`

To odpowiada Twojemu wymaganiu:  
> *numery tylko w formacie +99 xxx xxx*  
(payload jest canonical, UI robi spacing)

### 2) Username to alias (opcjonalny)
`@username` jest aliasem:
- może być pusty (konto nadal działa przez VN)
- jeśli jest użyty → backend musi wymusić unikalność

Payload używa handle bez `@`, UI dodaje `@` tylko do wyświetlania.

Walidacja v1:
- 3–24 znaki
- startuje literą
- dozwolone: `a-z`, `0-9`, `_`, `.`
- lowercase canonical

### 3) Avatar bez URL
W kontraktach v1 avatar to:
- `.none`
- `.mediaId(String)` (identyfikator obiektu multimediów po stronie backendu)

Nie przyjmujemy URL, żeby ograniczyć tracking i “leaky metadata”.

### 4) Device identity: public keys tylko do backendu
Device upload zawiera:
- Ed25519 public key (32B)
- X25519 public key (32B)
- optional: deviceName/platform/appVersion (nie-security-critical)

Prywatne klucze nigdy nie wychodzą poza urządzenie.

### 5) Daty
Kontrakty używają `Date` → zakładamy transport `JSONEncoder/Decoder` ustawiony na:
- `ISO8601` albo `secondsSince1970`
Ale to jest decyzja implementacji API klienta — kontrakt tylko niesie `Date`.

---

## Bezpieczeństwo i minimalizacja metadanych
- Kontrakty są jawne i audytowalne.
- Wszystko, co jest opcjonalne i nie-krytyczne, jest oznaczone jako takie.
- Canonical VN ogranicza błędy formatowania i ułatwia routing.

---

## Typy kluczowe

### `C6PVirtualNumberString`
- gwarantuje canonical: `+99` + 6 cyfr
- w payload zawsze bez spacji

### `C6PUsernameHandle`
- canonical lowercase
- walidacja znaków i długości

### `C6PDevicePublicIdentityContract`
- deviceIdHex: 16 hex chars (8 bytes)
- klucze kodowane base64url (bez paddingu)

---

## Ewolucja (v2+)
W przyszłości:
- można dodać podpisy rejestracji urządzenia (attestation)
- można dodać TOFU/pinning identity server-side
- można rozszerzyć VN (np. inne namespace) bez łamania payloadu dzięki `apiVersion`

W tym celu istnieje `C6P_IDENTITY_API_VERSION`.
