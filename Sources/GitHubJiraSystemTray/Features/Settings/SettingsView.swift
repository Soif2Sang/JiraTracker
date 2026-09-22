import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    let polling = PollingSettingsStore()
    let integrations = IntegrationSettingsStore()
    let store: AppStore
    let jiraStore: JiraStore
    let theme = ThemeStore()

    private init() {
        store = AppStore(polling: polling, integrations: integrations)
        jiraStore = JiraStore(polling: polling, integrations: integrations)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case display
    case notifications
    case polling
    case integrations
    case filters
    case categories
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .notifications: return "Notifications"
        case .polling: return "Polling & API"
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
        case .polling: return "arrow.triangle.2.circlepath"
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
    @ObservedObject private var polling: PollingSettingsStore
    @ObservedObject private var integrations: IntegrationSettingsStore
    @State private var selectedSection: SettingsSection = .general
    @AppStorage("jira.hiddenWorkflowStatuses") private var hiddenStatusesValue = ""
    @AppStorage("settings.animationsEnabled") private var animationsEnabled = true

    init(model: AppModel, trackingSort: TrackingSortStore, onClose: @escaping () -> Void = {}) {
        self.onClose = onClose
        _store = ObservedObject(wrappedValue: model.store)
        _jiraStore = ObservedObject(wrappedValue: model.jiraStore)
        _theme = ObservedObject(wrappedValue: model.theme)
        _trackingSort = ObservedObject(wrappedValue: trackingSort)
        _polling = ObservedObject(wrappedValue: model.polling)
        _integrations = ObservedObject(wrappedValue: model.integrations)
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
            LazyVStack(alignment: .leading, spacing: 16) {
                displayCard
                    .id(SettingsSection.display.anchor)

                notificationsCard
                    .id(SettingsSection.notifications.anchor)

                pollingCard
                    .id(SettingsSection.polling.anchor)

                integrationsCard
                    .id(SettingsSection.integrations.anchor)

                filtersCard
                    .id(SettingsSection.filters.anchor)

                categoriesCard
                    .id(SettingsSection.categories.anchor)

                aboutCard
                    .id(SettingsSection.about.anchor)
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var displayCard: some View {
        settingsCard(
            title: "Affichage",
            subtitle: "Apparence de l'interface et animations.",
            icon: "display"
        ) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    ForEach(AppTheme.allCases) { option in
                        themeButton(option)
                    }
                }
                Divider()
                SettingsToggleRow(
                    title: "Animations",
                    subtitle: "Activer les animations et transitions.",
                    isOn: $animationsEnabled
                )
            }
        }
    }

    private func themeButton(_ option: AppTheme) -> some View {
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

    private var notificationsCard: some View {
        settingsCard(
            title: "Notifications",
            subtitle: "Choisissez quand l'application doit vous avertir.",
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

    private var pollingCard: some View {
        settingsCard(
            title: "Polling & API",
            subtitle: "Fréquence d'actualisation et quota GitHub.",
            icon: "arrow.triangle.2.circlepath"
        ) {
            PollingSettingsView(polling: polling, store: store, jiraStore: jiraStore)
        }
    }

    private var integrationsCard: some View {
        settingsCard(
            title: "Intégrations",
            subtitle: "Gérez les connexions GitHub et Jira Cloud.",
            icon: "link"
        ) {
            VStack(alignment: .leading, spacing: 16) {
                integrationBlock(title: "Sources", icon: "globe") {
                    SourcesSettingsView(integrations: integrations)
                }
                Divider()
                integrationBlock(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right") {
                    if store.connectionState == .needsAuthentication {
                        AuthenticationView(store: store, compact: true)
                    } else {
                        connectionRow(
                            title: "Session GitHub active",
                            subtitle: store.connectionState == .stale ? "Données conservées hors ligne." : nil
                        ) {
                            store.disconnect()
                        }
                    }
                }
                Divider()
                integrationBlock(title: "Jira Cloud", icon: "link") {
                    if jiraStore.connectionState == .needsAuthentication {
                        JiraAuthenticationView(store: jiraStore, compact: true)
                    } else {
                        connectionRow(
                            title: "Session Jira active",
                            subtitle: jiraStore.connectionState == .stale ? "Données conservées hors ligne." : nil
                        ) {
                            jiraStore.disconnect()
                        }
                    }
                }
            }
        }
    }

    private func integrationBlock<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.primary.opacity(0.82))
            content()
        }
    }

    private var filtersCard: some View {
        settingsCard(
            title: "Filtres & Suivi",
            subtitle: "Organisez les éléments affichés dans le suivi.",
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
    }

    private var categoriesCard: some View {
        settingsCard(
            title: "Catégories",
            subtitle: "Choisissez les catégories visibles dans le suivi.",
            icon: "square.grid.2x2"
        ) {
            WorkflowCategorySettingsView(
                statusNames: allJiraStatusNames,
                isHidden: isStatusHidden,
                setHidden: setStatusHidden,
                embedded: true
            )
        }
    }

    private func connectionRow(
        title: String,
        subtitle: String?,
        disconnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Déconnecter", role: .destructive, action: disconnect)
                .buttonStyle(.bordered)
        }
    }

    private var aboutCard: some View {
        settingsCard(
            title: "À propos",
            subtitle: "Informations sur GitHub Jira Tracker.",
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

    private var allJiraStatusNames: [String] { JiraStatusCatalog.names(for: jiraStore) }

    private var statusVisibility: JiraStatusVisibility { JiraStatusVisibility(rawValue: hiddenStatusesValue) }

    private func isStatusHidden(_ status: String) -> Bool { statusVisibility.isHidden(status) }

    private func setStatusHidden(_ status: String, _ hidden: Bool) {
        var visibility = statusVisibility
        visibility.set(status, hidden: hidden)
        hiddenStatusesValue = visibility.rawValue
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
