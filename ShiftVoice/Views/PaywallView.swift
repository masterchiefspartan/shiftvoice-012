import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var offerings: Offerings?
    @State private var isLoading: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var selectedBilling: BillingPeriod = .annual
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var purchaseSuccess: Bool = false
    @State private var subscriptionsUnavailable: Bool = false
    @State private var isUsingFallbackPrices: Bool = false
    @State private var isRefreshingOfferings: Bool = false
    @State private var fallbackPriceMessage: String = "Prices may vary. Pull to refresh."

    private let subscription = SubscriptionService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                SVTheme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(SVTheme.accent)
                } else if subscriptionsUnavailable {
                    unavailableView
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            headerSection
                            if isUsingFallbackPrices {
                                fallbackPricingBanner
                            }
                            billingToggle
                            planCard
                            featuresSection
                            ctaButton
                            restoreButton
                            legalText
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
                    }
                    .refreshable {
                        await refreshOfferings()
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .frame(width: 32, height: 32)
                            .background(SVTheme.iconBackground)
                            .clipShape(Circle())
                    }
                }
            }
            .alert("Something went wrong", isPresented: $showError) {
                Button("OK") {}
            } message: {
                Text(errorMessage)
            }
            .onChange(of: purchaseSuccess) { _, success in
                if success { dismiss() }
            }
        }
        .task {
            await fetchOfferings()
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Text("Your first note is already structured and waiting in your feed. ✓")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(SVTheme.accentGreen)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(SVTheme.accentGreen.opacity(0.08))
                .clipShape(Capsule())

            Text("Keep your operations running.")
                .font(.system(size: 28, weight: .bold, design: .serif))
                .foregroundStyle(SVTheme.textPrimary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingOption(period: .monthly, label: "Monthly")
            billingOption(period: .annual, label: "Annual")
        }
        .padding(3)
        .background(SVTheme.surfaceSecondary)
        .clipShape(.rect(cornerRadius: 10))
    }

    private func billingOption(period: BillingPeriod, label: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.2)) {
                selectedBilling = period
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(selectedBilling == period ? SVTheme.textPrimary : SVTheme.textTertiary)
                if period == .annual {
                    Text("Save $189")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(SVTheme.successGreen)
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedBilling == period ? SVTheme.cardBackground : .clear)
            .clipShape(.rect(cornerRadius: 8))
            .shadow(color: selectedBilling == period ? .black.opacity(0.04) : .clear, radius: 4, y: 2)
        }
    }

    private var planCard: some View {
        VStack(spacing: 16) {
            Text("ShiftVoice Pro")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SVTheme.accent)
                .tracking(0.5)
                .textCase(.uppercase)

            if selectedBilling == .annual {
                VStack(spacing: 4) {
                    Text("\(annualPrice)/year ($33/mo)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(SVTheme.textPrimary)
                    Text("\(monthlyPrice)/month")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SVTheme.textSecondary)
                }
            } else {
                VStack(spacing: 4) {
                    Text("\(monthlyPrice)/month")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(SVTheme.textPrimary)
                    Button {
                        withAnimation(.spring(duration: 0.2)) {
                            selectedBilling = .annual
                        }
                    } label: {
                        Text("Save $189/year with annual →")
                            .font(.caption)
                            .foregroundStyle(SVTheme.accent)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SVTheme.accent.opacity(0.2), lineWidth: 1.5)
        )
    }

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.accentGreen)

                    Text(feature)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SVTheme.textPrimary)

                    Spacer()
                }
                .padding(.vertical, 11)

                if index < features.count - 1 {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 32)
                }
            }
        }
        .padding(.horizontal, 16)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var ctaButton: some View {
        Button {
            Task { await handlePurchase() }
        } label: {
            HStack(spacing: 8) {
                if isPurchasing {
                    ProgressView()
                        .tint(.white)
                } else {
                    Text("Start 7-Day Free Trial")
                        .font(.headline)
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(SVTheme.accent)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(color: SVTheme.accent.opacity(0.3), radius: 12, y: 6)
        }
        .disabled(isPurchasing)
        .sensoryFeedback(.impact(weight: .medium), trigger: isPurchasing)
    }

    private var restoreButton: some View {
        HStack(spacing: 16) {
            Button {
                Task { await handleRestore() }
            } label: {
                Text("Restore purchase")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SVTheme.textSecondary)
            }

            Button {
                if let url = URL(string: "https://shiftvoice.app/terms") {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Terms of Service / Privacy Policy")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SVTheme.textSecondary)
            }
        }
    }

    private var legalText: some View {
        Text("No charge for 7 days. Cancel anytime in Settings.")
            .font(.system(size: 12))
            .foregroundStyle(SVTheme.textTertiary)
            .multilineTextAlignment(.center)
    }

    private let features: [String] = [
        "Unlimited voice notes",
        "AI-powered structuring",
        "Shift handoff reports",
        "@Mentions & escalation",
        "Action item tracking",
        "Unlimited team members",
        "Offline mode — works anywhere",
        "Full access, no limits"
    ]

    private var monthlyPrice: String {
        if let pkg = monthlyPackage {
            return pkg.storeProduct.localizedPriceString
        }
        return "$49.00"
    }

    private var annualPrice: String {
        if let pkg = annualPackage {
            return pkg.storeProduct.localizedPriceString
        }
        return "$399.00"
    }

    private var monthlyPackage: Package? {
        if let byIdentifier = offerings?.current?.package(identifier: "monthly") {
            return byIdentifier
        }
        return offerings?.current?.availablePackages.first(where: { $0.storeProduct.productIdentifier == "shiftvoice_pro_monthly" })
    }

    private var annualPackage: Package? {
        if let byIdentifier = offerings?.current?.package(identifier: "annual") {
            return byIdentifier
        }
        return offerings?.current?.availablePackages.first(where: { $0.storeProduct.productIdentifier == "shiftvoice_pro_annual" })
    }

    private var selectedPackage: Package? {
        selectedBilling == .annual ? annualPackage : monthlyPackage
    }

    private var fallbackPricingBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.amber)

            Text(fallbackPriceMessage)
                .font(.caption.weight(.medium))
                .foregroundStyle(SVTheme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await refreshOfferings() }
            } label: {
                if isRefreshingOfferings {
                    ProgressView()
                        .controlSize(.small)
                        .tint(SVTheme.accent)
                } else {
                    Text("Retry")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
            .disabled(isRefreshingOfferings)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(SVTheme.amber.opacity(0.08))
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(SVTheme.amber.opacity(0.25), lineWidth: 1)
        )
    }

    private var unavailableView: some View {
        VStack(spacing: 20) {
            Image(systemName: "cart.badge.questionmark")
                .font(.system(size: 48))
                .foregroundStyle(SVTheme.textTertiary)
            Text("Subscriptions Unavailable")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SVTheme.textPrimary)
            Text("In-app purchases are not available at this time. Please try again later.")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Close") { dismiss() }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(SVTheme.accent)
                .clipShape(.rect(cornerRadius: 14))
                .padding(.horizontal, 32)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fetchOfferings() async {
        isLoading = true
        defer { isLoading = false }

        do {
            offerings = try await subscription.fetchOfferings()
            subscriptionsUnavailable = false
            isUsingFallbackPrices = false
            fallbackPriceMessage = "Prices may vary. Pull to refresh."
        } catch is SubscriptionServiceError {
            subscriptionsUnavailable = true
            isUsingFallbackPrices = false
        } catch {
            isUsingFallbackPrices = true
            fallbackPriceMessage = "Prices may vary. Pull to refresh."
        }
    }

    private func refreshOfferings() async {
        guard !isRefreshingOfferings else { return }
        isRefreshingOfferings = true
        defer { isRefreshingOfferings = false }

        do {
            offerings = try await subscription.fetchOfferings()
            subscriptionsUnavailable = false
            isUsingFallbackPrices = false
        } catch is SubscriptionServiceError {
            subscriptionsUnavailable = true
            isUsingFallbackPrices = false
        } catch {
            isUsingFallbackPrices = true
            fallbackPriceMessage = "Still using fallback prices. Pull to refresh again."
        }
    }

    private func handlePurchase() async {
        guard let package = selectedPackage else {
            errorMessage = "Unable to load this plan. Please try again."
            showError = true
            return
        }

        isPurchasing = true
        do {
            let success = try await subscription.purchase(package: package)
            if success {
                purchaseSuccess = true
            }
        } catch {
            if let rcError = error as? RevenueCat.ErrorCode, rcError == .purchaseCancelledError {
            } else {
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        isPurchasing = false
    }

    private func handleRestore() async {
        isPurchasing = true
        do {
            try await subscription.restorePurchases()
            if subscription.isProUser {
                purchaseSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }
}

private enum BillingPeriod {
    case monthly, annual
}
