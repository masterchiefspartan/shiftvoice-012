import SwiftUI

struct OnboardingCategoriesView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false

    private var allTemplates: [CategoryTemplate] {
        viewModel.businessType.industryTemplate.defaultCategories
    }

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Priority categories")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("What matters most during your \(viewModel.businessType.terminology.shiftHandoff.lowercased())s? We've preselected based on your \(viewModel.businessType.rawValue.lowercased()) setup.")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineSpacing(2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(viewModel.selectedCategoryTemplates.count) selected")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SVTheme.accent)

                        Spacer()

                        Button {
                            withAnimation(.easeOut(duration: 0.15)) {
                                if viewModel.selectedCategoryTemplates.count == allTemplates.count {
                                    viewModel.selectedCategoryTemplates = []
                                } else {
                                    viewModel.selectedCategoryTemplates = Set(allTemplates)
                                }
                            }
                        } label: {
                            Text(viewModel.selectedCategoryTemplates.count == allTemplates.count ? "Deselect all" : "Select all")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SVTheme.textTertiary)
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(allTemplates) { template in
                            categoryChip(template)
                        }
                    }

                    if let error = viewModel.categoryError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(SVTheme.urgentRed)
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .onAppear { appeared = true }
    }

    private func categoryChip(_ template: CategoryTemplate) -> some View {
        let isSelected = viewModel.selectedCategoryTemplates.contains(template)
        let color = SVTheme.color(fromHex: template.colorHex)

        return Button {
            withAnimation(.easeOut(duration: 0.12)) {
                viewModel.toggleCategoryTemplate(template)
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: template.icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? color : SVTheme.textTertiary)
                    .frame(width: 28, height: 28)
                    .background(isSelected ? color.opacity(0.12) : SVTheme.iconBackground)
                    .clipShape(.rect(cornerRadius: 6))

                Text(template.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isSelected ? SVTheme.textPrimary : SVTheme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(color)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? color.opacity(0.04) : SVTheme.surface)
            .clipShape(.rect(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isSelected ? color.opacity(0.3) : SVTheme.surfaceBorder, lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .sensoryFeedback(.selection, trigger: viewModel.selectedCategoryTemplates.count)
    }
}
