import SwiftUI

struct OnboardingIndustryView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Built for operations\nlike yours.")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("What's your industry?")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(BusinessType.allCases) { type in
                        industryCard(type)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private func industryCard(_ type: BusinessType) -> some View {
        let isSelected = viewModel.businessType == type

        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                viewModel.selectBusinessType(type)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 16))
                    .foregroundStyle(isSelected ? SVTheme.accent : SVTheme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(isSelected ? SVTheme.accent.opacity(0.1) : SVTheme.iconBackground)
                    .clipShape(.rect(cornerRadius: 8))

                Text(type.rawValue)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? SVTheme.textPrimary : SVTheme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? SVTheme.accent.opacity(0.04) : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? SVTheme.accent.opacity(0.4) : SVTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .sensoryFeedback(.selection, trigger: viewModel.businessType)
    }
}
