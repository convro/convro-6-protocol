# C6PPrekeyHTTPClient

Production HTTP client for Convro Tunnel `routes.prekeys.js`.

## Cel

Ten klient obsługuje **jedyny** fragment backendu, który jest niezbędny do uruchomienia handshake99:

- upload identity + prekeys (po stronie urządzenia, po rejestracji/logowaniu),
- pobieranie `C6PPrekeyBundle` dla iniciatora (gdy chce założyć sesję z peerem).

Klient nie implementuje kryptografii – tylko **transport** i **walidację** kontraktu HTTP/JSON.

---

## Endpointy (1:1 z Node)

### 1) POST `/v1/prekeys/upload` (requireAuth)

**Wymaga** `Authorization: Bearer <JWT_ACCESS_TOKEN>`

Body:
```json
{
  "identity": {
    "publicKeyEd25519": "<base64>",
    "fingerprint": "OPTIONAL_STRING"
  },
  "signedPrekey": {
    "publicKeyX25519": "<base64>",
    "signatureEd25519": "<base64>",
    "expiresAt": "2025-01-01T00:00:00.000Z"
  },
  "oneTimePrekeys": [
    { "keyId": "0011aabbccddeeff", "publicKeyX25519": "<base64>" }
  ]
}
