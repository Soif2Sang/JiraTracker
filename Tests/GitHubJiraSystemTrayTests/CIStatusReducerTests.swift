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
        #expect(CIStatusReducer.status(for: []) == .unknown)
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
