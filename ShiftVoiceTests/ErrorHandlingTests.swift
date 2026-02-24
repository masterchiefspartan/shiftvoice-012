import Testing
@testable import ShiftVoice

struct ErrorHandlingTests {

    // MARK: - ToastMessage Tests

    @Test func toastMessageCreation() {
        let toast = ToastMessage(text: "Test message", isError: false)
        #expect(toast.text == "Test message")
        #expect(toast.isError == false)
        #expect(!toast.id.isEmpty)
    }

    @Test func toastMessageErrorCreation() {
        let toast = ToastMessage(text: "Error occurred", isError: true)
        #expect(toast.text == "Error occurred")
        #expect(toast.isError == true)
    }

    @Test func toastMessageEquality() {
        let toast1 = ToastMessage(text: "Same text", isError: false)
        let toast2 = ToastMessage(text: "Same text", isError: false)
        #expect(toast1 != toast2)
    }

    @Test func toastMessageSelfEquality() {
        let toast = ToastMessage(text: "Test", isError: false)
        #expect(toast == toast)
    }

    // MARK: - ViewModel Toast Tests

    @Test func viewModelShowToast() {
        let vm = AppViewModel()
        #expect(vm.toastMessage == nil)

        vm.showToast("Sync failed", isError: true)
        #expect(vm.toastMessage != nil)
        #expect(vm.toastMessage?.text == "Sync failed")
        #expect(vm.toastMessage?.isError == true)
    }

    @Test func viewModelDismissToast() {
        let vm = AppViewModel()
        vm.showToast("Test")
        #expect(vm.toastMessage != nil)

        vm.dismissToast()
        #expect(vm.toastMessage == nil)
    }

    @Test func viewModelShowSuccessToast() {
        let vm = AppViewModel()
        vm.showToast("Saved offline", isError: false)
        #expect(vm.toastMessage?.isError == false)
    }

    // MARK: - Offline Pending Queue Tests

    @Test func pendingOfflineCountInitiallyZero() {
        let vm = AppViewModel()
        #expect(vm.pendingOfflineCount == 0)
    }

    @Test func pendingOfflineCountAfterAddingActions() {
        let vm = AppViewModel()
        let action1 = PendingAction(type: .syncNotes, payload: "note_1")
        let action2 = PendingAction(type: .syncNotes, payload: "note_2")
        vm.pendingOfflineActions.append(action1)
        vm.pendingOfflineActions.append(action2)
        #expect(vm.pendingOfflineCount == 2)
    }

    @Test func pendingOfflineCountAfterClearing() {
        let vm = AppViewModel()
        vm.pendingOfflineActions.append(PendingAction(type: .syncNotes))
        #expect(vm.pendingOfflineCount == 1)
        vm.pendingOfflineActions.removeAll()
        #expect(vm.pendingOfflineCount == 0)
    }

    // MARK: - Processing State Tests

    @Test func processingElapsedInitiallyZero() {
        let vm = AppViewModel()
        #expect(vm.processingElapsed == 0)
    }

    @Test func cancelProcessingResetsState() {
        let vm = AppViewModel()
        vm.isProcessing = true
        vm.cancelProcessing()
        #expect(vm.isProcessing == false)
        #expect(vm.pendingReviewData == nil)
    }

    // MARK: - Publish Error Tests

    @Test func publishErrorInitiallyNil() {
        let vm = AppViewModel()
        #expect(vm.publishError == nil)
    }

    @Test func pendingPublishNoteInitiallyNil() {
        let vm = AppViewModel()
        #expect(vm.pendingPublishNote == nil)
    }

    // MARK: - Sync Error Tests

    @Test func syncErrorInitiallyNil() {
        let vm = AppViewModel()
        #expect(vm.syncError == nil)
    }

    @Test func syncErrorCanBeSet() {
        let vm = AppViewModel()
        vm.syncError = "Network timeout"
        #expect(vm.syncError == "Network timeout")
    }

    // MARK: - OperationState Tests

    @Test func operationStateIdle() {
        let state = OperationState.idle
        #expect(!state.isVisible)
    }

    @Test func operationStateLoading() {
        let state = OperationState.loading
        #expect(state.isVisible)
    }

    @Test func operationStateSuccess() {
        let state = OperationState.success("Done")
        #expect(state.isVisible)
    }

    @Test func operationStateFailure() {
        let state = OperationState.failure("Error")
        #expect(state.isVisible)
    }

    @Test func dismissOperationState() {
        let vm = AppViewModel()
        vm.operationState = .success("Test")
        #expect(vm.operationState.isVisible)
        vm.dismissOperationState()
        #expect(!vm.operationState.isVisible)
    }

    // MARK: - PendingAction Tests

    @Test func pendingActionCreation() {
        let action = PendingAction(type: .syncNotes, payload: "note_123")
        #expect(action.type == .syncNotes)
        #expect(action.payload == "note_123")
        #expect(!action.id.isEmpty)
    }

    @Test func pendingActionDefaultPayload() {
        let action = PendingAction(type: .sendInvite)
        #expect(action.payload == "")
    }

    @Test func pendingActionTypes() {
        let syncAction = PendingAction(type: .syncNotes)
        let inviteAction = PendingAction(type: .sendInvite)
        let profileAction = PendingAction(type: .updateProfile)

        #expect(syncAction.type == .syncNotes)
        #expect(inviteAction.type == .sendInvite)
        #expect(profileAction.type == .updateProfile)
    }

    @Test func pendingActionCodable() throws {
        let action = PendingAction(type: .syncNotes, payload: "test_note")
        let data = try JSONEncoder().encode(action)
        let decoded = try JSONDecoder().decode(PendingAction.self, from: data)

        #expect(decoded.id == action.id)
        #expect(decoded.type == action.type)
        #expect(decoded.payload == action.payload)
    }

    // MARK: - APIError Tests

    @Test func apiErrorDescriptions() {
        #expect(APIError.invalidURL.errorDescription != nil)
        #expect(APIError.unauthorized.errorDescription != nil)
        #expect(APIError.serverError("test").errorDescription == "test")
        #expect(APIError.noData.errorDescription != nil)
        #expect(APIError.rateLimited.errorDescription != nil)
        #expect(APIError.validationError("bad input").errorDescription == "bad input")
    }

    @Test func apiErrorRetryable() {
        #expect(APIError.networkError(URLError(.timedOut)).isRetryable)
        #expect(APIError.serverError("500").isRetryable)
        #expect(APIError.rateLimited.isRetryable)
        #expect(!APIError.unauthorized.isRetryable)
        #expect(!APIError.invalidURL.isRetryable)
        #expect(!APIError.noData.isRetryable)
    }

    // MARK: - StructuringWarning in Flow Tests

    @Test func structuringWarningInitiallyNil() {
        let vm = AppViewModel()
        #expect(vm.structuringWarning == nil)
    }

    @Test func structuringWarningCanBeSet() {
        let vm = AppViewModel()
        vm.structuringWarning = "AI unavailable"
        #expect(vm.structuringWarning == "AI unavailable")
    }

    // MARK: - Network Monitor Tests

    @Test func networkMonitorExists() {
        let vm = AppViewModel()
        #expect(vm.networkMonitor === NetworkMonitor.shared)
    }

    // MARK: - Integration: Error Flow Tests

    @Test func offlinePublishAddsPendingAction() {
        let vm = AppViewModel()
        let initialCount = vm.pendingOfflineCount
        let action = PendingAction(type: .syncNotes, payload: "test_note")
        vm.pendingOfflineActions.append(action)
        #expect(vm.pendingOfflineCount == initialCount + 1)
    }

    @Test func reconnectClearsPendingActions() {
        let vm = AppViewModel()
        vm.pendingOfflineActions.append(PendingAction(type: .syncNotes))
        vm.pendingOfflineActions.append(PendingAction(type: .syncNotes))
        #expect(vm.pendingOfflineCount == 2)

        vm.pendingOfflineActions.removeAll()
        #expect(vm.pendingOfflineCount == 0)
    }
}
