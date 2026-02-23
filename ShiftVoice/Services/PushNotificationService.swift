import Foundation
import UserNotifications
import UIKit

@Observable
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    var isAuthorized: Bool = false
    var deviceToken: String?
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let notificationCenter = UNUserNotificationCenter.current()
    private let api = APIService.shared

    private override init() {
        super.init()
    }

    func setup() {
        notificationCenter.delegate = self
        checkAuthorizationStatus()
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .badge, .sound])
            isAuthorized = granted
            if granted {
                await registerForRemoteNotifications()
            }
            await checkAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    func checkAuthorizationStatus() {
        Task {
            let settings = await notificationCenter.notificationSettings()
            authorizationStatus = settings.authorizationStatus
            isAuthorized = settings.authorizationStatus == .authorized
            if isAuthorized {
                await registerForRemoteNotifications()
            }
        }
    }

    private func registerForRemoteNotifications() async {
        await UIApplication.shared.registerForRemoteNotifications()
    }

    func handleDeviceToken(_ tokenData: Data) {
        let token = tokenData.map { String(format: "%02.2hhx", $0) }.joined()
        deviceToken = token
        sendTokenToServer(token)
    }

    func handleRegistrationError(_ error: Error) {
        deviceToken = nil
    }

    private func sendTokenToServer(_ token: String) {
        guard api.isConfigured else { return }
        Task {
            do {
                _ = try await api.registerDeviceToken(token)
            } catch {
                // Silently fail — will retry on next app launch
            }
        }
    }

    func handleNotification(_ userInfo: [AnyHashable: Any], completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if let noteId = userInfo["noteId"] as? String {
            NotificationCenter.default.post(
                name: .pushNotificationReceived,
                object: nil,
                userInfo: ["noteId": noteId]
            )
        }
        completionHandler(.newData)
    }

    func scheduleLocalNotification(title: String, body: String, noteId: String? = nil, delay: TimeInterval = 0) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        if let noteId {
            content.userInfo = ["noteId": noteId]
        }

        let trigger: UNNotificationTrigger?
        if delay > 0 {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        } else {
            trigger = nil
        }

        let request = UNNotificationRequest(
            identifier: noteId ?? UUID().uuidString,
            content: content,
            trigger: trigger
        )

        notificationCenter.add(request)
    }

    func clearBadge() {
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    func removeAllDelivered() {
        notificationCenter.removeAllDeliveredNotifications()
    }
}

extension PushNotificationService: @preconcurrency UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .badge, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            if let noteId = userInfo["noteId"] as? String {
                NotificationCenter.default.post(
                    name: .pushNotificationTapped,
                    object: nil,
                    userInfo: ["noteId": noteId]
                )
            }
        }
        completionHandler()
    }
}

extension Notification.Name {
    static let pushNotificationReceived = Notification.Name("pushNotificationReceived")
    static let pushNotificationTapped = Notification.Name("pushNotificationTapped")
}
