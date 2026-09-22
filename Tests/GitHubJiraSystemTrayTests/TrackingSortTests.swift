#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Tracking sort")
@MainActor
struct TrackingSortTests {
    @Test func discoversJiraStatusesAndPriorities() {
        let store = makeStore()
        let issues = [
            makeIssue(id: "1", status: "To Merge", priority: "Medium"),
            makeIssue(id: "2", status: "In Review", priority: "High")
        ]

        store.synchronize(with: issues)

        #expect(Set(store.jiraStatusOrder) == ["To Merge", "In Review"])
        #expect(Set(store.jiraPriorityOrder) == ["Medium", "High"])
    }

    @Test func customCIOrderChangesTheResult() {
        let store = makeStore()
        for criterion in store.criteria {
            var updated = criterion
            updated.isEnabled = criterion.kind == .githubCI
            store.updateCriterion(updated)
        }
        let failure = makeFacts(id: "failure", ciStatus: .failure)
        let success = makeFacts(id: "success", ciStatus: .success)

        #expect(store.areInIncreasingOrder(failure, success))

        guard let successIndex = store.githubCIOrder.firstIndex(of: .success) else {
            Issue.record("L'état success doit être configurable")
            return
        }
        for index in stride(from: successIndex, to: 0, by: -1) {
            store.moveCIStatus(at: index, by: -1)
        }

        #expect(store.areInIncreasingOrder(success, failure))
    }

    @Test func mergedItemsAlwaysComeLast() {
        let store = makeStore()
        let active = makeFacts(id: "active", ciStatus: .running)
        let merged = makeFacts(id: "merged", ciStatus: .success, isMerged: true)

        #expect(store.areInIncreasingOrder(active, merged))
        #expect(!store.areInIncreasingOrder(merged, active))
    }

    @Test func recommendedPresetMatchesTheWorkflowOrder() {
        let store = makeStore()
        store.applyRecommendedPreset()

        #expect(store.criteria.map(\.kind) == [
            .reviewThreads,
            .smartPriority,
            .githubCI,
            .hasPullRequest,
            .jiraStatus,
            .pullRequestState,
            .jiraPriority,
            .updated,
            .key
        ])
        #expect(store.criteria.filter(\.isEnabled).map(\.kind) == [
            .reviewThreads,
            .smartPriority,
            .githubCI,
            .hasPullRequest,
            .jiraStatus,
            .pullRequestState,
            .updated,
            .key
        ])
        #expect(store.criteria.first(where: { $0.kind == .reviewThreads })?.direction == .descending)
        #expect(store.criteria.first(where: { $0.kind == .hasPullRequest })?.direction == .descending)
        #expect(store.criteria.first(where: { $0.kind == .updated })?.direction == .descending)
    }

    private func makeStore() -> TrackingSortStore {
        let suiteName = "TrackingSortTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return TrackingSortStore(defaults: defaults)
    }

    private func makeIssue(id: String, status: String, priority: String) -> JiraIssue {
        JiraIssue(
            id: id,
            key: "TEST-\(id)",
            selfURL: nil,
            fields: JiraIssueFields(
                summary: "Issue",
                status: JiraStatus(name: status, statusCategory: nil),
                priority: JiraNamedValue(name: priority),
                issueType: nil,
                updated: nil
            )
        )
    }

    private func makeFacts(
        id: String,
        ciStatus: CIStatus,
        isMerged: Bool = false
    ) -> TrackingSortFacts {
        TrackingSortFacts(
            id: id,
            isMerged: isMerged,
            smartRank: 0,
            jiraStatus: nil,
            jiraPriority: nil,
            ciStatuses: [ciStatus],
            pullRequestStates: [.open],
            unresolvedReviewThreads: 0,
            hasPullRequest: true,
            updatedAt: nil
        )
    }
}
#endif
