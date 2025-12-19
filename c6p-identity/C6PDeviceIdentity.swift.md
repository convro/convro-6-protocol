# C6PDeviceIdentity.swift

## Rola pliku
Ten plik definiuje **tożsamość urządzenia** (device identity) w C6P/Convro:
- urządzenie ma własne long-term klucze kryptograficzne
- urządzenie ma stabilny `deviceId`
- publiczna część tożsamości jest **bezpieczna do wysyłania na backend**
- prywatne klucze są **tylko lokalnie** (Keychain / Secure Enclave / at-rest encryption)

To jest fundament multi-device v1: konto może mieć wiele urządzeń, każde z własnym zestawem kluczy.

---

## Główne typy

### 1) `C6PPublicDeviceIdentity`
**Bezpieczna, publiczna reprezentacja urządzenia.**
Zawiera:
- `deviceId: C6PDeviceId`
- `identityPublicKeyEd25519: Data` (32 bytes)
- `identityPublicKeyX25519: Data` (32 bytes)

Zastosowania:
- rejestracja urządzenia na backendzie
- pobieranie identity key do weryfikacji prekey podpisów (handshake99)
- UI “session health” / weryfikacja fingerprintu

Ważne:
- to nie jest secret; backend może to przechowywać
- jest to metadata tożsamości, więc w designie minimal-metadata powinno być traktowane jawnie i audytowalnie

Walidacje:
- oba public keys muszą mieć długość 32 bajty, inaczej błąd `C6PDeviceIdentityError.invalidPublicKeyLength`

---

### 2) `C6PDeviceIdentity`
**Pełna prywatna tożsamość urządzenia (client-side only).**
Zawiera:
- `deviceId: C6PDeviceId`
- `ed25519PrivateKey: Curve25519.Signing.PrivateKey`
- `x25519PrivateKey: Curve25519.KeyAgreement.PrivateKey`

Zastosowania:
- podpisywanie eventów (np. attestation, device binding, upgrade, key transparency / future)
- w handshake99: weryfikacja podpisów prekey po stronie inicjatora i generowanie prekey bundle po stronie respondenta (w innych plikach)

Bezpieczeństwo:
- klucze prywatne nie mogą być serializowane “zwykłym Codable”
- nie mogą trafić do logs / crash reports
- muszą być składowane w bezpiecznym storage (Keychain + ograniczenia dostępu)

---

## Fingerprint
`C6PPublicDeviceIdentity.fingerprint`:
- bazuje na `C6PFingerprint` (z `c6p-crypto/Primitives.swift`)
- fingerprint = 8 pierwszych bajtów SHA-256(pubkey) w formacie `XXXX-XXXX-XXXX-XXXX`
- fingerprint jest WYŁĄCZNIE UI / weryfikacja użytkownika
- fingerprint nie jest elementem kryptografii protokołu i nie może być traktowany jako “dowód” czegokolwiek bez odpowiednich flow (np. manual verification)

---

## Kontrakty / założenia
1) `deviceId` jest stabilny dla urządzenia.
   - Polityka przydziału `deviceId` zależy od systemu backendowego (zwykle backend nadaje).
2) Long-term klucze urządzenia są generowane lokalnie (CryptoKit).
3) Publiczne klucze są kompatybilne z handshake99:
   - Ed25519 -> podpis signed prekey
   - X25519 -> (opcjonalnie) identity agreement future use / dodatkowa warstwa bindingu

---

## Granice odpowiedzialności
Ten plik NIE:
- nie rejestruje urządzenia na backendzie
- nie przechowuje kluczy w Keychain (to będzie osobny moduł identity-store)
- nie implementuje handshake99
- nie definiuje VN (+99) ani profilu konta

To jest wyłącznie: **model urządzenia + kontrakty + helpery podpisu**.

---

## Wymagane zależności
- CryptoKit (Curve25519)
- `C6PDeviceId` i `C6PFingerprint` z `c6p-crypto/Primitives.swift`

---

## Threat model notes (dla audytu)
- Jeżeli backend poda złośliwą publiczną tożsamość urządzenia (MITM przez serwer),
  to wykrycie zależy od:
  - manualnej weryfikacji fingerprintu
  - / lub “identity override” i pinning (patrz `remoteIdentityOverrideProvider` w SessionService)
  - / lub przyszłego mechanizmu transparency / TOFU rules
- Ten plik dostarcza podstawy do tych mechanizmów, ale sam ich nie wdraża.

---

## Planowane rozszerzenia (v2+)
- Device attestation events (signed by Ed25519) + “device history log”
- Optional Secure Enclave/Keychain flags, biometrics policy
- Key transparency / gossip / proofs (oddzielny moduł)
