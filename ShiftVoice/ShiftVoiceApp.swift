import SwiftUI
import GoogleSignIn

@main
struct ShiftVoiceApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var authService = AuthenticationService()
    @State private var appViewModel = AppViewModel()

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
            .onOpenURL { url in
                _ = authService.handleURL(url)
            }
        }
    }
}

struct LaunchLoadingView: View {
    var body: some View {
        ZStack {
            SVTheme.background.ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(SVTheme.accent)
                ProgressView()
                    .tint(SVTheme.textTertiary)
            }
        }
    }
}
