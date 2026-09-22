#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Ticket and PR linker")
struct TicketPRLinkerTests {
    @Test func keysPreferBranchAndDeduplicateAcrossSources() {
        let pullRequest = TrackedPullRequest(
            id: "dktunited/repo#1",
            repository: "dktunited/repo",
            number: 1,
            title: "feat(OPRM-1930): update checkout",
            url: URL(string: "https://github.com/dktunited/repo/pull/1")!,
            branch: "feat/oprm-1930/checkout",
            headSHA: "abc123",
            isDraft: false,
            body: "Related to OPRM-1931",
            updatedAt: Date(),
            isMerged: false,
            workflowRuns: []
        )

        #expect(TicketPRLinker.keys(for: pullRequest) == ["OPRM-1930", "OPRM-1931"])
    }

}
#endif
