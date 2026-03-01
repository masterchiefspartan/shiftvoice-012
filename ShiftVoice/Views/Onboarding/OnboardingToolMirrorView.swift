import SwiftUI

struct OnboardingToolMirrorView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("How are you handling handoffs today?")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SVTheme.textPrimary)

                VStack(spacing: 10) {
                    ForEach(OnboardingCurrentTool.allCases) { tool in
                        toolRow(tool)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Mirror Moment")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1)

                    Text(viewModel.mirrorMomentText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(SVTheme.textPrimary)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(SVTheme.surface)
                        .clipShape(.rect(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                        )
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
    }

    private func toolRow(_ tool: OnboardingCurrentTool) -> some View {
        let isSelected: Bool = viewModel.selectedTool == tool

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.selectedTool = tool
            }
        } label: {
            HStack {
                Text(tool.rawValue)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(SVTheme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(isSelected ? SVTheme.accent.opacity(0.08) : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? SVTheme.accent.opacity(0.5) : SVTheme.surfaceBorder, lineWidth: 1)
            )
        }
    }
}
