import Foundation

struct JiraIssueSearchResponse: Decodable {
    let issues: [JiraIssue]
    let nextPageToken: String?
    let isLast: Bool?
}

struct JiraUser: Decodable {
    let accountId: String
}

struct JiraUserRef: Codable, Equatable {
    let accountId: String
    let displayName: String?
}

struct JiraIssue: Codable, Equatable, Identifiable {
    let id: String
    let key: String
    let selfURL: URL?
    let fields: JiraIssueFields

    enum CodingKeys: String, CodingKey {
        case id
        case key
        case selfURL = "self"
        case fields
    }
}

struct JiraIssueFields: Codable, Equatable {
    let summary: String?
    let status: JiraStatus?
    let priority: JiraNamedValue?
    let issueType: JiraNamedValue?
    let updated: String?
    let codeReviewer: JiraUserRef?

    enum CodingKeys: String, CodingKey {
        case summary
        case status
        case priority
        case issueType = "issuetype"
        case updated
        case codeReviewer = "customfield_11268"
    }
}

extension JiraIssueFields {
    var updatedDate: Date? {
        updated.flatMap(ISO8601Parser.date(from:))
    }
}

extension JiraIssue {
    /// True when the current account is listed as the ticket's Code Reviewer.
    func isCodeReviewer(accountId: String?) -> Bool {
        guard let accountId, let reviewer = fields.codeReviewer else { return false }
        return reviewer.accountId == accountId
    }

    /// True when the ticket sits in a review status (e.g. "To Review").
    var isInReviewStatus: Bool {
        guard let name = fields.status?.name else { return false }
        let normalized = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return normalized.contains("review") && !normalized.contains("reviewed")
    }
}

struct JiraStatus: Codable, Equatable {
    let name: String
    let statusCategory: JiraStatusCategory?

    enum CodingKeys: String, CodingKey {
        case name
        case statusCategory = "statusCategory"
    }
}

struct JiraStatusCategory: Codable, Equatable {
    let key: String
}

struct JiraProjectIssueTypeStatuses: Decodable {
    let statuses: [JiraStatus]
}

struct JiraNamedValue: Codable, Equatable {
    let name: String
}

struct JiraTransitionResponse: Decodable {
    let transitions: [JiraTransition]
}

struct JiraTransition: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let to: JiraNamedValue?
}

struct JiraCacheSnapshot: Codable {
    let issues: [JiraIssue]
    let savedAt: Date
}

struct JiraDevStatusResponse: Decodable {
    let detail: [Detail]

    struct Detail: Decodable {
        let pullRequests: [JiraLinkedPullRequest]?
    }
}

struct JiraLinkedPullRequest: Codable, Equatable, Identifiable {
    let id: String
    let url: URL
    let name: String?
    let status: String?

    var identity: String { url.absoluteString }
}
