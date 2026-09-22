import Foundation

enum JiraAPIError: LocalizedError {
    case invalidURL
    case invalidResponse
    case http(statusCode: Int, message: String, endpoint: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "L'URL Jira est invalide."
        case .invalidResponse:
            return "Jira a renvoyé une réponse invalide."
        case let .http(statusCode, message, endpoint):
            if statusCode == 401 {
                return "Les identifiants Jira sont invalides. Utilisez l'e-mail Atlassian et l'API token associé."
            }
            if statusCode == 403 {
                return "Jira refuse cette opération. Vérifiez vos permissions sur les projets concernés. [\(endpoint)]"
            }
            return "Jira a renvoyé une erreur (\(statusCode)) : \(message) [\(endpoint)]"
        case let .decoding(error):
            return "Réponse Jira non comprise : \(error.localizedDescription)"
        }
    }
}

final class JiraClient {
    /// Custom field id of "Code Reviewer" on the Atlassian site.
    static let codeReviewerField = "customfield_11268"

    private let baseURL: URL
    private let email: String
    private let token: String
    private let session: URLSession

    init(baseURL: URL, email: String, token: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    func searchIssues(jql: String) async throws -> [JiraIssue] {
        var issues: [JiraIssue] = []
        var nextPageToken: String?

        repeat {
            var queryItems = [
                URLQueryItem(name: "jql", value: jql),
                URLQueryItem(name: "maxResults", value: "100"),
                URLQueryItem(name: "fields", value: "summary,status,priority,issuetype,updated,\(Self.codeReviewerField)")
            ]
            if let nextPageToken {
                queryItems.append(URLQueryItem(name: "nextPageToken", value: nextPageToken))
            }
            let response: JiraIssueSearchResponse = try await request(
                path: "/rest/api/3/search/jql",
                queryItems: queryItems
            )
            issues.append(contentsOf: response.issues)
            nextPageToken = response.isLast == true ? nil : response.nextPageToken
        } while nextPageToken != nil

        return issues
    }

    func currentUser() async throws -> JiraUser {
        try await request(path: "/rest/api/3/myself")
    }

    func issue(key: String) async throws -> JiraIssue {
        try await request(
            path: "/rest/api/3/issue/\(key)",
            queryItems: [URLQueryItem(name: "fields", value: "summary,status,priority,issuetype,updated,\(Self.codeReviewerField)")]
        )
    }

    /// Pull requests linked to an issue through the Jira GitHub integration (dev-status panel).
    func linkedPullRequests(issueId: String) async throws -> [JiraLinkedPullRequest] {
        for applicationType in ["oAuth-com.github.integration.production", "GitHub"] {
            let response: JiraDevStatusResponse = try await request(
                path: "/rest/dev-status/1.0/issue/detail",
                queryItems: [
                    URLQueryItem(name: "issueId", value: issueId),
                    URLQueryItem(name: "applicationType", value: applicationType),
                    URLQueryItem(name: "dataType", value: "pullrequest")
                ]
            )
            let pullRequests = response.detail.flatMap { $0.pullRequests ?? [] }
            if !pullRequests.isEmpty {
                return pullRequests
            }
        }
        return []
    }

    func statuses() async throws -> [JiraStatus] {
        try await request(path: "/rest/api/3/status")
    }

    func statuses(forProject projectKey: String) async throws -> [JiraStatus] {
        let issueTypes: [JiraProjectIssueTypeStatuses] = try await request(
            path: "/rest/api/3/project/\(projectKey)/statuses"
        )
        return issueTypes.flatMap(\.statuses)
    }

    func priorities() async throws -> [JiraNamedValue] {
        try await request(path: "/rest/api/3/priority")
    }

    func transitions(for issueKey: String) async throws -> [JiraTransition] {
        let response: JiraTransitionResponse = try await request(
            path: "/rest/api/3/issue/\(issueKey)/transitions"
        )
        return response.transitions
    }

    func transition(issueKey: String, transitionID: String) async throws {
        let body = try JSONSerialization.data(withJSONObject: [
            "transition": ["id": transitionID]
        ])
        try await requestWithoutResponse(
            path: "/rest/api/3/issue/\(issueKey)/transitions",
            method: "POST",
            body: body
        )
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = []
    ) async throws -> Response {
        let data = try await performRequest(path: path, method: "GET", queryItems: queryItems, body: nil)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw JiraAPIError.decoding(error)
        }
    }

    private func requestWithoutResponse(path: String, method: String, body: Data?) async throws {
        _ = try await performRequest(path: path, method: method, queryItems: [], body: body)
    }

    private func performRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem],
        body: Data?
    ) async throws -> Data {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw JiraAPIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw JiraAPIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let credentials = Data("\(email):\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw JiraAPIError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = (try? JSONDecoder().decode(JiraErrorResponse.self, from: data).errorMessages.joined(separator: "; "))
                ?? String(data: data, encoding: .utf8)
                ?? "Réponse vide"
            throw JiraAPIError.http(statusCode: httpResponse.statusCode, message: message, endpoint: path)
        }
        return data
    }
}

private struct JiraErrorResponse: Decodable {
    let errorMessages: [String]
}
