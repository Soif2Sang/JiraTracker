import Foundation

final class LocalCache {
    private let fileManager: FileManager
    private let githubFileURL: URL
    private let jiraFileURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directoryURL = baseURL.appendingPathComponent("GitHubJiraSystemTray", isDirectory: true)
        githubFileURL = directoryURL.appendingPathComponent("github-snapshot.json")
        jiraFileURL = directoryURL.appendingPathComponent("jira-snapshot.json")

        let legacyFileURL = directoryURL.appendingPathComponent("snapshot.json")
        if !fileManager.fileExists(atPath: githubFileURL.path),
           fileManager.fileExists(atPath: legacyFileURL.path) {
            try? fileManager.moveItem(at: legacyFileURL, to: githubFileURL)
        }
    }

    func load() -> CacheSnapshot? {
        guard let data = try? Data(contentsOf: githubFileURL) else { return nil }
        return try? GitHubJSON.decoder.decode(CacheSnapshot.self, from: data)
    }

    func save(_ snapshot: CacheSnapshot) {
        guard let data = try? GitHubJSON.encoder.encode(snapshot) else { return }
        do {
            try fileManager.createDirectory(
                at: githubFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: githubFileURL, options: [.atomic])
        } catch {
            // A cache failure must not prevent live GitHub data from being displayed.
        }
    }

    func loadJira() -> JiraCacheSnapshot? {
        guard let data = try? Data(contentsOf: jiraFileURL) else { return nil }
        return try? GitHubJSON.decoder.decode(JiraCacheSnapshot.self, from: data)
    }

    func saveJira(_ snapshot: JiraCacheSnapshot) {
        guard let data = try? GitHubJSON.encoder.encode(snapshot) else { return }
        do {
            try fileManager.createDirectory(
                at: jiraFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: jiraFileURL, options: [.atomic])
        } catch {
            // A cache failure must not prevent live Jira data from being displayed.
        }
    }

    func clearGitHub() {
        try? fileManager.removeItem(at: githubFileURL)
    }

    func clearJira() {
        try? fileManager.removeItem(at: jiraFileURL)
    }
}
