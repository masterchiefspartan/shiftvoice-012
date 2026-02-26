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

    // MARK: - Offline State Tests

    @Test func pendingOfflineCountIsZeroAfterQueueRemoval() {
        let vm = AppViewModel()
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

}
