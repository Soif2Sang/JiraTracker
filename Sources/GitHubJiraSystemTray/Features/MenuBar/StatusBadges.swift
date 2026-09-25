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
    struct BadgeItem {
        let text: String
        let color: NSColor
        let symbolName: String?
    }

    var style: BadgeDisplayStyle = .full {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    var summary = StatusSummary.empty {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    /// Explicit items used by the demo preview; when nil the items are derived from `summary`.
    var overrideItems: [BadgeItem]? {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private let barHeight: CGFloat = 22

    private var items: [BadgeItem] {
        overrideItems ?? Self.items(for: summary)
    }

    override var intrinsicContentSize: NSSize {
        let total = items.map(itemWidth).reduce(0, +) + CGFloat(max(0, items.count - 1)) * spacing
        return NSSize(width: max(ceil(total), 24), height: barHeight)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        var x: CGFloat = 0
        for item in items {
            let width = itemWidth(item)
            switch style {
            case .full: drawFull(item, x: x, width: width)
            case .compact: drawCompact(item, x: x, width: width)
            case .minimal: drawMinimal(item, x: x, width: width)
            }
            x += width + spacing
        }
    }

    override func accessibilityIsIgnored() -> Bool { false }

    override func accessibilityRole() -> NSAccessibility.Role? { .button }

    override func accessibilityLabel() -> String? {
        if summary.needsAuthentication { return "GitHub non connecté" }
        if summary.hasError { return "Erreur de synchronisation" }
        return "\(summary.jiraWithoutPR) tickets sans PR, \(summary.passed) PR réussies, \(summary.running) en cours, \(summary.failed) en échec, \(summary.reviewsPending) avec des conversations non résolues, \(summary.reviewerPending) à reviewer"
    }

    static func items(for summary: StatusSummary) -> [BadgeItem] {
        if summary.needsAuthentication || summary.hasError {
            return [BadgeItem(text: "!", color: .systemGray, symbolName: "exclamationmark.triangle.fill")]
        }

        var items: [BadgeItem] = []
        func add(_ count: Int, _ color: NSColor, _ symbol: String?) {
            guard count > 0 else { return }
            items.append(BadgeItem(text: String(count), color: color, symbolName: symbol))
        }
        add(summary.jiraWithoutPR, .systemBlue, "link")
        add(summary.passed, .systemGreen, "checkmark")
        add(summary.running, .systemOrange, "arrow.triangle.2.circlepath")
        add(summary.failed, .systemRed, "xmark")
        add(summary.reviewsPending, .systemPurple, "bubble.left.fill")
        add(summary.unknown, .systemGray, "questionmark")
        add(summary.reviewerPending, .systemIndigo, "eye.fill")

        return items.isEmpty
            ? [BadgeItem(text: "0", color: .systemGray, symbolName: nil)]
            : items
    }

    private var spacing: CGFloat {
        switch style {
        case .full: return 4
        case .compact: return 4
        case .minimal: return 7
        }
    }

    private func itemWidth(_ item: BadgeItem) -> CGFloat {
        let textWidth = Self.width(of: item.text)
        switch style {
        case .full:
            return 6 + 16 + 5 + textWidth + 9
        case .compact:
            return textWidth + 14
        case .minimal:
            return 10 + 6 + textWidth
        }
    }

    private func drawFull(_ item: BadgeItem, x: CGFloat, width: CGFloat) {
        let rect = NSRect(x: x, y: 1, width: width, height: barHeight - 2)
        item.color.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()

        let diameter: CGFloat = 16
        let circle = NSRect(x: rect.minX + 4, y: rect.midY - diameter / 2, width: diameter, height: diameter)
        item.color.setFill()
        NSBezierPath(ovalIn: circle).fill()
        if let symbolName = item.symbolName {
            let inset: CGFloat = symbolName.contains("eye") ? 2.5 : 3.5
            drawSymbol(symbolName, in: circle.insetBy(dx: inset, dy: inset))
        }
        drawText(item.text, x: circle.maxX + 5, centerY: rect.midY, fontSize: 12)
    }

    private func drawCompact(_ item: BadgeItem, x: CGFloat, width: CGFloat) {
        let height: CGFloat = 16
        let rect = NSRect(x: x, y: (barHeight - height) / 2, width: width, height: height)
        item.color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
        drawText(item.text, x: rect.minX + 7, centerY: rect.midY, fontSize: 11)
    }

    private func drawMinimal(_ item: BadgeItem, x: CGFloat, width: CGFloat) {
        let diameter: CGFloat = 9
        let dot = NSRect(x: x, y: (barHeight - diameter) / 2, width: diameter, height: diameter)
        item.color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        drawText(item.text, x: dot.maxX + 6, centerY: dot.midY, fontSize: 12)
    }

    private func drawText(_ text: String, x: CGFloat, centerY: CGFloat, fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        let rect = NSRect(x: x, y: centerY - size.height / 2, width: size.width + 1, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawSymbol(_ name: String, in rect: NSRect) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return }
        let sizeConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        let colorConfiguration = NSImage.SymbolConfiguration(paletteColors: [.white])
        let configured = image.withSymbolConfiguration(sizeConfiguration.applying(colorConfiguration)) ?? image
        configured.draw(in: rect)
    }

    static func width(of text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold)
        ]
        return ceil((text as NSString).size(withAttributes: attributes).width)
    }
}

@MainActor
enum BadgePreviewRenderer {
    struct Entry {
        let label: String
        let items: [StatusBadgesNSView.BadgeItem]
        let style: BadgeDisplayStyle
    }

    static func sheet(
        _ entries: [Entry],
        scale: CGFloat = 3,
        labelWidth: CGFloat = 112,
        gap: CGFloat = 10,
        padding: CGFloat = 18,
        background: NSColor = NSColor(calibratedWhite: 0.10, alpha: 1)
    ) -> Data? {
        let views = entries.map { entry -> StatusBadgesNSView in
            let view = StatusBadgesNSView(frame: .zero)
            view.overrideItems = entry.items
            view.style = entry.style
            return view
        }
        let sizes = views.map(\.intrinsicContentSize)
        let rowHeight = sizes.map(\.height).max() ?? 22
        let maxWidth = sizes.map(\.width).max() ?? 24
        let canvas = NSSize(
            width: labelWidth + maxWidth + padding * 2,
            height: CGFloat(entries.count) * rowHeight + CGFloat(max(0, entries.count - 1)) * gap + padding * 2
        )
        let pixelWidth = Int((canvas.width * scale).rounded())
        let pixelHeight = Int((canvas.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        rep.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        background.setFill()
        NSRect(origin: .zero, size: canvas).fill()

        let labelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.75, alpha: 1)
        ]

        for (index, entry) in entries.enumerated() {
            let y = canvas.height - padding - CGFloat(index + 1) * rowHeight - CGFloat(index) * gap
            let labelSize = (entry.label as NSString).size(withAttributes: labelAttributes)
            (entry.label as NSString).draw(
                at: NSPoint(x: padding, y: y + (rowHeight - labelSize.height) / 2),
                withAttributes: labelAttributes
            )

            context.cgContext.saveGState()
            context.cgContext.translateBy(x: padding + labelWidth, y: y)
            let view = views[index]
            view.frame = NSRect(origin: .zero, size: sizes[index])
            view.draw(view.bounds)
            context.cgContext.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
    }

    static func pngData(
        items: [StatusBadgesNSView.BadgeItem],
        style: BadgeDisplayStyle,
        scale: CGFloat = 3,
        padding: CGFloat = 14,
        background: NSColor = NSColor(calibratedWhite: 0.11, alpha: 1)
    ) -> Data? {
        let view = StatusBadgesNSView(frame: .zero)
        view.overrideItems = items
        view.style = style
        let size = view.intrinsicContentSize
        let canvas = NSSize(width: size.width + padding * 2, height: size.height + padding * 2)
        let pixelWidth = Int((canvas.width * scale).rounded())
        let pixelHeight = Int((canvas.height * scale).rounded())
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelWidth,
            pixelsHigh: pixelHeight,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ), let context = NSGraphicsContext(bitmapImageRep: rep) else {
            return nil
        }

        rep.size = canvas
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.scaleBy(x: scale, y: scale)
        background.setFill()
        NSRect(origin: .zero, size: canvas).fill()
        context.cgContext.translateBy(x: padding, y: padding)
        view.frame = NSRect(origin: .zero, size: size)
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()

        return rep.representation(using: .png, properties: [:])
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
    private var jiraIssues: [JiraIssue] = []
    private(set) var displaySummary = StatusSummary.empty

    private let appStore: AppStore
    private let jiraStore: JiraStore
    private let demoMode: Bool
    private var reviewerPending = 0
    private var isEvaluatingReviewer = false
    private var reviewerReevaluationNeeded = false
    private static let demoReviewerCount = 2

    init(store: AppStore, jiraStore: JiraStore, theme: ThemeStore, badgeStyle: BadgeStyleStore, demoMode: Bool = false) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        badgeView = StatusBadgesNSView(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        popover = NSPopover()
        appStore = store
        self.jiraStore = jiraStore
        self.demoMode = demoMode
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
        let hostingController = NSHostingController(rootView: ContentView(store: store, jiraStore: jiraStore, theme: theme))
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

        store.$mergedPullRequests
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateBadges()
            }
            .store(in: &cancellables)

        jiraStore.$issues
            .receive(on: RunLoop.main)
            .sink { [weak self] issues in
                self?.jiraIssues = issues
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

        badgeStyle.$style
            .receive(on: RunLoop.main)
            .sink { [weak self] style in
                self?.badgeView.style = style
                self?.statusItem.length = self?.badgeView.intrinsicContentSize.width ?? NSStatusItem.variableLength
            }
            .store(in: &cancellables)

        badgeView.style = badgeStyle.style
        githubSummary = store.summary
        jiraIssues = jiraStore.issues
        updateBadges()
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func showSettings() {
        if !popover.isShown, let button = statusItem.button {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .openSettingsRoute, object: nil)
        }
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
        applySummary()
        scheduleReviewerEvaluation()
    }

    private func applySummary() {
        var summary = githubSummary
        summary.jiraWithoutPR = jiraWithoutPRCount
        summary.reviewerPending = demoMode ? Self.demoReviewerCount : reviewerPending
        summary.hasError = summary.hasError
            || jiraConnectionState == .error
            || jiraConnectionState == .stale
        displaySummary = summary
        badgeView.summary = summary
        statusItem.length = badgeView.intrinsicContentSize.width
    }

    /// Counts "To Review" tickets where I am the Code Reviewer and my review is actionable:
    /// either I have not reviewed yet, or all of my threads have been resolved.
    private func scheduleReviewerEvaluation() {
        guard !demoMode else { return }
        guard let login = appStore.githubUserLogin, jiraStore.currentAccountId != nil else {
            resetReviewerCount()
            return
        }
        let tickets = jiraStore.reviewerIssues()
        guard !tickets.isEmpty else {
            resetReviewerCount()
            return
        }
        if isEvaluatingReviewer {
            reviewerReevaluationNeeded = true
            return
        }
        isEvaluatingReviewer = true

        Task { [weak self] in
            var count = 0
            for ticket in tickets {
                if Task.isCancelled { break }
                guard let self else { return }
                let linked = await self.jiraStore.linkedPullRequests(for: ticket)
                guard let reference = linked.compactMap({ GitHubPullReference(url: $0.url) }).first else {
                    continue
                }
                if let state = await self.appStore.reviewThreadState(for: reference, login: login),
                   state.isActionable {
                    count += 1
                }
            }
            await MainActor.run {
                guard let self else { return }
                self.isEvaluatingReviewer = false
                if self.reviewerPending != count {
                    self.reviewerPending = count
                    self.applySummary()
                }
                if self.reviewerReevaluationNeeded {
                    self.reviewerReevaluationNeeded = false
                    self.scheduleReviewerEvaluation()
                }
            }
        }
    }

    private func resetReviewerCount() {
        guard reviewerPending != 0 else { return }
        reviewerPending = 0
        applySummary()
    }

    /// Open Jira tickets that are not linked to any tracked pull request.
    private var jiraWithoutPRCount: Int {
        let pullRequests = appStore.allPullRequests
        return jiraIssues.filter { issue in
            TicketPRLinker.pullRequests(for: issue.key, in: pullRequests).isEmpty
        }.count
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
        refreshIfStale()
    }

    /// Refresh on open so the popover never shows stale CI statuses (e.g. an "unknown"
    /// workflow run that started after the last poll).
    private func refreshIfStale() {
        let threshold: TimeInterval = 15
        let now = Date()
        if appStore.lastUpdated.map({ now.timeIntervalSince($0) > threshold }) ?? true {
            appStore.refreshNow()
        }
        if jiraStore.lastUpdated.map({ now.timeIntervalSince($0) > threshold }) ?? true {
            jiraStore.refreshNow()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }
}
