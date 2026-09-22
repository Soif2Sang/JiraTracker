#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Status summary")
struct StatusSummaryTests {
    @Test func countsPullRequestsWithUnresolvedReviewThreads() {
        let pullRequests = [makePullRequest(id: "one", unresolvedCount: 2), makePullRequest(id: "two", unresolvedCount: 0)]

        let summary = StatusSummary(pullRequests: pullRequests)

        #expect(summary.reviewsPending == 1)
    }

    private func makePullRequest(id: String, unresolvedCount: Int) -> TrackedPullRequest {
        TrackedPullRequest(
            id: id,
            repository: "dktunited/repo",
            number: 1,
            title: "Pull request",
            url: URL(string: "https://github.com/dktunited/repo/pull/1")!,
            branch: "feature/test",
            headSHA: "abc123",
            isDraft: false,
            body: nil,
            updatedAt: Date(),
            workflowRuns: [],
            unresolvedReviewThreadCount: unresolvedCount
        )
    }
}
#endif
