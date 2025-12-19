//
//  C6PInnerPayload.swift
//  C6P-Protocol
//
//  E2EE message "shape" (context + kind + optional contextId) + body.
//  This is what gets JSON-encoded and sealed via AEAD.
//  Server MUST NOT see these fields.
//
import Foundation

// MARK: - Conversation Context (E2EE-only)

enum C6PConversationContext: String, Codable {
    case dm      = "DM"
    case group   = "GROUP"
    case channel = "CHANNEL"
    case control = "CONTROL"
}

// MARK: - Event Kind (E2EE-only)

/// High-level event kind inside encrypted payload.
/// Keep this stable and versioned; do not leak it via plaintext metadata.
enum C6PEventKind: String, Codable {
    case message        = "MESSAGE"         // normal message (text/media/etc. encoded in body)
    case edit           = "EDIT"
    case delete         = "DELETE"
    case reaction       = "REACTION"
    case typing         = "TYPING"          // optional feature
    case readReceipt    = "READ_RECEIPT"    // optional feature
    case keyUpdate      = "KEY_UPDATE"      // future extensions (explicit, versioned)
    case customControl  = "CUSTOM_CONTROL"  // explicit control events
}

// MARK: - Inner Payload (sealed)

/// NOTE: `contextId` is E2EE-only.
/// - DM: contextId == nil
/// - GROUP: contextId can be group_id (string/uuid) but encrypted
/// - CHANNEL: contextId can be channel_id (string/uuid) but encrypted
struct C6PInnerPayload: Codable, Hashable {

    /// Inner payload schema version (NOT the same as C6P_VERSION).
    /// Lets us evolve encrypted payload format safely.
    let payloadVersion: UInt8

    let context: C6PConversationContext
    let kind: C6PEventKind

    /// Encrypted context identifier (group_id / channel_id etc.).
    /// For DM it is nil by design.
    let contextId: String?

    /// Must match envelope.clientMessageId (and is also indirectly bound via wire AAD).
    let clientMessageId: String

    /// Client-side timestamp inside E2EE payload (authoritative for client UI ordering).
    let clientTimestamp: Date

    /// Opaque body bytes (usually JSON for higher-layer message schema).
    let body: Data

    init(
        payloadVersion: UInt8 = 1,
        context: C6PConversationContext,
        kind: C6PEventKind,
        contextId: String?,
        clientMessageId: String,
        clientTimestamp: Date,
        body: Data
    ) {
        self.payloadVersion = payloadVersion
        self.context = context
        self.kind = kind
        self.contextId = contextId
        self.clientMessageId = clientMessageId
        self.clientTimestamp = clientTimestamp
        self.body = body
    }
}
