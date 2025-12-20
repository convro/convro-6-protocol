# C6PRegistrationService.swift

## Cel pliku
`C6PRegistrationService` to produkcyjny orkiestrator rejestracji konta Convro/C6P po stronie klienta.
To jest warstwa **high-level**, która spina:
- walidację danych wejściowych (username, nazwy, avatar),
- generację i bezpieczny zapis kluczy urządzenia (Keychain),
- rozmowę z backendem (przez wstrzyknięty `C6PIdentityAPIClient`),
- przydział Virtual Number w przestrzeni `+99`,
- finalizację konta i zapis `C6PAccountIdentity` lokalnie.

**UI ma gadać z tym serwisem, a nie z prymitywami.**

---

## Najważniejsze założenia (v1)

### 1) Virtual Number (VN) jako główny adres konta
- VN jest server-authoritative (backend przydziela).
- Canonical payload: **`"+99" + 6 cyfr`** (bez spacji), np. `+99123456`.
- UI może formatować to do: `+99 123 456`.
- Serwis zawsze przechowuje canonical, a formatowanie to sprawa UI.

### 2) Username to alias
- `@username` jest aliasem (nie kluczem kryptograficznym).
- Serwis wspiera:
  - `checkUsername(...)`
  - `reserveUsername(...)` (zalecane przeciw race condition)
- `reserveUsername` trzyma token rezerwacji w draft i przekazuje go do `createAccount`.

### 3) Klucze urządzenia: generacja lokalnie i tylko raz
- Prywatne klucze są generowane lokalnie (`CryptoKit`) i trafiają do Keychain.
- Backend dostaje tylko klucze publiczne:
  - Ed25519 public (32B),
  - X25519 public (32B).
- Serwis ma metodę:
  - `ensureLocalDeviceIdentity(...)` — uruchamianą w kroku “Assigning +99…”.

### 4) Rejestracja w krokach = stan draftu
Serwis utrzymuje krótkożyjący `C6PRegistrationDraft`:
- username + reservation token,
- imię/nazwisko (opcjonalne),
- avatar (None / mediaId),
- VN (po przydziale),
- meta device/platform/appVersion.

To jest intencjonalnie w pamięci (actor-state), bo:
- onboarding ma być krótki i deterministyczny,
- dane wrażliwe i tak lądują w Keychain (klucze, account identity),
- persystencję draftu (resume po crashu) można dodać jako osobny extension.

---

## Zależności (Dependencies)

### `C6PIdentityAPIClient`
To kontrakt transportu (HTTP/gRPC/WS). Serwis jest transport-agnostic.
Wymagane endpointy:
- `checkUsernameAvailability`
- `reserveUsername`
- `assignVirtualNumber`
- `createAccount`
- `registerDevice` (opcjonalnie, jeśli backend rozdziela createAccount i registerDevice)

### `C6PIdentityKeychainStore`
To jedyne źródło prawdy dla:
- aktywnego `deviceId`,
- `C6PDeviceIdentity` (private keys),
- `C6PAccountIdentity` (konto).

Serwis traktuje brak spójności Keychain jako błąd krytyczny (fail closed).

---

## Model bezpieczeństwa (Security posture)

### Fail-closed
Serwis NIE robi cichych fallbacków typu:
- “a to doróbmy nowy deviceId, bo nie ma identity”
- “a to zapiszmy byle jak, a potem naprawimy”

Jeśli Keychain mówi: “activeDeviceId istnieje, ale nie ma kluczy” → to jest **stan uszkodzony** → błąd.

### Minimalizacja danych
- Avatar w rejestracji jest `.none` albo `.mediaId`, bez URL.
- Username jest canonical (lowercase, bez `@` w payload).
- VN jest canonical (bez spacji).

### Prywatne klucze nigdy nie opuszczają urządzenia
Serwis nigdy nie wysyła:
- ed25519 private
- x25519 private
- żadnych session keys / chain keys / gmk itd.
To dotyczy tylko `c6p-identity` i bootstrapu urządzenia.

---

## Rejestracja: dokładny flow

### Krok 0: Guard
`assertOnboardingNotCompleted()`:
- jeśli `AccountIdentity` istnieje w Keychain → onboarding zablokowany.

### Krok 1: Username
- `checkUsername(raw)`
- `reserveUsername(raw)` → zapisuje:
  - `draft.username`
  - `draft.usernameReservationToken`
- `skipUsername()` (jeśli chcesz alias opcjonalny)

### Krok 2: Name
`setProfileName(firstName:lastName:)`:
- obie wartości opcjonalne,
- normalizacja/trimming w walidatorze `C6PProfileName`.

### Krok 3: Avatar
- `setAvatarNone()`
- `setAvatarMediaId(mediaId)`:
  - walidacja długości i pustych stringów,
  - brak URL.

### Krok 4: Assigning +99 (klucze + VN)
- `ensureLocalDeviceIdentity(...)`:
  - jeśli brak aktywnego deviceId → generuje:
    - deviceId (8B),
    - Ed25519 private,
    - X25519 private,
    - zapis do Keychain,
    - ustawia activeDeviceId.
- `assignVirtualNumber()`:
  - żąda VN od backendu,
  - sprawdza canonical format `+99 + 6 cyfr`,
  - zapisuje `draft.virtualNumber`.

### Krok 5: Finalizacja konta
`finalizeAccountCreation()`:
- wymaga: VN + aktywny deviceId + deviceIdentity
- buduje `C6PDevicePublicIdentityContract` z public keys
- woła backend `createAccount`
- weryfikuje spójność VN (backend vs draft)
- buduje i zapisuje `C6PAccountIdentity` do Keychain
- czyści draft

---

## Obsługa błędów
Błędy są jawne i opisowe (`CustomStringConvertible`).
Kluczowe:
- `virtualNumberNotAssigned`
- `deviceIdentityMissing`
- `usernameNotReserved` (jeśli wymusisz w UI rezerwację)
- `apiReturnedInvalidData(...)` (np. VN niecanonical)

---

## Multi-device: miejsce na rozszerzenie
v1 rejestracji tworzy konto z **primary device**.
W przyszłości:
- onboarding dodatkowego device będzie osobnym flow:
  - tworzy `C6PDeviceIdentity`,
  - rejestruje device do istniejącego VN,
  - uruchamia handshake sessions niezależnie per device (zgodnie z Twoim modelem).

---

## Uwagi implementacyjne
- Serwis jest `actor` → brak race-conditionów w onboardingu.
- Draft jest w actor-state.
- Keychain jest źródłem prawdy dla identity.
- Transport jest wstrzykiwany (łatwe podmiany HTTP/gRPC bez dotykania protokołu).

---

## Co dalej logicznie w projekcie
Po domknięciu `c6p-identity` typowy kolejny krok to:
1) Spięcie identity z handshake:
   - `prekey publish` (upload signed prekey + OTP pool),
   - `prekey fetch` (bundle dla remote device),
2) Dopiero potem full `c6p-handshake` + `c6p-wire` routing.

To utrzymuje rozdział:
**Identity bootstrap ≠ Session handshake ≠ Message wire.**
