import Foundation

@MainActor
final class ConflictDetector {
    private let trackedFields: [String] = ["status", "assigneeId", "priority"]
    let conflictStore: ConflictStore
    private let syncEventLogger: SyncEventLogger

    init(conflictStore: ConflictStore, syncEventLogger: SyncEventLogger = .shared) {
        self.conflictStore = conflictStore
        self.syncEventLogger = syncEventLogger
    }

    func evaluateSnapshot(
        serverNote: ShiftNote,
        localPendingEdit: PendingOp?,
        editBaseline: EditBaseline?
    ) -> [ConflictItem] {
        guard let editBaseline else { return [] }
        guard let localPendingEdit else { return [] }

        let serverFields = collaborativeFields(from: serverNote)
        let serverFieldTimestamps = collaborativeFieldServerTimestamps(from: serverNote)
        let serverUpdatedByUserId = serverNote.updatedByUserId ?? ""
        let localIntendedFields = localPendingEdit.intendedFields ?? editBaseline.fields

        var conflicts: [ConflictItem] = []
        for field in trackedFields {
            guard let serverTimestamp = serverFieldTimestamps[field] else { continue }
            guard serverTimestamp > editBaseline.updatedAtServer else { continue }

            let baselineValue = editBaseline.fields[field] ?? ""
            let localIntendedValue = localIntendedFields[field] ?? baselineValue
            let serverCurrentValue = serverFields[field] ?? ""

            guard localIntendedValue != serverCurrentValue else { continue }
            guard hasValueChangedFromBaseline(
                baselineValue: baselineValue,
                localIntendedValue: localIntendedValue,
                serverCurrentValue: serverCurrentValue
            ) else {
                continue
            }

            let alreadyTracked = conflictStore.activeConflicts.contains {
                $0.noteId == serverNote.id && $0.fieldName == field
            }
            if alreadyTracked {
                continue
            }

            let conflict = ConflictItem(
                noteId: serverNote.id,
                fieldName: field,
                localIntendedValue: localIntendedValue,
                serverCurrentValue: serverCurrentValue,
                serverUpdatedBy: serverUpdatedByUserId,
                serverUpdatedAt: serverTimestamp,
                localEditStartedAt: editBaseline.updatedAtServer
            )
            conflicts.append(conflict)
            syncEventLogger.conflictDetected(noteId: conflict.noteId, field: conflict.fieldName)
        }

        return conflicts
    }

    func evaluateSnapshot(
        serverNote: ShiftNote,
        localPendingEdit: PendingOp?,
        editBaseline: EditBaseline?,
        isFromCache: Bool
    ) -> [ConflictItem] {
        guard !isFromCache else { return [] }
        return evaluateSnapshot(serverNote: serverNote, localPendingEdit: localPendingEdit, editBaseline: editBaseline)
    }

    private func hasValueChangedFromBaseline(
        baselineValue: String,
        localIntendedValue: String,
        serverCurrentValue: String
    ) -> Bool {
        let localChanged = localIntendedValue != baselineValue
        let serverChanged = serverCurrentValue != baselineValue
        return localChanged || serverChanged
    }

    private func collaborativeFields(from note: ShiftNote) -> [String: String] {
        let prioritizedActionItem = note.actionItems.max(by: { $0.updatedAt < $1.updatedAt })
        return [
            "status": prioritizedActionItem?.status.rawValue ?? "",
            "assigneeId": prioritizedActionItem?.assigneeId ?? "",
            "priority": prioritizedActionItem?.urgency.rawValue ?? ""
        ]
    }

    private func collaborativeFieldServerTimestamps(from note: ShiftNote) -> [String: Date] {
        let prioritizedActionItem = note.actionItems.max(by: { $0.updatedAt < $1.updatedAt })
        return [
            "status": prioritizedActionItem?.statusUpdatedAtServer ?? note.updatedAtServer ?? note.updatedAt,
            "assigneeId": prioritizedActionItem?.assigneeUpdatedAtServer ?? note.updatedAtServer ?? note.updatedAt,
            "priority": note.updatedAtServer ?? note.updatedAt
        ]
    }
}
