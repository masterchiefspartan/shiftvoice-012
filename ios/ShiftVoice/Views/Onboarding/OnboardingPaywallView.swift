import SwiftUI
import RevenueCat

struct OnboardingPaywallView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onSkip: () -> Void
    let onPurchaseSuccess: () -> Void

    @State private var selectedBilling: OnboardingBillingPeriod = .annual
    @State private var offerings: Offerings?
    @State private var isPurchasing: Bool = false
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var appeared: Bool = false

    private let subscription = SubscriptionService.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 8)

                hookSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 16)

                billingToggle
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                planCard
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)

                featuresSection
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 12)
                    .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                ctaSection
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)

                skipSection
                    .opacity(appeared ? 1 : 0)
                    .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
        .background(SVTheme.background)
        .task {
            await fetchOfferings()
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
        .alert("Something went wrong", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage)
        }
    }

    private var hookSection: some View {
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

    private func billingOption(period: OnboardingBillingPeriod, label: String) -> some View {
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

    private var ctaSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await handlePurchase() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Start 7-Day Free Trial")
                            .font(.system(size: 16, weight: .semibold))
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

            Text("No charge for 7 days. Cancel anytime in Settings.")
                .font(.system(size: 12))
                .foregroundStyle(SVTheme.textTertiary)
                .multilineTextAlignment(.center)

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
    }

    private var skipSection: some View {
        Button {
            onSkip()
        } label: {
            Text("Maybe later")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SVTheme.textTertiary)
                .underline()
        }
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

    private func fetchOfferings() async {
        do {
            offerings = try await subscription.fetchOfferings()
        } catch {}
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
                onPurchaseSuccess()
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
                onPurchaseSuccess()
            }
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
        isPurchasing = false
    }
}

private enum OnboardingBillingPeriod {
    case monthly, annual
}
