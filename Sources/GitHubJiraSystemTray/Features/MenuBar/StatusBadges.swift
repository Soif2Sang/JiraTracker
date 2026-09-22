import AppKit
import Combine
import SwiftUI

enum StatusBadgeKind {
    case review
    case failure
    case running
    case success
    case unknown

    var color: Color {
        switch self {
        case .review: return .purple
        case .failure: return .red
        case .running: return .orange
        case .success: return .green
        case .unknown: return .gray
        }
    }

    var nsColor: NSColor {
        switch self {
        case .review: return .systemPurple
        case .failure: return .systemRed
        case .running: return .systemOrange
        case .success: return .systemGreen
        case .unknown: return .systemGray
        }
    }

}

struct StatusBadge: View {
    let kind: StatusBadgeKind
    let count: Int
    let compact: Bool

    init(kind: StatusBadgeKind, count: Int, compact: Bool = false) {
        self.kind = kind
        self.count = count
        self.compact = compact
    }

    var body: some View {
        Text(String(count))
            .font(.system(size: compact ? 11 : 12, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(minWidth: compact ? 19 : 24, minHeight: compact ? 18 : 22)
            .padding(.horizontal, compact ? 2 : 4)
            .background(kind.color, in: Capsule())
            .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        switch kind {
        case .review: return "\(count) PR avec des commentaires non résolus"
        case .failure: return "\(count) PR en échec"
        case .running: return "\(count) PR en cours"
        case .success: return "\(count) PR réussie"
        case .unknown: return "\(count) PR avec état inconnu"
        }
    }
}

struct StatusSummaryView: View {
    let summary: StatusSummary
    var onSelect: ((CIStatus?) -> Void)?

    var body: some View {
        HStack(spacing: 5) {
            if summary.reviewsPending > 0 {
                StatusBadge(kind: .review, count: summary.reviewsPending)
            }
            badge(.failure, summary.failed, filter: .failure)
            badge(.running, summary.running, filter: .running)
            badge(.success, summary.passed, filter: .success)
            if summary.unknown > 0 {
                badge(.unknown, summary.unknown, filter: .unknown)
            }
        }
    }

    @ViewBuilder
    private func badge(_ kind: StatusBadgeKind, _ count: Int, filter: CIStatus) -> some View {
        if count > 0 {
            if let onSelect {
                Button { onSelect(filter) } label: {
                    StatusBadge(kind: kind, count: count)
                }
                .buttonStyle(.plain)
            } else {
                StatusBadge(kind: kind, count: count)
            }
        }
    }
}

final class StatusBadgesNSView: NSView {
    private struct BadgeItem {
        let text: String
        let color: NSColor
        let symbolName: String?
    }

    var summary = StatusSummary.empty {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    override var intrinsicContentSize: NSSize {
        let items = badgeItems
        var totalWidth: CGFloat = 0
        for item in items {
            totalWidth += width(of: item.text) + 12 + (item.symbolName == nil ? 0 : 14)
        }
        totalWidth += CGFloat(max(0, items.count - 1) * 4)
        return NSSize(width: max(totalWidth, 22), height: 22)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        var x: CGFloat = 0

        for item in badgeItems {
            let textWidth = width(of: item.text)
            let symbolWidth: CGFloat = item.symbolName == nil ? 0 : 14
            let pillRect = NSRect(x: x, y: 1, width: textWidth + symbolWidth + 12, height: 20)
            item.color.setFill()
            NSBezierPath(roundedRect: pillRect, xRadius: 10, yRadius: 10).fill()

            var textX = pillRect.minX + 6
            if let symbolName = item.symbolName,
               let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
                let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
                let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
                let configuredImage = image.withSymbolConfiguration(sizeConfiguration.applying(colorConfiguration)) ?? image
                configuredImage.draw(in: NSRect(x: textX, y: pillRect.minY + 5, width: 10, height: 10))
                textX += symbolWidth
            }

            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textRect = NSRect(
                x: textX,
                y: pillRect.minY + (pillRect.height - 13) / 2,
                width: textWidth,
                height: 15
            )
            (item.text as NSString).draw(in: textRect, withAttributes: attributes)
            x = pillRect.maxX + 4
        }
    }

    override func accessibilityIsIgnored() -> Bool { false }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        if summary.needsAuthentication { return "GitHub non connecté" }
        if summary.hasError { return "Erreur de synchronisation" }
        return "\(summary.failed) PR en échec, \(summary.running) en cours, \(summary.passed) réussies, \(summary.reviewsPending) avec des conversations non résolues"
    }

    private var badgeItems: [BadgeItem] {
        if summary.needsAuthentication || summary.hasError {
            return [BadgeItem(text: "!", color: StatusBadgeKind.unknown.nsColor, symbolName: nil)]
        }

        let items = [
            BadgeItem(text: String(summary.reviewsPending), color: StatusBadgeKind.review.nsColor, symbolName: "bubble.left.fill"),
            BadgeItem(text: String(summary.failed), color: StatusBadgeKind.failure.nsColor, symbolName: nil),
            BadgeItem(text: String(summary.running), color: StatusBadgeKind.running.nsColor, symbolName: nil),
            BadgeItem(text: String(summary.passed), color: StatusBadgeKind.success.nsColor, symbolName: nil),
            BadgeItem(text: String(summary.unknown), color: StatusBadgeKind.unknown.nsColor, symbolName: nil)
        ]
        let visible = items.filter { item in
            Int(item.text) ?? 0 > 0
        }
        return visible.isEmpty
            ? [BadgeItem(text: "0", color: StatusBadgeKind.unknown.nsColor, symbolName: nil)]
            : visible
    }

    private func width(of text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .bold)
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let badgeView: StatusBadgesNSView
    private let popover: NSPopover
    private var outsideClickMonitor: Any?
    private var githubSummary = StatusSummary.empty
    private var jiraConnectionState: ConnectionState = .needsAuthentication

    init(store: AppStore, jiraStore: JiraStore, demoMode: Bool = false) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        badgeView = StatusBadgesNSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        popover = NSPopover()
        super.init()

        if let button = statusItem.button {
            button.title = ""
            button.target = self
            button.action = #selector(statusItemClicked)
            badgeView.frame = button.bounds
            badgeView.autoresizingMask = [.width, .height]
            button.addSubview(badgeView)
        }

        popover.behavior = demoMode ? .applicationDefined : .transient
        popover.animates = true
        popover.delegate = self
        popover.contentSize = NSSize(width: 780, height: 600)
        let hostingController = NSHostingController(rootView: ContentView(store: store, jiraStore: jiraStore))
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hostingController

        store.$summary
            .receive(on: RunLoop.main)
            .sink { [weak self] summary in
                self?.githubSummary = summary
                self?.updateBadges()
            }
            .store(in: &cancellables)

        jiraStore.$connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                self?.jiraConnectionState = state
                self?.updateBadges()
            }
            .store(in: &cancellables)

        badgeView.summary = store.summary
        statusItem.length = badgeView.intrinsicContentSize.width
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func capturePopover(to path: String) {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        guard let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: URL(fileURLWithPath: path))
    }

    private func updateBadges() {
        var displaySummary = githubSummary
        displaySummary.hasError = displaySummary.hasError
            || jiraConnectionState == .error
            || jiraConnectionState == .stale
        badgeView.summary = displaySummary
        statusItem.length = badgeView.intrinsicContentSize.width
    }

    private var cancellables: Set<AnyCancellable> = []

    deinit {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
        }
    }

    @objc private func statusItemClicked() {
        if popover.isShown {
            popover.performClose(nil)
        } else if let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func popoverDidShow(_ notification: Notification) {
        guard let window = popover.contentViewController?.view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) {
            [weak self] _ in
            DispatchQueue.main.async {
                self?.popover.performClose(nil)
            }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
