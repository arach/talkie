import Foundation

enum TalkieDate {
    private static let isoParser: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let isoParserFallback: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func fromISO8601(_ value: String) -> Date? {
        isoParser.date(from: value) ?? isoParserFallback.date(from: value)
    }

    static func relativeCompact(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }

    static func toISO8601(_ date: Date) -> String {
        isoParser.string(from: date)
    }
}

extension Date {
    var iso8601: String {
        TalkieDate.toISO8601(self)
    }
}
