import SwiftUI

struct OnboardingTeamView: View {
    @Bindable var viewModel: OnboardingViewModel
    let onComplete: () -> Void
    @State private var appeared: Bool = false
    @State private var showReadyState: Bool = false
    @FocusState private var isAnyFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                if showReadyState {
                    readyContent
                } else {
                    inviteContent
                }
            }
            .onTapGesture {
                isAnyFieldFocused = false

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { appeared = true }
        .onChange(of: showReadyState) { _, newValue in
            if newValue {
                isAnyFieldFocused = false
            }
        }
    }

    private var inviteContent: some View {
        VStack(alignment: .leading, spacing: 32) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite your team")
                    .font(.system(size: 28, weight: .bold, design: .serif))
                    .foregroundStyle(SVTheme.textPrimary)

                Text("Add team members who'll use ShiftVoice at \(viewModel.locationName.isEmpty ? "your \(viewModel.businessType.terminology.location.lowercased())" : viewModel.locationName).")
                    .font(.system(size: 15))
                    .foregroundStyle(SVTheme.textSecondary)
                    .lineSpacing(2)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)

            VStack(spacing: 12) {
                ForEach(Array(viewModel.teamInvites.enumerated()), id: \.element.id) { index, invite in
                    inviteRow(invite: invite, index: index)
                }

                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        viewModel.addInvite()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        Text("Add team member")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(SVTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(SVTheme.accent.opacity(0.04))
                    .clipShape(.rect(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(SVTheme.accent.opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                    )
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.4).delay(0.1), value: appeared)

            VStack(spacing: 12) {
                Button {
                    guard viewModel.validateCurrentStep() else { return }
                    withAnimation(.easeOut(duration: 0.3)) {
                        showReadyState = true
                    }
                } label: {
                    Text("Continue")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(SVTheme.accent)
                        .clipShape(.rect(cornerRadius: 12))
                }
                .sensoryFeedback(.impact(weight: .light), trigger: showReadyState)

                Button {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showReadyState = true
                    }
                } label: {
                    Text("Skip for now")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SVTheme.textTertiary)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 12)
            .animation(.easeOut(duration: 0.4).delay(0.2), value: appeared)
        }
    }

    private func inviteRow(invite: TeamInvite, index: Int) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("team@example.com", text: Binding(
                        get: { viewModel.teamInvites[safe: index]?.email ?? "" },
                        set: { newValue in
                            if viewModel.teamInvites.indices.contains(index) {
                                viewModel.teamInvites[index].email = newValue
                            }
                        }
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(SVTheme.textPrimary)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .focused($isAnyFieldFocused)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            viewModel.removeInvite(invite.id)
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(SVTheme.textTertiary.opacity(0.5))
                    }
                }

                roleSelector(index: index)
            }
            .padding(14)

            if let error = viewModel.inviteErrors[invite.id] {
                HStack {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundStyle(SVTheme.urgentRed)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }
        }
        .background(SVTheme.surface)
        .clipShape(.rect(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(viewModel.inviteErrors[invite.id] != nil ? SVTheme.urgentRed.opacity(0.4) : SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func roleSelector(index: Int) -> some View {
        let selectedRole = viewModel.teamInvites[safe: index]?.roleTemplate
        return HStack(spacing: 6) {
            ForEach(viewModel.availableRoleTemplates) { role in
                let isSelected = selectedRole?.id == role.id
                Button {
                    if viewModel.teamInvites.indices.contains(index) {
                        viewModel.teamInvites[index].roleTemplate = role
                    }
                } label: {
                    Text(roleAbbreviation(role))
                        .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .white : SVTheme.textSecondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(isSelected ? SVTheme.accent : SVTheme.accent.opacity(0.06))
                        .clipShape(.rect(cornerRadius: 8))
                }
            }
        }
    }

    private func roleAbbreviation(_ role: RoleTemplate) -> String {
        let name = role.name
        if name.count <= 6 { return name }
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return words.map { String($0.prefix(1)) }.joined()
        }
        return String(name.prefix(6))
    }

    @State private var readyAppeared: Bool = false

    private var readyContent: some View {
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
                        .symbolEffect(.bounce, value: readyAppeared)
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
            .opacity(readyAppeared ? 1 : 0)
            .offset(y: readyAppeared ? 0 : 16)

            VStack(spacing: 1) {
                summaryRow(icon: viewModel.businessType.icon, label: viewModel.locationName.isEmpty ? "Your \(viewModel.businessType.terminology.location)" : viewModel.locationName, value: viewModel.businessType.rawValue)
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                summaryRow(icon: "tag", label: "Categories", value: "\(viewModel.selectedCategoryTemplates.count) active")
                Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                summaryRow(icon: "clock", label: "Shifts", value: viewModel.selectedShiftTemplates.map(\.name).joined(separator: ", "))
                if !viewModel.teamInvites.isEmpty {
                    Rectangle().fill(SVTheme.divider).frame(height: 1).padding(.leading, 52)
                    summaryRow(icon: "person.2", label: "Team invites", value: "\(viewModel.teamInvites.filter { !$0.email.isEmpty }.count) pending")
                }
            }
            .background(SVTheme.surface)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(SVTheme.surfaceBorder, lineWidth: 1)
            )
            .opacity(readyAppeared ? 1 : 0)
            .offset(y: readyAppeared ? 0 : 12)
            .animation(.easeOut(duration: 0.4).delay(0.15), value: readyAppeared)

            Button {
                onComplete()
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
            .sensoryFeedback(.impact(weight: .medium), trigger: readyAppeared)
            .opacity(readyAppeared ? 1 : 0)
            .animation(.easeOut(duration: 0.4).delay(0.3), value: readyAppeared)

            Spacer(minLength: 20)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                readyAppeared = true
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

extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
