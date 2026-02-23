import SwiftUI
import GoogleSignIn
import RevenueCat

@main
struct ShiftVoiceApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var authService = AuthenticationService()
    @State private var appViewModel = AppViewModel()
    private let pushService = PushNotificationService.shared
    private let subscriptionService = SubscriptionService.shared

    init() {
        subscriptionService.configure()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isLoading {
                    LaunchLoadingView()
                } else if !authService.isSignedIn {
                    SignInView(authService: authService)
                        .transition(.opacity)
                } else if hasCompletedOnboarding {
                    ContentView(authService: authService, viewModel: appViewModel)
                        .transition(.opacity)
                } else {
                    OnboardingView(hasCompletedOnboarding: $hasCompletedOnboarding) { onboardingVM in
                        appViewModel.applyOnboardingData(
                            businessType: onboardingVM.businessType,
                            locationName: onboardingVM.locationName,
                            timezone: onboardingVM.detectedTimezone,
                            teamInvites: onboardingVM.teamInvites
                        )
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: authService.isLoading)
            .animation(.easeOut(duration: 0.25), value: authService.isSignedIn)
            .animation(.easeOut(duration: 0.25), value: hasCompletedOnboarding)
            .onChange(of: authService.isSignedIn) { _, isSignedIn in
                if isSignedIn, let userId = authService.currentUserId {
                    if let token = authService.backendToken {
                        appViewModel.setBackendAuth(token: token, userId: userId)
                    }
                    appViewModel.setAuthenticatedUser(userId)
                    subscriptionService.setUserId(userId)
                } else {
                    appViewModel.clearAuthenticatedUser()
                    hasCompletedOnboarding = false
                }
            }
            .onChange(of: authService.currentUserId) { _, userId in
                if authService.isSignedIn, let userId {
                    if let token = authService.backendToken {
                        appViewModel.setBackendAuth(token: token, userId: userId)
                    }
                    appViewModel.setAuthenticatedUser(userId)
                }
            }
            .onAppear {
                if authService.isSignedIn, let userId = authService.currentUserId {
                    if let token = authService.backendToken {
                        appViewModel.setBackendAuth(token: token, userId: userId)
                    }
                    appViewModel.setAuthenticatedUser(userId)
                }
            }
            .onOpenURL { url in
                _ = authService.handleURL(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: .networkReconnected)) { _ in
                appViewModel.handleNetworkReconnect()
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushNotificationTapped)) { notification in
                if let noteId = notification.userInfo?["noteId"] as? String {
                    appViewModel.handlePushNotificationTap(noteId: noteId)
                }
            }
            .task {
                pushService.setup()
                if pushService.authorizationStatus == .authorized {
                    pushService.checkAuthorizationStatus()
                }
            }
        }
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            SVTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(uiImage: UIImage(named: "AppIcon") ?? UIImage())
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 64, height: 64)
                    .clipShape(.rect(cornerRadius: 14))
                ProgressView()
                    .tint(SVTheme.textTertiary)
            }
        }
    }
}
