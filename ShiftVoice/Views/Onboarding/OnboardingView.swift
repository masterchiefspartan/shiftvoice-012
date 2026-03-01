import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Binding var hasCompletedOnboarding: Bool
    var onComplete: ((OnboardingViewModel) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.currentStep < 5 {
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
                    OnboardingWorkspaceView(viewModel: viewModel)
                case 3:
                    OnboardingTeamView(viewModel: viewModel)
                case 4:
                    OnboardingPaywallView(viewModel: viewModel, onSkip: {
                        viewModel.paywallSkipped = true
                        withAnimation(.easeOut(duration: 0.3)) {
                            viewModel.currentStep = 5
                        }
                    }, onPurchaseSuccess: {
                        withAnimation(.easeOut(duration: 0.3)) {
                            viewModel.currentStep = 5
                        }
                    })
                case 5:
                    OnboardingCompletionView(viewModel: viewModel, onFinish: completeOnboarding)
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
    }

    private var shouldShowBottomActions: Bool {
        switch viewModel.currentStep {
        case 0: return false
        case 4, 5: return false
        default: return true
        }
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
        VStack(spacing: 12) {
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

            if viewModel.currentStep > 0 {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.goBack()
                    }
                } label: {
                    Text("Back")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
        }
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
