import SwiftUI
import UIKit

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel
    let authService: AuthenticationService
    private let pushService = PushNotificationService.shared
    private let subscription = SubscriptionService.shared
    @State private var pushEnabled: Bool = false
    @AppStorage("notif_urgentOnly") private var urgentOnly: Bool = false
    @AppStorage("notif_quietHoursEnabled") private var quietHoursEnabled: Bool = true
    @AppStorage("notif_quietStartMinutes") private var quietStartMinutes: Int = 1380
    @AppStorage("notif_quietEndMinutes") private var quietEndMinutes: Int = 420

    private var quietStartBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: quietStartMinutes / 60, minute: quietStartMinutes % 60)) ?? Date() },
            set: { quietStartMinutes = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
        )
    }

    private var quietEndBinding: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: quietEndMinutes / 60, minute: quietEndMinutes % 60)) ?? Date() },
            set: { quietEndMinutes = Calendar.current.component(.hour, from: $0) * 60 + Calendar.current.component(.minute, from: $0) }
        )
    }
    @State private var showTeamSheet: Bool = false
    @State private var showLocationSheet: Bool = false
    @State private var showDeleteConfirmation: Bool = false
    @State private var deletePassword: String = ""
    @State private var showDeletePasswordPrompt: Bool = false
    @State private var isPendingOpsExpanded: Bool = false
    @State private var isEventsExpanded: Bool = false
    @State private var isWriteFailuresExpanded: Bool = false
    @State private var showDeveloperSection: Bool = false

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
                    #if DEBUG
                    if showDeveloperSection {
                        developerSection
                    }
                    #endif
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
                if let role = viewModel.resolvedUserRole {
                    Text(role.rawValue)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.accent)
                } else {
                    Text("Loading role…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textTertiary)
                }
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

            if viewModel.featureFlags.diagnosticsEnabled {
                diagnosticsSyncCard
            } else {
                basicSyncCard
            }
        }
    }

    private var basicSyncCard: some View {
        VStack(spacing: 0) {
            syncSummaryRow
        }
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private var diagnosticsSyncCard: some View {
        VStack(spacing: 0) {
            syncSummaryRow

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            HStack(spacing: 10) {
                Circle()
                    .fill(syncStateColor)
                    .frame(width: 10, height: 10)
                Text(viewModel.syncStateLabel())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
                Text("Pending: \(viewModel.pendingOpsCountForDiagnostics)")
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            HStack(spacing: 8) {
                Label("Active Conflicts", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(viewModel.activeConflictCount > 0 ? SVTheme.amber : SVTheme.textTertiary)
                Spacer()
                Text("\(viewModel.activeConflictCount)")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SVTheme.textPrimary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            DisclosureGroup(isExpanded: $isPendingOpsExpanded) {
                VStack(alignment: .leading, spacing: 6) {
                    if viewModel.pendingDocIdsForDiagnostics.isEmpty {
                        Text("No pending documents")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    } else {
                        ForEach(viewModel.pendingDocIdsForDiagnostics, id: \.self) { docId in
                            Text(docId)
                                .font(.caption.monospaced())
                                .foregroundStyle(SVTheme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Pending Doc IDs")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text("\(viewModel.pendingOpsCountForDiagnostics)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            DisclosureGroup(isExpanded: $isEventsExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.recentSyncEventsForDiagnostics) { event in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(SVTheme.textTertiary)
                            Text(event.message)
                                .font(.caption)
                                .foregroundStyle(SVTheme.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Recent Sync Events")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text("10")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            DisclosureGroup(isExpanded: $isWriteFailuresExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    if viewModel.recentWriteFailuresForDiagnostics.isEmpty {
                        Text("No recent write failures")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    } else {
                        ForEach(viewModel.recentWriteFailuresForDiagnostics) { event in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.timestamp.formatted(date: .omitted, time: .standard))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(SVTheme.textTertiary)
                                Text(event.message)
                                    .font(.caption)
                                    .foregroundStyle(SVTheme.amber)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            } label: {
                HStack {
                    Text("Write Failures")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text("\(viewModel.writeFailureCountForDiagnostics)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

            HStack(spacing: 8) {
                Button {
                    UIPasteboard.general.string = viewModel.diagnosticsReport()
                } label: {
                    Label("Copy Diagnostics", systemImage: "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SVTheme.accent.opacity(0.1))
                        .clipShape(.rect(cornerRadius: 8))
                }

                Button {
                    viewModel.forceSyncListenerRestart()
                } label: {
                    Label("Restart Listeners", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SVTheme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(SVTheme.iconBackground)
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Button {
                viewModel.forceReconciliationFromDiagnostics()
            } label: {
                Label("Force Reconciliation", systemImage: "checkmark.arrow.trianglehead.counterclockwise")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SVTheme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(SVTheme.iconBackground)
                    .clipShape(.rect(cornerRadius: 8))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

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

    private var syncSummaryRow: some View {
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
                    settingsDateRow(title: "Start", selection: quietStartBinding)
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                    settingsDateRow(title: "End", selection: quietEndBinding)
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
                            viewModel.presentPaywall(reason: .manualUpgrade)
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
                HStack {
                    Text("Version")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textPrimary)
                    Spacer()
                    Text("1.0.0")
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .onTapGesture(count: 3) {
                    showDeveloperSection.toggle()
                }
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsNavigationRow(title: "Privacy Policy") {
                    if let url = URL(string: "https://shiftvoice.app/privacy") {
                        UIApplication.shared.open(url)
                    }
                }
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                settingsNavigationRow(title: "Terms of Service") {
                    if let url = URL(string: "https://shiftvoice.app/terms") {
                        UIApplication.shared.open(url)
                    }
                }
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

    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("DEVELOPER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)

            VStack(spacing: 0) {
                settingsValueRow(title: "Sync State", value: viewModel.syncStateLabel())
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                settingsToggleRow(
                    title: "Conflict UI",
                    isOn: Binding(
                        get: { viewModel.featureFlags.conflictUIEnabled },
                        set: { viewModel.featureFlags.conflictUIOverride = $0 }
                    )
                )
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                settingsToggleRow(
                    title: "Diagnostics",
                    isOn: Binding(
                        get: { viewModel.featureFlags.diagnosticsEnabled },
                        set: { viewModel.featureFlags.diagnosticsOverride = $0 }
                    )
                )
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                settingsToggleRow(
                    title: "Sync Banners",
                    isOn: Binding(
                        get: { viewModel.featureFlags.syncBannersEnabled },
                        set: { viewModel.featureFlags.syncBannersOverride = $0 }
                    )
                )
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                Menu {
                    Button("Use Live Reducer") { viewModel.setForcedSyncStateForDebug(nil) }
                    Button("Offline") { viewModel.setForcedSyncStateForDebug(.offline) }
                    Button("Online Cache") { viewModel.setForcedSyncStateForDebug(.onlineCache) }
                    Button("Syncing") { viewModel.setForcedSyncStateForDebug(.syncing) }
                    Button("Online Fresh") { viewModel.setForcedSyncStateForDebug(.onlineFresh) }
                    Button("Error") { viewModel.setForcedSyncStateForDebug(.error) }
                } label: {
                    HStack {
                        Text("Force Sync State")
                            .font(.subheadline)
                            .foregroundStyle(SVTheme.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                Button {
                    viewModel.featureFlags.clearAllOverrides()
                } label: {
                    HStack {
                        Text("Reset Feature Flag Overrides")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textPrimary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                Button {
                    viewModel.resetSyncDataForDebug()
                } label: {
                    HStack {
                        Text("Reset All Sync Data")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.urgentRed)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
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
    #endif

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
                if authService.isEmailAuth {
                    deletePassword = ""
                    showDeletePasswordPrompt = true
                } else {
                    showDeleteConfirmation = true
                }
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
            .disabled(authService.isSubmitting)
            .background(SVTheme.cardBackground)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
            .alert("Delete Account", isPresented: $showDeletePasswordPrompt) {
                SecureField("Enter your password", text: $deletePassword)
                Button("Delete", role: .destructive) {
                    authService.deleteAccount(password: deletePassword)
                }
                Button("Cancel", role: .cancel) {
                    deletePassword = ""
                }
            } message: {
                Text("Enter your password to confirm account deletion. This cannot be undone.")
            }
            .alert("Delete Account", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    authService.deleteAccount()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You will be asked to re-authenticate with Google. This will permanently delete your account and cannot be undone.")
            }
        }
    }

    private var syncStateColor: Color {
        switch viewModel.syncState {
        case .offline:
            return SVTheme.amber
        case .onlineCache:
            return SVTheme.textTertiary
        case .syncing:
            return SVTheme.accent
        case .onlineFresh:
            return SVTheme.successGreen
        case .error:
            return SVTheme.urgentRed
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
    @State private var showAddForm: Bool = false
    @State private var editingMember: TeamMember? = nil
    @State private var memberToDelete: TeamMember? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(viewModel.teamMembers.count) members")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SVTheme.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.teamMembers.enumerated()), id: \.element.id) { index, member in
                            let isCurrentUser = member.id == viewModel.currentUserId
                            let isOrgOwner = member.id == viewModel.organization.ownerId
                            let isProtected = isCurrentUser || isOrgOwner
                            Button {
                                if !isCurrentUser {
                                    editingMember = member
                                }
                            } label: {
                                TeamMemberRow(member: member, isCurrentUser: isCurrentUser)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                if !isCurrentUser {
                                    Button {
                                        editingMember = member
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    if !isProtected {
                                        Button(role: .destructive) {
                                            memberToDelete = member
                                        } label: {
                                            Label("Remove", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if !isProtected {
                                    Button(role: .destructive) {
                                        memberToDelete = member
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                                if !isCurrentUser {
                                    Button {
                                        editingMember = member
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(SVTheme.accent)
                                }
                            }

                            if index < viewModel.teamMembers.count - 1 {
                                Rectangle()
                                    .fill(SVTheme.divider)
                                    .frame(height: 1)
                                    .padding(.leading, 72)
                            }
                        }
                    }
                    .background(SVTheme.cardBackground)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showAddForm = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SVTheme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
            .sheet(isPresented: $showAddForm) {
                AddTeamMemberSheet(viewModel: viewModel, locations: viewModel.locations)
            }
            .sheet(item: $editingMember) { member in
                EditTeamMemberSheet(viewModel: viewModel, member: member, locations: viewModel.locations)
            }
            .alert("Remove Team Member", isPresented: Binding(
                get: { memberToDelete != nil },
                set: { if !$0 { memberToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { memberToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let member = memberToDelete {
                        viewModel.removeTeamMember(member.id)
                        memberToDelete = nil
                    }
                }
            } message: {
                if let member = memberToDelete {
                    Text("Are you sure you want to remove \(member.name)? This cannot be undone.")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct TeamMemberRow: View {
    let member: TeamMember
    let isCurrentUser: Bool

    private var statusColor: Color {
        switch member.inviteStatus {
        case .accepted: return SVTheme.successGreen
        case .pending: return SVTheme.amber
        case .deactivated: return SVTheme.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(member.avatarInitials)
                .font(.caption.weight(.bold))
                .foregroundStyle(SVTheme.textSecondary)
                .frame(width: 40, height: 40)
                .background(SVTheme.iconBackground)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(member.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    if isCurrentUser {
                        Text("You")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(SVTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                Text(member.email)
                    .font(.caption)
                    .foregroundStyle(SVTheme.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 3) {
                Text(member.roleDisplayInfo.name)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SVTheme.textSecondary)
                Text(member.inviteStatus.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(statusColor.opacity(0.1))
                    .clipShape(Capsule())
            }

            if !isCurrentUser {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(SVTheme.textTertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

struct AddTeamMemberSheet: View {
    let viewModel: AppViewModel
    let locations: [Location]
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var selectedRole: ManagerRole = .manager
    @State private var selectedLocationIds: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DETAILS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            TextField("Full Name", text: $name)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .textContentType(.name)
                                .autocorrectionDisabled()

                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                            TextField("Email Address", text: $email)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ROLE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            ForEach(ManagerRole.allCases.filter { $0 != .owner }, id: \.rawValue) { role in
                                Button {
                                    selectedRole = role
                                } label: {
                                    HStack {
                                        Text(role.rawValue)
                                            .font(.subheadline)
                                            .foregroundStyle(SVTheme.textPrimary)
                                        Spacer()
                                        if selectedRole == role {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(SVTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }

                                if role != ManagerRole.allCases.filter({ $0 != .owner }).last {
                                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                                }
                            }
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    if !locations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LOCATIONS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SVTheme.textTertiary)
                                .tracking(0.5)

                            VStack(spacing: 0) {
                                ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                                    let isSelected = selectedLocationIds.contains(location.id)
                                    Button {
                                        if isSelected {
                                            selectedLocationIds.remove(location.id)
                                        } else {
                                            selectedLocationIds.insert(location.id)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "mappin")
                                                .font(.subheadline)
                                                .foregroundStyle(SVTheme.textTertiary)
                                                .frame(width: 28, height: 28)

                                            VStack(alignment: .leading, spacing: 1) {
                                                Text(location.name)
                                                    .font(.subheadline)
                                                    .foregroundStyle(SVTheme.textPrimary)
                                                Text(location.address)
                                                    .font(.caption)
                                                    .foregroundStyle(SVTheme.textTertiary)
                                            }

                                            Spacer()

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.body)
                                                .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }

                                    if index < locations.count - 1 {
                                        Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 56)
                                    }
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Add Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        if let error = InputValidator.validateName(trimmedName, fieldName: "Name") {
                            viewModel.showToast(error, isError: true)
                            return
                        }
                        if let error = InputValidator.validateEmail(trimmedEmail) {
                            viewModel.showToast(error, isError: true)
                            return
                        }
                        let member = TeamMember(
                            name: trimmedName,
                            email: trimmedEmail,
                            role: selectedRole,
                            locationIds: Array(selectedLocationIds),
                            inviteStatus: .pending
                        )
                        viewModel.addTeamMember(member)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let first = locations.first {
                selectedLocationIds.insert(first.id)
            }
        }
    }
}

struct EditTeamMemberSheet: View {
    let viewModel: AppViewModel
    let member: TeamMember
    let locations: [Location]
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var email: String = ""
    @State private var selectedRole: ManagerRole = .manager
    @State private var selectedLocationIds: Set<String> = []
    @State private var selectedStatus: InviteStatus = .pending

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DETAILS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            TextField("Full Name", text: $name)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .textContentType(.name)
                                .autocorrectionDisabled()

                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                            TextField("Email Address", text: $email)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .keyboardType(.emailAddress)
                                .textContentType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("ROLE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            ForEach(ManagerRole.allCases.filter { $0 != .owner }, id: \.rawValue) { role in
                                Button {
                                    selectedRole = role
                                } label: {
                                    HStack {
                                        Text(role.rawValue)
                                            .font(.subheadline)
                                            .foregroundStyle(SVTheme.textPrimary)
                                        Spacer()
                                        if selectedRole == role {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.semibold))
                                                .foregroundStyle(SVTheme.accent)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 14)
                                    .contentShape(Rectangle())
                                }

                                if role != ManagerRole.allCases.filter({ $0 != .owner }).last {
                                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)
                                }
                            }
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("STATUS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        HStack(spacing: 8) {
                            ForEach([InviteStatus.pending, .accepted, .deactivated], id: \.rawValue) { status in
                                let isSelected = selectedStatus == status
                                Button {
                                    selectedStatus = status
                                } label: {
                                    Text(status.rawValue)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(isSelected ? statusColor(status) : SVTheme.surface)
                                        .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                                        .clipShape(.rect(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .stroke(isSelected ? Color.clear : SVTheme.surfaceBorder, lineWidth: 1)
                                        )
                                }
                            }
                        }
                    }

                    if !locations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("LOCATIONS")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SVTheme.textTertiary)
                                .tracking(0.5)

                            VStack(spacing: 0) {
                                ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                                    let isSelected = selectedLocationIds.contains(location.id)
                                    Button {
                                        if isSelected {
                                            selectedLocationIds.remove(location.id)
                                        } else {
                                            selectedLocationIds.insert(location.id)
                                        }
                                    } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "mappin")
                                                .font(.subheadline)
                                                .foregroundStyle(SVTheme.textTertiary)
                                                .frame(width: 28, height: 28)

                                            Text(location.name)
                                                .font(.subheadline)
                                                .foregroundStyle(SVTheme.textPrimary)

                                            Spacer()

                                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                                .font(.body)
                                                .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                    }

                                    if index < locations.count - 1 {
                                        Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 56)
                                    }
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
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Edit Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updated = TeamMember(
                            id: member.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                            role: selectedRole,
                            roleTemplateId: member.roleTemplateId,
                            locationIds: Array(selectedLocationIds),
                            inviteStatus: selectedStatus,
                            updatedAt: Date()
                        )
                        viewModel.updateTeamMember(updated)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = member.name
            email = member.email
            selectedRole = member.role
            selectedLocationIds = Set(member.locationIds)
            selectedStatus = member.inviteStatus
        }
    }

    private func statusColor(_ status: InviteStatus) -> Color {
        switch status {
        case .accepted: return SVTheme.successGreen
        case .pending: return SVTheme.amber
        case .deactivated: return SVTheme.textTertiary
        }
    }
}

struct LocationManagementSheet: View {
    let viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showAddForm: Bool = false
    @State private var editingLocation: Location? = nil
    @State private var locationToDelete: Location? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack {
                        Text("\(viewModel.locations.count) location\(viewModel.locations.count == 1 ? "" : "s")")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SVTheme.textSecondary)
                        Spacer()
                        Text("\(viewModel.organization.plan.rawValue) plan")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(SVTheme.accent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(SVTheme.accent.opacity(0.1))
                            .clipShape(Capsule())
                    }
                    .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.locations.enumerated()), id: \.element.id) { index, location in
                            Button {
                                editingLocation = location
                            } label: {
                                LocationRow(location: location, isSelected: location.id == viewModel.selectedLocationId)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button {
                                    editingLocation = location
                                } label: {
                                    Label("Edit", systemImage: "pencil")
                                }
                                if viewModel.locations.count > 1 {
                                    Button(role: .destructive) {
                                        locationToDelete = location
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                            }

                            if index < viewModel.locations.count - 1 {
                                Rectangle()
                                    .fill(SVTheme.divider)
                                    .frame(height: 1)
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(SVTheme.cardBackground)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    if !viewModel.canAddMoreLocations {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                            Text("Upgrade your plan to add more locations")
                                .font(.caption)
                        }
                        .foregroundStyle(SVTheme.textTertiary)
                        .padding(.horizontal, 24)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Locations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if viewModel.canAddMoreLocations {
                            showAddForm = true
                        } else {
                            viewModel.presentPaywall(reason: .manualUpgrade)
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(SVTheme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SVTheme.accent)
                }
            }
            .sheet(isPresented: $showAddForm) {
                AddLocationSheet(viewModel: viewModel)
            }
            .sheet(item: $editingLocation) { location in
                EditLocationSheet(viewModel: viewModel, location: location)
            }
            .alert("Remove Location", isPresented: Binding(
                get: { locationToDelete != nil },
                set: { if !$0 { locationToDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { locationToDelete = nil }
                Button("Remove", role: .destructive) {
                    if let location = locationToDelete {
                        viewModel.removeLocation(location.id)
                        locationToDelete = nil
                    }
                }
            } message: {
                if let location = locationToDelete {
                    Text("Are you sure you want to remove \(location.name)? All notes for this location will also be deleted.")
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

struct LocationRow: View {
    let location: Location
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "mappin")
                .font(.subheadline)
                .foregroundStyle(isSelected ? .white : SVTheme.textTertiary)
                .frame(width: 36, height: 36)
                .background(isSelected ? SVTheme.accent : SVTheme.iconBackground)
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(location.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SVTheme.textPrimary)
                    if isSelected {
                        Text("Active")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(SVTheme.accent)
                            .clipShape(Capsule())
                    }
                }
                if !location.address.isEmpty {
                    Text(location.address)
                        .font(.caption)
                        .foregroundStyle(SVTheme.textTertiary)
                        .lineLimit(1)
                }
                HStack(spacing: 12) {
                    shiftTimeLabel(icon: "sunrise", time: location.openingTime)
                    shiftTimeLabel(icon: "sun.max", time: location.midTime)
                    shiftTimeLabel(icon: "moon.stars", time: location.closingTime)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption2.weight(.medium))
                .foregroundStyle(SVTheme.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }

    private func shiftTimeLabel(icon: String, time: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text(time)
                .font(.caption2)
        }
        .foregroundStyle(SVTheme.textTertiary)
    }
}

struct AddLocationSheet: View {
    let viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var openingTime: Date = Calendar.current.date(from: DateComponents(hour: 6, minute: 0)) ?? Date()
    @State private var midTime: Date = Calendar.current.date(from: DateComponents(hour: 14, minute: 0)) ?? Date()
    @State private var closingTime: Date = Calendar.current.date(from: DateComponents(hour: 22, minute: 0)) ?? Date()
    @State private var selectedTimezoneId: String = TimeZone.current.identifier
    @State private var showPlanLimitAlert: Bool = false

    private let timezoneOptions: [String] = TimeZone.knownTimeZoneIdentifiers.sorted()

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !selectedTimezoneId.isEmpty
    }

    private var nameValidationMessage: String? {
        if trimmedName.isEmpty {
            return "Location name is required"
        }
        return nil
    }

    private var openingTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: openingTime), c.component(.minute, from: openingTime))
    }
    private var midTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: midTime), c.component(.minute, from: midTime))
    }
    private var closingTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: closingTime), c.component(.minute, from: closingTime))
    }
    private var timezoneDisplayName: String {
        selectedTimezoneId.replacingOccurrences(of: "_", with: " ")
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DETAILS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            TextField("Location Name", text: $name)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .autocorrectionDisabled()

                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                            TextField("Address (optional)", text: $address)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .textContentType(.fullStreetAddress)
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("TIMEZONE")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            HStack(spacing: 12) {
                                Image(systemName: "globe")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.textTertiary)
                                    .frame(width: 28, height: 28)

                                Text("Timezone")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.textPrimary)

                                Spacer()

                                Picker("Timezone", selection: $selectedTimezoneId) {
                                    ForEach(timezoneOptions, id: \.self) { timezoneId in
                                        Text(timezoneId.replacingOccurrences(of: "_", with: " "))
                                            .tag(timezoneId)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .tint(SVTheme.accent)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )

                        Text(timezoneDisplayName)
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)
                            .padding(.leading, 4)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SHIFT TIMES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        Text("Set when each shift starts so notes are automatically categorized.")
                            .font(.caption)
                            .foregroundStyle(SVTheme.textTertiary)

                        VStack(spacing: 0) {
                            shiftTimePicker(icon: "sunrise", label: "Opening Shift", selection: $openingTime)
                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                            shiftTimePicker(icon: "sun.max", label: "Mid Shift", selection: $midTime)
                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                            shiftTimePicker(icon: "moon.stars", label: "Closing Shift", selection: $closingTime)
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    if !viewModel.canAddMoreLocations {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption)
                            Text("Location limit reached for your current plan. Upgrade to add another location.")
                                .font(.caption)
                        }
                        .foregroundStyle(SVTheme.amber)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SVTheme.amber.opacity(0.12))
                        .clipShape(.rect(cornerRadius: 10))
                    }

                    if let nameValidationMessage {
                        Text(nameValidationMessage)
                            .font(.caption)
                            .foregroundStyle(SVTheme.amber)
                            .padding(.leading, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Add Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add") {
                        guard viewModel.canAddMoreLocations else {
                            showPlanLimitAlert = true
                            return
                        }
                        guard canSubmit else { return }
                        let location = Location(
                            name: trimmedName,
                            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                            timezone: selectedTimezoneId,
                            openingTime: openingTimeString,
                            midTime: midTimeString,
                            closingTime: closingTimeString,
                            managerIds: [viewModel.currentUserId]
                        )
                        viewModel.addLocation(location)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.accent)
                    .disabled(!canSubmit)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .alert("Location Limit Reached", isPresented: $showPlanLimitAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Upgrade") {
                viewModel.presentPaywall(reason: .manualUpgrade)
            }
        } message: {
            Text("Your \(viewModel.organization.plan.rawValue) plan supports up to \(viewModel.organization.plan.maxLocations) location\(viewModel.organization.plan.maxLocations == 1 ? "" : "s").")
        }
    }

    private func shiftTimePicker(icon: String, label: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
                .frame(width: 28, height: 28)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textPrimary)

            Spacer()

            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct EditLocationSheet: View {
    let viewModel: AppViewModel
    let location: Location
    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var openingTime: Date = Date()
    @State private var midTime: Date = Date()
    @State private var closingTime: Date = Date()

    private var openingTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: openingTime), c.component(.minute, from: openingTime))
    }
    private var midTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: midTime), c.component(.minute, from: midTime))
    }
    private var closingTimeString: String {
        let c = Calendar.current
        return String(format: "%02d:%02d", c.component(.hour, from: closingTime), c.component(.minute, from: closingTime))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("DETAILS")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            TextField("Location Name", text: $name)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .autocorrectionDisabled()

                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                            TextField("Address", text: $address)
                                .font(.subheadline)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .textContentType(.fullStreetAddress)
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("SHIFT TIMES")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            shiftTimePicker(icon: "sunrise", label: "Opening Shift", selection: $openingTime)
                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                            shiftTimePicker(icon: "sun.max", label: "Mid Shift", selection: $midTime)
                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                            shiftTimePicker(icon: "moon.stars", label: "Closing Shift", selection: $closingTime)
                        }
                        .background(SVTheme.cardBackground)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("INFO")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SVTheme.textTertiary)
                            .tracking(0.5)

                        VStack(spacing: 0) {
                            HStack {
                                Text("Timezone")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.textPrimary)
                                Spacer()
                                Text(location.timezone.replacingOccurrences(of: "_", with: " "))
                                    .font(.caption)
                                    .foregroundStyle(SVTheme.textTertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)

                            Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 16)

                            HStack {
                                Text("Managers")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.textPrimary)
                                Spacer()
                                Text("\(location.managerIds.count)")
                                    .font(.subheadline.monospacedDigit())
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
                .padding(.horizontal, 24)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(SVTheme.background)
            .navigationTitle("Edit Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.subheadline)
                        .foregroundStyle(SVTheme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let updated = Location(
                            id: location.id,
                            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                            address: address.trimmingCharacters(in: .whitespacesAndNewlines),
                            timezone: location.timezone,
                            openingTime: openingTimeString,
                            midTime: midTimeString,
                            closingTime: closingTimeString,
                            managerIds: location.managerIds
                        )
                        viewModel.updateLocation(updated)
                        dismiss()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.accent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear {
            name = location.name
            address = location.address
            openingTime = timeFromString(location.openingTime)
            midTime = timeFromString(location.midTime)
            closingTime = timeFromString(location.closingTime)
        }
    }

    private func shiftTimePicker(icon: String, label: String, selection: Binding<Date>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textTertiary)
                .frame(width: 28, height: 28)

            Text(label)
                .font(.subheadline)
                .foregroundStyle(SVTheme.textPrimary)

            Spacer()

            DatePicker("", selection: selection, displayedComponents: .hourAndMinute)
                .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func timeFromString(_ timeStr: String) -> Date {
        let parts = timeStr.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return Date()
        }
        return Calendar.current.date(from: DateComponents(hour: hour, minute: minute)) ?? Date()
    }
}
