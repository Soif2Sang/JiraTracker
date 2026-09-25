#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("CI status reducer")
struct CIStatusReducerTests {
    @Test func failureHasPriorityOverRunning() {
        let runs = [
            makeRun(status: "in_progress", conclusion: nil),
            makeRun(status: "completed", conclusion: "failure")
        ]

        #expect(CIStatusReducer.status(for: runs) == .failure)
    }

    @Test func runningHasPriorityOverSuccess() {
        let runs = [
            makeRun(status: "completed", conclusion: "success"),
            makeRun(status: "queued", conclusion: nil)
        ]

        #expect(CIStatusReducer.status(for: runs) == .running)
    }

    @Test func allSuccessfulRunsAreSuccessful() {
        let runs = [
            makeRun(status: "completed", conclusion: "success"),
            makeRun(status: "completed", conclusion: "skipped")
        ]

        #expect(CIStatusReducer.status(for: runs) == .success)
    }

    @Test func emptyRunsAreUnknown() {
        #expect(CIStatusReducer.status(for: [] as [GitHubWorkflowRun]) == .unknown)
    }

    @Test func checksSupplyCIWhenNoWorkflowRunsExist() {
        let url = URL(string: "https://github.com/example/repo/pull/1")!
        func pullRequest(_ checks: [GitHubCheck]?) -> TrackedPullRequest {
            TrackedPullRequest(
                id: "example/repo#1", repository: "example/repo", number: 1,
                title: "PR", url: url, branch: "feature", headSHA: "abc123",
                isDraft: false, body: nil, updatedAt: Date(),
                workflowRuns: [], checks: checks
            )
        }

        #expect(pullRequest([makeCheck(status: "completed", conclusion: "success")]).ciStatus == .success)
        #expect(pullRequest([makeCheck(status: "completed", conclusion: "failure")]).ciStatus == .failure)
        #expect(pullRequest([makeCheck(status: "in_progress", conclusion: nil)]).ciStatus == .running)
        #expect(pullRequest([makeCheck(status: "completed", conclusion: "cancelled")]).ciStatus == .cancelled)
        #expect(pullRequest(nil).ciStatus == .unknown)
        #expect(pullRequest([]).ciStatus == .unknown)
    }

    @Test func commitChecksReduceLikeWorkflowRuns() {
        #expect(CIStatusReducer.status(for: [makeCheck(status: "in_progress", conclusion: nil)]) == .running)
        #expect(CIStatusReducer.status(for: [makeCheck(status: "completed", conclusion: "failure")]) == .failure)
        #expect(CIStatusReducer.status(for: [makeCheck(status: "completed", conclusion: "cancelled")]) == .cancelled)
        #expect(CIStatusReducer.status(for: [makeCheck(status: "completed", conclusion: "success")]) == .success)
        #expect(CIStatusReducer.status(for: [makeCheck(status: "completed", conclusion: "neutral")]) == .success)
        #expect(CIStatusReducer.status(for: [] as [GitHubCheck]) == .unknown)
    }

    @Test func failureCheckHasPriorityOverRunningCheck() {
        let checks = [
            makeCheck(status: "in_progress", conclusion: nil),
            makeCheck(status: "completed", conclusion: "failure")
        ]

        #expect(CIStatusReducer.status(for: checks) == .failure)
    }

    @Test func boundedChecksWinOverStaleWorkflowRuns() {
        let url = URL(string: "https://github.com/example/repo/pull/1")!
        let pullRequest = TrackedPullRequest(
            id: "example/repo#1", repository: "example/repo", number: 1,
            title: "PR", url: url, branch: "feature", headSHA: "abc123",
            isDraft: false, body: nil, updatedAt: Date(),
            workflowRuns: [makeRun(status: "in_progress", conclusion: nil)],
            checks: [makeCheck(status: "completed", conclusion: "success")]
        )

        #expect(pullRequest.ciStatus == .success)
    }

    @Test func batchedSummariesPayloadUsesDynamicAliases() throws {
        let json = """
        {
          "pr0": {
            "pullRequest": {
              "reviewThreads": {
                "nodes": [
                  { "isResolved": false, "comments": { "nodes": [ { "createdAt": "2026-01-01T00:00:00Z" } ] } },
                  { "isResolved": true, "comments": { "nodes": [] } }
                ],
                "pageInfo": { "hasNextPage": false }
              }
            },
            "object": {
              "statusCheckRollup": {
                "contexts": { "nodes": [
                  { "__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "FAILURE", "detailsUrl": "https://example.com/1", "isRequired": true, "checkSuite": { "app": { "slug": "github-actions" } } },
                  { "__typename": "StatusContext", "context": "ci/foo", "state": "PENDING", "targetUrl": "https://example.com/2", "isRequired": false }
                ] }
              }
            }
          },
          "pr1": null
        }
        """

        let payload = try GitHubJSON.decoder.decode(
            GitHubBatchedSummariesPayload.self,
            from: Data(json.utf8)
        )

        #expect(payload.nodes.count == 1)
        let pullRequest = try #require(payload.nodes[0]?.pullRequest)
        #expect(pullRequest.reviewThreads.nodes.filter { !$0.isResolved }.count == 1)
        #expect(pullRequest.reviewThreads.pageInfo.hasNextPage == false)
        let contexts = try #require(payload.nodes[0]?.object?.statusCheckRollup?.contexts.nodes)
        #expect(contexts.count == 2)
        #expect(contexts[0].typename == "CheckRun")
        #expect(contexts[0].conclusion == "FAILURE")
        #expect(contexts[0].isRequired == true)
        #expect(contexts[0].checkSuite?.app?.slug == "github-actions")
        #expect(contexts[1].typename == "StatusContext")
        #expect(contexts[1].state == "PENDING")
        #expect(contexts[1].isRequired == false)
        #expect(payload.nodes[1] == nil)
    }

    @Test func requiredChecksIgnoreFailingOptionalChecks() {
        let identity = "example/repo#590"
        let build = GitHubCheck(id: "r1", name: "Build and push docker image / build", status: "completed", conclusion: "success", url: nil)
        let a11y = GitHubCheck(id: "r2", name: "Run a11y tests", status: "completed", conclusion: "success", url: nil)
        let sonar = GitHubCheck(id: "o1", name: "SonarCloud Code Analysis", status: "completed", conclusion: "failure", url: nil)

        // SonarCloud is failing but not required: the required checks win and the PR stays green.
        let selected = GitHubClient.selectedChecks(
            all: [build, a11y, sonar],
            required: [build, a11y],
            actions: [build, a11y],
            aggregate: "FAILURE",
            identity: identity
        )
        #expect(selected == [build, a11y])
        #expect(CIStatusReducer.status(for: selected) == .success)
    }

    @Test func actionsChecksWinOverFailingThirdPartyWhenNothingIsRequired() {
        let identity = "example/repo#3013"
        let build = GitHubCheck(id: "a1", name: "Build and push docker image / build", status: "completed", conclusion: "success", url: nil)
        let karate = GitHubCheck(id: "a2", name: "Run Karate tests / karate-runner", status: "completed", conclusion: "success", url: nil)
        let sonar = GitHubCheck(id: "o1", name: "SonarCloud Code Analysis", status: "completed", conclusion: "failure", url: nil)

        // No required checks (no branch protection), but Actions ran: keep Actions, drop SonarCloud.
        let selected = GitHubClient.selectedChecks(
            all: [build, karate, sonar],
            required: [],
            actions: [build, karate],
            aggregate: "FAILURE",
            identity: identity
        )
        #expect(selected == [build, karate])
        #expect(CIStatusReducer.status(for: selected) == .success)

        // Neither required nor Actions (e.g. only third-party apps): fall back to every check.
        let fallback = GitHubClient.selectedChecks(
            all: [sonar],
            required: [],
            actions: [],
            aggregate: "FAILURE",
            identity: identity
        )
        #expect(CIStatusReducer.status(for: fallback) == .failure)
    }

    @Test func aggregateStateBackfillsTruncatedChecks() {
        let identity = "example/repo#1"
        let success = makeCheck(status: "completed", conclusion: "success")

        // Aggregate failure not visible in the fetched page must still surface as failure.
        let failed = GitHubClient.reconciling(checks: [success], aggregate: "FAILURE", identity: identity)
        #expect(CIStatusReducer.status(for: failed) == .failure)

        // Aggregate pending beyond the page must not be reported as success.
        let pending = GitHubClient.reconciling(checks: [success], aggregate: "PENDING", identity: identity)
        #expect(CIStatusReducer.status(for: pending) == .running)

        // No checks but a successful rollup must be success, not unknown.
        let emptySuccess = GitHubClient.reconciling(checks: [], aggregate: "SUCCESS", identity: identity)
        #expect(CIStatusReducer.status(for: emptySuccess) == .success)

        // No aggregate, or an already-matching one, leaves the list untouched.
        #expect(GitHubClient.reconciling(checks: [success], aggregate: nil, identity: identity).count == 1)
        #expect(GitHubClient.reconciling(checks: [success], aggregate: "SUCCESS", identity: identity).count == 1)
    }

    private func makeCheck(status: String?, conclusion: String?) -> GitHubCheck {
        GitHubCheck(
            id: UUID().uuidString,
            name: "job",
            status: status,
            conclusion: conclusion,
            url: nil
        )
    }

    private func makeRun(status: String, conclusion: String?) -> GitHubWorkflowRun {
        GitHubWorkflowRun(
            id: Int64.random(in: 1...10_000),
            name: "CI",
            status: status,
            conclusion: conclusion,
            htmlURL: URL(string: "https://github.com/dktunited/repo/actions/runs/1")!,
            headSHA: "abc123",
            runAttempt: 1,
            createdAt: Date(),
            updatedAt: Date(),
            jobs: nil
        )
    }
}
#endif
