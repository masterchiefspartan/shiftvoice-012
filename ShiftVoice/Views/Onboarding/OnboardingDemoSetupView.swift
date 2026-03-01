import SwiftUI

struct OnboardingDemoSetupView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "mic.circle.fill")
                .font(.system(size: 88))
                .foregroundStyle(SVTheme.accent)

            VStack(spacing: 10) {
                Text("Let's do a quick demo")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SVTheme.textPrimary)

                Text("You can record a real shift update now, or preview with a sample.")
                    .font(.system(size: 15))
                    .foregroundStyle(SVTheme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 12) {
                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.continueFromDemoSetup()
                    }
                } label: {
                    Text("Start Recording")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SVTheme.accent)
                        .clipShape(.rect(cornerRadius: 12))
                }

                Button {
                    withAnimation(.easeOut(duration: 0.25)) {
                        viewModel.continueFromDemoSetup()
                    }
                } label: {
                    Text("See a sample instead")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SVTheme.textSecondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
