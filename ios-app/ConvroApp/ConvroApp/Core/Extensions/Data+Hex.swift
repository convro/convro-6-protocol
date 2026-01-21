import Foundation

// MARK: - Data + Hex
extension Data {
    // MARK: - To Hex
    func toHexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - From Hex
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex

        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            let bytes = hexString[i..<j]
            if var num = UInt8(bytes, radix: 16) {
                data.append(&num, count: 1)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }

    // MARK: - Base64
    func toBase64String() -> String {
        return self.base64EncodedString()
    }

    init?(base64String: String) {
        guard let data = Data(base64Encoded: base64String) else {
            return nil
        }
        self = data
    }
}
