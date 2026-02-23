import SwiftUI

struct ContentView: View {
    let authService: AuthenticationService
    let viewModel: AppViewModel
    @State private var selectedTab: AppTab = .inbox
    @State private var showRecordSheet: Bool = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ZStack {
                ShiftFeedView(viewModel: viewModel)
                    .opacity(selectedTab == .inbox ? 1 : 0)
                    .allowsHitTesting(selectedTab == .inbox)

                DashboardView(viewModel: viewModel)
                    .opacity(selectedTab == .actions ? 1 : 0)
                    .allowsHitTesting(selectedTab == .actions)

                SettingsView(viewModel: viewModel, authService: authService)
                    .opacity(selectedTab == .profile ? 1 : 0)
                    .allowsHitTesting(selectedTab == .profile)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                if viewModel.isOffline {
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
        .overlay(alignment: .top) {
            if case .success(let message) = viewModel.operationState {
                operationToast(message: message, isError: false)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(2))
                            withAnimation { viewModel.dismissOperationState() }
                        }
                    }
            } else if case .failure(let message) = viewModel.operationState {
                operationToast(message: message, isError: true)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            withAnimation { viewModel.dismissOperationState() }
                        }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: viewModel.operationState.isVisible)
    }

    private var offlineBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text("You're offline — changes are saved locally")
                .font(.system(size: 12, weight: .medium))
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
        HStack(spacing: 0) {
            tabButton(tab: .inbox, icon: "tray.fill", inactiveIcon: "tray", label: "Inbox", badge: viewModel.unacknowledgedCount)

            tabButton(tab: .actions, icon: "bolt.fill", inactiveIcon: "bolt", label: "Actions", badge: 0)

            recordButton

            Spacer().frame(maxWidth: .infinity)

            tabButton(tab: .profile, icon: "person.fill", inactiveIcon: "person", label: "Profile", badge: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(
            SVTheme.surface
                .shadow(color: .black.opacity(0.04), radius: 12, y: -4)
        )
        .overlay(alignment: .top) {
            Rectangle().fill(SVTheme.divider).frame(height: 1 / UIScreen.main.scale)
        }
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
    case inbox
    case actions
    case profile
}
