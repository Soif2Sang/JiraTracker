import AppKit
import SwiftUI

struct DashboardFilter: Identifiable, Hashable {
    static let all = DashboardFilter(statusName: nil)
    static let reviewer = DashboardFilter(statusName: nil, isReviewer: true)

    let statusName: String?
    let isReviewer: Bool
    var id: String { isReviewer ? "__reviewer__" : (statusName ?? "__all__") }
    var title: String { isReviewer ? "Reviewer" : (statusName ?? "Tous") }

    init(statusName: String?) {
        self.statusName = statusName
        self.isReviewer = false
    }

    private init(statusName: String?, isReviewer: Bool) {
        self.statusName = statusName
        self.isReviewer = isReviewer
    }

    private var normalized: String {
        statusName?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) ?? ""
    }

    var icon: StatusIcon {
        if isReviewer { return .review }
        if statusName == nil { return .grid }
        if normalized.contains("ready") { return .code }
        if normalized.contains("block") { return .blocked }
        if normalized.contains("review") { return .review }
        if normalized.contains("merge") { return .merge }
        if normalized.contains("qa") || normalized.contains("test") { return .qa }
        if normalized.contains("release") || normalized.contains("deploy") { return .release }
        if normalized.contains("done") || normalized.contains("termine") || normalized.contains("closed") { return .done }
        if normalized.contains("cours") || normalized.contains("progress") { return .inProgress }
        return .todo
    }

    var tint: Color {
        if isReviewer { return Color(red: 0.52, green: 0.55, blue: 0.98) }
        if statusName == nil { return Color(red: 0.70, green: 0.79, blue: 0.94) }
        if normalized.contains("block") { return Color(red: 1, green: 0.28, blue: 0.33) }
        if normalized.contains("review") { return Color(red: 0.68, green: 0.32, blue: 0.96) }
        if normalized.contains("merge") { return Color(red: 1, green: 0.72, blue: 0) }
        if normalized.contains("qa") || normalized.contains("test") { return Color(red: 0.13, green: 0.88, blue: 0.72) }
        if normalized.contains("release") || normalized.contains("deploy") { return Color(red: 1, green: 0.48, blue: 0.55) }
        if normalized.contains("done") || normalized.contains("termine") || normalized.contains("closed") { return Color(red: 0.31, green: 0.76, blue: 0.42) }
        if normalized.contains("ready") || normalized.contains("cours") || normalized.contains("progress") { return Color(red: 0.10, green: 0.48, blue: 1) }
        return Color(red: 0.70, green: 0.79, blue: 0.94)
    }

    func matches(status: String?) -> Bool {
        guard !isReviewer else { return false }
        guard let statusName else { return true }
        return status?.caseInsensitiveCompare(statusName) == .orderedSame
    }

    /// Issue-level matching, needed for the reviewer filter that depends on the Code Reviewer field.
    func matches(issue: JiraIssue, accountId: String?) -> Bool {
        if isReviewer {
            return issue.isCodeReviewer(accountId: accountId) && issue.isInReviewStatus
        }
        return matches(status: issue.fields.status?.name)
    }
}

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
    let filter: DashboardFilter
    let searchText: String
    let onConfigureJira: () -> Void
    let onConfigureGitHub: () -> Void
    @EnvironmentObject private var theme: ThemeStore

    private var linkedIssueKeys: Set<String> {
        Set(jiraStore.issues.map(\.key).map { $0.uppercased() })
    }

    private var workItems: [UnifiedWorkItem] {
        let accountId = jiraStore.currentAccountId
        let issues = jiraStore.issues
            .filter { issue in filter.matches(issue: issue, accountId: accountId) }
            .map(UnifiedWorkItem.issue)
        let standalonePullRequests = filter == .all ? store.pullRequests.filter { pullRequest in
            let keys = TicketPRLinker.keys(for: pullRequest).map { $0.uppercased() }
            return keys.isEmpty || keys.allSatisfy { !linkedIssueKeys.contains($0) }
        }.map(UnifiedWorkItem.pullRequest) : []
        return (issues + standalonePullRequests)
            .filter(matchesSearch)
            .map { ($0, sortFacts(for: $0)) }
            .sorted { sortStore.areInIncreasingOrder($0.1, $1.1) }
            .map(\.0)
    }

    var body: some View {
        let items = workItems
        VStack(spacing: 0) {
            sourceStatus
            if isInitialLoading(items) {
                loadingState
            } else if items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            DashboardWorkItemRow(item: item, store: store, jiraStore: jiraStore)
                            if index < items.count - 1 {
                                Rectangle()
                                    .fill(Color.primary.opacity(0.09))
                                    .frame(height: 1)
                            }
                        }
                    }
                }
                .background(theme.selection.backgroundColors[0].opacity(0.52))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.primary.opacity(0.11), lineWidth: 1)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
    }

    private func matchesSearch(_ item: UnifiedWorkItem) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        let haystack: String
        switch item {
        case let .issue(issue):
            let pullRequests = TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
            haystack = ([issue.key, issue.fields.summary ?? ""] + pullRequests.flatMap { [$0.title, $0.repository, $0.branch] }).joined(separator: " ")
        case let .pullRequest(pullRequest):
            haystack = [pullRequest.title, pullRequest.repository, pullRequest.branch, "#\(pullRequest.number)"].joined(separator: " ")
        }
        return haystack.localizedCaseInsensitiveContains(query)
    }

    private func isInitialLoading(_ items: [UnifiedWorkItem]) -> Bool {
        items.isEmpty && (store.isRefreshing || jiraStore.isRefreshing || store.connectionState == .loading || jiraStore.connectionState == .loading)
    }

    @ViewBuilder private var sourceStatus: some View {
        if store.connectionState == .needsAuthentication || jiraStore.connectionState == .needsAuthentication {
            HStack(spacing: 8) {
                if store.connectionState == .needsAuthentication {
                    SourceSetupRow(icon: "chevron.left.forwardslash.chevron.right", title: "GitHub non connecté", actionTitle: "Configurer", action: onConfigureGitHub)
                }
                if jiraStore.connectionState == .needsAuthentication {
                    SourceSetupRow(icon: "checklist", title: "Jira non connecté", actionTitle: "Configurer", action: onConfigureJira)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: searchText.isEmpty ? "tray" : "magnifyingglass")
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color.primary.opacity(0.45))
            Text(searchText.isEmpty ? "Aucun élément dans cette étape" : "Aucun résultat")
                .font(.system(size: 14, weight: .semibold))
            Text(searchText.isEmpty ? "Les tickets apparaîtront ici quand leur statut changera." : "Essayez une autre recherche.")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.5))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Synchronisation de GitHub et Jira…")
                .font(.system(size: 12))
                .foregroundStyle(Color.primary.opacity(0.55))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sortRank(for item: UnifiedWorkItem) -> Int {
        let prs: [TrackedPullRequest]
        switch item {
        case let .pullRequest(pr): prs = [pr]
        case let .issue(issue): prs = TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
        }
        if prs.contains(where: { !$0.isMerged && ($0.unresolvedReviewThreadCount > 0 || $0.ciStatus == .failure) }) { return 0 }
        return prs.isEmpty ? 2 : 4
    }

    private func sortFacts(for item: UnifiedWorkItem) -> TrackingSortFacts {
        switch item {
        case let .pullRequest(pr):
            return TrackingSortFacts(id: item.id, isMerged: pr.isMerged, smartRank: sortRank(for: item), jiraStatus: nil, jiraPriority: nil, ciStatuses: [pr.ciStatus], pullRequestStates: [pr.isMerged ? .merged : pr.isDraft ? .draft : .open], unresolvedReviewThreads: pr.unresolvedReviewThreadCount, hasPullRequest: true, updatedAt: pr.updatedAt)
        case let .issue(issue):
            let prs = TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
            return TrackingSortFacts(id: item.id, isMerged: !prs.isEmpty && prs.allSatisfy(\.isMerged), smartRank: sortRank(for: item), jiraStatus: issue.fields.status?.name, jiraPriority: issue.fields.priority?.name, ciStatuses: prs.map(\.ciStatus), pullRequestStates: prs.isEmpty ? [.none] : prs.map { $0.isMerged ? .merged : $0.isDraft ? .draft : .open }, unresolvedReviewThreads: prs.reduce(0) { $0 + $1.unresolvedReviewThreadCount }, hasPullRequest: !prs.isEmpty, updatedAt: issue.fields.updatedDate)
        }
    }
}

private struct DashboardWorkItemRow: View {
    let item: UnifiedWorkItem
    @ObservedObject var store: AppStore
    @ObservedObject var jiraStore: JiraStore
    @EnvironmentObject private var theme: ThemeStore
    @State private var isExpanded = false

    private var issue: JiraIssue? { if case let .issue(issue) = item { return issue }; return nil }
    private var pullRequests: [TrackedPullRequest] {
        switch item {
        case let .issue(issue): return TicketPRLinker.pullRequests(for: issue.key, in: store.allPullRequests)
        case let .pullRequest(pr): return [pr]
        }
    }
    private var primaryPR: TrackedPullRequest? { pullRequests.first }
    private var title: String { issue?.fields.summary ?? primaryPR?.title ?? "Sans titre" }
    private var key: String { issue?.key ?? primaryPR.map { "PR #\($0.number)" } ?? "PR" }
    private var destination: URL { issue.map { jiraStore.webURL(for: $0) } ?? primaryPR!.url }
    private var comments: Int { pullRequests.reduce(0) { $0 + $1.unresolvedReviewThreadCount } }
    private var updatedAt: Date { primaryPR?.updatedAt ?? issue?.fields.updatedDate ?? Date() }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                SourceMark(hasJira: issue != nil, hasGitHub: primaryPR != nil)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Link(key, destination: destination)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 0.28, green: 0.68, blue: 1))
                            .buttonStyle(.plain)
                        jiraStatusChip
                        reviewerChip
                    }
                    Link(title, destination: destination)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary)
                        .lineLimit(1)
                        .buttonStyle(.plain)
                    HStack(spacing: 10) {
                        if let pr = primaryPR {
                            Link(destination: pr.url) {
                                HStack(spacing: 4) {
                                    BrandIcon(asset: .github, size: 10, color: Color.primary.opacity(0.58))
                                    Text(pr.repository)
                                }
                            }
                            .buttonStyle(.plain)
                            if pr.isMerged {
                                Link(destination: pr.url) {
                                    Label("Mergée", systemImage: "arrow.triangle.merge")
                                        .foregroundStyle(Color(red: 0.68, green: 0.42, blue: 0.96))
                                }
                                .buttonStyle(.plain)
                            } else if !pr.branch.isEmpty {
                                Link(destination: pr.url) {
                                    Label(pr.branch, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                                        .foregroundStyle(Color(red: 0.28, green: 0.68, blue: 1).opacity(0.9))
                                }
                                .buttonStyle(.plain)
                            }
                        } else {
                            Label("Aucune PR liée", systemImage: "link.badge.plus")
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                ciControl
                commentControl
                Text(activityLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.58))
                    .frame(width: 30, alignment: .trailing)
                detailsControl
            }
            .padding(.horizontal, 10)
            .frame(height: 70)

            if isExpanded, let pullRequest = primaryPR, !pullRequest.isMerged {
                Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
                WorkflowDetails(pullRequest: pullRequest)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder private var ciControl: some View {
        if let pullRequest = primaryPR {
            Link(destination: ciDestination(for: pullRequest)) {
                ciIndicator
            }
            .buttonStyle(.plain)
            .help(pullRequest.isMerged ? "Ouvrir la PR fusionnée" : "Ouvrir le job ou workflow CI")
        } else {
            ciIndicator
        }
    }

    @ViewBuilder private var detailsControl: some View {
        if let pullRequest = primaryPR, !pullRequest.isMerged {
            Button {
                isExpanded.toggle()
                if isExpanded { store.loadJobs(for: pullRequest.id) }
            } label: {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.82))
                    .frame(width: 18, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Masquer les détails CI" : "Afficher les détails CI")
        } else if let pullRequest = primaryPR {
            Link(destination: pullRequest.url) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.72))
                    .frame(width: 18, height: 30)
            }
            .buttonStyle(.plain)
            .help("Ouvrir la PR fusionnée")
        } else {
            Color.clear.frame(width: 18, height: 30)
        }
    }

    private func ciDestination(for pullRequest: TrackedPullRequest) -> URL {
        let jobs: [GitHubJob] = pullRequest.workflowRuns.flatMap { run in
            run.jobs ?? []
        }
        let failedJob = jobs.first { job in
            job.conclusion == "failure" || job.conclusion == "timed_out"
        }
        return failedJob?.htmlURL ?? pullRequest.primaryWorkflowURL ?? pullRequest.url
    }

    private var ciIndicator: some View {
        CIIndicator(
            status: primaryPR?.ciStatus ?? .unknown,
            isMerged: primaryPR?.isMerged == true,
            hasPullRequest: primaryPR != nil
        )
        .frame(width: 26, height: 30)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var commentControl: some View {
        if let pullRequest = primaryPR {
            Link(destination: pullRequest.url) {
                commentBadge
            }
            .buttonStyle(.plain)
            .help("Ouvrir la PR")
        } else {
            commentBadge
        }
    }

    private var commentBadge: some View {
        Label("\(comments)", systemImage: "ellipsis.message.fill")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.primary.opacity(0.72))
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(theme.selection == .white ? 0.12 : 0.07), in: Capsule())
    }

    @ViewBuilder private var jiraStatusChip: some View {
        if let status = issue?.fields.status?.name {
            let category = DashboardFilter(statusName: status)
            HStack(spacing: 4) {
                Circle()
                    .fill(category.tint)
                    .frame(width: 6, height: 6)
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    private var isReviewerTicket: Bool {
        guard let issue else { return false }
        return issue.isCodeReviewer(accountId: jiraStore.currentAccountId) && issue.isInReviewStatus
    }

    @ViewBuilder private var reviewerChip: some View {
        if isReviewerTicket {
            HStack(spacing: 4) {
                StatusIconView(icon: .review, size: 11, color: theme.selection.reviewerAccent)
                Text("Reviewer")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.selection.reviewerAccent)
            }
        }
    }

    private var activityLabel: String {
        let seconds = max(0, Int(Date().timeIntervalSince(updatedAt)))
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m" }
        if seconds < 86_400 { return "\(seconds / 3_600)h" }
        return "\(seconds / 86_400)j"
    }
}

private struct SourceMark: View {
    let hasJira: Bool
    let hasGitHub: Bool

    private let jiraGradient = [Color(red: 0.12, green: 0.48, blue: 1), Color(red: 0, green: 0.28, blue: 0.9)]
    private let githubGradient = [Color(white: 0.17), Color(white: 0.03)]

    var body: some View {
        ZStack {
            if hasJira && hasGitHub {
                splitMark
            } else if hasJira {
                singleMark(gradient: jiraGradient, asset: .jira)
            } else if hasGitHub {
                singleMark(gradient: githubGradient, asset: .github)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.white.opacity(hasJira && hasGitHub ? 0.22 : 0.12), lineWidth: 0.75)
        }
        .accessibilityHidden(true)
    }

    private var splitMark: some View {
        ZStack {
            LinearGradient(colors: jiraGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: githubGradient, startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(DiagonalSplit())
            BrandIcon(asset: .jira, size: 15, color: .white)
                .offset(x: -8, y: 8)
            BrandIcon(asset: .github, size: 15, color: .white)
                .offset(x: 8, y: -8)
        }
    }

    private func singleMark(gradient: [Color], asset: BrandAsset) -> some View {
        ZStack {
            LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing)
            BrandIcon(asset: asset, size: 22, color: .white)
        }
    }
}

private struct DiagonalSplit: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct CIIndicator: View {
    let status: CIStatus
    let isMerged: Bool
    let hasPullRequest: Bool
    private static let glyphSize: CGFloat = 19

    var body: some View {
        Group {
            if !hasPullRequest {
                Image(systemName: "link.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primary.opacity(0.3))
                    .frame(width: Self.glyphSize, height: Self.glyphSize)
            } else if isMerged {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.68, green: 0.42, blue: 0.96))
            } else {
                switch status {
                case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(red: 0.31, green: 0.81, blue: 0.43))
                case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(Color(red: 1, green: 0.29, blue: 0.32))
                case .running:
                    ZStack {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(Color(red: 1, green: 0.62, blue: 0.04))
                        BrandIcon(asset: .githubActionsRunning, size: 11, color: .white)
                    }
                case .cancelled: Image(systemName: "minus.circle.fill").foregroundStyle(.orange)
                case .unknown: Image(systemName: "circle.dashed").foregroundStyle(Color.primary.opacity(0.3))
                }
            }
        }
        .font(.system(size: Self.glyphSize))
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
            Text(title).font(.caption)
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.borderless)
        }
        .padding(8)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
    }
}
