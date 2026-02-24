import Foundation

enum FirebaseConfig {
    static let apiKey = "FIREBASE_API_KEY"
    static let projectID = "FIREBASE_PROJECT_ID"
    static let appID = "FIREBASE_APP_ID"
    static let gcmSenderID = "FIREBASE_GCM_SENDER_ID"

    static var isConfigured: Bool {
        !apiKey.isEmpty && apiKey != "FIREBASE_API_KEY" &&
        !projectID.isEmpty && projectID != "FIREBASE_PROJECT_ID" &&
        !appID.isEmpty && appID != "FIREBASE_APP_ID" &&
        !gcmSenderID.isEmpty && gcmSenderID != "FIREBASE_GCM_SENDER_ID"
    }
}
