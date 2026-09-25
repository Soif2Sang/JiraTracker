import SwiftUI

struct JiraView: View {
    @ObservedObject var store: JiraStore
    @ObservedObject var githubStore: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.connectionState == .needsAuthentication {
                JiraAuthenticationView(store: store)
            } else if let errorMessage = store.errorMessage, store.issues.isEmpty {
                ErrorBanner(message: errorMessage)
                emptyState
            } else if store.issues.isEmpty {
                emptyState
            } else {
                if let errorMessage = store.errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                ScrollView {
                    LazyVStack(spacing: 5) {
                        ForEach(store.issues) { issue in
                            JiraIssueRow(issue: issue, store: store, githubStore: githubStore)
                        }
                    }
                    .padding(8)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checklist")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text("Aucun ticket Jira")
                .font(.headline)
            Text("Les tickets assignés apparaîtront ici.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct JiraAuthenticationView: View {
    @ObservedObject var store: JiraStore
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !compact { Spacer() }
            BrandIcon(asset: .jira, size: 32, color: .blue)
                .frame(maxWidth: .infinity)
            Text("Connecter Jira")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
            Text("Jira Cloud utilise l'e-mail du compte Atlassian avec son API token. Les variables JIRA_EMAIL et JIRA_TOKEN sont importées depuis l'environnement ou ~/.zshrc.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("email Atlassian", text: $store.emailInput)
                .textFieldStyle(.roundedBorder)
            SecureField("API token Jira", text: $store.tokenInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Importer") {
                    store.importShellCredentials()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Connecter") {
                    store.saveCredentials()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage = store.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            if !compact { Spacer() }
        }
        .padding(compact ? 0 : 22)
    }
}

struct JiraIssueRow: View {
    let issue: JiraIssue
    @ObservedObject var store: JiraStore
    @ObservedObject var githubStore: AppStore
    private var linkedPullRequests: [TrackedPullRequest] {
        TicketPRLinker.pullRequests(for: issue.key, in: githubStore.allPullRequests)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Link(destination: store.webURL(for: issue)) {
                    Text(issue.key)
                        .font(.caption.weight(.bold))
                }
                statusMenu
                if let priority = issue.fields.priority?.name {
                    Text(priority)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            Text(issue.fields.summary ?? "Sans résumé")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            if !linkedPullRequests.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(linkedPullRequests) { pullRequest in
                        LinkedPullRequestRow(pullRequest: pullRequest, githubStore: githubStore)
                    }
                }
            } else {
                Label("Aucune PR liée", systemImage: "link.badge.plus")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var statusMenu: some View {
        if let transitions = store.transitionsByIssueKey[issue.key], !transitions.isEmpty {
            Menu {
                ForEach(transitions) { transition in
                    Button {
                        store.performTransition(issueKey: issue.key, transitionID: transition.id)
                    } label: {
                        Text(transition.to.map { "Passer à « \($0.name) »" } ?? transition.name)
                    }
                }
            } label: {
                statusChip
            }
            .menuStyle(.borderlessButton)
            .help("Changer le statut Jira")
        } else {
            Button {
                store.loadTransitions(for: issue.key)
            } label: {
                if store.loadingTransitionsFor.contains(issue.key) {
                    ProgressView()
                        .controlSize(.mini)
                } else {
                    statusChip
                }
            }
            .buttonStyle(.plain)
            .help("Charger les changements de statut Jira")
        }
    }

    private var statusChip: some View {
        Text(issue.fields.status?.name ?? "Statut inconnu")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.055), in: Capsule())
            .contentShape(Capsule())
    }
}

struct LinkedPullRequestRow: View {
    let pullRequest: TrackedPullRequest
    @ObservedObject var githubStore: AppStore
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                if pullRequest.isMerged {
                    statusContent
                } else {
                    Button {
                        toggleExpansion()
                    } label: {
                        statusContent
                            .padding(.vertical, 4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Voir le détail CI")
                }
                Spacer(minLength: 0)
                if pullRequest.unresolvedReviewThreadCount > 0 {
                    ReviewCommentBadge(count: pullRequest.unresolvedReviewThreadCount)
                }
                Link(destination: pullRequest.url) {
                    Image(systemName: "arrow.up.right.square")
                        .iconHitTarget()
                }
                .buttonStyle(.borderless)
                .help("Ouvrir la PR")
                if !pullRequest.isMerged {
                    Button {
                        toggleExpansion()
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .iconHitTarget()
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Réduire" : "Voir le détail CI")
                }
            }

            if isExpanded && !pullRequest.isMerged {
                Divider()
                WorkflowDetails(
                    pullRequest: pullRequest,
                    isLoading: githubStore.loadingJobsFor.contains(pullRequest.id)
                )
                .padding(.leading, 4)
            }
        }
        .padding(.leading, 6)
        .padding(.vertical, 2)
        .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 7))
    }

    private var displayStatus: String {
        pullRequest.isMerged ? "Mergée" : pullRequest.ciStatus.title
    }

    private var statusContent: some View {
        HStack(spacing: 6) {
            CIStatusIcon(status: pullRequest.ciStatus, isMerged: pullRequest.isMerged)
            HStack(spacing: 5) {
                Text("\(shortRepositoryName) #\(pullRequest.number)")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(displayStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if pullRequest.failedJobCount > 0 {
                    Text("\(pullRequest.failedJobCount) job\(pullRequest.failedJobCount == 1 ? "" : "s")")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.1), in: Capsule())
                }
            }
        }
    }

    private var shortRepositoryName: String {
        pullRequest.repository.split(separator: "/").last.map(String.init) ?? pullRequest.repository
    }

    private func toggleExpansion() {
        isExpanded.toggle()
        if isExpanded {
            githubStore.loadDetails(for: pullRequest.id)
        }
    }
}
