# C6PEnvelope.swift — kontrakt idealny (v1)

## Cel
Jeden wspólny “wire envelope” dla wszystkich typów rozmów w v1.  
Serwer może routować ciphertext, ale NIE powinien widzieć “shape” (DM vs group vs channel).

## Zasada kluczowa
- `messageType` / “context” NIE jest jawne na drucie.
- Kontekst siedzi w zaszyfrowanym payload (`C6PInnerPayload`).

## Co jest w envelope (plaintext)
- c6pVersion
- fromDeviceId, toDeviceId
- sessionId
- clientMessageId, clientTimestamp
- serverTimestamp/serverMessageId (opcjonalne)
- deliveryState (UI)

## Co jest wiązane do AEAD (must)
- fromDeviceId, toDeviceId, sessionId, clientMessageId, c6pVersion
→ przez `C6PWireAAD.envelopeAAD(...)` jako `extraAAD` w `C6PAEAD`.

## Co NIE jest wiązane (must-not)
- serverTimestamp, serverMessageId, deliveryState

## Threat model / audyt
- Envelope jest niezaufany → klient nie ufa polom, tylko je *sprawdza kryptograficznie* przez AAD.
- Każda manipulacja routingiem powoduje `decryptFailed` (tag mismatch).
