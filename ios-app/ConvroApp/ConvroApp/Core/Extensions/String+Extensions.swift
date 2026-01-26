import Foundation

extension String {
    var trim: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
