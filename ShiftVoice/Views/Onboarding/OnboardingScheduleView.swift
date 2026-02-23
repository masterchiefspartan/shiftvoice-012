import SwiftUI

struct OnboardingScheduleView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shift schedule")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("Your shifts are pre-configured based on your industry. You can customize these later in settings.")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                        .lineSpacing(2)
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

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
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

                VStack(alignment: .leading, spacing: 16) {
                    Text("ACKNOWLEDGMENT")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)
                        .tracking(1.2)

                    HStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Require read receipts")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(SVTheme.textPrimary)

                            Text("Incoming shift must acknowledge \(viewModel.businessType.terminology.shiftHandoff.lowercased()) notes")
                                .font(.system(size: 13))
                                .foregroundStyle(SVTheme.textTertiary)
                        }

                        Spacer()

                        Toggle("", isOn: $viewModel.requireAcknowledgment)
                            .labelsHidden()
                            .tint(SVTheme.accent)
                    }
                    .padding(16)
                    .background(SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(SVTheme.surfaceBorder, lineWidth: 1)
                    )
                }
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)
                .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .onAppear { appeared = true }
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
