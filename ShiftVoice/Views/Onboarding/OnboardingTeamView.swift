import SwiftUI

struct OnboardingTeamView: View {
    @Bindable var viewModel: OnboardingViewModel
    @State private var appeared: Bool = false
    @FocusState private var isAnyFieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite your team")
                        .font(.system(size: 28, weight: .bold, design: .serif))
                        .foregroundStyle(SVTheme.textPrimary)

                    Text("ShiftVoice works best when your whole shift is on it. Team members get free access to view and respond.")
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

                Spacer(minLength: 80)
            }
            .onTapGesture {
                isAnyFieldFocused = false
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                appeared = true
            }
            if viewModel.teamInvites.isEmpty {
                viewModel.addInvite()
            }
        }
    }

    private func inviteRow(invite: TeamInvite, index: Int) -> some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    TextField("Email or phone number", text: Binding(
                        get: { viewModel.teamInvites[safe: index]?.contact ?? "" },
                        set: { newValue in
                            if viewModel.teamInvites.indices.contains(index) {
                                viewModel.teamInvites[index].contact = newValue
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
}
