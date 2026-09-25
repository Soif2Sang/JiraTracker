import Combine
import Foundation
import SwiftUI

enum ConnectionState: Equatable {
    case needsAuthentication
    case loading
    case connected
    case stale
    case error
}

struct StatusSummary: Equatable {
    var failed = 0
    var running = 0
    var passed = 0
    var unknown = 0
    var reviewsPending = 0
    var jiraWithoutPR = 0
    var reviewerPending = 0
    var hasError = false
    var needsAuthentication = false

    static let empty = StatusSummary()

    init(pullRequests: [TrackedPullRequest] = []) {
        for pullRequest in pullRequests {
            if pullRequest.unresolvedReviewThreadCount > 0 {
                reviewsPending += 1
            }
            switch pullRequest.ciStatus {
            case .failure: failed += 1
            case .running: running += 1
            case .success: passed += 1
            case .cancelled, .unknown: unknown += 1
            }
        }
    }
}

@MainActor
final class AppStore: ObservableObject {
    private struct RefreshResult {
        let pullRequests: [TrackedPullRequest]
        let warning: String?
    }

    @Published private(set) var pullRequests: [TrackedPullRequest] = []
    @Published private(set) var mergedPullRequests: [TrackedPullRequest] = []
    @Published private(set) var summary = StatusSummary.empty
    @Published private(set) var connectionState: ConnectionState = .needsAuthentication
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published private(set) var rateLimit: RateLimitSnapshot?
    @Published private(set) var notificationErrorMessage: String?
    @Published private(set) var expandedPullRequests: Set<String> = []
    @Published private(set) var loadingJobsFor: Set<String> = []
    @Published var tokenInput = ""

    var allPullRequests: [TrackedPullRequest] {
        pullRequests + mergedPullRequests
    }

    var githubUserLogin: String? { githubLogin }

    /// Resolution state of the review threads the given login participated in.
    func reviewThreadState(
        for reference: GitHubPullReference,
        login: String
    ) async -> GitHubReviewThreadState? {
        guard let client else { return nil }
        return try? await client.reviewThreadState(
            owner: reference.owner,
            repository: reference.repository,
            number: reference.number,
            login: login
        )
    }

    private let credentials: CredentialStore
    private let cache: LocalCache
    private let notifications: NotificationService
    private let polling: PollingSettingsStore
    private let integrations: IntegrationSettingsStore
    private var client: GitHubClient?
    private var pollingTask: Task<Void, Never>?
    @Published private(set) var isRefreshing = false
    private var githubLogin: String?
    private var cancellables: Set<AnyCancellable> = []

    init(
        credentials: CredentialStore = CredentialStore(),
        cache: LocalCache = LocalCache(),
        notifications: NotificationService = NotificationService(),
        polling: PollingSettingsStore,
        integrations: IntegrationSettingsStore
    ) {
        self.credentials = credentials
        self.cache = cache
        self.notifications = notifications
        self.polling = polling
        self.integrations = integrations

        if let snapshot = cache.load() {
            pullRequests = snapshot.pullRequests
            mergedPullRequests = snapshot.mergedPullRequests
            lastUpdated = snapshot.savedAt
            summary = StatusSummary(pullRequests: snapshot.pullRequests)
            connectionState = .stale
        }

        integrations.$githubOrganization
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.organizationDidChange()
            }
            .store(in: &cancellables)
    }

    private var organization: String {
        integrations.organization
    }

    private func organizationDidChange() {
        guard client != nil else { return }
        githubLogin = nil
        pullRequests = []
        mergedPullRequests = []
        summary = StatusSummary.empty
        cache.clearGitHub()
        refreshNow()
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        if let token = credentials.readGitHubToken() {
            configure(token: token)
            startPolling()
            requestNotificationPermission()
            return
        }

        if let token = credentials.tokenFromEnvironment() {
            tokenInput = token
            configure(token: token)
            startPolling()
            requestNotificationPermission()
            return
        }

        summary.needsAuthentication = true
        connectionState = .needsAuthentication
    }

    func loadDemoData() {
        let fixtures: [(
            status: CIStatus,
            unresolved: Int,
            title: String,
            branch: String,
            ticket: String,
            offset: TimeInterval,
            merged: Bool
        )] = [
            (.failure, 5, "Analytics onboarding", "fix/onboarding-analytics", "1250", -720, false),
            (.running, 0, "API error handling", "feature/error-handling", "1260", -3_600, false),
            (.success, 1, "Billing service refactor", "refactor/billing-service", "1242", -2_700, false),
            (.success, 2, "Workspace settings UI", "feature/workspace-settings", "1234", -120, false),
            (.success, 3, "Improve logging", "chore/logging", "1287", -7_200, true),
            (.success, 0, "Release 2.4 rollout", "release/2.4", "1290", -9_000, true)
        ]
        pullRequests = fixtures.enumerated().map { index, fixture in
            let run = GitHubWorkflowRun(
                id: Int64(index + 1),
                name: "CI",
                status: fixture.status == .running ? "in_progress" : "completed",
                conclusion: fixture.status == .failure ? "failure" : fixture.status == .success ? "success" : nil,
                htmlURL: URL(string: "https://github.com/acme/platform/actions")!,
                headSHA: "demo-sha-\(index)",
                runAttempt: 1,
                createdAt: Date().addingTimeInterval(fixture.offset - 60),
                updatedAt: Date().addingTimeInterval(fixture.offset),
                jobs: nil
            )
            return TrackedPullRequest(
                id: "acme/platform#\(index + 101)",
                repository: fixture.ticket == "1242" ? "acme/billing" : "acme/platform",
                number: index + 101,
                title: fixture.title,
                url: URL(string: "https://github.com/acme/platform/pull/\(index + 101)")!,
                branch: fixture.branch,
                headSHA: "demo-sha-\(index)",
                isDraft: false,
                body: "PROJ-\(fixture.ticket)",
                updatedAt: Date().addingTimeInterval(fixture.offset),
                isMerged: fixture.merged,
                workflowRuns: [run],
                unresolvedReviewThreadCount: fixture.unresolved
            )
        }
        mergedPullRequests = []
        summary = StatusSummary(pullRequests: pullRequests)
        lastUpdated = Date().addingTimeInterval(-120)
        connectionState = .connected
        errorMessage = nil
    }

    func saveToken() {
        let token = tokenInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            errorMessage = "Saisissez un token GitHub."
            return
        }

        errorMessage = nil
        connectionState = .loading
        Task { [weak self] in
            guard let self else { return }
            let validatingClient = GitHubClient(token: token)
            do {
                let user = try await validatingClient.currentUser()
                guard self.credentials.saveGitHubToken(token) else {
                    throw CredentialValidationError.keychainWrite
                }
                self.client = validatingClient
                self.githubLogin = user.login
                self.summary.needsAuthentication = false
                self.startPolling()
                self.requestNotificationPermission()
            } catch {
                self.client = nil
                self.connectionState = .needsAuthentication
                self.summary.needsAuthentication = true
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func importEnvironmentToken() {
        guard let token = credentials.tokenFromEnvironmentOrZshrc() else {
            errorMessage = "Aucun GITHUB_TOKEN ou GH_TOKEN n'est disponible dans l'environnement ou ~/.zshrc."
            return
        }
        tokenInput = token
        saveToken()
    }

    func disconnect() {
        pollingTask?.cancel()
        pollingTask = nil
        client = nil
        githubLogin = nil
        credentials.deleteGitHubToken()
        notifications.resetComparison()
        cache.clearGitHub()
        pullRequests = []
        mergedPullRequests = []
        summary = .empty
        summary.needsAuthentication = true
        lastUpdated = nil
        errorMessage = nil
        connectionState = .needsAuthentication
    }

    func requestNotificationPermission() {
        Task { [notifications] in
            let errorMessage = await notifications.requestAuthorization()
            await MainActor.run { [weak self] in
                self?.notificationErrorMessage = errorMessage
            }
        }
    }

    func testNotifications() {
        Task { [notifications] in
            let errorMessage = await notifications.requestAuthorization()
            await MainActor.run { [weak self] in
                self?.notificationErrorMessage = errorMessage
                if errorMessage == nil {
                    notifications.sendTestNotification()
                }
            }
        }
    }

    func refreshNow() {
        guard !isRefreshing else { return }
        Task { [weak self] in
            await self?.refresh(discover: true)
        }
    }

    func toggleExpanded(_ pullRequestID: String) {
        if expandedPullRequests.contains(pullRequestID) {
            expandedPullRequests.remove(pullRequestID)
        } else {
            expandedPullRequests.insert(pullRequestID)
            loadDetails(for: pullRequestID)
        }
    }

    /// Loads the CI detail (workflow runs then their jobs) on demand, when a row is expanded.
    func loadDetails(for pullRequestID: String) {
        guard let client,
              let pullRequest = pullRequests.first(where: { $0.id == pullRequestID }),
              !loadingJobsFor.contains(pullRequestID) else { return }

        let alreadyLoaded = !pullRequest.workflowRuns.isEmpty
            && pullRequest.workflowRuns.allSatisfy { $0.jobs != nil }
        guard !alreadyLoaded else { return }

        let owner = owner(from: pullRequest.repository)
        let repository = repositoryName(from: pullRequest.repository)
        guard !owner.isEmpty, !repository.isEmpty else { return }

        loadingJobsFor.insert(pullRequestID)
        Task { [weak self] in
            guard let self else { return }
            defer { self.loadingJobsFor.remove(pullRequestID) }
            do {
                var runs = try await client.workflowRuns(
                    owner: owner,
                    repository: repository,
                    headSHA: pullRequest.headSHA
                )
                for index in runs.indices {
                    runs[index].jobs = try await client.jobs(
                        owner: owner,
                        repository: repository,
                        runID: runs[index].id
                    )
                }
                guard let currentIndex = self.pullRequests.firstIndex(where: { $0.id == pullRequestID }) else { return }
                self.pullRequests[currentIndex].workflowRuns = runs
                self.recalculateSummary()
                self.cache.save(CacheSnapshot(
                    pullRequests: self.pullRequests,
                    mergedPullRequests: self.mergedPullRequests,
                    savedAt: self.lastUpdated ?? Date()
                ))
            } catch {
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func configure(token: String) {
        client = GitHubClient(token: token)
        summary.needsAuthentication = false
        summary.hasError = false
        connectionState = .loading
    }

    private func startPolling() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            await self?.pollingLoop()
        }
    }

    private func pollingLoop() async {
        var nextDiscovery = Date.distantPast

        while !Task.isCancelled {
            if polling.isEnabled {
                let shouldDiscover = Date() >= nextDiscovery || pullRequests.isEmpty
                await refresh(discover: shouldDiscover)
                if shouldDiscover {
                    nextDiscovery = Date().addingTimeInterval(polling.discoveryInterval)
                }
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(pollingInterval() * 1_000_000_000))
            } catch {
                break
            }
        }
    }

    private func pollingInterval() -> TimeInterval {
        guard polling.isEnabled else { return 5 }
        var interval = pullRequests.contains(where: { $0.ciStatus == .running }) ? polling.runningInterval : polling.idleInterval
        if let rateLimit, rateLimit.remaining < polling.lowRateLimitThreshold {
            interval = max(interval, polling.lowRateLimitInterval)
        }
        if let rateLimit, rateLimit.remaining == 0, let reset = rateLimit.reset {
            interval = max(interval, max(1, reset.timeIntervalSinceNow))
        }
        return interval
    }

    private func refresh(discover: Bool) async {
        guard let client else {
            connectionState = .needsAuthentication
            return
        }
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let previous = pullRequests
        connectionState = previous.isEmpty ? .loading : connectionState
        errorMessage = nil

        do {
            let refreshResult: RefreshResult
            if discover || githubLogin == nil {
                let user = try await client.currentUser()
                githubLogin = user.login
                let discovered = try await client.openPullRequests(author: user.login, organization: organization)
                refreshResult = await loadPullRequests(discovered, client: client)
                do {
                    let merged = try await client.recentlyMergedPullRequests(
                        author: user.login,
                        organization: organization,
                        since: Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
                    )
                    mergedPullRequests = makeMergedPullRequests(merged)
                } catch {
                    // Preserve the cached merged PRs when this secondary query fails.
                }
            } else {
                refreshResult = await refreshWorkflowRuns(for: previous, client: client)
            }

            pullRequests = refreshResult.pullRequests.sorted { $0.updatedAt > $1.updatedAt }
            recalculateSummary()
            lastUpdated = Date()
            connectionState = refreshResult.warning == nil ? .connected : .stale
            errorMessage = refreshResult.warning
            summary.hasError = refreshResult.warning != nil
            summary.needsAuthentication = false
            rateLimit = await client.lastRateLimit()
            cache.save(CacheSnapshot(
                pullRequests: pullRequests,
                mergedPullRequests: mergedPullRequests,
                savedAt: lastUpdated ?? Date()
            ))
            notifications.notifyChanges(from: previous, to: pullRequests)
        } catch {
            connectionState = pullRequests.isEmpty ? .error : .stale
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            summary.hasError = true
            rateLimit = await client.lastRateLimit()
        }
    }

    private func loadPullRequests(
        _ discovered: [GitHubDiscoveredPullRequest],
        client: GitHubClient
    ) async -> RefreshResult {
        let oldByID = Dictionary(uniqueKeysWithValues: pullRequests.map { ($0.id, $0) })

        // Search already returned title/url/body/head, so a single batched GraphQL call
        // is enough for review threads and CI checks — no per-PR REST call.
        let refs: [GitHubPullRequestRef] = discovered.compactMap { item in
            let components = item.repositoryFullName.split(separator: "/", maxSplits: 1).map(String.init)
            guard components.count == 2 else { return nil }
            return GitHubPullRequestRef(
                identity: item.identity,
                owner: components[0],
                repository: components[1],
                number: item.number,
                headSHA: item.headRefOid
            )
        }
        let summaries = (try? await client.pullRequestSummaries(refs)) ?? [:]

        var result: [TrackedPullRequest] = []
        var failedCount = 0

        for item in discovered {
            let previous = oldByID[item.identity]
            guard let summary = summaries[item.identity] else {
                failedCount += 1
                if let previous { result.append(previous) }
                continue
            }
            // Keep cached runs/jobs for the detail view only while the head commit is unchanged.
            let cachedRuns = previous?.headSHA == item.headRefOid ? (previous?.workflowRuns ?? []) : []
            result.append(TrackedPullRequest(
                id: item.identity,
                repository: item.repositoryFullName,
                number: item.number,
                title: item.title,
                url: item.url,
                branch: item.headRefName,
                headSHA: item.headRefOid,
                isDraft: item.isDraft,
                body: item.body,
                updatedAt: item.updatedAt,
                isMerged: false,
                workflowRuns: cachedRuns,
                unresolvedReviewThreadCount: summary.unresolvedReviewThreadCount,
                latestReviewCommentAt: summary.latestReviewCommentAt,
                checks: summary.checks
            ))
        }

        return RefreshResult(
            pullRequests: result,
            warning: failedCount == 0 ? nil : "\(failedCount) PR n'a pas pu être actualisée. Les dernières données disponibles sont conservées."
        )
    }

    private func makeMergedPullRequests(_ discovered: [GitHubDiscoveredPullRequest]) -> [TrackedPullRequest] {
        discovered.map { item in
            TrackedPullRequest(
                id: item.identity,
                repository: item.repositoryFullName,
                number: item.number,
                title: item.title,
                url: item.url,
                branch: item.headRefName,
                headSHA: item.headRefOid,
                isDraft: item.isDraft,
                body: item.body,
                updatedAt: item.mergedAt ?? item.updatedAt,
                isMerged: true,
                workflowRuns: []
            )
        }
    }

    private func refreshWorkflowRuns(
        for pullRequests: [TrackedPullRequest],
        client: GitHubClient
    ) async -> RefreshResult {
        let refs: [GitHubPullRequestRef] = pullRequests.compactMap { pullRequest in
            let components = pullRequest.repository.split(separator: "/", maxSplits: 1).map(String.init)
            guard components.count == 2 else { return nil }
            return GitHubPullRequestRef(
                identity: pullRequest.id,
                owner: components[0],
                repository: components[1],
                number: pullRequest.number,
                headSHA: pullRequest.headSHA
            )
        }

        let summaries: [String: GitHubPullRequestSummary]
        do {
            summaries = try await client.pullRequestSummaries(refs)
        } catch {
            return RefreshResult(
                pullRequests: pullRequests,
                warning: "Les statuts CI n'ont pas pu être actualisés. Les dernières données disponibles sont conservées."
            )
        }

        var result: [TrackedPullRequest] = []
        var failedCount = 0

        for pullRequest in pullRequests {
            guard let summary = summaries[pullRequest.id] else {
                failedCount += 1
                result.append(pullRequest)
                continue
            }
            var updated = pullRequest
            updated.unresolvedReviewThreadCount = summary.unresolvedReviewThreadCount
            updated.latestReviewCommentAt = summary.latestReviewCommentAt
            updated.checks = summary.checks
            result.append(updated)
        }

        return RefreshResult(
            pullRequests: result,
            warning: failedCount == 0 ? nil : "\(failedCount) PR n'a pas pu être actualisée. Les dernières données disponibles sont conservées."
        )
    }

    private func recalculateSummary() {
        summary = StatusSummary(pullRequests: pullRequests)
    }

    private func owner(from fullName: String) -> String {
        fullName.split(separator: "/", maxSplits: 1).first.map(String.init) ?? ""
    }

    private func repositoryName(from fullName: String) -> String {
        fullName.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? ""
    }
}

private enum CredentialValidationError: LocalizedError {
    case keychainWrite

    var errorDescription: String? {
        "Identifiants valides, mais impossible de les enregistrer dans le Keychain."
    }
}
