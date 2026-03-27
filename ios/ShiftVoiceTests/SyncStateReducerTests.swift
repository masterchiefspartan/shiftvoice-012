import Testing
@testable import ShiftVoice

struct SyncStateReducerTests {
    nonisolated private struct CaseInput: Sendable {
        let isConnected: Bool
        let snapshotFreshness: SnapshotFreshness
        let hasPendingWrites: Bool
        let hasServerSnapshotSinceReconnect: Bool
        let hasError: Bool
        let pendingNoteCount: Int
        let pendingDeleteCount: Int

        var syncInput: SyncStateInput {
            SyncStateInput(
                isConnected: isConnected,
                snapshotFreshness: snapshotFreshness,
                hasPendingWrites: hasPendingWrites,
                hasServerSnapshotSinceReconnect: hasServerSnapshotSinceReconnect,
                lastWriteError: hasError ? .permissionDenied : nil,
                pendingNoteCount: pendingNoteCount,
                pendingDeleteCount: pendingDeleteCount
            )
        }
    }

    nonisolated private func oracleState(for input: CaseInput) -> SyncState {
        if !input.isConnected {
            return .offline
        }
        if input.hasError {
            return .error
        }
        if input.hasPendingWrites || input.pendingNoteCount > 0 || input.pendingDeleteCount > 0 {
            return .syncing
        }
        if input.hasServerSnapshotSinceReconnect || input.snapshotFreshness == .server {
            return .onlineFresh
        }
        return .onlineCache
    }

    @Test func truthTableAllInputCombinationsMatchReducer() {
        let reachability: [Bool] = [false, true]
        let freshness: [SnapshotFreshness] = [.none, .cache, .server]
        let metadataPending: [Bool] = [false, true]
        let serverSinceReconnect: [Bool] = [false, true]
        let writeError: [Bool] = [false, true]
        let pendingCounts: [Int] = [0, 1]

        for isConnected in reachability {
            for snapshotFreshness in freshness {
                for hasPendingWrites in metadataPending {
                    for hasServerSnapshotSinceReconnect in serverSinceReconnect {
                        for hasError in writeError {
                            for pendingNoteCount in pendingCounts {
                                for pendingDeleteCount in pendingCounts {
                                    let input = CaseInput(
                                        isConnected: isConnected,
                                        snapshotFreshness: snapshotFreshness,
                                        hasPendingWrites: hasPendingWrites,
                                        hasServerSnapshotSinceReconnect: hasServerSnapshotSinceReconnect,
                                        hasError: hasError,
                                        pendingNoteCount: pendingNoteCount,
                                        pendingDeleteCount: pendingDeleteCount
                                    )

                                    let actual = SyncStateReducer.reduce(input.syncInput)
                                    let expected = oracleState(for: input)

                                    #expect(actual == expected)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @Test func allChangesSyncedClaimBlockedWithoutServerSnapshotAfterReconnect() {
        let input = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .cache,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: false,
            lastWriteError: nil,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )

        #expect(SyncStateReducer.canClaimAllChangesSynced(for: input) == false)
        #expect(SyncStateReducer.reduce(input) == .onlineCache)
    }

    @Test func allChangesSyncedClaimBlockedWhenWriteErrorExists() {
        let input = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: .invalidData,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )

        #expect(SyncStateReducer.canClaimAllChangesSynced(for: input) == false)
        #expect(SyncStateReducer.reduce(input) == .error)
    }

    @Test func allChangesSyncedClaimBlockedWhenPendingIdsExist() {
        let input = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: nil,
            pendingNoteCount: 1,
            pendingDeleteCount: 0
        )

        #expect(SyncStateReducer.canClaimAllChangesSynced(for: input) == false)
        #expect(SyncStateReducer.reduce(input) == .syncing)
    }

    @Test func transitionPathOfflineToOnlineCacheToSyncingToOnlineFresh() {
        let offlineInput = SyncStateInput(
            isConnected: false,
            snapshotFreshness: .none,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: false,
            lastWriteError: nil,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(offlineInput) == .offline)

        let onlineCacheInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .cache,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: false,
            lastWriteError: nil,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(onlineCacheInput) == .onlineCache)

        let syncingInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .cache,
            hasPendingWrites: true,
            hasServerSnapshotSinceReconnect: false,
            lastWriteError: nil,
            pendingNoteCount: 1,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(syncingInput) == .syncing)

        let freshInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: nil,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(freshInput) == .onlineFresh)
        #expect(SyncStateReducer.canClaimAllChangesSynced(for: freshInput) == true)
    }

    @Test func errorPathTransitionsToErrorAndRecoversAfterErrorCleared() {
        let errorInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: .authExpired,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(errorInput) == .error)

        let recoveredInput = SyncStateInput(
            isConnected: true,
            snapshotFreshness: .server,
            hasPendingWrites: false,
            hasServerSnapshotSinceReconnect: true,
            lastWriteError: nil,
            pendingNoteCount: 0,
            pendingDeleteCount: 0
        )
        #expect(SyncStateReducer.reduce(recoveredInput) == .onlineFresh)
    }

    @Test func bannerCopyMatchesState() {
        #expect(SyncStateReducer.bannerCopy(for: .offline) == "You're offline. Changes will sync when connection is restored.")
        #expect(SyncStateReducer.bannerCopy(for: .onlineCache) == "Connected. Waiting for fresh server data.")
        #expect(SyncStateReducer.bannerCopy(for: .syncing) == "Syncing changes…")
        #expect(SyncStateReducer.bannerCopy(for: .onlineFresh) == "All changes synced.")
        #expect(SyncStateReducer.bannerCopy(for: .error) == "Sync failed. Resolve the error to continue syncing.")
    }
}
