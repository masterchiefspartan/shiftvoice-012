import SwiftUI

struct ContentView: View {
    let authService: AuthenticationService
    let viewModel: AppViewModel
    @State private var selectedTab: AppTab = .feed
    @State private var tabsLoaded: Set<AppTab> = [.feed]
    @State private var showRecordSheet: Bool = false

    @AppStorage("hasSeenFirstRunGuide") private var hasSeenFirstRunGuide: Bool = false
    @State private var showFirstRunGuide: Bool = false
    @State private var feedNavPath: NavigationPath = NavigationPath()
    @State private var actionsNavPath: NavigationPath = NavigationPath()
    @State private var reviewNavPath: NavigationPath = NavigationPath()
    private let subscription = SubscriptionService.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                if tabsLoaded.contains(.feed) {
                    ShiftFeedView(viewModel: viewModel, navPath: $feedNavPath)
                        .opacity(selectedTab == .feed ? 1 : 0)
                        .allowsHitTesting(selectedTab == .feed)
                }

                if tabsLoaded.contains(.actions) {
                    DashboardView(viewModel: viewModel, navPath: $actionsNavPath)
                        .opacity(selectedTab == .actions ? 1 : 0)
                        .allowsHitTesting(selectedTab == .actions)
                }

                if tabsLoaded.contains(.review) {
                    ReviewView(viewModel: viewModel, navPath: $reviewNavPath)
                        .opacity(selectedTab == .review ? 1 : 0)
                        .allowsHitTesting(selectedTab == .review)
                }

                if tabsLoaded.contains(.profile) {
                    SettingsView(viewModel: viewModel, authService: authService)
                        .opacity(selectedTab == .profile ? 1 : 0)
                        .allowsHitTesting(selectedTab == .profile)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: selectedTab) { _, newTab in
                tabsLoaded.insert(newTab)
            }

            VStack(spacing: 0) {
                if viewModel.featureFlags.syncBannersEnabled, viewModel.isOffline {
                    offlineBanner
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                customTabBar
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isOffline)
        .sheet(isPresented: $showRecordSheet) {
            RecordView(viewModel: viewModel)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { viewModel.showPaywall },
            set: { if !$0 { viewModel.dismissPaywall() } }
        )) {
            PaywallView()
        }
        .onChange(of: viewModel.pendingNoteId) { _, noteId in
            guard let noteId else { return }
            viewModel.loadFirstPage(shiftFilter: nil)
            feedNavPath = NavigationPath()
            selectedTab = .feed
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                feedNavPath.append(AppRoute.shiftNoteDetail(noteId: noteId))
                viewModel.pendingNoteId = nil
            }
        }
        .sheet(isPresented: $showFirstRunGuide) {
            FirstRunGuideView(onStartRecording: {
                showFirstRunGuide = false
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    showRecordSheet = true
                }
            })
        }
        .overlay(alignment: .top) {
            if let toast = viewModel.toastMessage {
                operationToast(message: toast.text, isError: toast.isError)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(toast.isError ? 4 : 2.5))
                            withAnimation { viewModel.dismissToast() }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.toastMessage)
        .onAppear {
            if !hasSeenFirstRunGuide {
                Task {
                    try? await Task.sleep(for: .seconds(1.0))
                    showFirstRunGuide = true
                    hasSeenFirstRunGuide = true
                }
            }
        }
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            if viewModel.pendingOfflineCount > 0 {
                Text("Offline — \(viewModel.pendingOfflineCount) pending change\(viewModel.pendingOfflineCount == 1 ? "" : "s")")
                    .font(.system(size: 12, weight: .medium))
            } else {
                Text("You're offline — changes are saved locally")
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(SVTheme.amber)
    }

    private func operationToast(message: String, isError: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 14))
            Text(message)
                .font(.system(size: 13, weight: .medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isError ? SVTheme.urgentRed : SVTheme.successGreen)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .padding(.top, 52)
    }

    private var customTabBar: some View {
        VStack(spacing: 0) {
            Rectangle().fill(SVTheme.divider).frame(height: 1 / UIScreen.main.scale)
            HStack(spacing: 0) {
                tabButton(tab: .feed, icon: "tray.fill", inactiveIcon: "tray", label: "Feed", badge: viewModel.unacknowledgedCount)
                tabButton(tab: .actions, icon: "bolt.fill", inactiveIcon: "bolt", label: "Actions", badge: 0)
                recordButton
                tabButton(tab: .review, icon: "sparkles.rectangle.stack.fill", inactiveIcon: "sparkles.rectangle.stack", label: "Review", badge: viewModel.reviewBadgeCount)
                tabButton(tab: .profile, icon: "person.fill", inactiveIcon: "person", label: "Profile", badge: 0)
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .background(
            SVTheme.surface
                .shadow(color: .black.opacity(0.04), radius: 12, y: -4)
                .ignoresSafeArea(.container, edges: .bottom)
        )
    }

    private func tabButton(tab: AppTab, icon: String, inactiveIcon: String, label: String, badge: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 3) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: selectedTab == tab ? icon : inactiveIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(selectedTab == tab ? SVTheme.accent : SVTheme.textTertiary)
                        .frame(width: 28, height: 28)

                    if badge > 0 {
                        Text("\(badge)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(minWidth: 14, minHeight: 14)
                            .background(SVTheme.urgentRed)
                            .clipShape(Circle())
                            .offset(x: 6, y: -4)
                    }
                }

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(selectedTab == tab ? SVTheme.accent : SVTheme.textTertiary.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
        }
        .sensoryFeedback(.selection, trigger: selectedTab)
    }

    private var recordButton: some View {
        Button {
            showRecordSheet = true
        } label: {
            ZStack {
                Circle()
                    .fill(SVTheme.textPrimary)
                    .frame(width: 56, height: 56)
                    .shadow(color: SVTheme.textPrimary.opacity(0.18), radius: 8, y: 4)

                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .offset(y: -18)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: showRecordSheet)
        .frame(maxWidth: .infinity)
    }
}

nonisolated enum AppTab: Hashable, Sendable {
    case feed
    case actions
    case review
    case profile
}

nonisolated enum AppRoute: Hashable, Sendable {
    case shiftNoteDetail(noteId: String)
}
