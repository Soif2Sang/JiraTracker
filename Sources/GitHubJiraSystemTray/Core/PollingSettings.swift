import Foundation

@MainActor
final class PollingSettingsStore: ObservableObject {
    @Published var isEnabled: Bool { didSet { persist() } }
    @Published var discoveryInterval: Double { didSet { persist() } }
    @Published var runningInterval: Double { didSet { persist() } }
    @Published var idleInterval: Double { didSet { persist() } }
    @Published var lowRateLimitInterval: Double { didSet { persist() } }
    @Published var lowRateLimitThreshold: Int { didSet { persist() } }
    @Published var jiraInterval: Double { didSet { persist() } }

    private enum Key {
        static let enabled = "polling.enabled"
        static let discovery = "polling.discoveryInterval"
        static let running = "polling.runningInterval"
        static let idle = "polling.idleInterval"
        static let lowRateLimit = "polling.lowRateLimitInterval"
        static let lowRateLimitThreshold = "polling.lowRateLimitThreshold"
        static let jira = "polling.jiraInterval"
    }

    private enum Default {
        static let enabled = true
        static let discovery: Double = 300
        static let running: Double = 30
        static let idle: Double = 60
        static let lowRateLimit: Double = 300
        static let lowRateLimitThreshold = 100
        static let jira: Double = 180
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isEnabled = defaults.object(forKey: Key.enabled) as? Bool ?? Default.enabled
        discoveryInterval = defaults.object(forKey: Key.discovery) as? Double ?? Default.discovery
        runningInterval = defaults.object(forKey: Key.running) as? Double ?? Default.running
        idleInterval = defaults.object(forKey: Key.idle) as? Double ?? Default.idle
        lowRateLimitInterval = defaults.object(forKey: Key.lowRateLimit) as? Double ?? Default.lowRateLimit
        lowRateLimitThreshold = defaults.object(forKey: Key.lowRateLimitThreshold) as? Int ?? Default.lowRateLimitThreshold
        jiraInterval = defaults.object(forKey: Key.jira) as? Double ?? Default.jira
    }

    func reset() {
        isEnabled = Default.enabled
        discoveryInterval = Default.discovery
        runningInterval = Default.running
        idleInterval = Default.idle
        lowRateLimitInterval = Default.lowRateLimit
        lowRateLimitThreshold = Default.lowRateLimitThreshold
        jiraInterval = Default.jira
    }

    private func persist() {
        defaults.set(isEnabled, forKey: Key.enabled)
        defaults.set(discoveryInterval, forKey: Key.discovery)
        defaults.set(runningInterval, forKey: Key.running)
        defaults.set(idleInterval, forKey: Key.idle)
        defaults.set(lowRateLimitInterval, forKey: Key.lowRateLimit)
        defaults.set(lowRateLimitThreshold, forKey: Key.lowRateLimitThreshold)
        defaults.set(jiraInterval, forKey: Key.jira)
    }
}
