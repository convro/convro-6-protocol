# C6PPrekeyContracts.swift

## Cel pliku
To jest **jedyny** (canonical) zestaw kontraktów wire-level dla prekey flow w C6P:
- publikacja prekey material do backendu,
- pobranie prekey bundle przez inicjatora,
- “consume” OTP po stronie backendu, żeby uniknąć reuse.

**Tu nie ma logiki protokołu** (handshake, HKDF, session).  
Tu są tylko: struktury danych + zasady kodowania + walidacja.

---

## Najważniejsze założenia (produkcyjne)

### 1) Deterministyczne kodowanie binarek: base64url (no padding)
Wszystkie pola typu `Data` w kontraktach są kodowane przez:
`C6PBase64UrlData`

- base64url (`-` i `_`),
- bez `=` paddingu,
- stabilne do implementacji w Rust/Node,
- nie rozwala URL-i ani JSON.

To eliminuje problem “Swift Data Codable = base64 (z paddingiem)”, który bywa niespójny z resztą stacku.

---

### 2) Virtual Number (VN) — canonical wire format
Wymóg: **po +99 ma być dokładnie 6 cyfr**.

- canonical (WIRE): `+99123456`
- display (UI): `+99 123 456`

Typ `C6PVirtualNumber`:
- przechowuje `canonical`,
- potrafi zrobić `display`,
- waliduje format.

To jest kluczowe, bo VN jest “tożsamością routingu” w Twoim modelu (alias, nie numer telefonu).

---

### 3) Spójność OTP (one-time prekey)
W `C6PPrekeyBundleContract`:
- `oneTimePrekeyId` i `oneTimePrekeyPublicKeyX25519` muszą być **albo oba**, albo **żaden**.

Inaczej mamy bundle nieaudytowalny.

---

### 4) C6P version jest walidowane
Publish/consume request waliduje:
- `c6pVersion == C6P_VERSION`

To jest prosta ochrona przed mieszaniem wersji protokołu przy migracjach.

---

## Kontrakty backendu (co musi istnieć)

### Publish prekeys
Client -> backend:
- `C6PPublishPrekeysRequest`
Backend -> client:
- `C6PPublishPrekeysResponse`

Backend może zaakceptować subset OTP (np. quota, dedupe),
i zwraca `acceptedOneTimePrekeyIds`.

---

### Fetch prekey bundle
Initiator -> backend:
- remoteDeviceId (jako parametr endpointu)
Backend -> initiator:
- `C6PPrekeyBundleContract`

Bundle zawiera:
- identity ed25519 pub,
- signed prekey x25519 pub + signature,
- opcjonalny OTP (id + pub).

---

### Consume OTP
Client -> backend:
- `C6PConsumeOneTimePrekeyRequest`
Backend -> client:
- `C6PConsumeOneTimePrekeyResponse`

Cel:
- serwer musi przestać zwracać OTP, który został zużyty w handshake99.

---

## Co z handshake99?
Handshake99:
- bierze `C6PPrekeyBundleContract`,
- weryfikuje podpis SPK (label || spk_pub),
- używa OTP jeśli present,
- wyprowadza root/chain keys.

Handshake **nie definiuje** kontraktów — handshake korzysta z tego pliku.

---

## Zasada “single source of truth”
Ten plik ma być:
- łatwy do przeniesienia 1:1 do Rust,
- jedynym miejscem, gdzie definiujesz wire schema,
- bazą pod dokumentację API i DB backendu.

Nie duplikujemy tych struktur w:
- `c6p-handshake`,
- `c6p-wire`,
- `c6p-crypto`.
