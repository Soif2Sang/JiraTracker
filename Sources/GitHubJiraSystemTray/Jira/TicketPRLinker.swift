import Foundation

enum TicketPRLinker {
    private static let pattern = try! NSRegularExpression(pattern: #"\b[A-Z][A-Z0-9]+-\d+\b"#, options: .caseInsensitive)

    static func keys(for pullRequest: TrackedPullRequest) -> [String] {
        let sources = [pullRequest.branch, pullRequest.title, pullRequest.body ?? ""]
        var keys: [String] = []
        for source in sources {
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            for match in pattern.matches(in: source, options: [], range: range) {
                guard let matchRange = Range(match.range, in: source) else { continue }
                let key = String(source[matchRange]).uppercased()
                if !keys.contains(key) {
                    keys.append(key)
                }
            }
        }
        return keys
    }

    static func pullRequests(for key: String, in pullRequests: [TrackedPullRequest]) -> [TrackedPullRequest] {
        let normalizedKey = key.uppercased()
        return pullRequests.filter { keys(for: $0).contains(normalizedKey) }
    }

}
