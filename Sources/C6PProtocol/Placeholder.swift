// Placeholder.swift
// This file exists to satisfy Swift Package Manager structure requirements.
//
// The actual C6P Protocol implementation is provided by the C6PProtocolFFI
// binary target (XCFramework built from Rust).
//
// Usage:
//   import C6PProtocol
//
// The UniFFI-generated Swift bindings from c6p_ios.swift provide the full API:
//   - identity_generate_identity()
//   - handshake_create_offer()
//   - handshake_accept_offer()
//   - session_encrypt()
//   - session_decrypt()
//   etc.
//
// See rust/c6p-ios/docs/SWIFT_INTEGRATION.md for complete integration guide.

import Foundation

/// C6P Protocol version
public let c6pVersion = "0.1.0"

/// Minimum supported iOS version
public let c6pMinimumIOSVersion = "13.0"
