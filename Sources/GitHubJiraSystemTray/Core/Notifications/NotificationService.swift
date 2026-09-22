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
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            guard granted else {
                deliveryMode = .disabled
                return nil
            }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                deliveryMode = .disabled
                return nil
            }
            return nil
        } catch {
            deliveryMode = .disabled
            return nil
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
