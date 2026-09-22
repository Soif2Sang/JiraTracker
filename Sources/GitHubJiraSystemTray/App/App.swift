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
    private let store = AppStore()
    private let jiraStore = JiraStore()
    private var statusItemController: StatusItemController?
    private var wakeObserver: Any?
    private let networkMonitor = NWPathMonitor()
    private var networkWasUnavailable = false
    private let demoMode = ProcessInfo.processInfo.environment["JIRA_TRACKER_DEMO"] == "1"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        statusItemController = StatusItemController(store: store, jiraStore: jiraStore, demoMode: demoMode)
        if demoMode {
            store.loadDemoData()
            jiraStore.loadDemoData()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.statusItemController?.showPopover()
                if let path = ProcessInfo.processInfo.environment["JIRA_TRACKER_SCREENSHOT"] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self?.statusItemController?.capturePopover(to: path)
                    }
                }
            }
        } else {
            store.start()
            jiraStore.start()
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.store.refreshNow()
                self?.jiraStore.refreshNow()
            }
        }

        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isAvailable = path.status == .satisfied
            Task { @MainActor in
                if isAvailable && self.networkWasUnavailable {
                    self.store.refreshNow()
                    self.jiraStore.refreshNow()
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
}
