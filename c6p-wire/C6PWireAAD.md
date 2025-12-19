# C6PWireAAD.swift — kontrakt idealny (v1)

## Cel
WARSTWA WIRE (envelope) jest jawna dla serwera, więc traktujemy ją jako *niezaufaną*.  
Żeby serwer/pośrednik nie mógł podmienić routingu wiadomości (np. przekierować do innego deviceId) bez wykrycia, wiążemy część nagłówka do AEAD przez AAD.

## Co AAD wiąże (must)
- C6P_VERSION
- sessionId
- fromDeviceId
- toDeviceId
- clientMessageId (w formie stałej długości, hash)

## Co AAD celowo NIE wiąże (must-not)
- serverTimestamp, serverMessageId
- deliveryState
- pola typowo “transportowe” zmienne po drodze (retry flags, queue ids)

## Format (v1)
Stała długość 38 bajtów:
- wireAADVersion (1)
- c6pVersion (1)
- sessionId (4)
- fromDeviceId (8)
- toDeviceId (8)
- clientMessageIdHash16 (16) = SHA256(utf8(clientMessageId)) truncated

## Stabilność / interoperacyjność
- Stała długość → łatwo implementować w Rust.
- Brak zmiennych stringów w AAD → brak problemów z canonicalization.
- Zmiana layoutu AAD → tylko przez bump `wireAADVersion` i wersjonowanie w repo.

## Threat model (w skrócie)
- Serwer nie zna plaintext, ale zna routing.
- Serwer nie może zmienić routingu (from/to/session/clientMessageId) bez złamania tagu AEAD.
