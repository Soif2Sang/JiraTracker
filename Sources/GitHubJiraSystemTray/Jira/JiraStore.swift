import Combine
import Foundation
import SwiftUI

@MainActor
final class JiraStore: ObservableObject {
    static let legacyDefaultJQL = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"
    /// Fetches both tickets assigned to me and tickets where I am the Code Reviewer (cf[11268]).
    static let defaultJQL = "(assignee = currentUser() OR cf[11268] = currentUser()) AND resolution = Unresolved ORDER BY updated DESC"

    @Published private(set) var issues: [JiraIssue] = []
    @Published private(set) var currentAccountId: String?
    @Published private(set) var connectionState: ConnectionState = .needsAuthentication
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var transitionsByIssueKey: [String: [JiraTransition]] = [:]
    @Published private(set) var loadingTransitionsFor: Set<String> = []
    @Published private(set) var transitioningIssueKeys: Set<String> = []
    @Published private(set) var availableStatusNames: [String] = []
    @Published private(set) var availablePriorityNames: [String] = []
    @Published var emailInput = ""
    @Published var tokenInput = ""
    @Published var jql: String {
        didSet { UserDefaults.standard.set(jql, forKey: "jira.jql") }
    }

    private let credentials: CredentialStore
    private let cache: LocalCache
    private let polling: PollingSettingsStore
    private let integrations: IntegrationSettingsStore
    private var client: JiraClient?
    private var pollingTask: Task<Void, Never>?
    @Published private(set) var isRefreshing = false
    private var refreshRequested = false
    private var cancellables: Set<AnyCancellable> = []

    init(
        credentials: CredentialStore = CredentialStore(),
        cache: LocalCache = LocalCache(),
        polling: PollingSettingsStore,
        integrations: IntegrationSettingsStore
    ) {
        self.credentials = credentials
        self.cache = cache
        self.polling = polling
        self.integrations = integrations
        let storedJQL = UserDefaults.standard.string(forKey: "jira.jql")
        if storedJQL == nil || storedJQL == Self.legacyDefaultJQL {
            jql = Self.defaultJQL
        } else {
            jql = storedJQL ?? Self.defaultJQL
        }
        if let snapshot = cache.loadJira() {
            issues = snapshot.issues
            lastUpdated = snapshot.savedAt
            connectionState = .stale
        }

        integrations.$jiraSiteURL
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.applyStoredCredentials(reset: true)
            }
            .store(in: &cancellables)
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        applyStoredCredentials(reset: false)
    }

    private func applyStoredCredentials(reset: Bool) {
        let token = credentials.readJiraToken() ?? credentials.jiraTokenFromEnvironmentOrZshrc()
        let email = credentials.readJiraEmail() ?? credentials.jiraEmailFromEnvironmentOrZshrc()
        tokenInput = token ?? ""
        emailInput = email ?? ""

        guard let token, let email, !token.isEmpty, !email.isEmpty, let baseURL = integrations.jiraBaseURL else {
            connectionState = .needsAuthentication
            return
        }

        if reset {
            issues = []
            currentAccountId = nil
            transitionsByIssueKey = [:]
            availableStatusNames = []
            lastUpdated = nil
            cache.clearJira()
        }

        configure(baseURL: baseURL, email: email, token: token)
        startPolling()
    }

    /// Web URL of an issue, based on the configured Atlassian site.
    func webURL(for issue: JiraIssue) -> URL {
        let baseURL = integrations.jiraBaseURL ?? URL(string: IntegrationSettingsStore.defaultJiraSite)!
        return baseURL.appendingPathComponent("browse").appendingPathComponent(issue.key)
    }

    /// Tickets where the current account is the Code Reviewer and the status is a review status.
    func reviewerIssues() -> [JiraIssue] {
        issues.filter { $0.isCodeReviewer(accountId: currentAccountId) && $0.isInReviewStatus }
    }

    /// Pull requests linked to a ticket through the Jira GitHub integration.
    func linkedPullRequests(for issue: JiraIssue) async -> [JiraLinkedPullRequest] {
        guard let client else { return [] }
        return (try? await client.linkedPullRequests(issueId: issue.id)) ?? []
    }

    func loadDemoData() {
        let fixtures = [
            ("1301", "Ticket sans PR liée", "Ready to dev", "new", -300.0),
            ("1250", "Analytics onboarding", "En cours", "indeterminate", -720.0),
            ("1260", "API error handling", "En cours", "indeterminate", -3_600.0),
            ("1242", "Billing service refactor", "To review", "indeterminate", -2_700.0),
            ("1234", "Workspace settings UI", "To merge", "indeterminate", -120.0),
            ("1287", "Improve logging", "To QA", "indeterminate", -7_200.0),
            ("1290", "Release 2.4 rollout", "To release", "indeterminate", -9_000.0),
            ("1291", "Feature flags rollout", "To review", "indeterminate", -1_800.0)
        ]
        let demoAccountId = "demo-reviewer"
        let reviewerTickets: Set<String> = ["1242", "1291"]
        issues = fixtures.map { number, summary, status, category, offset in
            JiraIssue(
                id: number,
                key: "PROJ-\(number)",
                selfURL: nil,
                fields: JiraIssueFields(
                    summary: summary,
                    status: JiraStatus(name: status, statusCategory: JiraStatusCategory(key: category)),
                    priority: JiraNamedValue(name: "Medium"),
                    issueType: JiraNamedValue(name: "Story"),
                    updated: ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset)),
                    codeReviewer: reviewerTickets.contains(number)
                        ? JiraUserRef(accountId: demoAccountId, displayName: "Vous")
                        : nil
                )
            )
        }
        currentAccountId = demoAccountId
        availableStatusNames = ["Ready to dev", "À faire", "Blocked", "En cours", "To review", "To merge", "To QA", "To release", "Terminés"]
        availablePriorityNames = ["Highest", "High", "Medium", "Low"]
        lastUpdated = Date().addingTimeInterval(-120)
        connectionState = .connected
        errorMessage = nil
    }

    func saveCredentials() {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !token.isEmpty else {
            errorMessage = "L'e-mail Atlassian et l'API token Jira sont requis."
            return
        }
        guard let baseURL = integrations.jiraBaseURL else {
            connectionState = .needsAuthentication
            errorMessage = "L'URL du site Atlassian est invalide. Corrigez-la dans les réglages."
            return
        }
        errorMessage = nil
        connectionState = .loading
        Task { [weak self] in
            guard let self else { return }
            let validatingClient = JiraClient(baseURL: baseURL, email: email, token: token)
            do {
                _ = try await validatingClient.currentUser()
                guard self.credentials.saveJiraCredentials(email: email, token: token) else {
                    throw JiraCredentialValidationError.keychainWrite
                }
                self.client = validatingClient
                self.startPolling()
            } catch {
                self.client = nil
                self.connectionState = .needsAuthentication
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func importShellCredentials() {
        if let email = credentials.jiraEmailFromEnvironmentOrZshrc() {
            emailInput = email
        }
        if let token = credentials.jiraTokenFromEnvironmentOrZshrc() {
            tokenInput = token
        }
        if emailInput.isEmpty || tokenInput.isEmpty {
            errorMessage = "Variables attendues : JIRA_EMAIL et JIRA_TOKEN dans l'environnement ou ~/.zshrc."
        } else {
            errorMessage = nil
        }
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        client = nil
        issues = []
        currentAccountId = nil
        transitionsByIssueKey = [:]
        availableStatusNames = []
        availablePriorityNames = []
        lastUpdated = nil
        errorMessage = nil
        connectionState = .needsAuthentication
        credentials.deleteJiraCredentials()
        cache.clearJira()
    }

    func refreshNow() {
        Task { [weak self] in
            await self?.refresh()
        }
    }

    func loadTransitions(for issueKey: String) {
        guard let client, !loadingTransitionsFor.contains(issueKey) else { return }
        transitionsByIssueKey[issueKey] = nil
        loadingTransitionsFor.insert(issueKey)
        Task { [weak self] in
            guard let self else { return }
            do {
                transitionsByIssueKey[issueKey] = try await client.transitions(for: issueKey)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            loadingTransitionsFor.remove(issueKey)
        }
    }

    func performTransition(issueKey: String, transitionID: String) {
        guard let client, !transitioningIssueKeys.contains(issueKey) else { return }
        transitioningIssueKeys.insert(issueKey)
        Task { [weak self] in
            guard let self else { return }
            do {
                try await client.transition(issueKey: issueKey, transitionID: transitionID)
                transitionsByIssueKey[issueKey] = nil
                await reloadIssue(key: issueKey, client: client)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            transitioningIssueKeys.remove(issueKey)
        }
    }

    /// Reloads a single issue so a transition is reflected even while a poll refresh is running.
    private func reloadIssue(key: String, client: JiraClient) async {
        guard let updated = try? await client.issue(key: key) else {
            await refresh()
            return
        }
        if let index = issues.firstIndex(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            issues[index] = updated
            cache.saveJira(JiraCacheSnapshot(issues: issues, savedAt: lastUpdated ?? Date()))
        } else {
            await refresh()
        }
    }

    private func configure(baseURL: URL, email: String, token: String) {
        client = JiraClient(baseURL: baseURL, email: email, token: token)
        connectionState = .loading
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }

    private func pollingLoop() async {
        while !Task.isCancelled {
            if polling.isEnabled {
                await refresh()
            }
            let interval = polling.isEnabled ? polling.jiraInterval : 5
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    private func refresh() async {
        guard let client else { return }
        if isRefreshing {
            refreshRequested = true
            return
        }
        isRefreshing = true
        repeat {
            refreshRequested = false
            await performRefresh(using: client)
        } while refreshRequested && !Task.isCancelled
        isRefreshing = false
    }

    private func performRefresh(using client: JiraClient) async {
        do {
            if currentAccountId == nil {
                currentAccountId = try? await client.currentUser().accountId
            }
            issues = try await client.searchIssues(jql: jql)
                .sorted { ($0.fields.updatedDate ?? .distantPast) > ($1.fields.updatedDate ?? .distantPast) }
            let projectKeys = Set(issues.compactMap { issue in
                issue.key.split(separator: "-", maxSplits: 1).first.map(String.init)
            })
            var workflowStatusNames = await withTaskGroup(of: [JiraStatus].self) { group in
                for projectKey in projectKeys {
                    group.addTask {
                        (try? await client.statuses(forProject: projectKey)) ?? []
                    }
                }

                var statuses: [JiraStatus] = []
                for await projectStatuses in group {
                    statuses.append(contentsOf: projectStatuses)
                }
                return statuses.map(\.name)
            }
            if workflowStatusNames.isEmpty {
                workflowStatusNames = (try? await client.statuses().map(\.name)) ?? []
            }
            availableStatusNames = uniqueNames(workflowStatusNames)
            if availablePriorityNames.isEmpty {
                availablePriorityNames = (try? await client.priorities().map(\.name)) ?? []
            }
            transitionsByIssueKey = [:]
            lastUpdated = Date()
            connectionState = .connected
            errorMessage = nil
            cache.saveJira(JiraCacheSnapshot(issues: issues, savedAt: lastUpdated ?? Date()))
        } catch {
            connectionState = issues.isEmpty ? .error : .stale
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func uniqueNames(_ names: [String]) -> [String] {
        var result: [String] = []
        for name in names where !result.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            result.append(name)
        }
        return result
    }
}

private enum JiraCredentialValidationError: LocalizedError {
    case keychainWrite

    var errorDescription: String? {
        "Identifiants valides, mais impossible de les enregistrer dans le Keychain."
    }
}
