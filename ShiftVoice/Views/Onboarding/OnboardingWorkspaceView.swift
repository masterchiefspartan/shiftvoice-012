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

                    Text("Name your location, confirm shifts, and invite your team.")
                        .font(.system(size: 15))
                        .foregroundStyle(SVTheme.textSecondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("LOCATION NAME")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)

                    TextField(locationPlaceholder, text: $viewModel.locationName)
                        .font(.system(size: 16))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(SVTheme.surface)
                        .clipShape(.rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(viewModel.locationNameError == nil ? SVTheme.surfaceBorder : SVTheme.urgentRed.opacity(0.5), lineWidth: 1))

                    if let error = viewModel.locationNameError {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(SVTheme.urgentRed)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("SHIFT CONFIG")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)

                    VStack(spacing: 1) {
                        ForEach(Array(viewModel.selectedShiftTemplates.enumerated()), id: \.element.id) { index, shift in
                            if index > 0 {
                                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                            }
                            shiftRow(shift)
                        }
                    }
                    .background(SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(SVTheme.surfaceBorder, lineWidth: 1))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("TEAM INVITE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(SVTheme.textTertiary)

                    HStack(spacing: 10) {
                        TextField("Email or phone number", text: $viewModel.inviteInput)
                            .font(.system(size: 15))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button("Add") {
                            viewModel.addInviteFromInput()
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(SVTheme.accent)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(SVTheme.surface)
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(SVTheme.surfaceBorder, lineWidth: 1))

                    if !viewModel.teamInvites.isEmpty {
                        VStack(spacing: 8) {
                            ForEach(viewModel.teamInvites) { invite in
                                HStack {
                                    Image(systemName: "person.crop.circle.badge.plus")
                                        .foregroundStyle(SVTheme.accent)
                                    Text(invite.contact)
                                        .font(.system(size: 14))
                                        .foregroundStyle(SVTheme.textPrimary)
                                    Spacer()
                                    Button {
                                        viewModel.removeInvite(invite.id)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(SVTheme.textTertiary)
                                    }
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 10)
                                .background(SVTheme.surface)
                                .clipShape(.rect(cornerRadius: 10))
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 80)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.35)) {
                appeared = true
            }
        }
    }

    private var locationPlaceholder: String {
        viewModel.selectedIndustry.locationPlaceholder
    }

    private func shiftRow(_ shift: ShiftTemplate) -> some View {
        HStack(spacing: 12) {
            Image(systemName: shift.icon)
                .foregroundStyle(SVTheme.accent)
                .frame(width: 28, height: 28)
            Text(shift.name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(SVTheme.textPrimary)
            Spacer()
            Text("\(formatHour(shift.defaultStartHour))")
                .font(.system(size: 13))
                .foregroundStyle(SVTheme.textSecondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }

    private func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour):00 \(period)"
    }
}
