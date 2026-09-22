import Foundation
import AppKit
import UserNotifications

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    private enum DeliveryMode {
        case modern
        case disabled
    }

    private var hasComparedInitialSnapshot = false
    private var deliveryMode = DeliveryMode.modern

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() async -> String? {
        let center = UNUserNotificationCenter.current()
        let currentSettings = await center.notificationSettings()

        switch currentSettings.authorizationStatus {
        case .authorized, .provisional:
            deliveryMode = .modern
            return nil
        case .denied:
            deliveryMode = .disabled
            return "Les notifications sont désactivées dans les réglages macOS."
        case .notDetermined:
            await MainActor.run {
                NSApplication.shared.activate(ignoringOtherApps: true)
            }
        case .ephemeral:
            deliveryMode = .modern
            return nil
        @unknown default:
            break
        }

        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else {
                deliveryMode = .disabled
                return "L'autorisation d'envoyer des notifications a été refusée."
            }
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                deliveryMode = .disabled
                return "Les notifications sont désactivées dans les réglages macOS."
            }
            deliveryMode = .modern
            return nil
        } catch {
            deliveryMode = .disabled
            return "Impossible d'activer les notifications : \(error.localizedDescription)"
        }
    }

    func sendTestNotification() {
        send(
            identifier: "test-notification",
            title: "Notifications activées",
            body: "GitHub Jira Tracker pourra vous prévenir des commentaires et CI en échec.",
            url: URL(string: "https://github.com")!
        )
    }

    func notifyChanges(from old: [TrackedPullRequest], to new: [TrackedPullRequest]) {
        let oldByID = Dictionary(uniqueKeysWithValues: old.map { ($0.id, $0) })

        guard hasComparedInitialSnapshot else {
            hasComparedInitialSnapshot = true
            return
        }

        for pullRequest in new {
            guard let previous = oldByID[pullRequest.id] else { continue }
            let previousStatus = previous.ciStatus
            let currentStatus = pullRequest.ciStatus

            if let latestCommentAt = pullRequest.latestReviewCommentAt,
               previous.latestReviewCommentAt.map({ latestCommentAt > $0 })
                    ?? (pullRequest.unresolvedReviewThreadCount > previous.unresolvedReviewThreadCount) {
                send(
                    identifier: "review-\(pullRequest.id)-\(Int(latestCommentAt.timeIntervalSince1970))",
                    title: "Nouveau commentaire sur la PR",
                    body: "\(pullRequest.repository) #\(pullRequest.number) - \(pullRequest.title)",
                    url: pullRequest.url
                )
            }

            if currentStatus == .failure,
               previousStatus != .failure || previous.headSHA != pullRequest.headSHA {
                send(
                    identifier: "ci-failure-\(pullRequest.id)-\(pullRequest.headSHA)",
                    title: "CI en échec",
                    body: "\(pullRequest.repository) #\(pullRequest.number) - \(pullRequest.title)",
                    url: pullRequest.url
                )
            } else if currentStatus == .success, previousStatus == .failure {
                send(
                    identifier: "ci-success-\(pullRequest.id)-\(pullRequest.headSHA)",
                    title: "CI revenue au vert",
                    body: "\(pullRequest.repository) #\(pullRequest.number) - \(pullRequest.title)",
                    url: pullRequest.url
                )
            }
        }
    }

    func resetComparison() {
        hasComparedInitialSnapshot = false
    }

    private func send(identifier: String, title: String, body: String, url: URL) {
        guard deliveryMode == .modern else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                NSLog("GitHub Jira Tracker notification error: %@", error.localizedDescription)
            }
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard let value = response.notification.request.content.userInfo["url"] as? String,
              let url = URL(string: value) else { return }
        _ = await MainActor.run {
            NSWorkspace.shared.open(url)
        }
    }

}
