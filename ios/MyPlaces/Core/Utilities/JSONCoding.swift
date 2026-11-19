import Foundation

enum JSONCoding {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = DateParsing.parse(s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(DateParsing.isoString(date))
        }
        return e
    }()

    /// Plain coder for local persistence (outbox payloads, caches).
    static let localEncoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    static let localDecoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()
}

enum DateParsing {
    private static let isoNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func isoString(_ date: Date) -> String { isoFrac.string(from: date) }

    /// Parses `2026-11-19T09:13:00.123456+00:00`, `...Z`, `+00`, no zone (treated as UTC) or `yyyy-MM-dd`.
    static func parse(_ raw: String) -> Date? {
        var s = raw.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: " ", with: "T")
        if s.count == 10 { return day.date(from: s) }
        var fraction = 0.0
        if let dot = s.firstIndex(of: ".") {
            var end = s.index(after: dot)
            while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
            fraction = Double("0" + String(s[dot..<end])) ?? 0
            s.removeSubrange(dot..<end)
        }
        if s.range(of: #"[+-]\d{2}$"#, options: .regularExpression) != nil {
            s += ":00"
        } else if !(s.hasSuffix("Z") || s.range(of: #"[+-]\d{2}:?\d{2}$"#, options: .regularExpression) != nil) {
            s += "Z"
        }
        guard let d = isoNoFrac.date(from: s) else { return nil }
        return d.addingTimeInterval(fraction)
    }

    /// Wall-clock components of a zone-less timestamp (e.g. `visited_local`).
    static func localComponents(_ raw: String) -> DateComponents? {
        guard let d = parse(raw) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
    }
}
