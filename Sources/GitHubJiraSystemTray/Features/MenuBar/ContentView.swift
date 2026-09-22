import AppKit
import SwiftUI

enum TrackerSection: Hashable {
    case overview
    case pullRequests
    case jira
    case sorting
}

struct ContentView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var jiraStore: JiraStore
    @StateObject private var trackingSort = TrackingSortStore()
    @State private var selectedFilter: CIStatus?
    @State private var selectedSection: TrackerSection = .overview

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            content

            Divider()
            footer
        }
        .frame(width: 430, height: 570)
        .background {
            VisualEffectBackground()
                .ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            if selectedSection != .overview {
                Button {
                    selectedSection = .overview
                } label: {
                    Image(systemName: "chevron.left")
                        .iconHitTarget()
                }
                .buttonStyle(.borderless)
                .help("Retour au suivi")
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(sectionTitle)
                    .font(.headline)
                Text(sectionCountLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
            if selectedSection == .pullRequests {
                StatusSummaryView(summary: store.summary) { filter in
                    selectedFilter = selectedFilter == filter ? nil : filter
                }
            }
            Menu {
                Button("Suivi") { selectedSection = .overview }
                Button("Pull requests") { selectedSection = .pullRequests }
                Button("Tickets Jira") { selectedSection = .jira }
                Button("Ordre du suivi…") { selectedSection = .sorting }
                Divider()
                Button("Tester les notifications") {
                    store.testNotifications()
                }
                Button("Réglages des notifications…") {
                    openNotificationSettings()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .iconHitTarget()
            }
            .menuStyle(.borderlessButton)
            .help("Changer de vue")
            Button {
                refreshCurrentSection()
            } label: {
                if isCurrentSectionLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .iconHitTarget()
                }
            }
            .buttonStyle(.borderless)
            .help("Actualiser")
            .disabled(isCurrentSectionLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        if selectedSection == .overview {
            VStack(spacing: 0) {
                if let notificationErrorMessage = store.notificationErrorMessage {
                    ErrorBanner(message: notificationErrorMessage)
                }
                UnifiedView(store: store, jiraStore: jiraStore, sortStore: trackingSort) {
                    selectedSection = .jira
                } onConfigureGitHub: {
                    selectedSection = .pullRequests
                }
            }
        } else if selectedSection == .pullRequests {
            if store.connectionState == .needsAuthentication {
                AuthenticationView(store: store)
            } else {
                if let errorMessage = store.errorMessage {
                    ErrorBanner(message: errorMessage)
                }
                pullRequestList
            }
        } else if selectedSection == .jira {
            JiraView(store: jiraStore, githubStore: store)
        } else {
            TrackingSortSettingsView(
                sortStore: trackingSort,
                issues: jiraStore.issues,
                availableStatuses: jiraStore.availableStatusNames,
                availablePriorities: jiraStore.availablePriorityNames
            )
        }
    }

    @ViewBuilder
    private var pullRequestList: some View {
        let filtered = store.pullRequests.filter { pullRequest in
            selectedFilter == nil || pullRequest.ciStatus == selectedFilter
        }

        if store.connectionState == .loading && store.pullRequests.isEmpty {
            VStack(spacing: 12) {
                ProgressView()
                Text("Chargement des PR...")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if filtered.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: selectedFilter == nil ? "checkmark.circle" : "line.3.horizontal.decrease.circle")
                    .font(.system(size: 30))
                    .foregroundStyle(.green)
                Text(selectedFilter == nil ? "Aucune PR ouverte" : "Aucune PR dans ce filtre")
                    .font(.headline)
                Text(selectedFilter == nil ? "Les nouvelles PR apparaîtront automatiquement." : "Sélectionnez un autre état.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        } else {
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filtered) { pullRequest in
                        PullRequestCard(pullRequest: pullRequest, store: store)
                    }
                }
                .padding(8)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if selectedSection == .overview || selectedSection == .sorting {
                Text(overviewLastUpdatedLabel)
                    .foregroundStyle(.secondary)
            } else if selectedSection == .pullRequests, let lastUpdated = store.lastUpdated {
                Text("Mis à jour \(lastUpdated, style: .relative)")
                    .foregroundStyle(store.connectionState == .stale ? .orange : .secondary)
            } else if selectedSection == .jira, let lastUpdated = jiraStore.lastUpdated {
                Text("Jira mis à jour \(lastUpdated, style: .relative)")
                    .foregroundStyle(jiraStore.connectionState == .stale ? .orange : .secondary)
            } else {
                Text("Pas encore synchronisé")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if selectedSection == .overview || selectedSection == .sorting {
                Menu {
                    Button("Déconnecter GitHub") {
                        store.disconnect()
                    }
                    Button("Déconnecter Jira") {
                        jiraStore.disconnect()
                    }
                } label: {
                    Image(systemName: "person.crop.circle.badge.xmark")
                        .iconHitTarget()
                }
                .menuStyle(.borderlessButton)
                .help("Gérer les connexions")
            } else {
                Button(selectedSection == .jira ? "Déconnecter Jira" : "Déconnecter GitHub") {
                    if selectedSection == .pullRequests {
                        store.disconnect()
                    } else {
                        jiraStore.disconnect()
                    }
                }
                .buttonStyle(.borderless)
            }
            Button("Quitter") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sectionCountLabel: String {
        if selectedSection == .overview {
            return "\(store.pullRequests.count) PR • \(jiraStore.issues.count) ticket\(jiraStore.issues.count == 1 ? "" : "s")"
        }
        if selectedSection == .pullRequests {
            return "\(store.pullRequests.count) PR ouverte\(store.pullRequests.count == 1 ? "" : "s")"
        }
        if selectedSection == .sorting {
            return "Tri personnalisé"
        }
        return "\(jiraStore.issues.count) ticket\(jiraStore.issues.count == 1 ? "" : "s") Jira"
    }

    private var sectionTitle: String {
        switch selectedSection {
        case .overview: return "Suivi dev"
        case .pullRequests: return "Pull requests"
        case .jira: return "Tickets Jira"
        case .sorting: return "Ordre du suivi"
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }

    private var isCurrentSectionLoading: Bool {
        if selectedSection == .overview || selectedSection == .sorting {
            return store.isRefreshing
                || jiraStore.isRefreshing
                || store.connectionState == .loading
                || jiraStore.connectionState == .loading
        }
        return selectedSection == .pullRequests
            ? store.isRefreshing || store.connectionState == .loading
            : jiraStore.isRefreshing || jiraStore.connectionState == .loading
    }

    private func refreshCurrentSection() {
        if selectedSection == .pullRequests {
            store.refreshNow()
        } else if selectedSection == .jira {
            jiraStore.refreshNow()
        } else {
            store.refreshNow()
            jiraStore.refreshNow()
        }
    }

    private var overviewLastUpdatedLabel: String {
        let githubDate = store.lastUpdated
        let jiraDate = jiraStore.lastUpdated
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        switch (githubDate, jiraDate) {
        case let (githubDate?, jiraDate?):
            return "GitHub \(formatter.localizedString(for: githubDate, relativeTo: Date())) • Jira \(formatter.localizedString(for: jiraDate, relativeTo: Date()))"
        case let (githubDate?, nil):
            return "GitHub \(formatter.localizedString(for: githubDate, relativeTo: Date()))"
        case let (nil, jiraDate?):
            return "Jira \(formatter.localizedString(for: jiraDate, relativeTo: Date()))"
        case (nil, nil):
            return "Pas encore synchronisé"
        }
    }
}

extension View {
    func iconHitTarget(_ size: CGFloat = 28) -> some View {
        frame(width: size, height: size)
            .contentShape(Rectangle())
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .popover
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

struct AuthenticationView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: "key.horizontal")
                .font(.system(size: 34))
                .foregroundStyle(.blue)
                .frame(maxWidth: .infinity)
            Text("Connecter GitHub")
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity)
            Text("Ajoutez un fine-grained Personal Access Token autorisé par dktunited avec les permissions Metadata, Pull requests et Actions en lecture.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SecureField("github_pat_...", text: $store.tokenInput)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Importer depuis l'environnement ou ~/.zshrc") {
                    store.importEnvironmentToken()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Connecter") {
                    store.saveToken()
                }
                .buttonStyle(.borderedProminent)
            }

            if let errorMessage = store.errorMessage {
                ErrorBanner(message: errorMessage)
            }
            Spacer()
        }
        .padding(24)
    }
}

struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
        .padding(.top, 10)
    }
}
