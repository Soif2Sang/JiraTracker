import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let store = AppStore()
    let jiraStore = JiraStore()
    let theme = ThemeStore()

    private init() {}
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case display
    case notifications
    case integrations
    case filters
    case categories
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .notifications: return "Notifications"
        case .integrations: return "Intégrations"
        case .filters: return "Filtres & Suivi"
        case .categories: return "Catégories"
        case .display: return "Affichage"
        case .about: return "À propos"
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .notifications: return "bell"
        case .integrations: return "link"
        case .filters: return "slider.horizontal.3"
        case .categories: return "square.grid.2x2"
        case .display: return "display"
        case .about: return "info.circle"
        }
    }

    var anchor: String {
        switch self {
        case .display: return "settings-appearance"
        default: return "settings-\(rawValue)"
        }
    }
}

struct SettingsView: View {
    let onClose: () -> Void
    @ObservedObject private var store: AppStore
    @ObservedObject private var jiraStore: JiraStore
    @ObservedObject private var theme: ThemeStore
    @ObservedObject private var trackingSort: TrackingSortStore
    @State private var selectedSection: SettingsSection = .general
    @AppStorage("jira.hiddenWorkflowStatuses") private var hiddenStatusesValue = ""
    @AppStorage("settings.animationsEnabled") private var animationsEnabled = true

    init(model: AppModel, trackingSort: TrackingSortStore, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        _store = ObservedObject(wrappedValue: model.store)
        _jiraStore = ObservedObject(wrappedValue: model.jiraStore)
        _theme = ObservedObject(wrappedValue: model.theme)
        _trackingSort = ObservedObject(wrappedValue: trackingSort)
    }

    var body: some View {
        ScrollViewReader { proxy in
            HStack(spacing: 0) {
                sidebar(proxy: proxy)
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1)
                settingsDocument
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }

    private func sidebar(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .iconHitTarget(36)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.primary.opacity(0.65))
                .help("Retour aux tickets")

                VStack(alignment: .leading, spacing: 2) {
                    Text("Général")
                        .font(.system(size: 14, weight: .bold))
                    Text("Paramètres de l'application")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 66)

            VStack(spacing: 4) {
                ForEach(SettingsSection.allCases.filter { $0 != .general }) { section in
                    Button {
                        selectedSection = section
                        withAnimation(animationsEnabled ? .easeInOut(duration: 0.22) : nil) {
                            proxy.scrollTo(section.anchor, anchor: .top)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: section.icon)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 24)
                            Text(section.title)
                                .font(.system(size: 13, weight: selectedSection == section ? .semibold : .regular))
                            Spacer()
                        }
                        .foregroundStyle(selectedSection == section ? Color.white : Color.primary.opacity(0.78))
                        .padding(.horizontal, 13)
                        .frame(height: 42)
                        .contentShape(Rectangle())
                        .background {
                            if selectedSection == section {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(theme.selection.selectionGradient)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 11)
            .padding(.top, 4)

            Spacer()
        }
        .frame(width: 215)
        .background(Color.primary.opacity(0.045))
    }

    private var settingsDocument: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                documentHeader(
                    title: "Général",
                    subtitle: "Paramètres généraux de l'application.",
                    icon: "gearshape"
                )
                .id(SettingsSection.general.anchor)

                appearanceCard
                    .id(SettingsSection.display.anchor)

                settingsCard(
                    title: "Comportement",
                    subtitle: "Préférez votre expérience de travail.",
                    icon: "gearshape.2"
                ) {
                    SettingsToggleRow(
                        title: "Animations",
                        subtitle: "Activer les animations et transitions.",
                        isOn: $animationsEnabled
                    )
                }

                sectionTitle("Notifications", subtitle: "Choisissez quand l'application doit vous avertir.", icon: "bell")
                    .id(SettingsSection.notifications.anchor)
                notificationsCard

                sectionTitle("Intégrations", subtitle: "Gérez les connexions GitHub et Jira Cloud.", icon: "link")
                    .id(SettingsSection.integrations.anchor)
                integrationsCards

                sectionTitle("Filtres & Suivi", subtitle: "Organisez les éléments affichés dans le suivi.", icon: "slider.horizontal.3")
                    .id(SettingsSection.filters.anchor)
                settingsCard(
                    title: "Filtres et ordre",
                    subtitle: "Configurez la priorité des éléments du tableau de bord.",
                    icon: "slider.horizontal.3"
                ) {
                    TrackingSortSettingsView(
                        sortStore: trackingSort,
                        issues: jiraStore.issues,
                        availableStatuses: jiraStore.availableStatusNames,
                        availablePriorities: jiraStore.availablePriorityNames,
                        embedded: true
                    )
                }

                sectionTitle("Catégories", subtitle: "Choisissez les catégories visibles dans le suivi.", icon: "square.grid.2x2")
                    .id(SettingsSection.categories.anchor)
                settingsCard(
                    title: "Catégories Jira",
                    subtitle: "Sélectionnez les statuts affichés dans la barre latérale.",
                    icon: "square.grid.2x2"
                ) {
                    WorkflowCategorySettingsView(
                        statusNames: allJiraStatusNames,
                        isHidden: isStatusHidden,
                        setHidden: setStatusHidden,
                        embedded: true
                    )
                }

                sectionTitle("À propos", subtitle: "Informations sur GitHub Jira Tracker.", icon: "info.circle")
                    .id(SettingsSection.about.anchor)
                aboutCard
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func documentHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 27, weight: .light))
                .foregroundStyle(Color(red: 0.70, green: 0.79, blue: 0.94))
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }

    private func sectionTitle(_ title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.selection.accent)
                .frame(width: 25)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private var appearanceCard: some View {
        settingsCard(
            title: "Apparence",
            subtitle: "Choisissez l'apparence de l'interface.",
            icon: "display"
        ) {
            HStack(spacing: 9) {
                ForEach(AppTheme.allCases) { option in
                    Button {
                        guard theme.selection != option else { return }
                        theme.selection = option
                    } label: {
                        HStack(spacing: 9) {
                            Image(systemName: themeIcon(option))
                                .font(.system(size: 17, weight: .regular))
                            Text(themeTitle(option))
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            ZStack {
                                Circle()
                                    .stroke(theme.selection == option ? theme.selection.accent : Color.primary.opacity(0.45), lineWidth: 2)
                                if theme.selection == option {
                                    Circle()
                                        .fill(theme.selection.accent)
                                        .padding(4)
                                }
                            }
                            .frame(width: 18, height: 18)
                        }
                        .foregroundStyle(Color.primary.opacity(0.86))
                        .padding(.horizontal, 13)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .contentShape(Rectangle())
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        .overlay {
                            RoundedRectangle(cornerRadius: 9)
                                .stroke(theme.selection == option ? theme.selection.accent : Color.primary.opacity(0.12), lineWidth: theme.selection == option ? 1.5 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var notificationsCard: some View {
        settingsCard(
            title: "Notifications",
            subtitle: "Recevez les changements importants de CI.",
            icon: "bell.badge"
        ) {
            HStack(spacing: 10) {
                Button("Tester les notifications") { store.testNotifications() }
                    .buttonStyle(.bordered)
                Button("Ouvrir les réglages macOS…") { openNotificationSettings() }
                    .buttonStyle(.bordered)
                Spacer()
            }
            if let errorMessage = store.notificationErrorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var integrationsCards: some View {
        VStack(spacing: 12) {
            settingsCard(
                title: "GitHub",
                subtitle: "Identifiants et connexion GitHub.",
                icon: "chevron.left.forwardslash.chevron.right"
            ) {
                VStack(spacing: 12) {
                    AuthenticationView(store: store, compact: true)
                    if store.connectionState != .needsAuthentication {
                        Divider()
                        HStack {
                            Text("Session GitHub active")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Déconnecter", role: .destructive) { store.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
            settingsCard(
                title: "Jira Cloud",
                subtitle: "Identifiants et connexion Atlassian.",
                icon: "link"
            ) {
                VStack(spacing: 12) {
                    JiraAuthenticationView(store: jiraStore, compact: true)
                    if jiraStore.connectionState != .needsAuthentication {
                        Divider()
                        HStack {
                            Text("Session Jira active")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Déconnecter", role: .destructive) { jiraStore.disconnect() }
                                .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
    }

    private var aboutCard: some View {
        settingsCard(
            title: "GitHub Jira Tracker",
            subtitle: "Application macOS native de barre de menus.",
            icon: "info.circle"
        ) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Suivez les pull requests GitHub, leur CI et les tickets Jira associés.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Version 0.1.0")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.5))
            }
        }
    }

    private func settingsCard<Content: View>(
        title: String,
        subtitle: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color(red: 0.70, green: 0.79, blue: 0.94))
                    .frame(width: 36, height: 36)
                    .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Divider()
            content()
        }
        .padding(14)
        .background(theme.selection.backgroundColors[0].opacity(0.48), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        }
    }

    private func themeTitle(_ option: AppTheme) -> String {
        switch option {
        case .white: return "Clair"
        case .black: return "Sombre"
        case .blue: return "Bleu"
        }
    }

    private func themeIcon(_ option: AppTheme) -> String {
        switch option {
        case .white: return "sun.max"
        case .black: return "moon"
        case .blue: return "drop"
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

    private func isStatusHidden(_ status: String) -> Bool {
        hiddenStatuses.contains { $0.caseInsensitiveCompare(status) == .orderedSame }
    }

    private func setStatusHidden(_ status: String, _ hidden: Bool) {
        var statuses = hiddenStatuses
        if hidden {
            statuses.insert(status)
        } else {
            statuses = Set(statuses.filter { $0.caseInsensitiveCompare(status) != .orderedSame })
        }
        hiddenStatusesValue = statuses.sorted().joined(separator: "|")
    }

    private func openNotificationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(.accentColor)
        }
        .frame(minHeight: 38)
    }
}
