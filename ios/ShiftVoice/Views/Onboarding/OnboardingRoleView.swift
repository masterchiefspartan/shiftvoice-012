import SwiftUI

struct OnboardingRoleView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                Spacer(minLength: 40)

                VStack(spacing: 16) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(SVTheme.accent)
                        .symbolEffect(.pulse, options: .repeating)

                    VStack(spacing: 8) {
                        Text("Your shift runs on words.")
                            .font(.system(size: 28, weight: .bold, design: .serif))
                            .foregroundStyle(SVTheme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text("Let's make sure none get lost.")
                            .font(.system(size: 17))
                            .foregroundStyle(SVTheme.textSecondary)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 16)

                VStack(alignment: .leading, spacing: 12) {
                    Text("What best describes your role?")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SVTheme.textSecondary)
                        .padding(.horizontal, 4)

                    ForEach(OnboardingRole.allCases) { role in
                        roleCard(role)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private func roleCard(_ role: OnboardingRole) -> some View {
        let isSelected = viewModel.selectedRole == role

        return Button {
            withAnimation(.spring(duration: 0.25)) {
                viewModel.selectRole(role)
            }
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                withAnimation(.easeOut(duration: 0.25)) {
                    viewModel.advance()
                }
            }
        } label: {
            HStack(spacing: 16) {
                Image(systemName: role.icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? SVTheme.accent.opacity(0.1) : SVTheme.iconBackground)
                    .clipShape(.rect(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(role.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text(role.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(SVTheme.textTertiary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(SVTheme.accent)
                }
            }
            .padding(16)
            .background(isSelected ? SVTheme.accent.opacity(0.04) : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? SVTheme.accent.opacity(0.4) : SVTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedRole)
    }
}
