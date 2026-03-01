import SwiftUI

struct OnboardingCompletionView: View {
    let viewModel: OnboardingViewModel
    let onFinish: () -> Void
    @State private var appeared: Bool = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer(minLength: 40)

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(SVTheme.accentGreen.opacity(0.1))
                        .frame(width: 80, height: 80)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(SVTheme.accentGreen)
                        .symbolEffect(.bounce, value: appeared)
                }

                VStack(spacing: 8) {
                    Text("You're all set")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("Ready to run your first \(viewModel.businessType.terminology.shiftHandoff.lowercased()).")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 16)

            VStack(spacing: 1) {
                summaryRow(icon: viewModel.businessType.icon, label: viewModel.locationName.isEmpty ? "Your \(viewModel.businessType.terminology.location)" : viewModel.locationName, value: viewModel.businessType.rawValue)
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                summaryRow(icon: "clock", label: "Shifts", value: viewModel.selectedShiftTemplates.map(\.name).joined(separator: ", "))
                if !viewModel.validInvites.isEmpty {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                    summaryRow(icon: "person.2", label: "Team invites", value: "\(viewModel.validInvites.count) pending")
                }
                if !viewModel.paywallSkipped {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                    summaryRow(icon: "sparkles", label: "Trial", value: "7-day free trial active")
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
            .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)

            Button {
                onFinish()
            } label: {
                HStack(spacing: 8) {
                    Text("Start using ShiftVoice")
                        .font(.system(size: 16, weight: .semibold))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(SVTheme.accent)
                .clipShape(.rect(cornerRadius: 12))
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: appeared)
            .opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: appeared)

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 24)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
        }
    }

    private func summaryRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(SVTheme.textTertiary)
                .frame(width: 28, height: 28)

            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SVTheme.textPrimary)

            Spacer()

            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(SVTheme.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
