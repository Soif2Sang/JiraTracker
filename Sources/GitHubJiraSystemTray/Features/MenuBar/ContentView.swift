import AppKit
import SwiftUI

enum TrackerSection: Hashable {
    case overview
    case pullRequests
    case jira
    case sorting
    case categories
}

struct ContentView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var jiraStore: JiraStore
    @StateObject private var trackingSort = TrackingSortStore()
    @State private var selectedFilter = ProcessInfo.processInfo.environment["JIRA_TRACKER_DEMO"] == "1"
        ? DashboardFilter(statusName: "En cours")
        : DashboardFilter.all
    @State private var selectedSection: TrackerSection = .overview
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @AppStorage("jira.hiddenWorkflowStatuses") private var hiddenStatusesValue = ""

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Color.white.opacity(0.1)).frame(width: 1)
                detail
            }
            Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)
            footer
        }
        .frame(width: 780, height: 600)
        .background {
            ZStack {
                VisualEffectBackground().ignoresSafeArea()
                LinearGradient(
                    colors: [Color(red: 0.035, green: 0.085, blue: 0.14).opacity(0.98), Color(red: 0.025, green: 0.055, blue: 0.09).opacity(0.98)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .preferredColorScheme(.dark)
        .overlay {
            Button("") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .opacity(0)
                .frame(width: 0, height: 0)
        }
        .onAppear {
            DispatchQueue.main.async { searchFocused = false }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(Color(red: 0.68, green: 0.78, blue: 0.93))
            TextField("Rechercher un ticket, une PR, un commit…", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { selectedSection = .overview }
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.4))
            }
            HStack(spacing: 7) {
                Image(systemName: "command")
                Text("K")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.7))
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.horizontal, 15)
        .frame(height: 40)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.09)) }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var sidebar: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(visibleDashboardFilters) { filter in
                Button {
                    selectedFilter = filter
                    selectedSection = .overview
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: filter.icon)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(filter.tint)
                            .frame(width: 25)
                        Text(filter.title)
                            .font(.system(size: 13, weight: selectedFilter == filter && selectedSection == .overview ? .semibold : .regular))
                            .foregroundStyle(Color.white.opacity(0.82))
                        Spacer()
                        Text("\(count(for: filter))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.8))
                            .frame(minWidth: 28, minHeight: 28)
                            .background(Color.white.opacity(0.08), in: Circle())
                    }
                    .padding(.horizontal, 13)
                    .frame(height: 42)
                    .background {
                        if selectedFilter == filter && selectedSection == .overview {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(LinearGradient(colors: [Color(red: 0.06, green: 0.40, blue: 0.95), Color(red: 0.08, green: 0.27, blue: 0.71)], startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 11)
            .padding(.bottom, 6)
        }
        .frame(width: 215)
        .background(Color.black.opacity(0.05))
    }

    private var detail: some View {
        VStack(spacing: 0) {
            detailHeader
            if let message = currentErrorMessage {
                ErrorBanner(message: message)
            }
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var detailHeader: some View {
        HStack(spacing: 12) {
            if selectedSection != .overview {
                Button { selectedSection = .overview } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.white.opacity(0.7))
            } else {
                Image(systemName: selectedFilter.icon)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(selectedFilter.tint)
            }
            Text(sectionTitle)
                .font(.system(size: 17, weight: .semibold))
            Text("\(sectionCount)")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.78))
                .frame(minWidth: 31, minHeight: 31)
                .background(Color.white.opacity(0.07), in: Circle())
            Spacer()
            Menu {
                Button("Ordre du suivi…") { selectedSection = .sorting }
                Button("Catégories Jira…") { selectedSection = .categories }
                Button("Tester les notifications") { store.testNotifications() }
                Button("Réglages des notifications…") { openNotificationSettings() }
                Divider()
                Button("Déconnecter GitHub") { store.disconnect() }
                Button("Déconnecter Jira") { jiraStore.disconnect() }
                Divider()
                Button("Quitter") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
    }

    @ViewBuilder private var content: some View {
        switch selectedSection {
        case .overview:
            UnifiedView(store: store, jiraStore: jiraStore, sortStore: trackingSort, filter: selectedFilter, searchText: searchText) {
                selectedSection = .jira
            } onConfigureGitHub: {
                selectedSection = .pullRequests
            }
        case .pullRequests:
            if store.connectionState == .needsAuthentication {
                AuthenticationView(store: store)
            } else {
                pullRequestList
            }
        case .jira:
            JiraView(store: jiraStore, githubStore: store)
        case .sorting:
            TrackingSortSettingsView(sortStore: trackingSort, issues: jiraStore.issues, availableStatuses: jiraStore.availableStatusNames, availablePriorities: jiraStore.availablePriorityNames)
        case .categories:
            WorkflowCategorySettingsView(
                statusNames: allJiraStatusNames,
                isHidden: isStatusHidden,
                setHidden: setStatusHidden
            )
        }
    }

    @ViewBuilder private var pullRequestList: some View {
        if store.connectionState == .loading && store.pullRequests.isEmpty {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(store.pullRequests) { PullRequestCard(pullRequest: $0, store: store) }
                }
                .padding(12)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { refreshCurrentSection() } label: {
                if isCurrentSectionLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 16))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color(red: 0.68, green: 0.78, blue: 0.93))
            .disabled(isCurrentSectionLoading)
            Text(lastUpdatedLabel)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.65))
            Spacer()
            Rectangle().fill(Color.white.opacity(0.11)).frame(width: 1, height: 22)
            brandFooterButton("Jira", asset: .jira) { selectedSection = .jira }
            brandFooterButton("GitHub", asset: .github) { selectedSection = .pullRequests }
            footerButton("CI/CD", icon: "point.3.connected.trianglepath.dotted") { selectedSection = .pullRequests }
            Rectangle().fill(Color.white.opacity(0.11)).frame(width: 1, height: 22)
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                HStack(spacing: 7) {
                    Text("Quitter")
                    Image(systemName: "power")
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(Color.white.opacity(0.72))
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.72))
    }

    private func brandFooterButton(_ title: String, asset: BrandAsset, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                BrandIcon(asset: asset, size: 15, color: Color.white.opacity(0.78))
                Text(title)
            }
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundStyle(Color.white.opacity(0.72))
    }

    private func count(for filter: DashboardFilter) -> Int {
        if filter == .all { return jiraStore.issues.count + unlinkedPullRequestCount }
        return jiraStore.issues.filter { filter.matches(status: $0.fields.status?.name) }.count
    }

    private var unlinkedPullRequestCount: Int {
        let keys = Set(jiraStore.issues.map { $0.key.uppercased() })
        return store.pullRequests.filter { pr in
            let linked = TicketPRLinker.keys(for: pr).map { $0.uppercased() }
            return linked.isEmpty || linked.allSatisfy { !keys.contains($0) }
        }.count
    }

    private var sectionTitle: String {
        switch selectedSection {
        case .overview: return selectedFilter.title
        case .pullRequests: return "Pull requests"
        case .jira: return "Tickets Jira"
        case .sorting: return "Ordre du suivi"
        case .categories: return "Catégories Jira"
        }
    }

    private var sectionCount: Int {
        switch selectedSection {
        case .overview: return count(for: selectedFilter)
        case .pullRequests: return store.pullRequests.count
        case .jira: return jiraStore.issues.count
        case .sorting: return trackingSort.criteria.count
        case .categories: return allJiraStatusNames.count - hiddenStatuses.count
        }
    }

    private var currentErrorMessage: String? {
        if selectedSection == .jira { return jiraStore.errorMessage }
        return store.notificationErrorMessage ?? store.errorMessage
    }

    private var isCurrentSectionLoading: Bool {
        switch selectedSection {
        case .pullRequests: return store.isRefreshing || store.connectionState == .loading
        case .jira: return jiraStore.isRefreshing || jiraStore.connectionState == .loading
        case .overview, .sorting, .categories: return store.isRefreshing || jiraStore.isRefreshing || store.connectionState == .loading || jiraStore.connectionState == .loading
        }
    }

    private func refreshCurrentSection() {
        switch selectedSection {
        case .pullRequests: store.refreshNow()
        case .jira: jiraStore.refreshNow()
        case .overview, .sorting, .categories: store.refreshNow(); jiraStore.refreshNow()
        }
    }

    private var allJiraStatusNames: [String] {
        var result: [String] = []
        let names = jiraStore.availableStatusNames + jiraStore.issues.compactMap { $0.fields.status?.name }
        for name in names where !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            result.append(name)
        }
        return result
    }

    private var hiddenStatuses: Set<String> {
        Set(hiddenStatusesValue.split(separator: "|").map(String.init))
    }

    private var visibleDashboardFilters: [DashboardFilter] {
        [.all] + allJiraStatusNames
            .filter { !isStatusHidden($0) }
            .map { DashboardFilter(statusName: $0) }
    }

    private func isStatusHidden(_ status: String) -> Bool {
        hiddenStatuses.contains { $0.caseInsensitiveCompare(status) == .orderedSame }
    }

    private func setStatusHidden(_ status: String, _ hidden: Bool) {
        var statuses = hiddenStatuses
        if hidden {
            statuses.insert(status)
            if selectedFilter.statusName?.caseInsensitiveCompare(status) == .orderedSame {
                selectedFilter = .all
                selectedSection = .overview
            }
        } else {
            statuses = Set(statuses.filter { $0.caseInsensitiveCompare(status) != .orderedSame })
        }
        hiddenStatusesValue = statuses.sorted().joined(separator: "|")
    }

    private var lastUpdatedLabel: String {
        let dates = [store.lastUpdated, jiraStore.lastUpdated].compactMap { $0 }
        guard let date = dates.min() else { return "Pas encore synchronisé" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Dernière mise à jour : \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

extension View {
    func iconHitTarget(_ size: CGFloat = 28) -> some View {
        frame(width: size, height: size).contentShape(Rectangle())
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}

struct WorkflowCategorySettingsView: View {
    let statusNames: [String]
    let isHidden: (String) -> Bool
    let setHidden: (String, Bool) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Workflow Jira")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Choisissez les statuts affichés dans la barre latérale. La liste est synchronisée avec les workflows Jira au lancement.")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                }

                if statusNames.isEmpty {
                    HStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text("Chargement des statuts Jira…")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .frame(maxWidth: .infinity, minHeight: 140)
                } else {
                    VStack(spacing: 0) {
                        ForEach(statusNames, id: \.self) { status in
                            let category = DashboardFilter(statusName: status)
                            Toggle(isOn: Binding(
                                get: { !isHidden(status) },
                                set: { setHidden(status, !$0) }
                            )) {
                                HStack(spacing: 11) {
                                    Image(systemName: category.icon)
                                        .font(.system(size: 17, weight: .medium))
                                        .foregroundStyle(category.tint)
                                        .frame(width: 24)
                                    Text(status)
                                        .font(.system(size: 13, weight: .medium))
                                }
                            }
                            .toggleStyle(.switch)
                            .padding(.horizontal, 14)
                            .frame(height: 48)

                            if status != statusNames.last {
                                Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    .overlay { RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.09)) }

                    Button("Tout afficher") {
                        for status in statusNames { setHidden(status, false) }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 12, weight: .medium))
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }
}

struct AuthenticationView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer()
            Image(systemName: "key.horizontal").font(.system(size: 34)).foregroundStyle(.blue).frame(maxWidth: .infinity)
            Text("Connecter GitHub").font(.title3.weight(.semibold)).frame(maxWidth: .infinity)
            Text("Ajoutez un fine-grained Personal Access Token avec les permissions Metadata, Pull requests et Actions en lecture.")
                .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            SecureField("github_pat_…", text: $store.tokenInput).textFieldStyle(.roundedBorder)
            HStack {
                Button("Importer") { store.importEnvironmentToken() }.buttonStyle(.borderless)
                Spacer()
                Button("Connecter") { store.saveToken() }.buttonStyle(.borderedProminent)
            }
            Spacer()
        }
        .padding(28)
    }
}

struct ErrorBanner: View {
    let message: String
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text(message).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
        .padding(.horizontal, 16)
    }
}
