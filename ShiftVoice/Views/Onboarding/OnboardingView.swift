import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @State private var blackTransitionOpacity: Double = 0
    @Binding var hasCompletedOnboarding: Bool
    var onComplete: ((OnboardingViewModel) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 16)
                .padding(.top, 8)

            if viewModel.currentStep != 5 {
                progressBar
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
            }
            

            Group {
                switch viewModel.currentStep {
                case 0:
                    OnboardingRoleView(viewModel: viewModel)
                case 1:
                    OnboardingIndustryView(viewModel: viewModel)
                case 2:
                    OnboardingPainPointsView(viewModel: viewModel)
                case 3:
                    OnboardingToolMirrorView(viewModel: viewModel)
                case 4:
                    OnboardingDemoSetupView(viewModel: viewModel)
                case 5:
                    OnboardingLiveRecordingView(viewModel: viewModel)
                case 6:
                    OnboardingAIRevealView(viewModel: viewModel)
                case 7:
                    OnboardingWorkspaceView(viewModel: viewModel)
                case 8:
                    OnboardingPaywallView(viewModel: viewModel, onSkip: {
                        viewModel.paywallSkipped = true
                        completeOnboarding()
                    }, onPurchaseSuccess: {
                        completeOnboarding()
                    })
                default:
                    EmptyView()
                }
            }
            .animation(.easeOut(duration: 0.3), value: viewModel.currentStep)

            if shouldShowBottomActions {
                bottomActions
            }
        }
        .background(SVTheme.background)
        .overlay {
            Color.black
                .opacity(blackTransitionOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onChange(of: viewModel.currentStep) { oldValue, newValue in
            guard oldValue == 3, newValue == 4 else { return }
            Task {
                withAnimation(.easeInOut(duration: 0.16)) {
                    blackTransitionOpacity = 1
                }
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeInOut(duration: 0.2)) {
                    blackTransitionOpacity = 0
                }
            }
        }
    }

    private var shouldShowBottomActions: Bool {
        switch viewModel.currentStep {
        case 0, 1, 4, 5, 6, 8:
            return false
        default:
            return true
        }
    }

    private var topBar: some View {
        HStack {
            if viewModel.currentStep > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.goBack()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(SVTheme.surface)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                }
            } else {
                Color.clear
                    .frame(width: 36, height: 36)
            }

            Spacer()
        }
        .frame(height: 44)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(SVTheme.divider)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2)
                    .fill(SVTheme.accent)
                    .frame(width: width * viewModel.progress, height: 3)
                    .animation(.easeOut(duration: 0.3), value: viewModel.currentStep)
            }
        }
        .frame(height: 3)
    }

    private var bottomActions: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.advance()
            }
        } label: {
            Text("Continue")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(viewModel.canAdvance ? SVTheme.accent : SVTheme.accent.opacity(0.4))
                .clipShape(.rect(cornerRadius: 12))
        }
        .disabled(!viewModel.canAdvance)
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.currentStep)
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    private func completeOnboarding() {
        onComplete?(viewModel)
        withAnimation(.easeOut(duration: 0.3)) {
            hasCompletedOnboarding = true
        }
    }
}
