import Foundation
import RevenueCat

nonisolated enum SubscriptionTier: String, Sendable {
    case free
    case pro
    case team
}

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    var currentTier: SubscriptionTier = .free
    var isProUser: Bool { currentTier == .pro || currentTier == .team }
    var isTeamUser: Bool { currentTier == .team }

    private let freeMonthlyNoteLimit = 5
    private let proEntitlementId = "pro"
    private let teamEntitlementId = "team"

    private init() {}

    func configure() {
        let apiKey: String
        #if DEBUG
        Purchases.logLevel = .debug
        apiKey = Self.configValue("EXPO_PUBLIC_REVENUECAT_TEST_API_KEY")
            ?? Self.configValue("EXPO_PUBLIC_REVENUECAT_IOS_API_KEY")
            ?? ""
        #else
        apiKey = Self.configValue("EXPO_PUBLIC_REVENUECAT_IOS_API_KEY")
            ?? Self.configValue("EXPO_PUBLIC_REVENUECAT_TEST_API_KEY")
            ?? ""
        #endif

        guard !apiKey.isEmpty else { return }
        Purchases.configure(withAPIKey: apiKey)
    }

    private static func configValue(_ key: String) -> String? {
        let mirror = Mirror(reflecting: Config.self as Any)
        for child in mirror.children {
            if child.label == key, let val = child.value as? String, !val.isEmpty {
                return val
            }
        }
        return nil
    }

    func setUserId(_ userId: String) {
        guard !userId.isEmpty else { return }
        Task {
            do {
                let (_, _) = try await Purchases.shared.logIn(userId)
                await refreshStatus()
            } catch {}
        }
    }

    func refreshStatus() async {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateTier(from: customerInfo)
        } catch {}
    }

    func purchase(package: Package) async throws -> Bool {
        let result = try await Purchases.shared.purchase(package: package)
        updateTier(from: result.customerInfo)
        return isProUser
    }

    func restorePurchases() async throws {
        let customerInfo = try await Purchases.shared.restorePurchases()
        updateTier(from: customerInfo)
    }

    func canRecordNote(currentMonthNoteCount: Int) -> Bool {
        if isProUser { return true }
        return currentMonthNoteCount < freeMonthlyNoteLimit
    }

    var remainingFreeNotes: Int {
        freeMonthlyNoteLimit
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        if customerInfo.entitlements[teamEntitlementId]?.isActive == true {
            currentTier = .team
        } else if customerInfo.entitlements[proEntitlementId]?.isActive == true {
            currentTier = .pro
        } else {
            currentTier = .free
        }
    }
}
