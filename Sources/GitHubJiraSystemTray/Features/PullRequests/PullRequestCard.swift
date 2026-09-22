import SwiftUI

struct PullRequestCard: View {
    let pullRequest: TrackedPullRequest
    @ObservedObject var store: AppStore
    var contextLabel: String? = nil

    private var isExpanded: Bool {
        store.expandedPullRequests.contains(pullRequest.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    store.toggleExpanded(pullRequest.id)
                } label: {
                    HStack(alignment: .center, spacing: 8) {
                        CIStatusIcon(status: pullRequest.ciStatus, isMerged: pullRequest.isMerged)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if let contextLabel {
                                    Text(contextLabel)
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(shortRepositoryName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text("#\(pullRequest.number)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if pullRequest.isDraft {
                                    Text("Draft")
                                        .font(.caption2.weight(.medium))
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(.secondary.opacity(0.14), in: Capsule())
                                }
                            }
                            Text(pullRequest.title)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 5, height: 5)
                                Text(displayStatus)
                                if pullRequest.failedJobCount > 0 {
                                    Text("•")
                                    Text("\(pullRequest.failedJobCount) échec\(pullRequest.failedJobCount == 1 ? "" : "s")")
                                }
                                if pullRequest.unresolvedReviewThreadCount > 0 {
                                    ReviewCommentBadge(count: pullRequest.unresolvedReviewThreadCount)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                VStack(spacing: 5) {
                    Link(destination: pullRequest.url) {
                        Image(systemName: "arrow.up.right.square")
                            .iconHitTarget()
                    }
                    .help("Ouvrir la PR")
                    .buttonStyle(.borderless)

                    if let workflowURL = pullRequest.primaryWorkflowURL {
                        Link(destination: workflowURL) {
                            Image(systemName: "gearshape.2")
                                .iconHitTarget()
                        }
                        .help("Ouvrir le workflow")
                        .buttonStyle(.borderless)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if pullRequest.isMerged {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.purple)
                        .frame(width: 16, height: 22)
                        .help("PR mergée")
                } else {
                    Button {
                        store.toggleExpanded(pullRequest.id)
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .iconHitTarget()
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Réduire" : "Voir les jobs")
                }
            }

            if isExpanded && !pullRequest.isMerged {
                Divider()
                HStack(spacing: 12) {
                    Link(destination: pullRequest.url) {
                        Label("Ouvrir la PR", systemImage: "arrow.up.right.square")
                    }
                    .font(.caption)

                    if let workflowURL = pullRequest.primaryWorkflowURL {
                        Link(destination: workflowURL) {
                            Label("Workflow", systemImage: "gearshape.2")
                        }
                        .font(.caption)
                    }
                }
                WorkflowDetails(pullRequest: pullRequest)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(.separator.opacity(0.45), lineWidth: 0.5)
        }
    }

    private var statusColor: Color {
        if pullRequest.isMerged { return .purple }
        switch pullRequest.ciStatus {
        case .failure: return .red
        case .running: return .orange
        case .success: return .green
        case .cancelled, .unknown: return .secondary
        }
    }

    private var displayStatus: String {
        pullRequest.isMerged ? "Mergée" : pullRequest.ciStatus.title
    }

    private var shortRepositoryName: String {
        pullRequest.repository.split(separator: "/").last.map(String.init) ?? pullRequest.repository
    }
}

struct CIStatusIcon: View {
    let status: CIStatus
    let isMerged: Bool

    init(status: CIStatus, isMerged: Bool = false) {
        self.status = status
        self.isMerged = isMerged
    }

    var body: some View {
        Image(systemName: isMerged ? "arrow.merge" : symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(isMerged ? Color.purple : color)
            .frame(width: 20, height: 20)
            .accessibilityLabel(status.title)
    }

    private var symbol: String {
        switch status {
        case .failure: return "xmark.circle.fill"
        case .running: return "clock.arrow.circlepath"
        case .success: return "checkmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .failure: return .red
        case .running: return .orange
        case .success: return .green
        case .cancelled, .unknown: return .secondary
        }
    }
}

struct ReviewCommentBadge: View {
    let count: Int

    var body: some View {
        Label(String(count), systemImage: "bubble.left.fill")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.12), in: Capsule())
            .help("\(count) conversation\(count == 1 ? "" : "s") non résolue\(count == 1 ? "" : "s")")
    }
}

struct WorkflowDetails: View {
    let pullRequest: TrackedPullRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if pullRequest.workflowRuns.isEmpty {
                Text("Aucun workflow GitHub Actions pour ce commit.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(pullRequest.workflowRuns) { run in
                    WorkflowRunRow(run: run)
                }
            }
        }
    }
}

struct WorkflowRunRow: View {
    let run: GitHubWorkflowRun

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(color)
                    .frame(width: 7, height: 7)
                Text(run.name ?? "Workflow sans nom")
                    .font(.caption.weight(.semibold))
                Spacer()
                if let url = URL(string: run.htmlURL.absoluteString) {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right")
                            .iconHitTarget()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let jobs = run.jobs {
                if jobs.isEmpty {
                    Text("Aucun job dans ce run.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(jobs) { job in
                        JobRow(job: job)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Chargement des jobs...")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
    }

    private var color: Color {
        if ["failure", "timed_out", "action_required"].contains(run.conclusion) { return .red }
        if ["queued", "in_progress", "waiting", "requested", "pending"].contains(run.status) { return .orange }
        if ["success", "neutral", "skipped"].contains(run.conclusion) { return .green }
        return .secondary
    }
}

struct JobRow: View {
    let job: GitHubJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                Text(job.name)
                    .font(.caption)
                Spacer()
                if let url = job.htmlURL {
                    Link(destination: url) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                            .iconHitTarget()
                    }
                    .buttonStyle(.borderless)
                }
            }

            if let steps = relevantSteps, !steps.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(steps) { step in
                        HStack(spacing: 5) {
                            Image(systemName: stepSymbol(step))
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(stepColor(step))
                            Text(step.name)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .padding(.leading, 17)
            }
        }
    }

    private var symbol: String {
        if job.conclusion == "failure" || job.conclusion == "timed_out" { return "xmark.circle.fill" }
        if job.status == "in_progress" || job.status == "queued" { return "clock.fill" }
        if job.conclusion == "success" || job.conclusion == "skipped" { return "checkmark.circle.fill" }
        return "questionmark.circle"
    }

    private var color: Color {
        if job.conclusion == "failure" || job.conclusion == "timed_out" { return .red }
        if job.status == "in_progress" || job.status == "queued" { return .orange }
        if job.conclusion == "success" || job.conclusion == "skipped" { return .green }
        return .secondary
    }

    private var relevantSteps: [GitHubStep]? {
        job.steps?.filter { step in
            step.conclusion != "success" && step.conclusion != "skipped"
        }
    }

    private func stepSymbol(_ step: GitHubStep) -> String {
        if step.conclusion == "failure" || step.conclusion == "timed_out" { return "xmark" }
        if step.status == "in_progress" || step.status == "queued" { return "clock" }
        if step.conclusion == "success" || step.conclusion == "skipped" { return "checkmark" }
        return "minus"
    }

    private func stepColor(_ step: GitHubStep) -> Color {
        if step.conclusion == "failure" || step.conclusion == "timed_out" { return .red }
        if step.status == "in_progress" || step.status == "queued" { return .orange }
        if step.conclusion == "success" || step.conclusion == "skipped" { return .green }
        return .secondary
    }
}
