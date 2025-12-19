# C6PInnerPayload.swift — kontrakt idealny (v1)

## Cel
Wszystko, co zdradza “shape” rozmowy (DM vs group vs channel, typ eventu) ma być E2EE.

## Zasady
- Outer envelope: minimal routing.
- Inner payload: kontekst + typ eventu + treść.

## Pola v1
- innerVersion: wersja formatu payload (oddzielna od C6P_VERSION)
- context: dm/group/channel (encrypted)
- kind: text/media/edit/reaction/delete/receipt/typing/system (encrypted)
- contextId:
  - dm: nil
  - group: group_id
  - channel: channel_id
- clientMessageId + clientTimestamp:
  - w v1 trzymamy w środku dla spójności i debug/audytu.
  - jeśli kiedyś uznasz, że timestamp w środku “za dużo metadata”, można go obciąć polityką.
- body: Data (na razie elastyczne; schema aplikacyjna może ewoluować)

## Interoperacyjność (Rust)
- `context` i `kind` są UInt8 -> stabilne.
- `body` to bytes -> dowolny codec.
- Dzięki temu Rust implementuje tylko: parse/validate fields + forward body.

## Polityka metadata
- Serwer nie zna:
  - dm/group/channel
  - rodzaju eventu
  - group_id/channel_id
  - timestamps w środku
- Serwer zna tylko routing z envelope (from/to/session) i swoje timestampy.
