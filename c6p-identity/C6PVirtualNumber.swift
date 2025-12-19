//
//  C6PVirtualNumber.swift
//  C6P-Protocol
//
//  c6p-identity/
//  Virtual Number (VN) in +99 namespace.
//
//  v1 REQUIREMENT:
//  - Exactly 6 digits after +99
//  - Display format only: "+99 xxx xxx"
//  - Canonical format (storage/JSON): "+99" + 6 digits (no spaces), e.g. "+99123456"
//

import Foundation

// MARK: - Errors

enum C6PVirtualNumberError: Error, CustomStringConvertible {
    case invalidPrefix
    case invalidDigitsCount(expected: Int, actual: Int)
    case invalidCharacter
    case randomGenerationFailed

    var description: String {
        switch self {
        case .invalidPrefix:
            return "C6PVirtualNumberError.invalidPrefix – VN must start with \"+99\""
        case .invalidDigitsCount(let expected, let actual):
            return "C6PVirtualNumberError.invalidDigitsCount(expected=\(expected), actual=\(actual))"
        case .invalidCharacter:
            return "C6PVirtualNumberError.invalidCharacter – digits must be 0-9 only"
        case .randomGenerationFailed:
            return "C6PVirtualNumberError.randomGenerationFailed"
        }
    }
}

// MARK: - VN

/// Convro Virtual Number (VN) – +99 namespace.
///
/// Contract (v1):
/// - digits: exactly 6 numeric characters (leading zeros allowed)
/// - canonical: "+99" + digits (no spaces)
/// - display: "+99 xxx xxx"
struct C6PVirtualNumber: Hashable, Codable, CustomStringConvertible {

    static let prefix = "+99"
    static let digitsCount = 6

    /// Exactly 6 digits, numeric only, leading zeros allowed.
    private(set) var digits: String

    // MARK: - Init

    /// Create from raw digits (must be exactly 6).
    init(digits: String) throws {
        let clean = digits.trimmingCharacters(in: .whitespacesAndNewlines)

        guard clean.count == Self.digitsCount else {
            throw C6PVirtualNumberError.invalidDigitsCount(expected: Self.digitsCount, actual: clean.count)
        }
        guard clean.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
            throw C6PVirtualNumberError.invalidCharacter
        }

        self.digits = clean
    }

    /// Parse from a string that must start with "+99" and contain exactly 6 digits total.
    /// Accepts both:
    /// - "+99123456"
    /// - "+99 123 456"
    init(string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix(Self.prefix) else {
            throw C6PVirtualNumberError.invalidPrefix
        }

        // Remove prefix, then strip all whitespaces
        let afterPrefix = trimmed.dropFirst(Self.prefix.count)
        let noSpaces = afterPrefix.filter { !$0.isWhitespace }

        guard noSpaces.count == Self.digitsCount else {
            throw C6PVirtualNumberError.invalidDigitsCount(expected: Self.digitsCount, actual: noSpaces.count)
        }
        guard noSpaces.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) else {
            throw C6PVirtualNumberError.invalidCharacter
        }

        self.digits = String(noSpaces)
    }

    // MARK: - Representations

    /// Canonical string for storage/JSON: "+99" + 6 digits, no spaces.
    var canonicalString: String {
        Self.prefix + digits
    }

    /// Display string for UI: "+99 xxx xxx"
    var displayString: String {
        let a = digits.prefix(3)
        let b = digits.suffix(3)
        return "\(Self.prefix) \(a) \(b)"
    }

    var description: String {
        displayString
    }

    // MARK: - Generation

    /// Generates a VN with exactly 6 digits after "+99" (uniform via rejection sampling).
    static func generate() throws -> C6PVirtualNumber {
        // We want uniform 0...999999
        let bound: UInt32 = 1_000_000
        let limit = UInt32.max - (UInt32.max % bound)

        var r: UInt32 = 0
        while true {
            r = try C6PRandom.randomUInt32()
            if r < limit { break }
        }

        let value = r % bound
        let digits = String(format: "%06u", value)
        return try C6PVirtualNumber(digits: digits)
    }

    // MARK: - Codable (encode canonical, decode tolerant)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        // decode accepts both canonical and display, but must start with +99
        try self.init(string: raw)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(canonicalString)
    }
}
