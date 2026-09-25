import Foundation

enum GitHubJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = ISO8601Parser.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date GitHub invalide")
            }
            return date
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
        let isDraft: Bool?
        let commits: Commits?
        let reviewThreads: ReviewThreads
    }

    struct Commits: Decodable {
        let nodes: [Node]

        struct Node: Decodable {
            let commit: Commit

            struct Commit: Decodable {
                let statusCheckRollup: StatusCheckRollup?

                struct StatusCheckRollup: Decodable {
                    let state: String?
                }
            }
        }
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
        let author: Author?
        let createdAt: Date

        struct Author: Decodable {
            let login: String
        }
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

/// A single CI check attached to a commit, normalized from a GitHub GraphQL
/// `CheckRun` or `StatusContext` so it shares the same vocabulary as `GitHubWorkflowRun`.
struct GitHubCheck: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let status: String?
    let conclusion: String?
    let url: URL?
}

/// Reference to a pull request used to batch several summaries in one GraphQL call.
struct GitHubPullRequestRef: Equatable {
    let identity: String
    let owner: String
    let repository: String
    let number: Int
    let headSHA: String
}

/// Review-thread and CI-check summary for a single pull request, fetched in batch.
struct GitHubPullRequestSummary: Equatable {
    let identity: String
    let unresolvedReviewThreadCount: Int
    let latestReviewCommentAt: Date?
    let checks: [GitHubCheck]
}

/// Dynamic top-level GraphQL payload keyed by alias (`pr0`, `pr1`, …).
struct GitHubBatchedSummariesPayload: Decodable {
    let nodes: [Int: Node]

    struct Node: Decodable {
        let pullRequest: PullRequest?
        let object: GitObject?

        struct PullRequest: Decodable {
            let reviewThreads: ReviewThreads
        }

        struct GitObject: Decodable {
            let statusCheckRollup: StatusCheckRollup?
        }

        struct ReviewThreads: Decodable {
            let nodes: [Thread]
            let pageInfo: PageInfo

            struct Thread: Decodable {
                let isResolved: Bool
                let comments: Comments

                struct Comments: Decodable {
                    let nodes: [Comment]
                }

                struct Comment: Decodable {
                    let createdAt: Date
                }
            }

            struct PageInfo: Decodable {
                let hasNextPage: Bool
            }
        }

        struct StatusCheckRollup: Decodable {
            let state: String?
            let contexts: Contexts
        }

        struct Contexts: Decodable {
            let nodes: [Context]
        }

        struct Context: Decodable {
            let typename: String
            let name: String?
            let status: String?
            let conclusion: String?
            let detailsUrl: URL?
            let context: String?
            let state: String?
            let targetUrl: URL?
            /// Whether this check is required by the base branch protection rules (or rulesets).
            let isRequired: Bool?
            /// The check suite that produced this check run, used to tell GitHub Actions apart
            /// from third-party apps (SonarCloud, Wiz, …).
            let checkSuite: CheckSuite?

            enum CodingKeys: String, CodingKey {
                case typename = "__typename"
                case name
                case status
                case conclusion
                case detailsUrl
                case context
                case state
                case targetUrl
                case isRequired
                case checkSuite
            }

            struct CheckSuite: Decodable {
                let app: App?

                struct App: Decodable {
                    let slug: String?
                }
            }
        }
    }

    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { Int(stringValue) }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { self.stringValue = String(intValue) }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var nodes: [Int: Node] = [:]
        for key in container.allKeys {
            guard key.stringValue.hasPrefix("pr"),
                  let index = Int(key.stringValue.dropFirst(2)) else { continue }
            if let node = try? container.decode(Node.self, forKey: key) {
                nodes[index] = node
            }
        }
        self.nodes = nodes
    }
}

/// Review threads on a pull request, restricted to the ones the given login took part in.
struct GitHubReviewThreadState: Equatable {
    let myThreadCount: Int
    let myUnresolvedCount: Int
    let latestMyCommentAt: Date?
    /// The pull request is still a draft.
    var isDraft: Bool = false
    /// Combined `statusCheckRollup` state of the head commit (SUCCESS, FAILURE, PENDING, …).
    var checkState: String?

    /// Nothing left on my side and the branch is ready: not a draft and checks are green (or absent).
    var isActionable: Bool {
        guard myUnresolvedCount == 0, !isDraft else { return false }
        guard let checkState else { return true }
        return checkState.uppercased() == "SUCCESS"
    }
}

/// Owner/repository/number parsed from a GitHub pull request URL.
struct GitHubPullReference: Equatable {
    let owner: String
    let repository: String
    let number: Int

    init?(url: URL) {
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count >= 4,
              components[2] == "pull",
              let number = Int(components[3]) else {
            return nil
        }
        owner = components[0]
        repository = components[1]
        self.number = number
    }
}

struct GitHubUser: Codable, Equatable {
    let login: String
}

struct GitHubViewerPayload: Decodable {
    let viewer: Viewer

    struct Viewer: Decodable {
        let login: String
    }
}

/// A pull request discovered via GraphQL search, carrying enough metadata to build
/// a `TrackedPullRequest` without any additional REST call.
struct GitHubDiscoveredPullRequest: Equatable {
    let number: Int
    let repositoryFullName: String
    let title: String
    let url: URL
    let body: String?
    let updatedAt: Date
    let isDraft: Bool
    let headRefName: String
    let headRefOid: String
    let mergedAt: Date?

    var identity: String { "\(repositoryFullName)#\(number)" }
}

struct GitHubSearchPullRequestsPayload: Decodable {
    let search: Search

    struct Search: Decodable {
        let nodes: [Node]
        let pageInfo: PageInfo

        struct Node: Decodable {
            let number: Int?
            let title: String?
            let url: URL?
            let body: String?
            let updatedAt: Date?
            let isDraft: Bool?
            let mergedAt: Date?
            let repository: Repository?
            let headRefName: String?
            let headRefOid: String?

            struct Repository: Decodable {
                let nameWithOwner: String
            }
        }

        struct PageInfo: Decodable {
            let hasNextPage: Bool
            let endCursor: String?
        }
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
    var checks: [GitHubCheck]?

    var ciStatus: CIStatus {
        if let checks, !checks.isEmpty { return CIStatusReducer.status(for: checks) }
        if !workflowRuns.isEmpty { return CIStatusReducer.status(for: workflowRuns) }
        return .unknown
    }

    var failedJobCount: Int {
        let jobs = workflowRuns.flatMap { run in run.jobs ?? [] }
        return jobs.filter { job in
            job.conclusion == "failure" || job.conclusion == "timed_out"
        }.count
    }

    var primaryWorkflowURL: URL? {
        if let url = workflowRuns.first(where: { ["failure", "timed_out", "action_required"].contains($0.conclusion) })?.htmlURL {
            return url
        }
        if let url = workflowRuns.first(where: { ["queued", "in_progress", "waiting", "requested", "pending"].contains($0.status) })?.htmlURL {
            return url
        }
        if let url = workflowRuns.first?.htmlURL {
            return url
        }
        // Runs are now fetched lazily, so fall back to the batched checks until the row is expanded.
        if let url = checks?.first(where: { ["failure", "timed_out", "action_required"].contains($0.conclusion) })?.url {
            return url
        }
        if let url = checks?.first(where: { ["queued", "in_progress", "waiting", "requested", "pending"].contains($0.status) })?.url {
            return url
        }
        return checks?.first?.url
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
        latestReviewCommentAt: Date? = nil,
        checks: [GitHubCheck]? = nil
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
        self.checks = checks
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
        case checks
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
        checks = try container.decodeIfPresent([GitHubCheck].self, forKey: .checks)
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
