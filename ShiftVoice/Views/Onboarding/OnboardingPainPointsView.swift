import SwiftUI

struct OnboardingPainPointsView: View {
    @Bindable var viewModel: OnboardingViewModel

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("What breaks most often?")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SVTheme.textPrimary)

                Text("Pick all that apply.")
                    .font(.system(size: 15))
                    .foregroundStyle(SVTheme.textSecondary)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(OnboardingPainPoint.allCases) { point in
                        painPointCard(point)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 80)
        }
    }

    private func painPointCard(_ point: OnboardingPainPoint) -> some View {
        let isSelected: Bool = viewModel.selectedPainPoints.contains(point)

        return Button {
            withAnimation(.easeOut(duration: 0.2)) {
                viewModel.togglePainPoint(point)
            }
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: point.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)

                Text(point.rawValue)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(isSelected ? SVTheme.accent.opacity(0.08) : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? SVTheme.accent.opacity(0.5) : SVTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
    }
}
