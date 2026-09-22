import Foundation

struct JiraIssueSearchResponse: Decodable {
    let issues: [JiraIssue]
    let nextPageToken: String?
    let isLast: Bool?
}

struct JiraUser: Decodable {
    let accountId: String
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

    enum CodingKeys: String, CodingKey {
        case summary
        case status
        case priority
        case issueType = "issuetype"
        case updated
    }
}

extension JiraIssueFields {
    var updatedDate: Date? {
        updated.flatMap(ISO8601Parser.date(from:))
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
