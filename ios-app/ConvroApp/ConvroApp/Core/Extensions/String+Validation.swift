import Foundation

// MARK: - String + Validation
extension String {
    // MARK: - Username Validation
    var isValidUsername: Bool {
        let pattern = "^[a-zA-Z0-9_]{3,30}$"
        return range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Password Validation
    var isValidPassword: Bool {
        // At least 8 characters, 1 uppercase, 1 lowercase, 1 number
        return count >= 8 &&
               contains(where: { $0.isUppercase }) &&
               contains(where: { $0.isLowercase }) &&
               contains(where: { $0.isNumber })
    }

    // MARK: - Convro Number Validation
    var isValidConvroNumber: Bool {
        let pattern = "^\\+99\\s?\\d{3}\\s?\\d{3}$"
        return range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Trimmed
    var trimmed: String {
        return trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
