import Foundation

@MainActor
final class IntegrationSettingsStore: ObservableObject {
    static let defaultOrganization = "dktunited"
    static let defaultJiraSite = "https://decathlon.atlassian.net"

    @Published var githubOrganization: String { didSet { persist() } }
    @Published var jiraSiteURL: String { didSet { persist() } }

    private enum Key {
        static let organization = "integrations.githubOrganization"
        static let jiraSite = "integrations.jiraSiteURL"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        githubOrganization = defaults.string(forKey: Key.organization) ?? Self.defaultOrganization
        jiraSiteURL = defaults.string(forKey: Key.jiraSite) ?? Self.defaultJiraSite
    }

    /// Organization name without surrounding whitespace, ready for a GitHub search query.
    var organization: String {
        githubOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validated Jira base URL, or `nil` when the user typed something invalid.
    var jiraBaseURL: URL? {
        let value = jiraSiteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    var isOrganizationValid: Bool {
        !organization.isEmpty
    }

    func reset() {
        githubOrganization = Self.defaultOrganization
        jiraSiteURL = Self.defaultJiraSite
    }

    private func persist() {
        defaults.set(githubOrganization, forKey: Key.organization)
        defaults.set(jiraSiteURL, forKey: Key.jiraSite)
    }
}
