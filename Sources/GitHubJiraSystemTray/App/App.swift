import AppKit
import Network
import SwiftUI

@main
struct GitHubJiraSystemTrayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel.shared
    private var statusItemController: StatusItemController?
    private var wakeObserver: Any?
    private let networkMonitor = NWPathMonitor()
    private var networkWasUnavailable = false
    private let demoMode = ProcessInfo.processInfo.environment["JIRA_TRACKER_DEMO"] == "1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(store: model.store, jiraStore: model.jiraStore, theme: model.theme, badgeStyle: model.badgeStyle, demoMode: demoMode)
        if demoMode {
            model.store.loadDemoData()
            model.jiraStore.loadDemoData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.statusItemController?.showPopover()
                if let path = ProcessInfo.processInfo.environment["JIRA_TRACKER_SCREENSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.statusItemController?.capturePopover(to: path)
                    }
                }
                if let path = ProcessInfo.processInfo.environment["JIRA_TRACKER_SETTINGS_SCREENSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        self?.showSettings()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            self?.captureSettingsWindow(to: path)
                        }
                    }
                }
                if let path = ProcessInfo.processInfo.environment["JIRA_TRACKER_BADGES_SCREENSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        self?.captureBadges(to: path)
                    }
                }
            }
        } else {
            model.store.start()
            model.jiraStore.start()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model.store.refreshNow()
                self?.model.jiraStore.refreshNow()
            }
        }

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isAvailable = path.status == .satisfied
            Task { @MainActor in
                if isAvailable && self.networkWasUnavailable {
                    self.model.store.refreshNow()
                    self.model.jiraStore.refreshNow()
                }
                self.networkWasUnavailable = !isAvailable
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "GitHubJiraSystemTray.NetworkMonitor"))
    }

    func applicationWillTerminate(_ notification: Notification) {
        networkMonitor.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
    }

    func showSettings() {
        statusItemController?.showSettings()
    }

    private func captureSettingsWindow(to path: String) {
        statusItemController?.capturePopover(to: path)
    }

    private func captureBadges(to path: String) {
        typealias Item = StatusBadgesNSView.BadgeItem
        func item(_ count: Int, _ color: NSColor, _ symbol: String?) -> Item {
            Item(text: String(count), color: color, symbolName: symbol)
        }
        let failure = item(2, .systemRed, "xmark")
        let running = item(1, .systemOrange, "arrow.triangle.2.circlepath")
        let comments = item(4, .systemPurple, "bubble.left.fill")
        let withoutPR = item(1, .systemBlue, "link")
        let passed = item(3, .systemGreen, "checkmark")
        let unknown = item(2, .systemGray, "questionmark")
        let reviewer = item(2, .systemIndigo, "eye.fill")
        var errorSummary = StatusSummary.empty
        errorSummary.hasError = true
        let mixed = StatusBadgesNSView.items(for: statusItemController?.displaySummary ?? model.store.summary)

        let entries: [BadgePreviewRenderer.Entry] = [
            .init(label: "complet", items: mixed, style: .full),
            .init(label: "compact", items: mixed, style: .compact),
            .init(label: "minimal", items: mixed, style: .minimal),
            .init(label: "échec", items: [failure], style: .full),
            .init(label: "en cours", items: [running], style: .full),
            .init(label: "commentaires", items: [comments], style: .full),
            .init(label: "sans PR", items: [withoutPR], style: .full),
            .init(label: "reviewer", items: [reviewer], style: .full),
            .init(label: "réussi / inconnu", items: [passed, unknown], style: .full),
            .init(label: "vide", items: StatusBadgesNSView.items(for: .empty), style: .full),
            .init(label: "erreur", items: StatusBadgesNSView.items(for: errorSummary), style: .full)
        ]

        guard let data = BadgePreviewRenderer.sheet(entries) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }
}
