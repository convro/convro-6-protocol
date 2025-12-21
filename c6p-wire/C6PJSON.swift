import Foundation

enum C6PJSON {
    // ISO8601 z ms
    static let iso8601Frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    // ISO8601 bez ms (fallback)
    static let iso8601NoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static func encodeDate(_ date: Date) -> String {
        // zawsze wysyłaj z ms (kanonicznie)
        iso8601Frac.string(from: date)
    }

    static func decodeDate(_ s: String) -> Date? {
        if let d = iso8601Frac.date(from: s) { return d }
        if let d = iso8601NoFrac.date(from: s) { return d }
        return nil
    }

    static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(encodeDate(date))
        }
        return e
    }

    static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = decodeDate(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid ISO8601 date: \(s)")
        }
        return d
    }
}
