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

    private struct PullRequestFetchResult {
        let pullRequest: TrackedPullRequest?
        let failed: Bool
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

    let organization = "dktunited"

    var allPullRequests: [TrackedPullRequest] {
        pullRequests + mergedPullRequests
    }

    private let credentials: CredentialStore
    private let cache: LocalCache
    private let notifications: NotificationService
    private var client: GitHubClient?
    private var pollingTask: Task<Void, Never>?
    @Published private(set) var isRefreshing = false
    private var githubLogin: String?

    init(
        credentials: CredentialStore = CredentialStore(),
        cache: LocalCache = LocalCache(),
        notifications: NotificationService = NotificationService()
    ) {
        self.credentials = credentials
        self.cache = cache
        self.notifications = notifications

        if let snapshot = cache.load() {
            pullRequests = snapshot.pullRequests
            mergedPullRequests = snapshot.mergedPullRequests
            lastUpdated = snapshot.savedAt
            summary = StatusSummary(pullRequests: snapshot.pullRequests)
            connectionState = .stale
        }
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
        let statuses: [(CIStatus, Int, String, String, Int, TimeInterval)] = [
            (.success, 2, "Workspace settings UI", "feature/workspace-settings", 2, -120),
            (.failure, 5, "Analytics onboarding", "fix/onboarding-analytics", 5, -720),
            (.success, 1, "Billing service refactor", "refactor/billing-service", 1, -2_700),
            (.running, 0, "API error handling", "feature/error-handling", 0, -3_600),
            (.success, 3, "Improve logging", "chore/logging", 3, -7_200)
        ]
        pullRequests = statuses.enumerated().map { index, fixture in
            let run = GitHubWorkflowRun(
                id: Int64(index + 1),
                name: "CI",
                status: fixture.0 == .running ? "in_progress" : "completed",
                conclusion: fixture.0 == .failure ? "failure" : fixture.0 == .success ? "success" : nil,
                htmlURL: URL(string: "https://github.com/acme/platform/actions")!,
                headSHA: "demo-sha-\(index)",
                runAttempt: 1,
                createdAt: Date().addingTimeInterval(fixture.5 - 60),
                updatedAt: Date().addingTimeInterval(fixture.5),
                jobs: nil
            )
            return TrackedPullRequest(
                id: "acme/platform#\(index + 101)",
                repository: index == 2 ? "acme/billing" : "acme/platform",
                number: index + 101,
                title: fixture.2,
                url: URL(string: "https://github.com/acme/platform/pull/\(index + 101)")!,
                branch: fixture.3,
                headSHA: "demo-sha-\(index)",
                isDraft: false,
                body: "PROJ-\([1234, 1250, 1242, 1260, 1287][index])",
                updatedAt: Date().addingTimeInterval(fixture.5),
                isMerged: index == 4,
                workflowRuns: [run],
                unresolvedReviewThreadCount: fixture.1
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
            loadJobs(for: pullRequestID)
        }
    }

    func loadJobs(for pullRequestID: String) {
        guard let client,
              let pullRequest = pullRequests.first(where: { $0.id == pullRequestID }),
              !loadingJobsFor.contains(pullRequestID) else { return }

        loadingJobsFor.insert(pullRequestID)
        Task { [weak self] in
            guard let self else { return }
            var runs = pullRequest.workflowRuns
            do {
                for index in runs.indices {
                    runs[index].jobs = try await client.jobs(
                        owner: self.owner(from: pullRequest.repository),
                        repository: self.repositoryName(from: pullRequest.repository),
                        runID: runs[index].id
                    )
                }
                guard let currentIndex = self.pullRequests.firstIndex(where: { $0.id == pullRequestID }) else {
                    self.loadingJobsFor.remove(pullRequestID)
                    return
                }
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
            self.loadingJobsFor.remove(pullRequestID)
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
            let shouldDiscover = Date() >= nextDiscovery || pullRequests.isEmpty
            await refresh(discover: shouldDiscover)
            if shouldDiscover {
                nextDiscovery = Date().addingTimeInterval(300)
            }

            var interval: UInt64 = pullRequests.contains(where: { $0.ciStatus == .running }) ? 30 : 120
            if let rateLimit, rateLimit.remaining < 100 {
                interval = max(interval, 300)
            }
            if let rateLimit, rateLimit.remaining == 0, let reset = rateLimit.reset {
                interval = max(interval, UInt64(max(1, reset.timeIntervalSinceNow)))
            }
            do {
                try await Task.sleep(nanoseconds: interval * 1_000_000_000)
            } catch {
                break
            }
        }
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
        _ discovered: [GitHubSearchPullRequest],
        client: GitHubClient
    ) async -> RefreshResult {
        let oldByID = Dictionary(uniqueKeysWithValues: pullRequests.map { ($0.id, $0) })
        let fetchResults = await withTaskGroup(of: PullRequestFetchResult.self) { group in
            for item in discovered {
                group.addTask {
                    guard let fullName = item.repositoryFullName else {
                        return PullRequestFetchResult(pullRequest: nil, failed: false)
                    }
                    let components = fullName.split(separator: "/", maxSplits: 1).map(String.init)
                    guard components.count == 2 else {
                        return PullRequestFetchResult(pullRequest: nil, failed: false)
                    }
                    do {
                        let details = try await client.pullRequest(
                            owner: components[0],
                            repository: components[1],
                            number: item.number
                        )
                        let runs = try await client.workflowRuns(
                            owner: components[0],
                            repository: components[1],
                            headSHA: details.head.sha
                        )
                        let previousRuns = oldByID[item.identity]?.workflowRuns ?? []
                        let reviewSummary = try? await client.reviewThreadSummary(
                            owner: components[0],
                            repository: components[1],
                            number: details.number
                        )
                        let runsWithCachedJobs = runs.map { run in
                            var run = run
                            run.jobs = previousRuns.first(where: { $0.id == run.id })?.jobs
                            return run
                        }
                        return PullRequestFetchResult(
                            pullRequest: TrackedPullRequest(
                                id: item.identity,
                                repository: fullName,
                                number: details.number,
                                title: details.title,
                                url: details.htmlURL,
                                branch: details.head.ref,
                                headSHA: details.head.sha,
                                isDraft: details.draft ?? false,
                                body: details.body,
                                updatedAt: details.updatedAt,
                                isMerged: false,
                                workflowRuns: runsWithCachedJobs,
                                unresolvedReviewThreadCount: reviewSummary?.unresolvedCount
                                    ?? oldByID[item.identity]?.unresolvedReviewThreadCount
                                    ?? 0,
                                latestReviewCommentAt: reviewSummary?.latestCommentAt
                                    ?? oldByID[item.identity]?.latestReviewCommentAt
                            ),
                            failed: false
                        )
                    } catch {
                        return PullRequestFetchResult(
                            pullRequest: oldByID[item.identity],
                            failed: true
                        )
                    }
                }
            }

            var results: [PullRequestFetchResult] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let result = fetchResults.compactMap(\.pullRequest)
        let failedCount = fetchResults.filter(\.failed).count

        return RefreshResult(
            pullRequests: result,
            warning: failedCount == 0 ? nil : "\(failedCount) PR n'a pas pu être actualisée. Les dernières données disponibles sont conservées."
        )
    }

    private func makeMergedPullRequests(_ discovered: [GitHubSearchPullRequest]) -> [TrackedPullRequest] {
        discovered.compactMap { item in
            guard let fullName = item.repositoryFullName else { return nil }
            return TrackedPullRequest(
                id: item.identity,
                repository: fullName,
                number: item.number,
                title: item.title,
                url: item.htmlURL,
                branch: "",
                headSHA: "",
                isDraft: false,
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
        var result: [TrackedPullRequest] = []
        var failedCount = 0

        for pullRequest in pullRequests {
            let components = pullRequest.repository.split(separator: "/", maxSplits: 1).map(String.init)
            guard components.count == 2 else { continue }
            do {
                var updated = pullRequest
                let runs = try await client.workflowRuns(
                    owner: components[0],
                    repository: components[1],
                    headSHA: pullRequest.headSHA
                )
                updated.workflowRuns = runs.map { run in
                    var run = run
                    run.jobs = pullRequest.workflowRuns.first(where: { $0.id == run.id })?.jobs
                    return run
                }
                if let reviewSummary = try? await client.reviewThreadSummary(
                    owner: components[0],
                    repository: components[1],
                    number: pullRequest.number
                ) {
                    updated.unresolvedReviewThreadCount = reviewSummary.unresolvedCount
                    updated.latestReviewCommentAt = reviewSummary.latestCommentAt
                }
                result.append(updated)
            } catch {
                failedCount += 1
                result.append(pullRequest)
            }
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
