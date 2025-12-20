# C6PPrekeyService.swift

## Po co istnieje ten plik
`C6PPrekeyService` zarządza **prekey material** urządzenia (device-level), które jest potrzebne do handshake99:
- **signed prekey** (X25519) + **podpis Ed25519** kluczem tożsamości urządzenia,
- **one-time prekeys** (X25519) z unikalnymi `C6PKeyId`.

To jest warstwa produkcyjna: generuje, przechowuje w Keychain, publikuje do backendu i udostępnia klucze prywatne do akceptacji handshaku po stronie respondenta.

---

## Security stance (najważniejsze)
### Fail-closed
- Jeśli brakuje kluczy tożsamości → błąd (brak fallbacków).
- Jeśli backend zwróci bundle o złych długościach → błąd.
- Jeśli nie uda się oznaczyć OTP jako zużytego na serwerze → błąd (minimalizujemy ryzyko reuse).

### Private keys never leave device
- `signed prekey private` i `one-time prekey private` nigdy nie są wysyłane na serwer.
- Serwer dostaje wyłącznie:
  - `identityPublicKeyEd25519`,
  - `signedPrekeyPublicKeyX25519 + signature`,
  - listę OTP public keys `(id, pub)`.

---

## Domain separation i podpis signed prekey
Signed prekey musi być weryfikowalny przez inicjatora:
- podpis Ed25519 nad dokładnie:
  - `label || signedPrekeyPublicKeyX25519`
- label w v1: `C6P_PREKEY_V1`

To musi być **spójne** z handshake99 (weryfikacja podpisu).

---

## Co jest przechowywane w Keychain (lokalnie)
### Signed prekey (jeden aktywny)
- private X25519 (rawRepresentation)
- public X25519
- signature Ed25519
- createdAt (do rotacji)

### OTP pool
- index: lista `C6PKeyId` (hex) dla danego deviceId
- per OTP: private X25519 rawRepresentation

Wszystko w `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.

---

## Rotacja i replenishment (v1 polityka)
- Signed prekey rotujemy co `signedPrekeyMaxAgeDays` (domyślnie 7 dni).
- OTP utrzymujemy minimum `minOneTimePrekeys` (domyślnie 50).
- Uzupełniamy batchami `oneTimeBatchSize` (domyślnie 25).

Te parametry są wstrzykiwane w init — nie są “magic constants”.

---

## Public API serwisu

### `bootstrapAndPublishIfNeeded()`
Robi pełny bootstrap:
1. Guard: account identity istnieje (rejestracja zakończona).
2. Ensure signed prekey istnieje i jest świeży (w razie potrzeby generuje).
3. Ensure OTP pool >= minimum (w razie potrzeby generuje).
4. Publish do backendu: signed prekey + nowe OTP.
5. Oczyszcza drift: usuwa OTP, które serwer odrzucił (jeśli zwrócił subset).

### `fetchPrekeyBundle(remoteDeviceId:)`
Pobiera bundle dla inicjatora i waliduje długości.  
To jest fundament dla `C6PSessionService` (getOrCreateSession → handshake99 startAsInitiator).

### `loadSignedPrekeyPrivateKey()`
Zwraca private signed prekey do acceptowania handshaku jako responder.

### `loadOneTimePrekeyPrivateKey(for:)`
Zwraca private OTP do acceptowania handshaku jako responder.

### `consumeOneTimePrekey(_:)`
- usuwa OTP lokalnie,
- zgłasza do backendu, że OTP został zużyty (aby nie wrócił w bundle).

---

## Kontrakty backendu, które muszą istnieć
To plik wymusza konkretne operacje po stronie backendu:

1) publish prekeys:
- wejście: `C6PPublishPrekeysRequest`
- wyjście: `C6PPublishPrekeysResponse`
- backend powinien:
  - zweryfikować format VN,
  - zweryfikować signature signed prekey (opcjonalnie na serwerze),
  - wstawić/rotować signed prekey,
  - wstawić OTP pool,
  - deduplikować OTP ids.

2) fetch bundle:
- wejście: remoteDeviceId
- wyjście: `C6PPrekeyBundleContract` (z opcjonalnym OTP)

3) consume OTP:
- wejście: responderDeviceId + oneTimePrekeyId
- backend usuwa/oznacza jako zużyty.

---

## Co jest “identity-level”, a co “handshake-level”
`c6p-identity` powinno definiować:
- kontrakty prekey bundle publish/fetch/consume,
- storage prekey privates,
- politykę rotacji i replenishment.

`c6p-handshake` powinno definiować:
- dokładne wyprowadzenie shared secret,
- transcript / salt,
- root/chain keys i session creation.

To rozdziela “logistykę prekey” od “matematyki handshaku”.

---

## Uwagi dot. spójności z C6PSessionService
`C6PSessionService` w v1 używa `C6PPrekeyBundleProvider` (sync closure).
PrekeyService dostarcza:
- `fetchPrekeyBundle(remoteDeviceId:)` (sync)
- więc można to podpiąć 1:1:
  `prekeyBundleProvider = { try prekeyService.fetchPrekeyBundle(remoteDeviceId: $0) }`

---

## Hard rule na przyszłość
Kontrakt `C6PPrekeyBundleContract` ma być **single source of truth**.
Nie duplikujemy tej struktury w kilku folderach.
