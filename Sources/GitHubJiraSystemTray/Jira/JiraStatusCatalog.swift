import Foundation

@MainActor
enum JiraStatusCatalog {
    /// Every distinct status name known from the workflow discovery and the loaded issues.
    static func names(for store: JiraStore) -> [String] {
        var result: [String] = []
        let candidates = store.availableStatusNames + store.issues.compactMap { $0.fields.status?.name }
        for name in candidates where !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            result.append(name)
        }
        return result
    }
}

/// Case-insensitive visibility of Jira statuses, persisted as a `|`-separated list.
struct JiraStatusVisibility {
    private(set) var hidden: Set<String>

    init(rawValue: String) {
        hidden = Set(rawValue.split(separator: "|").map(String.init))
    }

    var rawValue: String {
        hidden.sorted().joined(separator: "|")
    }

    func isHidden(_ status: String) -> Bool {
        hidden.contains { $0.caseInsensitiveCompare(status) == .orderedSame }
    }

    mutating func set(_ status: String, hidden shouldHide: Bool) {
        if shouldHide {
            hidden.insert(status)
        } else {
            hidden = Set(hidden.filter { $0.caseInsensitiveCompare(status) != .orderedSame })
        }
    }
}
