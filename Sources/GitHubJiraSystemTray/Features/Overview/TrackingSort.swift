import Foundation
import SwiftUI

enum TrackingSortDirection: String, Codable, CaseIterable, Identifiable {
    case ascending
    case descending

    var id: String { rawValue }
    var title: String { self == .ascending ? "Croissant" : "Décroissant" }
}

enum TrackingSortCriterionKind: String, Codable, CaseIterable, Identifiable {
    case smartPriority
    case jiraStatus
    case jiraPriority
    case githubCI
    case pullRequestState
    case reviewThreads
    case hasPullRequest
    case updated
    case key

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartPriority: return "Urgence (CI / reviews)"
        case .jiraStatus: return "Statut Jira"
        case .jiraPriority: return "Priorité Jira"
        case .githubCI: return "État CI GitHub"
        case .pullRequestState: return "État de la PR"
        case .reviewThreads: return "Conversations non résolues"
        case .hasPullRequest: return "Présence d'une PR"
        case .updated: return "Dernière mise à jour"
        case .key: return "Clé Jira / PR"
        }
    }
}

struct TrackingSortCriterion: Codable, Equatable, Identifiable {
    let kind: TrackingSortCriterionKind
    var isEnabled: Bool
    var direction: TrackingSortDirection

    var id: String { kind.rawValue }
}

enum TrackingPullRequestState: String, Codable, CaseIterable {
    case open = "Ouverte"
    case draft = "Draft"
    case merged = "Fusionnée"
    case none = "Sans PR"
}

struct TrackingSortFacts: Equatable {
    let id: String
    let isMerged: Bool
    let smartRank: Int
    let jiraStatus: String?
    let jiraPriority: String?
    let ciStatuses: [CIStatus]
    let pullRequestStates: [TrackingPullRequestState]
    let unresolvedReviewThreads: Int
    let hasPullRequest: Bool
    let updatedAt: Date?
}

private struct TrackingSortConfiguration: Codable {
    var criteria: [TrackingSortCriterion]
    var jiraStatusOrder: [String]
    var jiraPriorityOrder: [String]
    var githubCIOrder: [CIStatus]
    var pullRequestStateOrder: [TrackingPullRequestState]
}

@MainActor
final class TrackingSortStore: ObservableObject {
    @Published private(set) var criteria: [TrackingSortCriterion]
    @Published private(set) var jiraStatusOrder: [String]
    @Published private(set) var jiraPriorityOrder: [String]
    @Published private(set) var githubCIOrder: [CIStatus]
    @Published private(set) var pullRequestStateOrder: [TrackingPullRequestState]

    private let defaults: UserDefaults
    private let storageKey = "tracking.sort.configuration"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let configuration = defaults.data(forKey: storageKey)
            .flatMap { try? JSONDecoder().decode(TrackingSortConfiguration.self, from: $0) }
            ?? Self.defaultConfiguration
        criteria = configuration.criteria
        jiraStatusOrder = configuration.jiraStatusOrder
        jiraPriorityOrder = configuration.jiraPriorityOrder
        githubCIOrder = configuration.githubCIOrder
        pullRequestStateOrder = configuration.pullRequestStateOrder
        addMissingCriteria()
    }

    func synchronize(
        with issues: [JiraIssue],
        availableStatuses: [String] = [],
        availablePriorities: [String] = []
    ) {
        let statuses = Set(issues.compactMap { $0.fields.status?.name } + availableStatuses)
        let priorities = Set(issues.compactMap { $0.fields.priority?.name } + availablePriorities)
        if !availableStatuses.isEmpty {
            jiraStatusOrder.removeAll { current in
                !statuses.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame })
            }
        }
        if !availablePriorities.isEmpty {
            jiraPriorityOrder.removeAll { current in
                !priorities.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame })
            }
        }
        appendMissing(statuses, to: &jiraStatusOrder)
        appendMissing(priorities, to: &jiraPriorityOrder)
        persist()
    }

    func updateCriterion(_ criterion: TrackingSortCriterion) {
        guard let index = criteria.firstIndex(where: { $0.kind == criterion.kind }) else { return }
        criteria[index] = criterion
        persist()
    }

    func moveCriterion(at index: Int, by offset: Int) {
        moveItem(in: &criteria, at: index, by: offset)
        persist()
    }

    func moveJiraStatus(at index: Int, by offset: Int) {
        moveItem(in: &jiraStatusOrder, at: index, by: offset)
        persist()
    }

    func moveJiraPriority(at index: Int, by offset: Int) {
        moveItem(in: &jiraPriorityOrder, at: index, by: offset)
        persist()
    }

    func moveCIStatus(at index: Int, by offset: Int) {
        moveItem(in: &githubCIOrder, at: index, by: offset)
        persist()
    }

    func movePullRequestState(at index: Int, by offset: Int) {
        moveItem(in: &pullRequestStateOrder, at: index, by: offset)
        persist()
    }

    func reset() {
        let configuration = Self.defaultConfiguration
        criteria = configuration.criteria
        jiraStatusOrder = configuration.jiraStatusOrder
        jiraPriorityOrder = configuration.jiraPriorityOrder
        githubCIOrder = configuration.githubCIOrder
        pullRequestStateOrder = configuration.pullRequestStateOrder
        persist()
    }

    func applyRecommendedPreset() {
        criteria = [
            TrackingSortCriterion(kind: .reviewThreads, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .smartPriority, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .githubCI, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .hasPullRequest, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .jiraStatus, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .pullRequestState, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .jiraPriority, isEnabled: false, direction: .ascending),
            TrackingSortCriterion(kind: .updated, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .key, isEnabled: true, direction: .ascending)
        ]
        persist()
    }

    func applyJiraWorkflowPreset() {
        applyPreset([
            (.jiraStatus, .ascending),
            (.githubCI, .ascending),
            (.pullRequestState, .ascending),
            (.jiraPriority, .ascending),
            (.updated, .descending),
            (.key, .ascending)
        ])
    }

    func applyCIFirstPreset() {
        applyPreset([
            (.githubCI, .ascending),
            (.reviewThreads, .descending),
            (.jiraStatus, .ascending),
            (.updated, .descending),
            (.key, .ascending)
        ])
    }

    func areInIncreasingOrder(_ left: TrackingSortFacts, _ right: TrackingSortFacts) -> Bool {
        let mergedComparison = (left.isMerged ? 1 : 0).compared(to: right.isMerged ? 1 : 0)
        if mergedComparison != 0 {
            return mergedComparison < 0
        }

        for criterion in criteria where criterion.isEnabled {
            let comparison = compare(left, right, using: criterion.kind)
            guard comparison != 0 else { continue }
            return criterion.direction == .ascending ? comparison < 0 : comparison > 0
        }
        return left.id.localizedStandardCompare(right.id) == .orderedAscending
    }

    private func compare(
        _ left: TrackingSortFacts,
        _ right: TrackingSortFacts,
        using kind: TrackingSortCriterionKind
    ) -> Int {
        switch kind {
        case .smartPriority:
            return left.smartRank.compared(to: right.smartRank)
        case .jiraStatus:
            return orderedIndex(left.jiraStatus, in: jiraStatusOrder)
                .compared(to: orderedIndex(right.jiraStatus, in: jiraStatusOrder))
        case .jiraPriority:
            return orderedIndex(left.jiraPriority, in: jiraPriorityOrder)
                .compared(to: orderedIndex(right.jiraPriority, in: jiraPriorityOrder))
        case .githubCI:
            return bestIndex(left.ciStatuses, in: githubCIOrder)
                .compared(to: bestIndex(right.ciStatuses, in: githubCIOrder))
        case .pullRequestState:
            return bestIndex(left.pullRequestStates, in: pullRequestStateOrder)
                .compared(to: bestIndex(right.pullRequestStates, in: pullRequestStateOrder))
        case .reviewThreads:
            return left.unresolvedReviewThreads.compared(to: right.unresolvedReviewThreads)
        case .hasPullRequest:
            return (left.hasPullRequest ? 0 : 1).compared(to: right.hasPullRequest ? 0 : 1)
        case .updated:
            return (left.updatedAt ?? .distantPast).compared(to: right.updatedAt ?? .distantPast)
        case .key:
            return comparisonValue(left.id.localizedStandardCompare(right.id))
        }
    }

    private func orderedIndex(_ value: String?, in order: [String]) -> Int {
        guard let value else { return Int.max }
        return order.firstIndex(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) ?? Int.max - 1
    }

    private func bestIndex<Value: Equatable>(_ values: [Value], in order: [Value]) -> Int {
        values.compactMap { order.firstIndex(of: $0) }.min() ?? Int.max
    }

    private func comparisonValue(_ result: ComparisonResult) -> Int {
        switch result {
        case .orderedAscending: return -1
        case .orderedDescending: return 1
        case .orderedSame: return 0
        }
    }

    private func addMissingCriteria() {
        for kind in TrackingSortCriterionKind.allCases where !criteria.contains(where: { $0.kind == kind }) {
            criteria.append(TrackingSortCriterion(kind: kind, isEnabled: false, direction: .ascending))
        }
    }

    private func appendMissing(_ values: Set<String>, to order: inout [String]) {
        let missing = values.filter { value in
            !order.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame })
        }
        order.append(contentsOf: missing.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    private func moveItem<Value>(in values: inout [Value], at index: Int, by offset: Int) {
        let destination = index + offset
        guard values.indices.contains(index), values.indices.contains(destination) else { return }
        values.swapAt(index, destination)
    }

    private func persist() {
        let configuration = TrackingSortConfiguration(
            criteria: criteria,
            jiraStatusOrder: jiraStatusOrder,
            jiraPriorityOrder: jiraPriorityOrder,
            githubCIOrder: githubCIOrder,
            pullRequestStateOrder: pullRequestStateOrder
        )
        if let data = try? JSONEncoder().encode(configuration) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func applyPreset(_ enabledCriteria: [(TrackingSortCriterionKind, TrackingSortDirection)]) {
        let enabledKinds = Set(enabledCriteria.map(\.0))
        let remainingKinds = TrackingSortCriterionKind.allCases.filter { !enabledKinds.contains($0) }
        criteria = enabledCriteria.map {
            TrackingSortCriterion(kind: $0.0, isEnabled: true, direction: $0.1)
        } + remainingKinds.map {
            TrackingSortCriterion(kind: $0, isEnabled: false, direction: Self.defaultDirection(for: $0))
        }
        persist()
    }

    private static let defaultConfiguration = TrackingSortConfiguration(
        criteria: [
            TrackingSortCriterion(kind: .reviewThreads, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .smartPriority, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .githubCI, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .hasPullRequest, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .jiraStatus, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .pullRequestState, isEnabled: true, direction: .ascending),
            TrackingSortCriterion(kind: .jiraPriority, isEnabled: false, direction: .ascending),
            TrackingSortCriterion(kind: .updated, isEnabled: true, direction: .descending),
            TrackingSortCriterion(kind: .key, isEnabled: true, direction: .ascending)
        ],
        jiraStatusOrder: [],
        jiraPriorityOrder: [],
        githubCIOrder: [.failure, .running, .cancelled, .unknown, .success],
        pullRequestStateOrder: [.open, .draft, .merged, .none]
    )

    private static func defaultDirection(for kind: TrackingSortCriterionKind) -> TrackingSortDirection {
        switch kind {
        case .reviewThreads, .updated: return .descending
        default: return .ascending
        }
    }
}

private extension Comparable {
    func compared(to other: Self) -> Int {
        self < other ? -1 : (self > other ? 1 : 0)
    }
}

struct TrackingSortSettingsView: View {
    @ObservedObject var sortStore: TrackingSortStore
    let issues: [JiraIssue]
    let availableStatuses: [String]
    let availablePriorities: [String]
    var embedded = false

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                ScrollView { content }
            }
        }
        .onAppear { synchronizeValues() }
        .onChange(of: issues) { _ in synchronizeValues() }
        .onChange(of: availableStatuses) { _ in synchronizeValues() }
        .onChange(of: availablePriorities) { _ in synchronizeValues() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
                Text("Le critère n° 1 est appliqué en premier. En cas d'égalité, l'application passe au suivant.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Partir d'un préréglage")
                        .font(.caption.weight(.semibold))
                    Spacer()
                    Menu("Choisir…") {
                        Button("Recommandé") { sortStore.applyRecommendedPreset() }
                        Button("Workflow Jira") { sortStore.applyJiraWorkflowPreset() }
                        Button("CI GitHub d'abord") { sortStore.applyCIFirstPreset() }
                    }
                    .font(.caption)
                }

                ForEach(Array(sortStore.criteria.enumerated()), id: \.element.id) { index, criterion in
                    criterionRow(criterion, at: index)
                }

                HStack {
                    Spacer()
                    Button("Réinitialiser") { sortStore.reset() }
                }
        }
        .padding(embedded ? 0 : 12)
    }

    private func synchronizeValues() {
        sortStore.synchronize(
            with: issues,
            availableStatuses: availableStatuses,
            availablePriorities: availablePriorities
        )
    }

    private func criterionRow(_ criterion: TrackingSortCriterion, at index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Text(activePosition(for: criterion).map(String.init) ?? "–")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(criterion.isEnabled ? .white : .secondary)
                    .frame(width: 21, height: 21)
                    .background(
                        criterion.isEnabled ? Color.accentColor : Color.primary.opacity(0.08),
                        in: Circle()
                    )
                Toggle(
                    isOn: Binding(
                        get: { criterion.isEnabled },
                        set: { enabled in
                            var updated = criterion
                            updated.isEnabled = enabled
                            sortStore.updateCriterion(updated)
                        }
                    )
                ) {
                    Text(criterion.kind.title)
                        .font(.caption.weight(.medium))
                }
                Spacer(minLength: 4)
                if !hasCustomValueOrder(criterion.kind) {
                    directionMenu(for: criterion)
                }
                moveButtons(index: index, count: sortStore.criteria.count) { offset in
                    sortStore.moveCriterion(at: index, by: offset)
                }
            }

            if criterion.isEnabled {
                customValueOrder(for: criterion.kind)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func customValueOrder(for kind: TrackingSortCriterionKind) -> some View {
        switch kind {
        case .jiraStatus:
            orderedValues(
                title: "Ordre des statuts Jira",
                values: sortStore.jiraStatusOrder,
                move: sortStore.moveJiraStatus
            )
        case .jiraPriority:
            orderedValues(
                title: "Ordre des priorités Jira",
                values: sortStore.jiraPriorityOrder,
                move: sortStore.moveJiraPriority
            )
        case .githubCI:
            orderedValues(
                title: "Ordre des états CI",
                values: sortStore.githubCIOrder.map(\.title),
                move: sortStore.moveCIStatus
            )
        case .pullRequestState:
            orderedValues(
                title: "Ordre des états de PR",
                values: sortStore.pullRequestStateOrder.map(\.rawValue),
                move: sortStore.movePullRequestState
            )
        default:
            EmptyView()
        }
    }

    private func orderedValues(
        title: String,
        values: [String],
        move: @escaping (Int, Int) -> Void
    ) -> some View {
        DisclosureGroup("\(title) · 1 = affiché en premier") {
            VStack(spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                    HStack(spacing: 6) {
                        Text("\(index + 1).")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 20, alignment: .trailing)
                        Text(value)
                            .font(.caption)
                        Spacer()
                        moveButtons(index: index, count: values.count) { offset in
                            move(index, offset)
                        }
                    }
                }
            }
            .padding(.top, 5)
        }
        .font(.caption2.weight(.medium))
        .padding(.leading, 28)
    }

    private func activePosition(for criterion: TrackingSortCriterion) -> Int? {
        guard criterion.isEnabled else { return nil }
        return sortStore.criteria.filter(\.isEnabled).firstIndex(where: { $0.kind == criterion.kind }).map { $0 + 1 }
    }

    private func hasCustomValueOrder(_ kind: TrackingSortCriterionKind) -> Bool {
        [.jiraStatus, .jiraPriority, .githubCI, .pullRequestState].contains(kind)
    }

    private func directionMenu(for criterion: TrackingSortCriterion) -> some View {
        let options = directionOptions(for: criterion.kind)
        return Menu(directionLabel(for: criterion)) {
            ForEach(options, id: \.direction) { option in
                Button(option.title) {
                    var updated = criterion
                    updated.direction = option.direction
                    sortStore.updateCriterion(updated)
                }
            }
        }
        .font(.caption2)
    }

    private func directionLabel(for criterion: TrackingSortCriterion) -> String {
        switch (criterion.kind, criterion.direction) {
        case (.smartPriority, .ascending): return "Urgents d'abord"
        case (.smartPriority, .descending): return "Normaux d'abord"
        case (.reviewThreads, .descending): return "Plus d'abord"
        case (.reviewThreads, .ascending): return "Aucune d'abord"
        case (.hasPullRequest, .ascending): return "Avec PR"
        case (.hasPullRequest, .descending): return "Sans PR"
        case (.updated, .descending): return "Récent d'abord"
        case (.updated, .ascending): return "Ancien d'abord"
        case (.key, .ascending): return "A → Z"
        case (.key, .descending): return "Z → A"
        default: return criterion.direction.title
        }
    }

    private func directionOptions(
        for kind: TrackingSortCriterionKind
    ) -> [(direction: TrackingSortDirection, title: String)] {
        switch kind {
        case .smartPriority:
            return [(.ascending, "Urgent d'abord"), (.descending, "Normal d'abord")]
        case .reviewThreads:
            return [(.descending, "Plus de conversations d'abord"), (.ascending, "Sans conversation d'abord")]
        case .hasPullRequest:
            return [(.ascending, "Avec PR d'abord"), (.descending, "Sans PR d'abord")]
        case .updated:
            return [(.descending, "Plus récent d'abord"), (.ascending, "Plus ancien d'abord")]
        case .key:
            return [(.ascending, "A → Z"), (.descending, "Z → A")]
        default:
            return TrackingSortDirection.allCases.map { ($0, $0.title) }
        }
    }

    private func moveButtons(
        index: Int,
        count: Int,
        move: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.up")
                    .iconHitTarget(32)
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)
            Button { move(1) } label: {
                Image(systemName: "chevron.down")
                    .iconHitTarget(32)
            }
            .buttonStyle(.borderless)
            .disabled(index == count - 1)
        }
    }
}
