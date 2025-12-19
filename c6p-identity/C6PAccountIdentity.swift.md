# C6PAccountIdentity.swift

## Cel pliku
Ten plik definiuje **tożsamość konta (account identity)** w Convro/C6P:
- konto jest adresowane przez **Virtual Number (VN)** w przestrzeni `+99`
- `username` jest tylko aliasem (opcjonalny @handle), unikalność egzekwuje backend
- konto ma profil (imię/nazwisko/avatary) i listę urządzeń (public identities)

To jest model warstwy „identity”, odseparowany od:
- handshake / session / ratchet
- wire envelopes
- UI flow rejestracji (UI tylko wypełnia pola i prosi o akcje)

---

## Główne założenia v1

### 1) Adresowanie: Virtual Number +99
`virtualNumber: C6PVirtualNumber`
- format: `+99` + **dokładnie 6 cyfr**
- prezentacja UI: `+99 123 456`
- canonical (do DB / API): `+99123456`

To jest **stabilny identyfikator konta** (zamiast SIM/telefonu).

---

### 2) Username jako alias (opcjonalny)
`username: String?`
- tylko walidacja formatu po stronie klienta
- unikalność i rezerwacja: backend
- UI może renderować `@username`

Polityka v1 (client validation):
- 3–24 znaki
- start od litery
- dozwolone: `a-z 0-9 _ .`

---

### 3) Profil: firstName / lastName / avatar
`firstName`, `lastName` są opcjonalne.
Walidacja v1:
- max 64 znaki
- brak znaków kontrolnych

`avatar: C6PAvatarReference`
- w v1 **bez dowolnych URL** (anty-tracking, anty-metadata leak)
- avatar to:
  - `.localAssetId("...")` lub
  - `.backendMediaId("...")`
- jeśli kiedyś chcesz CDN URL, to jako *versioned extension*, nie domyślnie.

---

### 4) Multi-device jako fundament
`devices: [C6PAccountDeviceEntry]`
- lista urządzeń powiązanych z kontem (tylko public identity)
- v1 wymaga istnienia `primary device` (pierwsze urządzenie rejestrujące konto)
- urządzenia są „first-class” -> protokół sesji jest device-to-device, nie „account-to-account magic”

---

## Granice odpowiedzialności
Ten plik:
- ✅ definiuje model danych + walidacje + mutatory (update username/name/avatar)
- ✅ zarządza listą urządzeń (add/remove/set primary)
- ❌ nie przechowuje sekretów (private keys) — to robi Keychain store
- ❌ nie robi networku (rezerwacja username, generacja VN, upload avatar) — to robi warstwa API
- ❌ nie implementuje handshake

---

## Threat model / privacy notes
- username i profil to metadata aplikacyjna → minimalizuj ekspozycję, ale nie udawaj że jest „crypto”
- avatar URL jest wielkim wektorem trackingowym → dlatego w v1 tylko local asset id / backend media id
- urządzenia: public keys są jawne dla backendu, ale prywatne klucze nigdy nie wychodzą z klienta
- weryfikacja identity key peerów (pinning/override) jest w session layer, nie tutaj

---

## Co powinno być obok w folderze (v1)
- `C6PVirtualNumber.swift` (VN +99 6 cyfr)
- `C6PDeviceIdentity.swift` (device keys: private+public)
- `C6PAccountIdentity.swift` (ten plik)
- `C6PIdentityKeychainStore.swift` (sekrety + bezpieczne składowanie)
- (kolejny krok) `C6PIdentityRegistrationContracts.swift` (payloady rejestracji do backendu)
