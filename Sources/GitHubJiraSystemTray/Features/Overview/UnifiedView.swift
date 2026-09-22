import SwiftUI

private enum UnifiedWorkItem: Identifiable {
    case issue(JiraIssue)
    case pullRequest(TrackedPullRequest)

    var id: String {
        switch self {
        case let .issue(issue): return "jira-\(issue.id)"
        case let .pullRequest(pullRequest): return "github-\(pullRequest.id)"
        }
    }
}

struct UnifiedView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var jiraStore: JiraStore
    @ObservedObject var sortStore: TrackingSortStore
    let onConfigureJira: () -> Void
    let onConfigureGitHub: () -> Void

    private var linkedIssueKeys: Set<String> {
        Set(jiraStore.issues.map(\.key).map { $0.uppercased() })
    }

    private var workItems: [UnifiedWorkItem] {
        let issues = jiraStore.issues.map(UnifiedWorkItem.issue)
        let standalonePullRequests = store.pullRequests.filter { pullRequest in
            let keys = TicketPRLinker.keys(for: pullRequest).map { $0.uppercased() }
            return keys.isEmpty || keys.allSatisfy { !linkedIssueKeys.contains($0) }
        }.map(UnifiedWorkItem.pullRequest)
        return (issues + standalonePullRequests).sorted {
            sortStore.areInIncreasingOrder(sortFacts(for: $0), sortFacts(for: $1))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            sourceStatus

            if isInitialLoading {
                loadingState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(workItems) { item in
                            workItemView(item)
                        }

                        if workItems.isEmpty {
                            emptyState
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private var isInitialLoading: Bool {
        workItems.isEmpty
            && (store.isRefreshing || jiraStore.isRefreshing
                || store.connectionState == .loading
                || jiraStore.connectionState == .loading)
    }

    @ViewBuilder
    private var sourceStatus: some View {
        if store.connectionState == .needsAuthentication || jiraStore.connectionState == .needsAuthentication {
            VStack(spacing: 5) {
                if store.connectionState == .needsAuthentication {
                    SourceSetupRow(
                        icon: "chevron.left.forwardslash.chevron.right",
                        title: "GitHub non connecté",
                        actionTitle: "Configurer",
                        action: onConfigureGitHub
                    )
                }
                if jiraStore.connectionState == .needsAuthentication {
                    SourceSetupRow(
                        icon: "checklist",
                        title: "Jira non connecté",
                        actionTitle: "Configurer",
                        action: onConfigureJira
                    )
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func workItemView(_ item: UnifiedWorkItem) -> some View {
        switch item {
        case let .issue(issue):
            JiraIssueRow(issue: issue, store: jiraStore, githubStore: store)
        case let .pullRequest(pullRequest):
            PullRequestCard(
                pullRequest: pullRequest,
                store: store,
                contextLabel: "Sans ticket Jira"
            )
        }
    }

    private func sortRank(for item: UnifiedWorkItem) -> Int {
        switch item {
        case let .pullRequest(pullRequest):
            return needsAttention(pullRequest) ? 0 : 4
        case let .issue(issue):
            let pullRequests = TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
            if pullRequests.contains(where: needsAttention) { return 0 }
            if pullRequests.isEmpty { return 2 }
            if issue.fields.status?.statusCategory?.key != "done",
               pullRequests.contains(where: { isActiveOpenPullRequest($0) }) {
                return 1
            }
            return 4
        }
    }

    private func sortFacts(for item: UnifiedWorkItem) -> TrackingSortFacts {
        switch item {
        case let .pullRequest(pullRequest):
            return TrackingSortFacts(
                id: item.id,
                isMerged: pullRequest.isMerged,
                smartRank: sortRank(for: item),
                jiraStatus: nil,
                jiraPriority: nil,
                ciStatuses: [pullRequest.ciStatus],
                pullRequestStates: [pullRequestState(for: pullRequest)],
                unresolvedReviewThreads: pullRequest.unresolvedReviewThreadCount,
                hasPullRequest: true,
                updatedAt: pullRequest.updatedAt
            )
        case let .issue(issue):
            let pullRequests = TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
            return TrackingSortFacts(
                id: item.id,
                isMerged: !pullRequests.isEmpty && pullRequests.allSatisfy(\.isMerged),
                smartRank: sortRank(for: item),
                jiraStatus: issue.fields.status?.name,
                jiraPriority: issue.fields.priority?.name,
                ciStatuses: pullRequests.map(\.ciStatus),
                pullRequestStates: pullRequests.isEmpty
                    ? [.none]
                    : pullRequests.map(pullRequestState),
                unresolvedReviewThreads: pullRequests.reduce(0) { $0 + $1.unresolvedReviewThreadCount },
                hasPullRequest: !pullRequests.isEmpty,
                updatedAt: issue.fields.updated.flatMap(parseJiraDate)
            )
        }
    }

    private func pullRequestState(for pullRequest: TrackedPullRequest) -> TrackingPullRequestState {
        if pullRequest.isMerged { return .merged }
        return pullRequest.isDraft ? .draft : .open
    }

    private func parseJiraDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func needsAttention(_ pullRequest: TrackedPullRequest) -> Bool {
        !pullRequest.isMerged
            && (pullRequest.unresolvedReviewThreadCount > 0 || pullRequest.ciStatus == .failure)
    }

    private func isActiveOpenPullRequest(_ pullRequest: TrackedPullRequest) -> Bool {
        !pullRequest.isMerged
            && (pullRequest.ciStatus == .success || pullRequest.ciStatus == .running)
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
            Text("Rien à afficher")
                .font(.headline)
            Text("Les tickets et PR ouverts apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
            Text("Chargement de GitHub et Jira...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SourceSetupRow: View {
    let icon: String
    let title: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.caption)
            Spacer()
            Button(actionTitle, action: action)
                .font(.caption.weight(.medium))
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}
