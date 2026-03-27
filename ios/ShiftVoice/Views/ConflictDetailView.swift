import SwiftUI

struct ConflictDetailView: View {
    let noteId: String
    @Bindable var viewModel: AppViewModel

    @Environment(\.dismiss) private var dismiss

    private var conflicts: [ConflictItem] {
        viewModel.activeConflictsForNote(noteId)
    }

    var body: some View {
        NavigationStack {
            Group {
                if conflicts.isEmpty {
                    ContentUnavailableView(
                        "No Active Conflicts",
                        systemImage: "checkmark.circle.fill",
                        description: Text("This note is in sync.")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(conflicts) { conflict in
                                conflictCard(conflict)
                            }
                        }
                        .padding(16)
                    }
                }
            }
            .navigationTitle("Resolve Conflicts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func conflictCard(_ conflict: ConflictItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text(readableFieldName(conflict.fieldName))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SVTheme.textPrimary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Your change: \(displayValue(conflict.localIntendedValue))")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
                Text("Current value: \(displayValue(conflict.serverCurrentValue))")
                    .font(.subheadline)
                    .foregroundStyle(SVTheme.textSecondary)
            }

            Text("Changed by \(conflict.serverUpdatedBy) at \(conflict.serverUpdatedAt, format: .dateTime.month(.abbreviated).day().hour().minute())")
                .font(.caption)
                .foregroundStyle(SVTheme.textTertiary)

            VStack(spacing: 8) {
                Button {
                    viewModel.resolveConflict(id: conflict.id, resolution: .keptServer)
                } label: {
                    Text("Keep Current")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.orange)
                .accessibilityLabel("Keep current value")

                Button {
                    viewModel.resolveConflict(id: conflict.id, resolution: .appliedLocal)
                } label: {
                    Text("Apply My Update")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityLabel("Apply my update")

                Button {
                    viewModel.resolveConflict(id: conflict.id, resolution: .dismissed)
                } label: {
                    Text("Dismiss")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .foregroundStyle(SVTheme.textTertiary)
                .accessibilityLabel("Dismiss conflict")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SVTheme.cardBackground)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SVTheme.surfaceBorder, lineWidth: 1)
        )
    }

    private func readableFieldName(_ field: String) -> String {
        switch field {
        case "status":
            return "Status"
        case "assigneeId":
            return "Assignee"
        case "priority":
            return "Priority"
        default:
            return field
        }
    }

    private func displayValue(_ value: String) -> String {
        value.isEmpty ? "Not set" : value
    }
}
