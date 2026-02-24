import UIKit
import UserNotifications
import FirebaseCore

class AppDelegate: NSObject, UIApplicationDelegate {
    nonisolated func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureFirebase()
        return true
    }

    private nonisolated func configureFirebase() {
        guard FirebaseConfig.isConfigured else { return }

        let options = FirebaseOptions(
            googleAppID: FirebaseConfig.appID,
            gcmSenderID: FirebaseConfig.gcmSenderID
        )
        options.apiKey = FirebaseConfig.apiKey
        options.projectID = FirebaseConfig.projectID

        let clientID = Config.GOOGLE_CLIENT_ID
        if !clientID.isEmpty, clientID != "GOOGLE_CLIENT_ID" {
            options.clientID = clientID
        }

        FirebaseApp.configure(options: options)
    }

    nonisolated func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleDeviceToken(deviceToken)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleRegistrationError(error)
        }
    }

    nonisolated func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            PushNotificationService.shared.handleNotification(userInfo, completionHandler: completionHandler)
        }
    }
}
