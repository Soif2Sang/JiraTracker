#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Jira date parsing")
struct JiraDateParsingTests {
    @Test func parsesFractionalSecondTimestamps() {
        #expect(ISO8601Parser.date(from: "2024-05-06T13:44:22.000+0200") != nil)
    }

    @Test func parsesPlainTimestamps() {
        #expect(ISO8601Parser.date(from: "2024-05-06T13:44:22+0200") != nil)
    }

    @Test func fieldsExposeUpdatedDate() {
        let fields = JiraIssueFields(
            summary: nil,
            status: nil,
            priority: nil,
            issueType: nil,
            updated: "2024-05-06T13:44:22.000+0200",
            codeReviewer: nil
        )

        #expect(fields.updatedDate != nil)
    }
}

@Suite("Jira status visibility")
struct JiraStatusVisibilityTests {
    @Test func togglesCaseInsensitively() {
        var visibility = JiraStatusVisibility(rawValue: "To Merge|Done")

        #expect(visibility.isHidden("to merge"))

        visibility.set("TO MERGE", hidden: false)
        #expect(!visibility.isHidden("To Merge"))
        #expect(visibility.rawValue == "Done")
    }
}
#endif
