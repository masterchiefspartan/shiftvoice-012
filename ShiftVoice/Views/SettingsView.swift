import SwiftUI

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    let authService: AuthenticationService
    private let pushService = PushNotificationService.shared
    private let subscription = SubscriptionService.shared
    @State private var pushEnabled: Bool = false
    @State private var urgentOnly: Bool = false
    @State private var quietHoursEnabled: Bool = true
    @State private var quietStart: Date = Calendar.current.date(from: DateComponents(hour: 23)) ?? Date()
    @State private var quietEnd: Date = Calendar.current.date(from: DateComponents(hour: 7)) ?? Date()
    @State private var showTeamSheet: Bool = false
    @State private var showLocationSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your Profile")
                            .font(.system(.largeTitle, design: .serif, weight: .bold))
                            .foregroundStyle(SVTheme.textPrimary)
                            .tracking(-0.5)
                        Text("Manage your account and preferences")
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    profileSection
                    syncSection
                    notificationSection
                    organizationSection
                    locationSection
                    teamSection
                    subscriptionSection
                    aboutSection
                    signOutSection
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(SVTheme.background)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Profile")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                }
            }
            .toolbarBackground(SVTheme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showTeamSheet) {
                TeamManagementSheet(viewModel: viewModel)
            }
            .sheet(isPresented: $showLocationSheet) {
                LocationManagementSheet(viewModel: viewModel)
            }

        }
    }

    private var profileSection: some View {
        HStack(spacing: 14) {
            if let imageURL = authService.userProfileImageURL {
                AsyncImage(url: imageURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        initialsAvatar
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(Circle())
            } else {
                initialsAvatar
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(authService.userName.isEmpty ? viewModel.currentUserName : authService.userName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Text(authService.userEmail.isEmpty ? "No email" : authService.userEmail)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
                Text("Owner")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SVTheme.accent)
            }

            Spacer()
        }
        .padding(20)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var initialsAvatar: some View {
        Text(authService.userInitials.isEmpty ? viewModel.currentUserInitials : authService.userInitials)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(SVTheme.textSecondary)
            .frame(width: 52, height: 52)
            .background(SVTheme.iconBackground)
            .clipShape(Circle())
    }

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DATA SYNC")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14))
                        .foregroundStyle(SVTheme.accent)
                        .frame(width: 28, height: 28)
                        .background(SVTheme.accent.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cloud Sync")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textPrimary)
                        if let lastSync = viewModel.lastSyncDate {
                            Text("Last synced \(lastSync.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        } else {
                            Text(APIService.shared.isConfigured ? "Not yet synced" : "Backend not configured")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                    }

                    Spacer()

                    Button {
                        viewModel.forceSync()
                    } label: {
                        Text("Sync Now")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(SVTheme.accent)
                            .clipShape(Capsule())
                    }
                    .disabled(!APIService.shared.isConfigured)
                }
                .padding(16)

                if let error = viewModel.syncError {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(SVTheme.amber)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(SVTheme.textSecondary)
                            .lineLimit(2)
                    }
                    .padding(16)
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NOTIFICATIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                Toggle("Push Notifications", isOn: Binding(
                    get: { pushEnabled },
                    set: { newValue in
                        if newValue {
                            Task {
                                let granted = await pushService.requestPermission()
                                pushEnabled = granted
                                if !granted && pushService.authorizationStatus == .denied {
                                    if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                        await UIApplication.shared.open(settingsURL)
                                    }
                                }
                            }
                        } else {
                            pushEnabled = false
                        }
                    }
                ))
                .font(.subheadline)
                .foregroundStyle(SVTheme.textPrimary)
                .tint(SVTheme.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                if pushService.authorizationStatus == .denied {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(SVTheme.amber)
                        Text("Notifications disabled in Settings")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                        Spacer()
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.accent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
                }

                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsToggleRow(title: "Urgent Only", isOn: $urgentOnly)
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsToggleRow(title: "Quiet Hours", isOn: $quietHoursEnabled)
                if quietHoursEnabled {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                    settingsDateRow(title: "Start", selection: $quietStart)
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                    settingsDateRow(title: "End", selection: $quietEnd)
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
        .onAppear {
            pushEnabled = pushService.isAuthorized
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ORGANIZATION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                settingsValueRow(title: "Business", value: viewModel.organization.name)
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsValueRow(title: "Industry", value: viewModel.organization.industryType.rawValue)
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                HStack {
                    Text("Plan")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text(viewModel.organization.plan.rawValue)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("LOCATIONS")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                    HStack(spacing: 12) {
                        Image(systemName: "mappin")
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textTertiary)
                            .frame(width: 36, height: 36)
                            .background(SVTheme.iconBackground)
                            .clipShape(.rect(cornerRadius: 6))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(location.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SVTheme.textPrimary)
                            Text(location.address)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SVTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < viewModel.locations.count - 1 {
                        Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 64)
                    }
                }

                Rectangle().fill(SVTheme.divider).frame(height: 1)

                Button {
                    showLocationSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.subheadline.weight(.medium))
                        Text("Manage Locations")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(SVTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TEAM")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                ForEach(Array(viewModel.teamMembers.prefix(4).enumerated()), id: \.element.id) { index, member in
                    HStack(spacing: 12) {
                        Text(member.avatarInitials)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(SVTheme.textSecondary)
                            .frame(width: 32, height: 32)
                            .background(SVTheme.iconBackground)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 1) {
                            Text(member.name)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SVTheme.textPrimary)
                            Text(member.roleDisplayInfo.name)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                        }

                        Spacer()

                        Text(member.inviteStatus.rawValue)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(member.inviteStatus == .accepted ? SVTheme.successGreen : SVTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    if index < min(viewModel.teamMembers.count, 4) - 1 {
                        Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 60)
                    }
                }

                Rectangle().fill(SVTheme.divider).frame(height: 1)

                Button {
                    showTeamSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "person.badge.plus")
                            .font(.subheadline.weight(.medium))
                        Text("Manage Team")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                    }
                    .foregroundStyle(SVTheme.accent)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var subscriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SUBSCRIPTION")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(subscriptionTierName)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SVTheme.textPrimary)
                            if subscription.isProUser {
                                Text("Active")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(SVTheme.successGreen)
                                    .clipShape(Capsule())
                            }
                        }
                        Text(subscriptionTierDetail)
                            .font(.caption)
                            .foregroundStyle(SVTheme.accent)
                    }
                    Spacer()
                }

                if !subscription.isProUser {
                    Rectangle().fill(SVTheme.divider).frame(height: 1)

                    VStack(spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "waveform")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)
                            Text("\(viewModel.notesThisMonth)/\(subscription.remainingFreeNotes) notes this month")
                                .font(.caption)
                                .foregroundStyle(SVTheme.textSecondary)
                            Spacer()
                        }

                        Button {
                            viewModel.showPaywall = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "crown.fill")
                                    .font(.caption)
                                Text("Upgrade to Pro")
                                    .font(.subheadline.weight(.semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(SVTheme.accent)
                            .clipShape(.rect(cornerRadius: 10))
                        }
                    }
                } else {
                    Rectangle().fill(SVTheme.divider).frame(height: 1)

                    HStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NOTES")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(SVTheme.textTertiary)
                                .tracking(0.5)
                            Text("Unlimited")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SVTheme.textPrimary)
                        }
                        if subscription.isTeamUser {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("LOCATIONS")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(SVTheme.textTertiary)
                                    .tracking(0.5)
                                Text("\(viewModel.locations.count)")
                                    .font(.subheadline.weight(.medium).monospacedDigit())
                                    .foregroundStyle(SVTheme.textPrimary)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var subscriptionTierName: String {
        switch subscription.currentTier {
        case .free: return "Free Plan"
        case .pro: return "Pro Plan"
        case .team: return "Team Plan"
        }
    }

    private var subscriptionTierDetail: String {
        switch subscription.currentTier {
        case .free: return "5 notes/month"
        case .pro: return "Unlimited notes"
        case .team: return "Unlimited notes + team features"
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ABOUT")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                settingsValueRow(title: "Version", value: "1.0.0")
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsNavigationRow(title: "Privacy Policy") {}
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsNavigationRow(title: "Terms of Service") {}
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                HStack {
                    Text("Support")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text("help@shiftvoice.app")
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }

    private var signOutSection: some View {
        VStack(spacing: 12) {
            Button {
                authService.signOut()
            } label: {
                HStack {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.subheadline)
                    Text("Sign Out")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(SVTheme.urgentRed)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                        .font(.subheadline)
                    Text("Delete Account")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundStyle(SVTheme.urgentRed.opacity(0.7))
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    authService.deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will permanently delete your account, credentials, and all associated data. This cannot be undone.")
            }
        }
    }

    private func settingsToggleRow(title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.subheadline)
            .foregroundStyle(SVTheme.textPrimary)
            .tint(SVTheme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func settingsDateRow(title: String, selection: Binding<Date>) -> some View {
        DatePicker(title, selection: selection, displayedComponents: .hourAndMinute)
            .font(.subheadline)
            .foregroundStyle(SVTheme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
    }

    private func settingsValueRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textPrimary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func settingsNavigationRow(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SVTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
    }
}

struct TeamManagementSheet: View {
    let viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.teamMembers.enumerated()), id: \.element.id) { index, member in
                        HStack(spacing: 12) {
                            Text(member.avatarInitials)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(SVTheme.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(SVTheme.iconBackground)
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.name)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(SVTheme.textPrimary)
                                Text(member.email)
                                    .font(.caption)
                                    .foregroundStyle(SVTheme.textTertiary)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 2) {
                                Text(member.roleDisplayInfo.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(SVTheme.textSecondary)
                                Text(member.inviteStatus.rawValue)
                                    .font(.caption2)
                                    .foregroundStyle(member.inviteStatus == .accepted ? SVTheme.successGreen : SVTheme.textTertiary)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)

                        if index < viewModel.teamMembers.count - 1 {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 72)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .background(SVTheme.background)
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct LocationManagementSheet: View {
    let viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(location.name)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(SVTheme.textPrimary)
                            Text(location.address)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textTertiary)

                            HStack(spacing: 16) {
                                shiftTimeLabel(icon: "sunrise", label: "Open", time: location.openingTime)
                                shiftTimeLabel(icon: "sun.max", label: "Mid", time: location.midTime)
                                shiftTimeLabel(icon: "moon.stars", label: "Close", time: location.closingTime)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)

                        if index < viewModel.locations.count - 1 {
                            Rectangle()
                                .fill(SVTheme.divider)
                                .frame(height: 1)
                                .padding(.leading, 24)
                        }
                    }
                }
                .padding(.top, 8)
            }
            .background(SVTheme.background)
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func shiftTimeLabel(icon: String, label: String, time: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text("\(label) \(time)")
                .font(.caption2)
        }
        .foregroundStyle(SVTheme.textTertiary)
    }
}
