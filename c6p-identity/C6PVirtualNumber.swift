//
//  C6PVirtualNumber.swift
//  C6P-Protocol
//
//  Convro Virtual Number (VN) in +99 namespace.
//
//  v1 REQUIREMENT:
//  - Exactly 6 digits after +99
//  - Display format: "+99 xxx xxx"
//  - Canonical (storage/JSON): "+99" + 6 digits (no spaces), e.g. "+99123456"
//

import Foundation
import Security

// MARK: - Errors

public enum C6PVirtualNumberError: Error, CustomStringConvertible {
    case invalidPrefix
    case invalidDigitsCount(expected: Int, actual: Int)
    case invalidCharacter
    case randomGenerationFailed

    public var description: String {
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

public struct C6PVirtualNumber: Hashable, Codable, CustomStringConvertible {
    public static let prefix = "+99"
    public static let digitsCount = 6

    /// Exactly 6 digits, numeric only, leading zeros allowed.
    public private(set) var digits: String

    // MARK: Init

    /// Create from raw digits (must be exactly 6).
    public init(digits: String) throws {
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
    /// Accepts:
    /// - "+99123456" (canonical)
    /// - "+99 123 456" (display)
    public init(string: String) throws {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix(Self.prefix) else {
            throw C6PVirtualNumberError.invalidPrefix
        }

        // Remove prefix, then strip whitespaces
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

    // MARK: Representations

    /// Canonical string for storage/JSON: "+99" + 6 digits, no spaces.
    public var canonicalString: String {
        Self.prefix + digits
    }

    /// Display string for UI: "+99 xxx xxx"
    public var displayString: String {
        let a = digits.prefix(3)
        let b = digits.suffix(3)
        return "\(Self.prefix) \(a) \(b)"
    }

    public var description: String { displayString }

    // MARK: Generation

    /// Generates a VN with exactly 6 digits after "+99" (uniform via rejection sampling).
    public static func generate() throws -> C6PVirtualNumber {
        let bound: UInt32 = 1_000_000
        let limit = UInt32.max - (UInt32.max % bound)

        while true {
            let r = try C6PSecureRandom.randomUInt32()
            if r < limit {
                let value = r % bound
                let digits = String(format: "%06u", value)
                return try C6PVirtualNumber(digits: digits)
            }
        }
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        try self.init(string: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(canonicalString)
    }
}

// MARK: - Secure random

public enum C6PSecureRandom {
    public static func randomUInt32() throws -> UInt32 {
        var value: UInt32 = 0
        let status = withUnsafeMutableBytes(of: &value) { ptr in
            SecRandomCopyBytes(kSecRandomDefault, ptr.count, ptr.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw C6PVirtualNumberError.randomGenerationFailed
        }
        return value
    }
}

