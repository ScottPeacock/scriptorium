import Foundation

enum JSONCoding {
    /// Grimmory serialises `Instant` as ISO-8601 with milliseconds
    /// ("2026-08-26T18:32:00.543Z") and `LocalDate` as "2026-08-26".
    /// ISO8601DateFormatter with fractional seconds rejects the latter and
    /// vice versa, so we try each in turn.
    // ISO8601DateFormatter is not Sendable, but these are configured once and
    // then only read -- parsing is thread-safe.
    nonisolated(unsafe) private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    nonisolated(unsafe) private static let whole: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let plainDay: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDate(_ string: String) -> Date? {
        fractional.date(from: string)
            ?? whole.date(from: string)
            ?? plainDay.date(from: string)
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let raw = try decoder.singleValueContainer().decode(String.self)
            guard let date = parseDate(raw) else {
                throw DecodingError.dataCorrupted(
                    .init(codingPath: decoder.codingPath, debugDescription: "Unparseable date: \(raw)")
                )
            }
            return date
        }
        return d
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractional.string(from: date))
        }
        return e
    }
}
