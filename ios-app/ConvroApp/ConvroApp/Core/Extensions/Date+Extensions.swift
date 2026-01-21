import Foundation

// MARK: - Date + Extensions
extension Date {
    // MARK: - Relative Time
    func timeAgo() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }

    // MARK: - Formatted
    func formatted(style: DateFormatter.Style = .medium) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = style
        formatter.timeStyle = style
        return formatter.string(from: self)
    }

    // MARK: - ISO8601
    var iso8601String: String {
        return ISO8601DateFormatter().string(from: self)
    }
}
