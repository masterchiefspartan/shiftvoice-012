import Foundation

nonisolated enum PaywallTriggerReason: String, Hashable, Sendable {
    case recordingLimitReached
    case manualUpgrade
    case unknown
}
