import Foundation

enum GitHubJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date GitHub invalide")
        }
        return decoder
    }()

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()
}

struct GitHubErrorResponse: Decodable {
    let message: String
}

struct GitHubGraphQLResponse<Payload: Decodable>: Decodable {
    let data: Payload?
    let errors: [GitHubGraphQLError]?
}

struct GitHubGraphQLError: Decodable {
    let message: String
}

struct GitHubReviewThreadsPayload: Decodable {
    let repository: Repository?

    struct Repository: Decodable {
        let pullRequest: PullRequest?
    }

    struct PullRequest: Decodable {
        let reviewThreads: ReviewThreads
    }

    struct ReviewThreads: Decodable {
        let nodes: [ReviewThread]
        let pageInfo: PageInfo
    }

    struct ReviewThread: Decodable {
        let isResolved: Bool
        let comments: Comments
    }

    struct Comments: Decodable {
        let nodes: [Comment]
    }

    struct Comment: Decodable {
        let createdAt: Date
    }

    struct PageInfo: Decodable {
        let hasNextPage: Bool
        let endCursor: String?
    }
}

struct GitHubReviewThreadSummary: Equatable {
    let unresolvedCount: Int
    let latestCommentAt: Date?
}

struct GitHubUser: Codable, Equatable {
    let login: String
}

struct GitHubRepositoryReference: Codable, Equatable {
    let fullName: String

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
    }
}

struct GitHubSearchPullRequest: Codable, Equatable, Identifiable {
    let id: Int64
    let number: Int
    let title: String
    let htmlURL: URL
    let updatedAt: Date
    let repository: GitHubRepositoryReference?
    let repositoryURL: URL?
    let body: String?
    let pullRequest: GitHubSearchPullRequestMetadata?

    var mergedAt: Date? {
        pullRequest?.mergedAt
    }

    var repositoryFullName: String? {
        if let repository {
            return repository.fullName
        }
        guard let repositoryURL else { return nil }
        let components = repositoryURL.path.split(separator: "/").map(String.init)
        guard components.count >= 3, components[0] == "repos" else { return nil }
        return "\(components[1])/\(components[2])"
    }

    var identity: String {
        "\(repositoryFullName ?? "unknown")#\(number)"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case repository
        case repositoryURL = "repository_url"
        case body
        case pullRequest = "pull_request"
    }
}

struct GitHubSearchResponse: Decodable {
    let items: [GitHubSearchPullRequest]
}

struct GitHubSearchPullRequestMetadata: Codable, Equatable {
    let mergedAt: Date?

    enum CodingKeys: String, CodingKey {
        case mergedAt = "merged_at"
    }
}

struct GitHubBranch: Codable, Equatable {
    let ref: String
    let sha: String
}

struct GitHubPullRequest: Codable, Equatable, Identifiable {
    let id: Int64
    let number: Int
    let title: String
    let htmlURL: URL
    let draft: Bool?
    let body: String?
    let updatedAt: Date
    let head: GitHubBranch
    let repository: GitHubRepositoryReference?
    let mergedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case number
        case title
        case htmlURL = "html_url"
        case draft
        case body
        case updatedAt = "updated_at"
        case head
        case repository
        case mergedAt = "merged_at"
    }
}

struct GitHubWorkflowRunsResponse: Decodable {
    let workflowRuns: [GitHubWorkflowRun]

    enum CodingKeys: String, CodingKey {
        case workflowRuns = "workflow_runs"
    }
}

struct GitHubWorkflowRun: Codable, Equatable, Identifiable {
    let id: Int64
    let name: String?
    let status: String?
    let conclusion: String?
    let htmlURL: URL
    let headSHA: String
    let runAttempt: Int?
    let createdAt: Date
    let updatedAt: Date
    var jobs: [GitHubJob]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case status
        case conclusion
        case htmlURL = "html_url"
        case headSHA = "head_sha"
        case runAttempt = "run_attempt"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case jobs
    }
}

struct GitHubJobsResponse: Decodable {
    let jobs: [GitHubJob]
}

struct GitHubJob: Codable, Equatable, Identifiable {
    let id: Int64
    let runID: Int64
    let name: String
    let status: String
    let conclusion: String?
    let htmlURL: URL?
    let startedAt: Date?
    let completedAt: Date?
    let steps: [GitHubStep]?

    enum CodingKeys: String, CodingKey {
        case id
        case runID = "run_id"
        case name
        case status
        case conclusion
        case htmlURL = "html_url"
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case steps
    }
}

struct GitHubStep: Codable, Equatable, Identifiable {
    let number: Int
    let name: String
    let status: String
    let conclusion: String?
    let startedAt: Date?
    let completedAt: Date?

    var id: Int { number }

    enum CodingKeys: String, CodingKey {
        case number
        case name
        case status
        case conclusion
        case startedAt = "started_at"
        case completedAt = "completed_at"
    }
}

enum CIStatus: String, Codable, CaseIterable {
    case failure
    case running
    case cancelled
    case success
    case unknown

    var title: String {
        switch self {
        case .failure: return "Échec"
        case .running: return "En cours"
        case .cancelled: return "Annulée"
        case .success: return "Réussie"
        case .unknown: return "Inconnue"
        }
    }
}

struct TrackedPullRequest: Codable, Equatable, Identifiable {
    let id: String
    let repository: String
    let number: Int
    let title: String
    let url: URL
    let branch: String
    let headSHA: String
    let isDraft: Bool
    let body: String?
    let updatedAt: Date
    let isMerged: Bool
    var workflowRuns: [GitHubWorkflowRun]
    var unresolvedReviewThreadCount: Int
    var latestReviewCommentAt: Date?

    var ciStatus: CIStatus {
        CIStatusReducer.status(for: workflowRuns)
    }

    var failedJobCount: Int {
        let jobs = workflowRuns.flatMap { run in run.jobs ?? [] }
        return jobs.filter { job in
            job.conclusion == "failure" || job.conclusion == "timed_out"
        }.count
    }

    var primaryWorkflowURL: URL? {
        workflowRuns.first(where: { ["failure", "timed_out", "action_required"].contains($0.conclusion) })?.htmlURL
            ?? workflowRuns.first(where: { ["queued", "in_progress", "waiting", "requested", "pending"].contains($0.status) })?.htmlURL
            ?? workflowRuns.first?.htmlURL
    }

    init(
        id: String,
        repository: String,
        number: Int,
        title: String,
        url: URL,
        branch: String,
        headSHA: String,
        isDraft: Bool,
        body: String?,
        updatedAt: Date,
        isMerged: Bool = false,
        workflowRuns: [GitHubWorkflowRun],
        unresolvedReviewThreadCount: Int = 0,
        latestReviewCommentAt: Date? = nil
    ) {
        self.id = id
        self.repository = repository
        self.number = number
        self.title = title
        self.url = url
        self.branch = branch
        self.headSHA = headSHA
        self.isDraft = isDraft
        self.body = body
        self.updatedAt = updatedAt
        self.isMerged = isMerged
        self.workflowRuns = workflowRuns
        self.unresolvedReviewThreadCount = unresolvedReviewThreadCount
        self.latestReviewCommentAt = latestReviewCommentAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case repository
        case number
        case title
        case url
        case branch
        case headSHA
        case isDraft
        case body
        case updatedAt
        case isMerged
        case workflowRuns
        case unresolvedReviewThreadCount
        case latestReviewCommentAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        repository = try container.decode(String.self, forKey: .repository)
        number = try container.decode(Int.self, forKey: .number)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(URL.self, forKey: .url)
        branch = try container.decode(String.self, forKey: .branch)
        headSHA = try container.decode(String.self, forKey: .headSHA)
        isDraft = try container.decode(Bool.self, forKey: .isDraft)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        isMerged = try container.decodeIfPresent(Bool.self, forKey: .isMerged) ?? false
        workflowRuns = try container.decode([GitHubWorkflowRun].self, forKey: .workflowRuns)
        unresolvedReviewThreadCount = try container.decodeIfPresent(Int.self, forKey: .unresolvedReviewThreadCount) ?? 0
        latestReviewCommentAt = try container.decodeIfPresent(Date.self, forKey: .latestReviewCommentAt)
    }
}

struct CacheSnapshot: Codable {
    let pullRequests: [TrackedPullRequest]
    let mergedPullRequests: [TrackedPullRequest]
    let savedAt: Date

    init(
        pullRequests: [TrackedPullRequest],
        mergedPullRequests: [TrackedPullRequest] = [],
        savedAt: Date
    ) {
        self.pullRequests = pullRequests
        self.mergedPullRequests = mergedPullRequests
        self.savedAt = savedAt
    }

    enum CodingKeys: String, CodingKey {
        case pullRequests
        case mergedPullRequests
        case savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        pullRequests = try container.decode([TrackedPullRequest].self, forKey: .pullRequests)
        mergedPullRequests = try container.decodeIfPresent([TrackedPullRequest].self, forKey: .mergedPullRequests) ?? []
        savedAt = try container.decode(Date.self, forKey: .savedAt)
    }
}
