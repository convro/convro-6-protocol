import Foundation

// MARK: - Convro Number
struct ConvroNumber: Codable, Equatable, Hashable {
    let number: String

    init(_ number: String) {
        self.number = number.trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Formatting
    var formatted: String {
        // Format as "+99 XXX XXX"
        let digits = number.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        guard digits.hasPrefix("+99") else {
            return number
        }

        let remaining = digits.dropFirst(3)
        let chunks = remaining.chunked(into: 3)
        return "+99 " + chunks.joined(separator: " ")
    }

    // MARK: - Validation
    var isValid: Bool {
        let pattern = "^\\+99\\s?\\d{3}\\s?\\d{3}$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let range = NSRange(number.startIndex..., in: number)
        return regex?.firstMatch(in: number, range: range) != nil
    }
}

// MARK: - String Extension
private extension String {
    func chunked(into size: Int) -> [String] {
        return stride(from: 0, to: count, by: size).map {
            let start = index(startIndex, offsetBy: $0)
            let end = index(start, offsetBy: size, limitedBy: endIndex) ?? endIndex
            return String(self[start..<end])
        }
    }
}
