import Foundation
import RevenueCat

nonisolated enum SubscriptionTier: String, Sendable {
    case free
    case pro
    case team
}

nonisolated enum SubscriptionServiceError: Error, LocalizedError, Sendable {
    case notConfigured

    var errorDescription: String? {
        "Subscriptions are temporarily unavailable. Please try again later."
    }
}

@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    var currentTier: SubscriptionTier = .free
    var isProUser: Bool { currentTier == .pro || currentTier == .team }
    var isTeamUser: Bool { currentTier == .team }

    var hasTrialStarted: Bool = false
    var isInTrial: Bool = false

    private let freeMonthlyNoteLimit = 5
    private let proAccessEntitlementId = "pro_access"
    private let proEntitlementId = "pro"
    private let teamEntitlementId = "team"

    private var isConfigured: Bool = false

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
        isConfigured = true
    }

    private static func configValue(_ key: String) -> String? {
        let value: String
        switch key {
        case "EXPO_PUBLIC_REVENUECAT_TEST_API_KEY":
            value = Config.EXPO_PUBLIC_REVENUECAT_TEST_API_KEY
        case "EXPO_PUBLIC_REVENUECAT_IOS_API_KEY":
            value = Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY
        default:
            return nil
        }
        return value.isEmpty ? nil : value
    }

    func setUserId(_ userId: String) {
        guard !userId.isEmpty, isConfigured else { return }
        Task {
            do {
                let (_, _) = try await Purchases.shared.logIn(userId)
                await refreshStatus()
            } catch {}
        }
    }

    func refreshStatus() async {
        guard isConfigured else { return }
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateTier(from: customerInfo)
        } catch {}
    }

    func fetchOfferings() async throws -> Offerings {
        guard isConfigured else {
            throw SubscriptionServiceError.notConfigured
        }
        return try await Purchases.shared.offerings()
    }

    func purchase(package: Package) async throws -> Bool {
        guard isConfigured else {
            throw SubscriptionServiceError.notConfigured
        }
        let result = try await Purchases.shared.purchase(package: package)
        updateTier(from: result.customerInfo)
        return isProUser
    }

    func restorePurchases() async throws {
        guard isConfigured else {
            throw SubscriptionServiceError.notConfigured
        }
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

    var correspondingPlan: SubscriptionPlan {
        switch currentTier {
        case .free: return .free
        case .pro: return .professional
        case .team: return .enterprise
        }
    }

    private func updateTier(from customerInfo: CustomerInfo) {
        let proAccess = customerInfo.entitlements[proAccessEntitlementId]
        let proLegacy = customerInfo.entitlements[proEntitlementId]
        let teamAccess = customerInfo.entitlements[teamEntitlementId]

        let activeEntitlement = proAccess?.isActive == true ? proAccess
            : proLegacy?.isActive == true ? proLegacy
            : teamAccess?.isActive == true ? teamAccess
            : nil

        if let activeEntitlement {
            if teamAccess?.isActive == true {
                currentTier = .team
            } else {
                currentTier = .pro
            }
            hasTrialStarted = true
            isInTrial = activeEntitlement.periodType == .trial
        } else {
            currentTier = .free
            let anyEntitlement = proAccess ?? proLegacy ?? teamAccess
            hasTrialStarted = anyEntitlement != nil
            isInTrial = false
        }
    }
}
