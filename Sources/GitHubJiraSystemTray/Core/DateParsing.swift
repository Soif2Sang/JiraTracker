import Foundation

enum ISO8601Parser {
    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let standardFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Parses GitHub and Jira timestamps, with or without fractional seconds.
    static func date(from string: String) -> Date? {
        fractionalFormatter.date(from: string) ?? standardFormatter.date(from: string)
    }
}
