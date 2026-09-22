#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Reviewer detection")
struct ReviewerTests {
    private func issue(
        status: String,
        reviewer: JiraUserRef?
    ) -> JiraIssue {
        JiraIssue(
            id: "1",
            key: "OPRM-1",
            selfURL: nil,
            fields: JiraIssueFields(
                summary: "Issue",
                status: JiraStatus(name: status, statusCategory: nil),
                priority: nil,
                issueType: nil,
                updated: nil,
                codeReviewer: reviewer
            )
        )
    }

    @Test func detectsCurrentAccountAsCodeReviewer() {
        let me = JiraUserRef(accountId: "me", displayName: "Me")
        #expect(issue(status: "To Review", reviewer: me).isCodeReviewer(accountId: "me"))
        #expect(!issue(status: "To Review", reviewer: me).isCodeReviewer(accountId: "other"))
        #expect(!issue(status: "To Review", reviewer: nil).isCodeReviewer(accountId: "me"))
        #expect(!issue(status: "To Review", reviewer: me).isCodeReviewer(accountId: nil))
    }

    @Test func detectsReviewStatus() {
        #expect(issue(status: "To Review", reviewer: nil).isInReviewStatus)
        #expect(issue(status: "Code Review", reviewer: nil).isInReviewStatus)
        #expect(!issue(status: "Reviewed", reviewer: nil).isInReviewStatus)
        #expect(!issue(status: "En cours", reviewer: nil).isInReviewStatus)
    }

    @Test func reviewThreadStateIsActionableWhenNothingUnresolved() {
        #expect(GitHubReviewThreadState(myThreadCount: 0, myUnresolvedCount: 0, latestMyCommentAt: nil).isActionable)
        #expect(GitHubReviewThreadState(myThreadCount: 2, myUnresolvedCount: 0, latestMyCommentAt: nil).isActionable)
        #expect(!GitHubReviewThreadState(myThreadCount: 2, myUnresolvedCount: 1, latestMyCommentAt: nil).isActionable)
    }

    @Test func reviewThreadStateRequiresReadyBranch() {
        #expect(!GitHubReviewThreadState(myThreadCount: 0, myUnresolvedCount: 0, latestMyCommentAt: nil, isDraft: true).isActionable)
        #expect(!GitHubReviewThreadState(myThreadCount: 0, myUnresolvedCount: 0, latestMyCommentAt: nil, checkState: "FAILURE").isActionable)
        #expect(!GitHubReviewThreadState(myThreadCount: 0, myUnresolvedCount: 0, latestMyCommentAt: nil, checkState: "PENDING").isActionable)
        #expect(GitHubReviewThreadState(myThreadCount: 0, myUnresolvedCount: 0, latestMyCommentAt: nil, checkState: "SUCCESS").isActionable)
    }

    @Test func parsesPullRequestReference() {
        let reference = GitHubPullReference(url: URL(string: "https://github.com/dktunited/onepromotion-front/pull/590")!)
        #expect(reference?.owner == "dktunited")
        #expect(reference?.repository == "onepromotion-front")
        #expect(reference?.number == 590)
        #expect(GitHubPullReference(url: URL(string: "https://github.com/dktunited/onepromotion-front")!) == nil)
    }
}
#endif
