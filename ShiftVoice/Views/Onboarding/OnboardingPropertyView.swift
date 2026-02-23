import SwiftUI

struct OnboardingPropertyView: View {
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
                    Text("Set up your \(viewModel.businessType.terminology.location.lowercased())")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("Tailor ShiftVoice for your team in under 2 minutes.")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineSpacing(2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

                VStack(alignment: .leading, spacing: 12) {
                    Text("INDUSTRY")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1.2)

                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(BusinessType.allCases) { type in
                            industryCard(type)
                        }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                VStack(alignment: .leading, spacing: 12) {
                    Text("\(viewModel.businessType.terminology.location.uppercased()) NAME")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1.2)

                    VStack(alignment: .leading, spacing: 6) {
                        TextField(locationPlaceholder, text: $viewModel.locationName)
                            .font(.system(size: 16))
                            .foregroundStyle(SVTheme.textPrimary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(SVTheme.surface)
                            .clipShape(.rect(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(viewModel.locationNameError != nil ? SVTheme.urgentRed.opacity(0.6) : SVTheme.surfaceBorder, lineWidth: 1)
                            )

                        if let error = viewModel.locationNameError {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(SVTheme.urgentRed)
                        }
                    }
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                VStack(alignment: .leading, spacing: 12) {
                    Text("TIMEZONE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1.2)

                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .font(.system(size: 16))
                            .foregroundStyle(SVTheme.textTertiary)

                        Text(viewModel.formattedTimezone)
                            .font(.system(size: 15))
                            .foregroundStyle(SVTheme.textPrimary)

                        Spacer()

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(SVTheme.accentGreen)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )

                    Text("Auto-detected from your device")
                        .font(.system(size: 12))
                        .foregroundStyle(SVTheme.textTertiary)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

                Spacer(minLength: 80)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { appeared = true }
    }

    private var locationPlaceholder: String {
        switch viewModel.businessType {
        case .restaurant: return "e.g. The Ember Room"
        case .barPub: return "e.g. The Copper Tap"
        case .hotel: return "e.g. Grand Meridian Hotel"
        case .cafe: return "e.g. Morning Brew Café"
        case .retail: return "e.g. Main Street Store"
        case .healthcare: return "e.g. Cedar Valley Medical"
        case .manufacturing: return "e.g. Westside Plant A"
        case .security: return "e.g. Riverside Campus"
        case .propertyManagement: return "e.g. Oakwood Apartments"
        case .construction: return "e.g. Harbor Bridge Project"
        case .other: return "e.g. My Location"
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
