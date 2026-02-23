import SwiftUI

struct OnboardingView: View {
    @State private var viewModel = OnboardingViewModel()
    @Binding var hasCompletedOnboarding: Bool
    var onComplete: ((OnboardingViewModel) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            headerBar

            progressBar
                .padding(.horizontal, 24)
                .padding(.top, 12)

            TabView(selection: $viewModel.currentStep) {
                OnboardingPropertyView(viewModel: viewModel)
                    .tag(0)

                OnboardingCategoriesView(viewModel: viewModel)
                    .tag(1)

                OnboardingTeamView(viewModel: viewModel, onComplete: completeOnboarding)
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeOut(duration: 0.25), value: viewModel.currentStep)

            if viewModel.currentStep < 2 {
                bottomActions
            }
        }
        .background(SVTheme.background)
    }

    private var headerBar: some View {
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
                        .frame(width: 44, height: 44)
                }
            } else {
                Spacer().frame(width: 44, height: 44)
            }

            Spacer()

            Text("Step \(viewModel.currentStep + 1) of \(viewModel.totalSteps)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SVTheme.textTertiary)
                .tracking(0.5)
                .textCase(.uppercase)

            Spacer()

            Spacer().frame(width: 44, height: 44)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let segmentWidth = width / CGFloat(viewModel.totalSteps)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(SVTheme.divider)
                    .frame(height: 3)

                RoundedRectangle(cornerRadius: 2)
                    .fill(SVTheme.accent)
                    .frame(width: segmentWidth * CGFloat(viewModel.currentStep + 1), height: 3)
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
