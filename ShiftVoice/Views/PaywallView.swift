import SwiftUI
import RevenueCat

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var offerings: Offerings?
    @State private var isLoading: Bool = true
    @State private var isPurchasing: Bool = false
    @State private var selectedPlanType: PlanType = .pro
    @State private var selectedBilling: BillingPeriod = .annual
    @State private var showError: Bool = false
    @State private var errorMessage: String = ""
    @State private var purchaseSuccess: Bool = false

    private let subscription = SubscriptionService.shared

    var body: some View {
        NavigationStack {
            ZStack {
                SVTheme.background.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(SVTheme.accent)
                } else {
                    ScrollView {
                        VStack(spacing: 28) {
                            headerSection
                            planSelector
                            billingToggle
                            selectedPlanCard
                            featuresSection
                            ctaButton
                            restoreButton
                            legalText
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                        .padding(.bottom, 40)
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
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(SVTheme.accent)
                .symbolEffect(.pulse, options: .repeating)

            Text("Unlock ShiftVoice")
                .font(.system(.title, design: .serif, weight: .bold))
                .foregroundStyle(SVTheme.textPrimary)

            Text("Record unlimited shift notes, unlock team features, and streamline your operations.")
                .font(.subheadline)
                .foregroundStyle(SVTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.top, 8)
    }

    private var planSelector: some View {
        HStack(spacing: 0) {
            planTab(type: .pro, label: "Pro", sublabel: "Individual")
            planTab(type: .team, label: "Team", sublabel: "Up to 10 users")
        }
        .background(SVTheme.iconBackground)
        .clipShape(.rect(cornerRadius: 12))
    }

    private func planTab(type: PlanType, label: String, sublabel: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25)) {
                selectedPlanType = type
            }
        } label: {
            VStack(spacing: 2) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selectedPlanType == type ? .white : SVTheme.textSecondary)
                Text(sublabel)
                    .font(.caption2)
                    .foregroundStyle(selectedPlanType == type ? .white.opacity(0.8) : SVTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(selectedPlanType == type ? SVTheme.accent : .clear)
            .clipShape(.rect(cornerRadius: 12))
        }
        .sensoryFeedback(.selection, trigger: selectedPlanType)
    }

    private var billingToggle: some View {
        HStack(spacing: 0) {
            billingOption(period: .monthly, label: "Monthly")
            billingOption(period: .annual, label: "Annual")
        }
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
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(selectedBilling == period ? SVTheme.textPrimary : SVTheme.textTertiary)
                if period == .annual {
                    Text("Save 33%")
                        .font(.system(size: 9, weight: .bold))
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
        .padding(2)
    }

    private var selectedPlanCard: some View {
        let price = currentPrice
        let period = selectedBilling == .annual ? "/year" : "/month"
        let perUser = selectedPlanType == .team ? " per user" : ""

        return VStack(spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(price)
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(SVTheme.textPrimary)
                Text(period + perUser)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
            }

            if selectedBilling == .annual {
                let monthly = selectedPlanType == .pro ? "$6.67" : "$5.42"
                Text("That's just \(monthly)/month")
                    .font(.caption)
                    .foregroundStyle(SVTheme.successGreen)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(SVTheme.successGreen.opacity(0.1))
                    .clipShape(Capsule())
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
            ForEach(Array(currentFeatures.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(feature.included ? SVTheme.accent : SVTheme.textTertiary)
                        .frame(width: 28, height: 28)
                        .background(feature.included ? SVTheme.accent.opacity(0.1) : SVTheme.iconBackground)
                        .clipShape(.rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textPrimary)
                        if let subtitle = feature.subtitle {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: feature.included ? "checkmark.circle.fill" : "minus.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(feature.included ? SVTheme.successGreen : SVTheme.textTertiary.opacity(0.5))
                }
                .padding(.vertical, 12)

                if index < currentFeatures.count - 1 {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 40)
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
                    Text("Start \(selectedPlanType == .pro ? "Pro" : "Team") Plan")
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
        Button {
            Task { await handleRestore() }
        } label: {
            Text("Restore Purchases")
                .font(.footnote.weight(.medium))
                .foregroundStyle(SVTheme.textSecondary)
        }
    }

    private var legalText: some View {
        Text("Subscriptions auto-renew. Cancel anytime in Settings. Payment charged to your Apple ID. By subscribing you agree to our Terms of Service and Privacy Policy.")
            .font(.system(size: 10))
            .foregroundStyle(SVTheme.textTertiary)
            .multilineTextAlignment(.center)
            .lineSpacing(1.5)
    }

    private var currentPrice: String {
        if let pkg = currentPackage {
            return pkg.storeProduct.localizedPriceString
        }
        switch (selectedPlanType, selectedBilling) {
        case (.pro, .monthly): return "$9.99"
        case (.pro, .annual): return "$79.99"
        case (.team, .monthly): return "$24.99"
        case (.team, .annual): return "$199.99"
        }
    }

    private var currentPackage: Package? {
        guard let current = offerings?.current else { return nil }
        let key: String
        switch (selectedPlanType, selectedBilling) {
        case (.pro, .monthly): key = "pro_monthly"
        case (.pro, .annual): key = "pro_annual"
        case (.team, .monthly): key = "team_monthly"
        case (.team, .annual): key = "team_annual"
        }
        return current.package(identifier: key)
    }

    private var currentFeatures: [FeatureRow] {
        if selectedPlanType == .pro {
            return [
                FeatureRow(icon: "waveform", title: "Unlimited Voice Notes", subtitle: "No monthly cap", included: true),
                FeatureRow(icon: "building.2", title: "All Industry Templates", subtitle: "Restaurant, hotel, bar & more", included: true),
                FeatureRow(icon: "magnifyingglass", title: "Full Search & History", subtitle: "Find any note instantly", included: true),
                FeatureRow(icon: "square.and.arrow.up", title: "Export & Share Notes", subtitle: "PDF, text, email", included: true),
                FeatureRow(icon: "bolt", title: "Priority Transcription", subtitle: "Faster, more accurate results", included: true),
                FeatureRow(icon: "person.2", title: "Team Features", subtitle: "Shared feed, roles, admin", included: false),
            ]
        } else {
            return [
                FeatureRow(icon: "checkmark.seal", title: "Everything in Pro", subtitle: "All Pro features included", included: true),
                FeatureRow(icon: "person.2", title: "Team Dashboard", subtitle: "Shared feed & real-time updates", included: true),
                FeatureRow(icon: "shield.checkered", title: "Role-Based Access", subtitle: "Owner, manager, shift lead", included: true),
                FeatureRow(icon: "gearshape.2", title: "Admin Controls", subtitle: "Manage team permissions", included: true),
                FeatureRow(icon: "mappin.and.ellipse", title: "Multi-Location Support", subtitle: "Up to 5 locations", included: true),
                FeatureRow(icon: "person.3", title: "Up to 10 Users", subtitle: "Invite your whole team", included: true),
            ]
        }
    }

    private func fetchOfferings() async {
        isLoading = true
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            // continue with fallback prices
        }
        isLoading = false
    }

    private func handlePurchase() async {
        guard let package = currentPackage else {
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
                // user cancelled
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

private enum PlanType {
    case pro, team
}

private enum BillingPeriod {
    case monthly, annual
}

private struct FeatureRow {
    let icon: String
    let title: String
    let subtitle: String?
    let included: Bool
}
