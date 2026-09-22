import Foundation
import SwiftUI

@MainActor
final class JiraStore: ObservableObject {
    static let defaultJQL = "assignee = currentUser() AND resolution = Unresolved ORDER BY updated DESC"

    @Published private(set) var issues: [JiraIssue] = []
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

    let baseURL = URL(string: "https://decathlon.atlassian.net")!

    private let credentials: CredentialStore
    private let cache: LocalCache
    private var client: JiraClient?
    private var pollingTask: Task<Void, Never>?
    @Published private(set) var isRefreshing = false

    init(credentials: CredentialStore = CredentialStore(), cache: LocalCache = LocalCache()) {
        self.credentials = credentials
        self.cache = cache
        jql = UserDefaults.standard.string(forKey: "jira.jql") ?? Self.defaultJQL
        if let snapshot = cache.loadJira() {
            issues = snapshot.issues
            lastUpdated = snapshot.savedAt
            connectionState = .stale
        }
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        let token = credentials.readJiraToken() ?? credentials.jiraTokenFromEnvironmentOrZshrc()
        let email = credentials.readJiraEmail() ?? credentials.jiraEmailFromEnvironmentOrZshrc()
        tokenInput = token ?? ""
        emailInput = email ?? ""

        guard let token, let email, !token.isEmpty, !email.isEmpty else {
            connectionState = .needsAuthentication
            return
        }

        configure(email: email, token: token)
        startPolling()
    }

    func saveCredentials() {
        let email = emailInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !email.isEmpty, !token.isEmpty else {
            errorMessage = "L'e-mail Atlassian et l'API token Jira sont requis."
            return
        }
        errorMessage = nil
        connectionState = .loading
        Task { [weak self] in
            guard let self else { return }
            let validatingClient = JiraClient(email: email, token: token)
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
        guard !isRefreshing else { return }
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
                await refresh()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            transitioningIssueKeys.remove(issueKey)
        }
    }

    private func configure(email: String, token: String) {
        client = JiraClient(email: email, token: token)
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
            await refresh()
            do {
                try await Task.sleep(nanoseconds: 180 * 1_000_000_000)
            } catch {
                break
            }
        }
    }

    private func refresh() async {
        guard let client, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            issues = try await client.searchIssues(jql: jql)
                .sorted { ($0.fields.updated ?? "") > ($1.fields.updated ?? "") }
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
