import Foundation

enum CIStatusReducer {
    static func status(for runs: [GitHubWorkflowRun]) -> CIStatus {
        guard !runs.isEmpty else { return .unknown }

        if runs.contains(where: { run in
            ["failure", "timed_out", "action_required"].contains(run.conclusion)
        }) {
            return .failure
        }

        if runs.contains(where: { run in
            ["queued", "in_progress", "waiting", "requested", "pending"].contains(run.status)
        }) {
            return .running
        }

        if runs.contains(where: { $0.conclusion == "cancelled" }) {
            return .cancelled
        }

        let completedConclusions = runs.compactMap(\.conclusion)
        if completedConclusions.count == runs.count,
           completedConclusions.allSatisfy({ ["success", "neutral", "skipped"].contains($0) }) {
            return .success
        }

        return .unknown
    }

    /// Same priority order as `status(for:)`, applied to normalized commit checks.
    static func status(for checks: [GitHubCheck]) -> CIStatus {
        guard !checks.isEmpty else { return .unknown }

        if checks.contains(where: { check in
            ["failure", "timed_out", "action_required"].contains(check.conclusion)
        }) {
            return .failure
        }

        if checks.contains(where: { check in
            ["queued", "in_progress", "waiting", "requested", "pending"].contains(check.status)
        }) {
            return .running
        }

        if checks.contains(where: { $0.conclusion == "cancelled" }) {
            return .cancelled
        }

        let conclusions = checks.compactMap(\.conclusion)
        if conclusions.count == checks.count,
           conclusions.allSatisfy({ ["success", "neutral", "skipped"].contains($0) }) {
            return .success
        }

        return .unknown
    }
}
