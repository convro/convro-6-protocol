# C6PVirtualNumber.swift

## Cel pliku
Ten plik definiuje **Convro Virtual Number (VN)** w przestrzeni `+99` jako **stabilny identyfikator konta** (account identity), niezależny od numerów SIM/operatorów.

VN jest elementem **warstwy identity** – używany do:
- adresowania użytkowników (np. wyszukiwanie, invite, UI),
- powiązania profilu i listy urządzeń z kontem,
- utrzymania spójnego identyfikatora przez całe życie konta.

VN **nie jest** tożsamością kryptograficzną. Tożsamość kryptograficzna = klucze urządzeń (Ed25519/X25519) oraz ich binding do konta.

---

## Wersja i format (kontrakt v1)
### 1) Namespace
- Prefix: `+99`

### 2) Długość
- Dokładnie **6 cyfr** po `+99`.
- Dozwolone są zera wiodące.

### 3) Format wyświetlania
- UI: `+99 xxx xxx`  
  Przykład: `+99 123 456`

### 4) Format kanoniczny (storage / JSON)
- Kanonicznie zapisujemy zawsze bez spacji: `+99` + 6 cyfr  
  Przykład: `+99123456`

---

## Parsowanie i tolerancja
Decoder przyjmuje:
- `+99123456` (kanoniczny)
- `+99 123 456` (display)

W obu przypadkach wynik jest normalizowany do:
- `digits = "123456"`
- `canonicalString = "+99123456"`
- `displayString = "+99 123 456"`

---

## Generowanie VN
`C6PVirtualNumber.generate()`:
- generuje liczbę z zakresu `0...999999` **uniformly** (rejection sampling),
- formatuje do `"%06u"` (dokładnie 6 cyfr),
- tworzy `C6PVirtualNumber(digits:)`.

**Uwagi bezpieczeństwa / prywatności**
- VN nie może być przewidywalny z perspektywy klienta (używamy CSPRNG).
- VN nie gwarantuje unikalności globalnej – unikalność wymusza backend przy rejestracji.
- VN jest identyfikatorem konta, więc może być traktowany jako metadata; projekt powinien minimalizować ekspozycję VN poza koniecznymi flow.

---

## Błędy (Error model)
`C6PVirtualNumberError`:
- `invalidPrefix` – brak `+99`
- `invalidDigitsCount` – != 6
- `invalidCharacter` – nie-cyfry
- `randomGenerationFailed` – zarezerwowane na awarie generowania (w praktyce SecRandomCopyBytes)

---

## Zależności
Wymaga:
- `C6PRandom.randomUInt32()` (z `c6p-crypto/Primitives.swift`)

Nie wymaga:
- handshake
- sesji
- AEAD
- wire envelope

---

## Granice odpowiedzialności
Ten plik:
- NIE przechowuje stanu konta
- NIE komunikuje się z backendem
- NIE “rezerwuje” numeru w systemie

To jest **czysta reprezentacja i walidacja** + generowanie lokalne.

---

## TODO / rozszerzenia (v2+)
Opcjonalne przyszłe dodatki (jeśli kiedyś potrzebne):
- checksum / kontrola literówek (np. dodatkowa cyfra kontrolna) – tylko jeśli UX tego wymaga.
- obsługa aliasów (username) w tym module, ale raczej w osobnym pliku.
- możliwość migracji VN (raczej NIE – VN ma być stabilny).
