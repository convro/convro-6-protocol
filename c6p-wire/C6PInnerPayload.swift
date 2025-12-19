//
//  C6PInnerPayload.swift
//  C6P-Protocol
//
//  Zaszyfrowany (E2EE) payload v1.
//  Tutaj siedzi “shape” rozmowy: dm/group/channel + typ zdarzenia.
//
//  Outer envelope (C6PEnvelope) ma minimalne routing metadata.
//  Inner payload jest w całości szyfrowany w C6PAEAD.
//

import Foundation

// MARK: - Context (encrypted)

enum C6PConversationContext: UInt8, Codable {
    case dm      = 0x01
    case group   = 0x02
    case channel = 0x03
}

// MARK: - Event kind (encrypted)

enum C6PEventKind: UInt8, Codable {
    case text        = 0x01
    case media       = 0x02
    case edit        = 0x03
    case reaction    = 0x04
    case delete      = 0x05

    case receipt     = 0x10   // read/delivered receipts (policy-dependent)
    case typing      = 0x11   // typing indicators (policy-dependent)
    case system      = 0x7F   // reserved for protocol-level events
}

// MARK: - Inner payload

/// Minimalny, stabilny format E2EE dla v1.
///
/// - `contextId`:
///    * dm: nil (session + peer device routing wystarcza)
///    * group: group_id (string)
///    * channel: channel_id (string)
///
/// - `body`:
///    W v1 trzymamy to jako Data (np. JSON, CBOR, protobuf) żeby nie blokować
///    rozwoju “app schema” na tym etapie.
///    Docelowo możesz to ustandaryzować (np. strict JSON schema) w kolejnej iteracji.
struct C6PInnerPayload: Codable, Hashable {

    /// Wersja formatu inner payload (nie mylić z C6P_VERSION).
    let innerVersion: UInt8

    /// DM / group / channel (ukryte przed serwerem).
    let context: C6PConversationContext

    /// Typ zdarzenia (ukryte przed serwerem).
    let kind: C6PEventKind

    /// Kontekstowy identyfikator (group_id / channel_id) — zaszyfrowany.
    let contextId: String?

    /// Id klienta (kopiujemy z envelope dla spójności dedupe po decrypt).
    let clientMessageId: String

    /// Timestamp klienta (zaszyfrowany – opcjonalnie “minimal metadata”).
    let clientTimestamp: Date

    /// Dowolne dane payload (najczęściej JSON).
    let body: Data

    init(
        innerVersion: UInt8 = 1,
        context: C6PConversationContext,
        kind: C6PEventKind,
        contextId: String? = nil,
        clientMessageId: String,
        clientTimestamp: Date,
        body: Data
    ) {
        self.innerVersion = innerVersion
        self.context = context
        self.kind = kind
        self.contextId = contextId
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.body = body
    }
}
