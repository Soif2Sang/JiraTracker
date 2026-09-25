import Foundation

enum GitHubAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(statusCode: Int, message: String, retryAfter: Date?, endpoint: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "L'URL GitHub est invalide."
        case .invalidResponse:
            return "GitHub a renvoyé une réponse invalide."
        case let .http(statusCode, message, retryAfter, endpoint):
            let endpointDescription = " [\(endpoint)]"
            if statusCode == 401 {
                return "Le token GitHub est invalide ou expiré.\(endpointDescription)"
            }
            if statusCode == 403 {
                if let retryAfter {
                    return "GitHub a limité les requêtes. Nouvelle tentative après le \(retryAfter.formatted(date: .omitted, time: .shortened)).\(endpointDescription)"
                }
                return "GitHub refuse la requête. Vérifiez les permissions du token et le SSO de l'organisation.\(endpointDescription)"
            }
            if statusCode == 404 {
                return "La ressource GitHub est inaccessible avec ce token.\(endpointDescription)"
            }
            return "GitHub a renvoyé une erreur (\(statusCode)) : \(message)\(endpointDescription)"
        case let .decoding(error):
            return "Réponse GitHub non comprise : \(decodingMessage(error))"
        }
    }

    private func decodingMessage(_ error: Error) -> String {
        let path: (String) -> String = { codingPath in
            codingPath.isEmpty ? "racine" : codingPath
        }

        switch error {
        case let DecodingError.keyNotFound(key, context):
            let codingPath = (context.codingPath + [key]).map(\.stringValue).joined(separator: ".")
            return "champ manquant `\(path(codingPath))`"
        case let DecodingError.typeMismatch(type, context):
            let codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "type \(type) inattendu pour `\(path(codingPath))`"
        case let DecodingError.valueNotFound(type, context):
            let codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "valeur \(type) absente pour `\(path(codingPath))`"
        case let DecodingError.dataCorrupted(context):
            let codingPath = context.codingPath.map(\.stringValue).joined(separator: ".")
            return "donnée invalide pour `\(path(codingPath))`"
        default:
            return error.localizedDescription
        }
    }
}

struct RateLimitSnapshot: Equatable {
    let limit: Int
    let remaining: Int
    let reset: Date?
}

final class GitHubClient {
    private let baseURL = URL(string: "https://api.github.com")!
    private let token: String
    private let session: URLSession

    private let rateLimitStore = RateLimitStore()

    func lastRateLimit() async -> RateLimitSnapshot? {
        await rateLimitStore.value
    }

    init(token: String, session: URLSession = .shared) {
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    /// GraphQL `viewer` replaces `GET /user`.
    func currentUser() async throws -> GitHubUser {
        let payload: GitHubViewerPayload = try await graphQLRequest(
            query: "query { viewer { login } }",
            variables: [:]
        )
        return GitHubUser(login: payload.viewer.login)
    }

    func openPullRequests(author: String, organization: String) async throws -> [GitHubDiscoveredPullRequest] {
        try await searchPullRequests(query: "is:pr is:open author:\(author) org:\(organization)")
    }

    func recentlyMergedPullRequests(
        author: String,
        organization: String,
        since: Date
    ) async throws -> [GitHubDiscoveredPullRequest] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let date = formatter.string(from: since)
        return try await searchPullRequests(
            query: "is:pr is:merged author:\(author) org:\(organization) merged:>=\(date)"
        )
    }

    /// GraphQL search replaces `GET /search/issues`, returning PR metadata and head ref in one call.
    private func searchPullRequests(query: String) async throws -> [GitHubDiscoveredPullRequest] {
        var results: [GitHubDiscoveredPullRequest] = []
        var cursor: String?

        repeat {
            let payload: GitHubSearchPullRequestsPayload = try await graphQLRequest(
                query: """
                query($query: String!, $cursor: String) {
                  search(query: $query, type: ISSUE, first: 100, after: $cursor) {
                    nodes {
                      ... on PullRequest {
                        number
                        title
                        url
                        body
                        updatedAt
                        isDraft
                        mergedAt
                        repository { nameWithOwner }
                        headRefName
                        headRefOid
                      }
                    }
                    pageInfo { hasNextPage endCursor }
                  }
                }
                """,
                variables: ["query": query, "cursor": cursor.map { $0 as Any } ?? NSNull()]
            )

            for node in payload.search.nodes {
                guard let number = node.number,
                      let title = node.title,
                      let url = node.url,
                      let repository = node.repository,
                      let headRefName = node.headRefName,
                      let headRefOid = node.headRefOid else { continue }
                results.append(GitHubDiscoveredPullRequest(
                    number: number,
                    repositoryFullName: repository.nameWithOwner,
                    title: title,
                    url: url,
                    body: node.body,
                    updatedAt: node.updatedAt ?? Date(),
                    isDraft: node.isDraft ?? false,
                    headRefName: headRefName,
                    headRefOid: headRefOid,
                    mergedAt: node.mergedAt
                ))
            }

            cursor = payload.search.pageInfo.hasNextPage ? payload.search.pageInfo.endCursor : nil
        } while cursor != nil

        return results
    }

    func workflowRuns(owner: String, repository: String, headSHA: String) async throws -> [GitHubWorkflowRun] {
        let response: GitHubWorkflowRunsResponse = try await request(
            path: "/repos/\(owner)/\(repository)/actions/runs",
            queryItems: [
                URLQueryItem(name: "head_sha", value: headSHA),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        return response.workflowRuns
    }

    func jobs(owner: String, repository: String, runID: Int64) async throws -> [GitHubJob] {
        let response: GitHubJobsResponse = try await request(
            path: "/repos/\(owner)/\(repository)/actions/runs/\(runID)/jobs",
            queryItems: [
                URLQueryItem(name: "filter", value: "latest"),
                URLQueryItem(name: "per_page", value: "100")
            ]
        )
        return response.jobs
    }

    func reviewThreadSummary(owner: String, repository: String, number: Int) async throws -> GitHubReviewThreadSummary {
        var cursor: String?
        var unresolvedCount = 0
        var latestCommentAt: Date?

        repeat {
            let payload: GitHubReviewThreadsPayload = try await graphQLRequest(
                query: """
                query($owner: String!, $repository: String!, $number: Int!, $cursor: String) {
                  repository(owner: $owner, name: $repository) {
                    pullRequest(number: $number) {
                      reviewThreads(first: 100, after: $cursor) {
                        nodes {
                          isResolved
                          comments(last: 1) { nodes { createdAt } }
                        }
                        pageInfo { hasNextPage endCursor }
                      }
                    }
                  }
                }
                """,
                variables: [
                    "owner": owner,
                    "repository": repository,
                    "number": number,
                    "cursor": cursor.map { $0 as Any } ?? NSNull()
                ]
            )
            guard let threads = payload.repository?.pullRequest?.reviewThreads else {
                return GitHubReviewThreadSummary(
                    unresolvedCount: unresolvedCount,
                    latestCommentAt: latestCommentAt
                )
            }
            unresolvedCount += threads.nodes.filter { !$0.isResolved }.count
            let pageLatestCommentAt = threads.nodes
                .compactMap { $0.comments.nodes.first?.createdAt }
                .max()
            if let pageLatestCommentAt {
                if let currentLatestCommentAt = latestCommentAt {
                    latestCommentAt = max(pageLatestCommentAt, currentLatestCommentAt)
                } else {
                    latestCommentAt = pageLatestCommentAt
                }
            }
            cursor = threads.pageInfo.endCursor
            if !threads.pageInfo.hasNextPage { break }
        } while cursor != nil

        return GitHubReviewThreadSummary(
            unresolvedCount: unresolvedCount,
            latestCommentAt: latestCommentAt
        )
    }

    /// Fetches review-thread counts and CI checks for many pull requests in a single GraphQL call.
    ///
    /// Replaces the per-pull-request `reviewThreadSummary` + `workflowRuns` fan-out during polling,
    /// keeping the REST rate-limit budget untouched. Identities missing from the result could not be
    /// fetched (they should keep their previously known values).
    func pullRequestSummaries(_ refs: [GitHubPullRequestRef]) async throws -> [String: GitHubPullRequestSummary] {
        guard !refs.isEmpty else { return [:] }

        let maxPerRequest = 50
        guard refs.count > maxPerRequest else {
            return try await pullRequestSummariesChunk(refs)
        }

        var merged: [String: GitHubPullRequestSummary] = [:]
        for start in stride(from: 0, to: refs.count, by: maxPerRequest) {
            let chunk = Array(refs[start..<min(start + maxPerRequest, refs.count)])
            // A failing chunk only leaves its identities missing, so they keep their previous values.
            if let partial = try? await pullRequestSummariesChunk(chunk) {
                merged.merge(partial) { _, new in new }
            }
        }
        return merged
    }

    private func pullRequestSummariesChunk(_ refs: [GitHubPullRequestRef]) async throws -> [String: GitHubPullRequestSummary] {
        var variableDeclarations: [String] = []
        var variables: [String: Any] = [:]
        var fragments: [String] = []

        for (index, ref) in refs.enumerated() {
            variableDeclarations.append("$owner\(index): String!")
            variableDeclarations.append("$repo\(index): String!")
            variableDeclarations.append("$number\(index): Int!")
            variableDeclarations.append("$sha\(index): GitObjectID!")
            variables["owner\(index)"] = ref.owner
            variables["repo\(index)"] = ref.repository
            variables["number\(index)"] = ref.number
            variables["sha\(index)"] = ref.headSHA
            fragments.append("""
            pr\(index): repository(owner: $owner\(index), name: $repo\(index)) {
              pullRequest(number: $number\(index)) {
                reviewThreads(first: 50) {
                  nodes { isResolved comments(last: 1) { nodes { createdAt } } }
                  pageInfo { hasNextPage }
                }
              }
              object(oid: $sha\(index)) {
                ... on Commit {
                  statusCheckRollup {
                    state
                    contexts(first: 100) {
                      nodes {
                        __typename
                        ... on CheckRun {
                          name
                          status
                          conclusion
                          detailsUrl
                          isRequired(pullRequestNumber: $number\(index))
                          checkSuite { app { slug } }
                        }
                        ... on StatusContext {
                          context
                          state
                          targetUrl
                          isRequired(pullRequestNumber: $number\(index))
                        }
                      }
                    }
                  }
                }
              }
            }
            """)
        }

        let query = "query(\(variableDeclarations.joined(separator: ", "))) {\n\(fragments.joined(separator: "\n"))\n}"
        let payload: GitHubBatchedSummariesPayload = try await graphQLRequest(query: query, variables: variables)

        var summaries: [String: GitHubPullRequestSummary] = [:]
        for (index, ref) in refs.enumerated() {
            guard let node = payload.nodes[index], let reviewThreads = node.pullRequest?.reviewThreads else { continue }

            var unresolvedCount = reviewThreads.nodes.filter { !$0.isResolved }.count
            var latestCommentAt = reviewThreads.nodes
                .compactMap { $0.comments.nodes.first?.createdAt }
                .max()

            // A single page is usually enough; fall back to the paginated query for very chatty PRs.
            if reviewThreads.pageInfo.hasNextPage,
               let full = try? await reviewThreadSummary(
                   owner: ref.owner,
                   repository: ref.repository,
                   number: ref.number
               ) {
                unresolvedCount = full.unresolvedCount
                latestCommentAt = full.latestCommentAt
            }

            let rollup = node.object?.statusCheckRollup
            let contexts = rollup?.contexts.nodes ?? []
            let normalized = contexts.enumerated().compactMap { offset, context in
                Self.normalize(context: context, index: offset)
            }
            let checks = Self.selectedChecks(
                all: normalized.map(\.check),
                required: normalized.filter(\.isRequired).map(\.check),
                actions: normalized.filter(\.isActions).map(\.check),
                aggregate: rollup?.state,
                identity: ref.identity
            )

            summaries[ref.identity] = GitHubPullRequestSummary(
                identity: ref.identity,
                unresolvedReviewThreadCount: unresolvedCount,
                latestReviewCommentAt: latestCommentAt,
                checks: checks
            )
        }

        return summaries
    }

    /// Picks the checks that actually represent the pull request CI, in order of preference:
    ///
    /// 1. the checks enforced by branch protection/rulesets, matching what GitHub blocks a merge on;
    /// 2. otherwise, every GitHub Actions check run — the build/tests users mean by "CI";
    /// 3. otherwise, fall back to every check (aggregate `state` backfills truncated contexts).
    ///
    /// Third-party checks (SonarCloud, Wiz, …) that are neither required nor part of an Actions
    /// workflow no longer turn a green PR red.
    static func selectedChecks(
        all: [GitHubCheck],
        required: [GitHubCheck],
        actions: [GitHubCheck],
        aggregate: String?,
        identity: String
    ) -> [GitHubCheck] {
        if !required.isEmpty { return required }
        if !actions.isEmpty { return actions }
        return reconciling(checks: all, aggregate: aggregate, identity: identity)
    }

    /// The aggregate `state` is free (scalar) and covers checks truncated beyond the first page.
    /// A synthetic check is only appended when the truncated list would report a different outcome.
    static func reconciling(checks: [GitHubCheck], aggregate: String?, identity: String) -> [GitHubCheck] {
        guard let aggregate = aggregate?.uppercased() else { return checks }
        let current = CIStatusReducer.status(for: checks)
        switch aggregate {
        case "FAILURE", "ERROR":
            guard current != .failure else { return checks }
            return checks + [GitHubCheck(id: "aggregate:\(identity)", name: "Checks", status: "completed", conclusion: "failure", url: nil)]
        case "PENDING", "EXPECTED":
            guard current != .failure, current != .running else { return checks }
            return checks + [GitHubCheck(id: "aggregate:\(identity)", name: "Checks", status: "in_progress", conclusion: nil, url: nil)]
        case "SUCCESS":
            guard current == .unknown else { return checks }
            return checks + [GitHubCheck(id: "aggregate:\(identity)", name: "Checks", status: "completed", conclusion: "success", url: nil)]
        default:
            return checks
        }
    }

    /// Normalizes a GraphQL check union member to the lowercase vocabulary used by `CIStatusReducer`,
    /// keeping track of whether the check is required by branch protection and whether it comes from
    /// a GitHub Actions workflow.
    private static func normalize(
        context: GitHubBatchedSummariesPayload.Node.Context,
        index: Int
    ) -> (check: GitHubCheck, isRequired: Bool, isActions: Bool)? {
        let isRequired = context.isRequired ?? false
        let isActions = context.checkSuite?.app?.slug == "github-actions"
        switch context.typename {
        case "CheckRun":
            guard let name = context.name else { return nil }
            return (GitHubCheck(
                id: "check:\(index):\(name)",
                name: name,
                status: context.status?.lowercased(),
                conclusion: context.conclusion?.lowercased(),
                url: context.detailsUrl
            ), isRequired, isActions)
        case "StatusContext":
            guard let name = context.context else { return nil }
            let normalized: (status: String?, conclusion: String?)
            switch context.state?.uppercased() {
            case "SUCCESS": normalized = ("completed", "success")
            case "FAILURE", "ERROR": normalized = ("completed", "failure")
            case "PENDING", "EXPECTED": normalized = ("in_progress", nil)
            default: normalized = (nil, nil)
            }
            return (GitHubCheck(
                id: "status:\(index):\(name)",
                name: name,
                status: normalized.status,
                conclusion: normalized.conclusion,
                url: context.targetUrl
            ), isRequired, false)
        default:
            return nil
        }
    }

    /// Review threads of a pull request that the given login participated in, with resolution state.
    func reviewThreadState(
        owner: String,
        repository: String,
        number: Int,
        login: String
    ) async throws -> GitHubReviewThreadState {
        var cursor: String?
        var myThreadCount = 0
        var myUnresolvedCount = 0
        var latestMyCommentAt: Date?
        var isDraft = false
        var checkState: String?
        var capturedMetadata = false
        let target = login.lowercased()

        repeat {
            let payload: GitHubReviewThreadsPayload = try await graphQLRequest(
                query: """
                query($owner: String!, $repository: String!, $number: Int!, $cursor: String) {
                  repository(owner: $owner, name: $repository) {
                    pullRequest(number: $number) {
                      isDraft
                      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
                      reviewThreads(first: 100, after: $cursor) {
                        nodes {
                          isResolved
                          comments(first: 100) { nodes { author { login } createdAt } }
                        }
                        pageInfo { hasNextPage endCursor }
                      }
                    }
                  }
                }
                """,
                variables: [
                    "owner": owner,
                    "repository": repository,
                    "number": number,
                    "cursor": cursor.map { $0 as Any } ?? NSNull()
                ]
            )
            guard let pullRequest = payload.repository?.pullRequest else { break }
            if !capturedMetadata {
                capturedMetadata = true
                isDraft = pullRequest.isDraft ?? false
                checkState = pullRequest.commits?.nodes.first?.commit.statusCheckRollup?.state
            }
            let threads = pullRequest.reviewThreads

            for thread in threads.nodes {
                let myComments = thread.comments.nodes.filter { $0.author?.login.lowercased() == target }
                guard !myComments.isEmpty else { continue }
                myThreadCount += 1
                if !thread.isResolved {
                    myUnresolvedCount += 1
                }
                if let latest = myComments.map(\.createdAt).max() {
                    latestMyCommentAt = max(latestMyCommentAt ?? latest, latest)
                }
            }

            cursor = threads.pageInfo.endCursor
            if !threads.pageInfo.hasNextPage { break }
        } while cursor != nil

        return GitHubReviewThreadState(
            myThreadCount: myThreadCount,
            myUnresolvedCount: myUnresolvedCount,
            latestMyCommentAt: latestMyCommentAt,
            isDraft: isDraft,
            checkState: checkState
        )
    }

    private func graphQLRequest<Response: Decodable>(
        query: String,
        variables: [String: Any]
    ) async throws -> Response {
        let url = baseURL.appendingPathComponent("graphql")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Réponse vide"
            throw GitHubAPIError.http(
                statusCode: httpResponse.statusCode,
                message: message,
                retryAfter: nil,
                endpoint: "/graphql"
            )
        }

        let result = try GitHubJSON.decoder.decode(GitHubGraphQLResponse<Response>.self, from: data)
        if let payload = result.data { return payload }
        let message = result.errors?.map(\.message).joined(separator: "; ") ?? "Réponse GraphQL vide"
        throw GitHubAPIError.http(statusCode: 200, message: message, retryAfter: nil, endpoint: "/graphql")
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw GitHubAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let url = components.url else {
            throw GitHubAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        let resetDate = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Reset")
            .flatMap { TimeInterval($0) }
            .map(Date.init(timeIntervalSince1970:))
        if let limit = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Limit").flatMap(Int.init),
           let remaining = httpResponse.value(forHTTPHeaderField: "X-RateLimit-Remaining").flatMap(Int.init) {
            await rateLimitStore.update(
                RateLimitSnapshot(limit: limit, remaining: remaining, reset: resetDate)
            )
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(GitHubErrorResponse.self, from: data).message)
                ?? String(data: data, encoding: .utf8)
                ?? "Réponse vide"
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After")
                .flatMap(TimeInterval.init)
                .map { Date().addingTimeInterval($0) }
                ?? resetDate
            throw GitHubAPIError.http(
                statusCode: httpResponse.statusCode,
                message: message,
                retryAfter: retryAfter,
                endpoint: path
            )
        }

        do {
            return try GitHubJSON.decoder.decode(Response.self, from: data)
        } catch {
            throw GitHubAPIError.decoding(error)
        }
    }
}

private actor RateLimitStore {
    private(set) var value: RateLimitSnapshot?

    func update(_ value: RateLimitSnapshot) {
        self.value = value
    }
}
