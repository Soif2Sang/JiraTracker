#if canImport(Testing)
import Foundation
import Testing
@testable import GitHubJiraSystemTray

@Suite("Integration settings")
@MainActor
struct IntegrationSettingsTests {
    @Test func defaultsMatchTheProductDefaults() {
        let store = makeStore()

        #expect(store.organization == IntegrationSettingsStore.defaultOrganization)
        #expect(store.jiraBaseURL?.host == "decathlon.atlassian.net")
    }

    @Test func trimsOrganizationAndValidatesJiraSite() {
        let store = makeStore()

        store.githubOrganization = "  acme  "
        store.jiraSiteURL = "not a url"

        #expect(store.organization == "acme")
        #expect(store.jiraBaseURL == nil)
        #expect(store.isOrganizationValid)
    }

    private func makeStore() -> IntegrationSettingsStore {
        let suiteName = "IntegrationSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return IntegrationSettingsStore(defaults: defaults)
    }
}
#endif
