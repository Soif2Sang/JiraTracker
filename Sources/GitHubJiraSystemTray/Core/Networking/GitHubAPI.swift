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

    func currentUser() async throws -> GitHubUser {
        try await request(path: "/user")
    }

    func openPullRequests(author: String, organization: String) async throws -> [GitHubSearchPullRequest] {
        try await searchPullRequests(query: "is:pr is:open author:\(author) org:\(organization)")
    }

    func recentlyMergedPullRequests(
        author: String,
        organization: String,
        since: Date
    ) async throws -> [GitHubSearchPullRequest] {
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

    private func searchPullRequests(query: String) async throws -> [GitHubSearchPullRequest] {
        var results: [GitHubSearchPullRequest] = []
        var page = 1

        repeat {
            let response: GitHubSearchResponse = try await request(
                path: "/search/issues",
                queryItems: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "sort", value: "updated"),
                    URLQueryItem(name: "order", value: "desc"),
                    URLQueryItem(name: "per_page", value: "100"),
                    URLQueryItem(name: "page", value: String(page))
                ]
            )
            results.append(contentsOf: response.items)
            page += 1

            if response.items.count < 100 || page > 10 {
                break
            }
        } while true

        return results
    }

    func pullRequest(owner: String, repository: String, number: Int) async throws -> GitHubPullRequest {
        try await request(path: "/repos/\(owner)/\(repository)/pulls/\(number)")
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

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw error
        }

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
