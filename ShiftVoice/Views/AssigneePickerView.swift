import SwiftUI

struct AssigneePickerView: View {
    let teamMembers: [TeamMember]
    let currentAssigneeId: String?
    let onSelect: (_ memberId: String?, _ memberName: String?) -> Void

    @State private var searchText: String = ""
    @Environment(\.dismiss) private var dismiss

    private var filteredMembers: [TeamMember] {
        if searchText.isEmpty { return teamMembers }
        return teamMembers.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.email.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if currentAssigneeId != nil {
                    Section {
                        Button {
                            onSelect(nil, nil)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "person.slash")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.textTertiary)
                                    .frame(width: 36, height: 36)
                                    .background(SVTheme.iconBackground)
                                    .clipShape(Circle())

                                Text("Unassign")
                                    .font(.subheadline)
                                    .foregroundStyle(SVTheme.urgentRed)
                            }
                        }
                    }
                }

                Section {
                    ForEach(filteredMembers) { member in
                        Button {
                            onSelect(member.id, member.name)
                        } label: {
                            HStack(spacing: 12) {
                                Text(member.avatarInitials)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(SVTheme.textSecondary)
                                    .frame(width: 36, height: 36)
                                    .background(SVTheme.iconBackground)
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(member.name)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(SVTheme.textPrimary)
                                    Text(member.roleDisplayInfo.name)
                                        .font(.caption)
                                        .foregroundStyle(SVTheme.textTertiary)
                                }

                                Spacer()

                                if currentAssigneeId == member.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.body)
                                        .foregroundStyle(SVTheme.accent)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Team Members")
                }
            }
            .searchable(text: $searchText, prompt: "Search team members")
            .navigationTitle("Assign To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }
}
