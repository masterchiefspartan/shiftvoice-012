import SwiftUI

struct OnboardingWorkspaceView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Set up your workspace")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("We've pre-configured your shifts based on your \(viewModel.businessType.rawValue.lowercased()) setup.")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineSpacing(2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

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
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                VStack(alignment: .leading, spacing: 12) {
                    Text("SHIFTS")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1.2)

                    VStack(spacing: 1) {
                        ForEach(Array(viewModel.selectedShiftTemplates.enumerated()), id: \.element.id) { index, shift in
                            if index > 0 {
                                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 64)
                            }
                            shiftRow(shift: shift)
                        }
                    }
                    .background(SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )

                    Text("You can customize shifts later in Settings")
                        .font(.system(size: 12))
                        .foregroundStyle(SVTheme.textTertiary)
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
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
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

    private func shiftRow(shift: ShiftTemplate) -> some View {
        let iconColor = shiftColor(for: shift.icon)
        let formattedHour = formatHour(shift.defaultStartHour)

        return HStack(spacing: 14) {
            Image(systemName: shift.icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12))
                .clipShape(.rect(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(shift.name)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SVTheme.textPrimary)

                Text("Starts at \(formattedHour)")
                    .font(.system(size: 12))
                    .foregroundStyle(SVTheme.textTertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    private func shiftColor(for icon: String) -> Color {
        switch icon {
        case "sunrise.fill": return Color(red: 245/255, green: 158/255, blue: 11/255)
        case "sun.max.fill": return Color(red: 234/255, green: 179/255, blue: 8/255)
        case "sunset.fill": return Color(red: 234/255, green: 88/255, blue: 12/255)
        case "moon.stars.fill": return Color(red: 99/255, green: 102/255, blue: 241/255)
        case "moon.zzz.fill": return Color(red: 79/255, green: 70/255, blue: 229/255)
        default: return SVTheme.accent
        }
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(period)"
    }
}
