# Offline-First Execution & Auto-Sync — Product Requirements Document

## Executive Summary

ShiftVoice serves frontline workers in basements, kitchens, warehouses, and back-of-house environments where connectivity is unreliable or nonexistent. Today, the app has basic offline scaffolding — a `NetworkMonitor`, a `PendingAction` queue, and local JSON persistence — but it's fragile. Actions queue but don't retry intelligently. Conflict resolution is "newest wins" with no per-field merging. There's no audit trail. No user visibility into sync state per-record. No guarantee that offline-created notes survive edge cases (app kill during write, background termination, storage pressure).

This PRD defines a production-grade offline-first architecture that makes ShiftVoice work as reliably without connectivity as it does with it — and syncs seamlessly when the connection returns.

**The promise to the user:** "If you can open the app, you can do your job. Period."

---

## Problem Statement

### Current State (What Exists)

| Component | Status | Gaps |
|-----------|--------|------|
| `NetworkMonitor` | Detects online/offline transitions | No distinction between "connected but slow" vs "no connection" |
| `PersistenceService` | Saves/loads `AppData` as monolithic JSON | No incremental writes; entire dataset serialized on every save |
| `PendingAction` queue | Stores action types + payload strings | No retry with backoff; no max retry cap; no error categorization; clears all on replay regardless of individual success/failure |
| `replayPendingActions()` | Iterates queue sequentially | No partial failure handling; if action 3 of 10 fails, actions 4-10 still attempt but the queue is cleared entirely |
| `mergeNoteWithConflictDetection()` | Returns whichever has newer `updatedAt` | No per-field merge; silently drops the loser's changes; no conflict UI |
| `ShiftNote.isSynced` / `isDirty` | Flags exist on model | Not consistently set or checked; no visual indicator in UI |
| Backend `sync.push` | Accepts full data blob | No delta sync; no versioning; no conflict detection server-side |

### What's Broken

1. **Data loss on partial sync failure.** `clearPendingActions()` runs after `replayPendingActions()` regardless of whether individual actions succeeded. If 3 of 5 actions fail (server error, timeout), those 3 are silently dropped.

2. **No retry intelligence.** Failed actions aren't retried with exponential backoff. A transient 500 error permanently loses the action.

3. **Conflict resolution is destructive.** Two shift leads updating the same action item offline — one marks it "Resolved", the other assigns it to someone — results in one change being silently dropped. No notification, no merge, no audit.

4. **Monolithic persistence is fragile.** The entire `AppData` struct is serialized to one JSON file. A crash mid-write corrupts all data, not just the changed record. With 1,000+ notes, this file grows large and serialization becomes slow.

5. **No sync state visibility.** Users have no way to see which notes are synced, which are pending, or which failed. The only indicator is a global "pending count" badge.

6. **No audit trail.** There's no record of what changed, when, by whom, or what was overwritten during sync. Enterprise customers require this for compliance.

7. **No offline recording guarantee.** If the app is killed during a recording or note review, the partially-created note may be lost. There's no crash recovery for in-flight operations.

---

## Goals & Success Metrics

### Goals

| # | Goal | Measurable Target |
|---|------|-------------------|
| G1 | Zero data loss | 0 notes/actions lost across 10,000 offline→online sync cycles in testing |
| G2 | Transparent sync state | Every record shows its sync status (synced / pending / failed) in the UI |
| G3 | Intelligent conflict resolution | Per-field merge for action items; user-facing conflict UI for true conflicts |
| G4 | Resilient retry | Failed syncs retry with exponential backoff; permanent failures surface to user after N retries |
| G5 | Fast offline writes | Local save completes in <50ms for any single record operation |
| G6 | Seamless reconnect | Pending queue drains within 30 seconds of connectivity restoration |
| G7 | Audit trail | Every sync event (push, pull, conflict, resolution) is logged locally with timestamp |

### Success Metrics

| Metric | Current | Target | How Measured |
|--------|---------|--------|--------------|
| Data loss incidents per 1,000 sync cycles | Unknown (no tracking) | 0 | Automated sync stress tests |
| Sync queue drain time (reconnect → all synced) | Unbounded | <30 seconds for 50 pending actions | Instrumented timer in `SyncEngine` |
| Conflict resolution accuracy | 0% (newest-wins, no field merge) | >95% auto-resolved correctly | Manual review of conflict logs |
| User-reported "lost note" support tickets | Baseline TBD | 80% reduction from baseline | Support ticket tagging |
| Offline note creation success rate | Unknown | 99.9% | Crash recovery test suite |
| Time to first sync after app launch | Variable | <3 seconds | App launch instrumentation |

---

## User Stories

### Frontline Worker (Shift Lead)

> **US-1:** As a shift lead in a basement kitchen with no cell signal, I want to record a voice note about a broken walk-in cooler, review and publish it, and trust that it will sync to my team when I walk back upstairs — without me having to remember to do anything.

> **US-2:** As a shift lead, I want to see a clear indicator on each note showing whether it's synced, pending sync, or failed — so I know if my team has received my update.

> **US-3:** As a shift lead who marked an action item "Resolved" while offline, I want to be notified if another team member changed the same item while I was offline — so I can decide which update should stand.

### Manager (GM / Owner)

> **US-4:** As a GM reviewing the shift feed, I want to see all notes from my team even if some were created hours ago while offline — with a timestamp showing when they were originally created (not when they synced).

> **US-5:** As a GM, I want an audit log showing when data was synced, what changed, and whether any conflicts were resolved — so I have a compliance-ready record of operations.

### System

> **US-6:** As the system, when a user reconnects after being offline, I want to automatically sync all pending changes in the correct order, handle partial failures gracefully, and retry failed items without user intervention.

> **US-7:** As the system, if two users modified the same action item's status while both were offline, I want to merge non-conflicting field changes automatically and only surface true conflicts (same field, different values) to the user.

---

## Technical Architecture

### Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                    SwiftUI Views                     │
│  (Sync status badges, conflict banners, retry UI)   │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                   AppViewModel                       │
│  (Orchestrates UI state, delegates to SyncEngine)   │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                   SyncEngine                         │
│  - Manages offline queue (SyncQueue)                │
│  - Orchestrates push/pull                            │
│  - Conflict detection & resolution                  │
│  - Retry with exponential backoff                   │
│  - Audit logging                                    │
└────────┬────────────────────────────┬───────────────┘
         │                            │
┌────────▼────────┐          ┌────────▼────────┐
│ OfflineStore     │          │ APIService       │
│ (Record-level    │          │ (Network calls)  │
│  JSON files)     │          │                  │
└─────────────────┘          └──────────────────┘
```

### Component Design

#### 1. OfflineStore (replaces monolithic PersistenceService for note data)

**Current problem:** One giant `app_data.json` file. Crash during write = total corruption. Slow with large datasets.

**New design:** Record-level file storage.

```
users/{userId}/
├── profile.json                    # User profile (unchanged)
├── organization.json               # Org data (small, monolithic OK)
├── locations.json                  # Location list
├── team_members.json               # Team member list
├── sync_metadata.json              # Last sync timestamps, version vectors
├── audit_log.jsonl                 # Append-only audit log (JSON Lines)
├── notes/
│   ├── {noteId}.json               # Individual note files
│   ├── {noteId}.json
│   └── ...
└── sync_queue/
    ├── {actionId}.json             # Individual queued actions
    └── ...
```

**Benefits:**
- Crash during write of one note doesn't corrupt others
- Faster reads — load only what's needed (pagination-friendly)
- Atomic writes per record via `.atomic` flag
- Easy to enumerate pending/dirty records
- Audit log is append-only — never rewritten, only appended

**Migration:** On first launch after update, decompose existing `app_data.json` into individual files. Keep `app_data.json` as backup until successful migration confirmed.

#### 2. SyncQueue (replaces PendingAction array)

**Current problem:** `PendingAction` stores a type + string payload. No error tracking, no retry metadata, no ordering guarantees.

**New design:**

```swift
nonisolated struct SyncOperation: Identifiable, Codable, Sendable {
    let id: String
    let type: SyncOperationType
    let entityId: String
    let entityType: SyncEntityType
    let payload: Data        // Full serialized entity snapshot
    let createdAt: Date
    let originalTimestamp: Date  // When the user action actually happened
    var lastAttemptAt: Date?
    var retryCount: Int
    var lastError: String?
    var status: SyncOperationStatus

    nonisolated enum SyncOperationType: String, Codable, Sendable {
        case create
        case update
        case delete
    }

    nonisolated enum SyncEntityType: String, Codable, Sendable {
        case shiftNote
        case actionItem
        case acknowledgment
        case voiceReply
        case teamMember
        case organization
        case location
    }

    nonisolated enum SyncOperationStatus: String, Codable, Sendable {
        case pending
        case inFlight
        case failed
        case permanentlyFailed  // After max retries
    }
}
```

**Queue rules:**
- Each operation persisted as individual file in `sync_queue/` immediately on creation
- Operations processed FIFO within same entity; parallel across different entities
- Max 5 retries with exponential backoff: 2s → 4s → 8s → 16s → 32s
- After 5 failures: mark `permanentlyFailed`, surface to user with retry button
- On success: delete the queue file
- On partial batch failure: only remove succeeded operations

#### 3. SyncEngine (new orchestration layer)

Responsibilities:
- Listen for `NetworkMonitor` connectivity changes
- On reconnect: drain `SyncQueue` with backoff
- On app foreground: pull latest from server, merge with local
- Periodic background sync (every 60s when online)
- Conflict detection and resolution
- Audit log writes

**Sync Flow (Reconnect):**

```
1. Network reconnects
2. SyncEngine.drainQueue() triggered
3. For each pending operation (ordered by originalTimestamp):
   a. Set status = .inFlight
   b. Attempt API call
   c. On success:
      - Remove from queue
      - Update local record: isSynced = true, isDirty = false
      - Write audit log entry
   d. On retryable failure (5xx, timeout, network):
      - Increment retryCount
      - Set lastError, lastAttemptAt
      - Schedule retry with backoff
      - Keep in queue
   e. On permanent failure (4xx validation, 409 conflict):
      - Mark permanentlyFailed
      - Surface to user
      - Write audit log entry
4. After queue drained: pull latest from server
5. Merge server data with local (see Conflict Resolution)
6. Save merged state locally
7. Write audit log summary
```

**Sync Flow (Pull/Merge):**

```
1. Request server state (delta if supported, full otherwise)
2. For each server record:
   a. If no local version → insert locally
   b. If local version exists and is NOT dirty → overwrite with server
   c. If local version exists and IS dirty → run conflict resolution
3. For each local-only record (not on server):
   a. If isSynced was true → server deleted it; remove locally (or flag)
   b. If isSynced was false → created offline; push to server
```

#### 4. Conflict Resolution

**Strategy: Per-Field Last-Write-Wins with Conflict Detection**

For `ShiftNote` (primarily single-author, append-only):
- **Newest-wins at the note level** is acceptable
- Exception: `acknowledgments` and `voiceReplies` arrays are **union-merged** (append-only collections)

For `ActionItem` (multi-user, concurrent edits expected):
- **Per-field merge** using field-level timestamps (`statusUpdatedAt`, `assigneeUpdatedAt`, `updatedAt`)
- For each field, take the value with the newer timestamp
- **True conflict** = same field changed by different users to different values within the same offline window
- True conflicts: keep the newer value BUT flag `hasConflict = true` with `conflictDescription` and surface to the user

```swift
func mergeActionItem(local: ActionItem, server: ActionItem) -> ActionItem {
    var merged = local

    // Status: per-field by statusUpdatedAt
    if server.statusUpdatedAt > local.statusUpdatedAt {
        merged.status = server.status
        merged.statusUpdatedAt = server.statusUpdatedAt
    }

    // Assignee: per-field by assigneeUpdatedAt
    if server.assigneeUpdatedAt > local.assigneeUpdatedAt {
        merged.assignee = server.assignee
        merged.assigneeId = server.assigneeId
        merged.assigneeUpdatedAt = server.assigneeUpdatedAt
    }

    // Detect true conflict: same field, different values, both changed in offline window
    let statusConflict = local.statusUpdatedAt != server.statusUpdatedAt
        && local.status != server.status
        && abs(local.statusUpdatedAt.timeIntervalSince(server.statusUpdatedAt)) < 300 // 5-min window
    let assigneeConflict = local.assigneeUpdatedAt != server.assigneeUpdatedAt
        && local.assigneeId != server.assigneeId
        && abs(local.assigneeUpdatedAt.timeIntervalSince(server.assigneeUpdatedAt)) < 300

    if statusConflict || assigneeConflict {
        merged.hasConflict = true
        merged.conflictDescription = buildConflictDescription(local: local, server: server)
    }

    return merged
}
```

#### 5. Audit Log

Append-only JSON Lines file (`audit_log.jsonl`):

```swift
nonisolated struct AuditEntry: Codable, Sendable {
    let id: String
    let timestamp: Date
    let eventType: AuditEventType
    let entityType: String
    let entityId: String
    let userId: String
    let details: String        // Human-readable description
    let metadata: [String: String]?  // Machine-readable context

    nonisolated enum AuditEventType: String, Codable, Sendable {
        case localCreate
        case localUpdate
        case localDelete
        case syncPushSuccess
        case syncPushFailed
        case syncPullReceived
        case conflictDetected
        case conflictAutoResolved
        case conflictUserResolved
        case queueRetry
        case queuePermanentFailure
    }
}
```

**Retention:** Keep 30 days locally. Older entries pruned on app launch. Enterprise tier: upload audit logs to server for long-term retention.

---

## UI/UX Requirements

### 1. Per-Record Sync Status Indicators

Every note card in the feed shows sync state:

| State | Indicator | Color |
|-------|-----------|-------|
| Synced | Checkmark icon (hidden by default — clean state) | — |
| Pending sync | Cloud with arrow-up icon | Orange |
| Syncing now | Animated cloud icon | Blue |
| Failed (retryable) | Cloud with exclamation | Red |
| Permanently failed | Red warning badge with "Tap to retry" | Red |

**Placement:** Small icon in the top-right corner of `ShiftNoteCardView`, next to the timestamp.

### 2. Offline Mode Banner

When `NetworkMonitor.isConnected == false`:
- Persistent banner at top of main views: "You're offline — changes will sync when you're back online"
- Subtle, non-intrusive (thin bar, `.ultraThinMaterial` background)
- Shows count of pending changes: "3 changes waiting to sync"
- Dismissable but reappears on each app foreground while offline

### 3. Sync Status in Settings

New section in Settings: **"Sync & Storage"**
- Last sync time: "Last synced: 2 minutes ago"
- Pending changes count
- "Force Sync" button (already exists, enhanced)
- "View Sync Log" → scrollable audit log viewer
- Storage used (local data size)

### 4. Conflict Resolution UI

When a conflict is detected on an action item:
- Yellow "Conflict" badge on the action item in dashboard and note detail
- Tapping shows a conflict resolution sheet:
  - "Your change" vs "Team member's change" side-by-side
  - "Keep mine" / "Keep theirs" / "Keep both" (where applicable) buttons
  - Timestamp of each change
- After resolution: conflict flag cleared, audit log entry written

### 5. Reconnect Toast

On reconnect:
- Toast: "Back online — syncing N changes..."
- Progress updates: "Synced 3 of 7..."
- Completion: "All changes synced" (green checkmark, auto-dismiss after 3s)
- If partial failure: "5 synced, 2 failed — tap to review" (stays until tapped)

---

## Backend Changes

### 1. Delta Sync Endpoint

**Current:** `sync.pull` returns the entire dataset. With 1,000+ notes, this is slow and wasteful.

**New:** Add a `since` parameter for incremental sync.

```typescript
// New: Delta pull
pull: protectedProcedure
  .input(z.object({
    since: z.string().optional(), // ISO 8601 timestamp
  }))
  .query(({ ctx, input }) => {
    if (input.since) {
      return {
        hasData: true,
        isDelta: true,
        data: storage.getUserDataSince(ctx.userId, input.since),
      };
    }
    return { hasData: true, isDelta: false, data: storage.getUserData(ctx.userId) };
  }),
```

### 2. Per-Record Push (Granular Sync)

**Current:** `sync.push` accepts the entire dataset blob. Overwrites everything.

**New:** Add granular endpoints for individual record operations.

```typescript
// New granular endpoints
shiftNotes: {
  upsert: protectedProcedure
    .input(shiftNoteSchema)
    .mutation(({ ctx, input }) => {
      const existing = storage.getShiftNote(ctx.userId, input.id);
      if (existing && existing.updatedAt > input.updatedAt) {
        return { success: true, conflict: true, serverVersion: existing };
      }
      storage.upsertShiftNote(ctx.userId, input);
      return { success: true, conflict: false };
    }),

  delete: protectedProcedure
    .input(z.object({ noteId: z.string() }))
    .mutation(({ ctx, input }) => {
      storage.deleteShiftNote(ctx.userId, input.noteId);
      return { success: true };
    }),
}
```

### 3. Server-Side Conflict Detection

When a client pushes a record:
1. Server compares `updatedAt` of incoming vs stored
2. If server version is newer: return `conflict: true` with the server version
3. Client receives conflict and runs local merge logic
4. Client re-pushes merged result (or surfaces to user if true conflict)

### 4. Record-Level Timestamps

Every stored record gets:
- `createdAt`: When originally created
- `updatedAt`: Last modification time
- `syncedAt`: When last successfully synced to this server
- `deletedAt`: Soft delete timestamp (for sync — don't permanently delete until all clients have synced)

### 5. Soft Deletes

Records are not immediately removed from server storage. Instead:
- Set `deletedAt` timestamp
- Delta sync includes deleted records so offline clients can remove them
- Permanent purge after 30 days (or after all known clients have synced past that timestamp)

---

## Data Model Changes

### ShiftNote Additions

```swift
// Existing fields enhanced:
var isSynced: Bool          // true = matches server state
var isDirty: Bool           // true = local changes not yet pushed
// New fields:
var syncedAt: Date?         // Last successful sync timestamp
var localVersion: Int       // Incremented on every local edit (optimistic concurrency)
var serverVersion: Int      // Version from server (for conflict detection)
var syncError: String?      // Last sync error for this specific record
var deletedAt: Date?        // Soft delete support
```

### PendingAction → SyncOperation Migration

The existing `PendingAction` model is replaced by `SyncOperation` (defined above). Migration:
1. On first launch, read existing `pending_queue.json`
2. Convert each `PendingAction` to a `SyncOperation` with `status = .pending`
3. Write individual files to `sync_queue/`
4. Delete old `pending_queue.json`

---

## Edge Cases & Failure Modes

### 1. App Killed During Note Creation

**Scenario:** User finishes recording, AI structures the note, user is on review screen, app is killed before publish.

**Solution:** Save a "draft" snapshot after AI structuring completes, before user publishes. On next launch, detect orphaned drafts and prompt: "You have an unsaved note from [timestamp]. Resume editing?"

### 2. App Killed During Sync

**Scenario:** Sync is in progress, 3 of 7 operations completed, app killed.

**Solution:** Each operation is individually persisted. On next launch, the queue still contains the 4 unsynced operations. The 3 completed ones were already deleted from the queue on success. No data loss.

### 3. Storage Pressure

**Scenario:** Device is low on storage. Writing a new note file fails.

**Solution:**
- Catch file write errors and surface to user: "Low storage — note saved in memory but may be lost if the app closes. Free up space to ensure your data is saved."
- Attempt to prune old audit log entries first
- Never delete user data to make room

### 4. Clock Skew

**Scenario:** User's device clock is significantly wrong, causing timestamp-based merge to produce incorrect results.

**Solution:**
- Use server timestamp as authoritative for `syncedAt`
- For `updatedAt` on local edits, use device time (unavoidable) but include device time offset in sync metadata
- Server can detect gross clock skew (>5 min difference) and log a warning

### 5. Concurrent Edits on Same Device

**Scenario:** User rapidly taps status changes on multiple action items while offline. Each generates a sync operation.

**Solution:** Coalesce operations for the same entity within a short window (2 seconds). If the user changes status from Open → In Progress → Resolved in rapid succession, only queue the final state.

### 6. Large Offline Backlog

**Scenario:** User is offline for a full 8-hour shift, creating 30+ notes with action items.

**Solution:**
- Queue handles 100+ operations without degradation
- Sync operations are batched: up to 5 concurrent API calls
- Progress indicator shows sync progress to user
- Prioritize: action item status updates first (most time-sensitive), then notes, then profile/org changes

---

## Testing Strategy

### Unit Tests

| Test | Description |
|------|-------------|
| `testSyncOperationPersistence` | Write/read individual sync operations to disk |
| `testQueueOrdering` | FIFO ordering maintained across app restarts |
| `testRetryBackoff` | Verify 2s → 4s → 8s → 16s → 32s backoff schedule |
| `testMaxRetryTransition` | After 5 failures, status = `.permanentlyFailed` |
| `testPerFieldMerge` | Two action items with different field changes merge correctly |
| `testTrueConflictDetection` | Same field, different values → `hasConflict = true` |
| `testAcknowledgmentUnionMerge` | Acknowledgments from both sides preserved |
| `testCoalesceRapidUpdates` | Rapid status changes produce single queued operation |
| `testDraftRecovery` | Orphaned draft detected on next launch |
| `testMigrationFromPendingAction` | Old `PendingAction` queue converts to `SyncOperation` |
| `testPartialSyncFailure` | Failed operations remain in queue; succeeded ones removed |

### Integration Tests

| Test | Description |
|------|-------------|
| `testFullOfflineOnlineLoop` | Create note offline → reconnect → verify synced to server |
| `testConflictResolutionFlow` | Two clients edit same item offline → both sync → conflict surfaced |
| `testLargeQueueDrain` | 50+ pending operations drain within 30s on reconnect |
| `testDeltaSyncAccuracy` | Only changed records returned after `since` parameter |
| `testSoftDeleteSync` | Deleted note syncs as soft delete; other clients remove it |

### Stress Tests

| Test | Description |
|------|-------------|
| `testCrashDuringWrite` | Simulate crash mid-file-write; verify no data corruption |
| `testCrashDuringSync` | Simulate crash mid-sync; verify queue integrity on relaunch |
| `test1000NotesPerformance` | 1,000 notes stored as individual files; measure load time |
| `testRapidOnlineOfflineToggle` | Toggle connectivity 20 times in 60 seconds; verify no duplicate syncs |

---

## Security & Privacy Considerations

- **Audit logs contain no PII beyond user IDs.** Note content is referenced by ID, not embedded in log entries.
- **Local data encrypted at rest** via iOS Data Protection (enabled by default when device has passcode).
- **Sync operations contain auth tokens** only in HTTP headers, never persisted in queue files.
- **Soft-deleted records** are purged from server after 30 days — no indefinite PII retention.
- **Conflict resolution metadata** (who changed what) is visible only to users with appropriate role permissions.

---

## Rollout & Feature Flags

| Flag | Description | Default |
|------|-------------|---------|
| `offline_record_level_storage` | Use per-file note storage instead of monolithic JSON | OFF (migrate gradually) |
| `offline_sync_engine_v2` | Use new SyncEngine with retry/backoff instead of simple replay | OFF |
| `offline_conflict_ui` | Show conflict resolution UI for action items | OFF |
| `offline_audit_log` | Write local audit log entries | OFF |
| `offline_delta_sync` | Use `since` parameter for incremental pull | OFF |

Flags enabled sequentially: storage first, then sync engine, then conflict UI, then delta sync.

---

## Execution Plan

### Phase 1: Foundation — Record-Level Storage (Week 1-2)

**Goal:** Replace monolithic `app_data.json` with per-record file storage. Zero behavior change from user perspective.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 1.1 | Build `OfflineStore` service with per-file CRUD for notes | 3 days | Medium — migration complexity |
| 1.2 | Build migration logic: decompose existing `app_data.json` into individual files | 2 days | High — must be bulletproof |
| 1.3 | Add migration rollback: keep `app_data.json` backup for 7 days post-migration | 1 day | Low |
| 1.4 | Update `AppViewModel` to use `OfflineStore` for note operations | 2 days | Medium — many call sites |
| 1.5 | Add file-write error handling with user-facing storage alerts | 1 day | Low |
| 1.6 | Unit tests for `OfflineStore` + migration | 2 days | Low |
| 1.7 | Performance benchmarks: 100, 500, 1000 notes load time | 0.5 day | Low |

**Acceptance:** App functions identically. All existing tests pass. Notes load from individual files after migration.

### Phase 2: Sync Queue V2 (Week 3-4)

**Goal:** Replace `PendingAction` with `SyncOperation`. Add retry with backoff. Partial failure handling.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 2.1 | Build `SyncOperation` model and file-based queue | 1 day | Low |
| 2.2 | Build `SyncQueue` manager: enqueue, dequeue, retry scheduling | 2 days | Medium |
| 2.3 | Implement exponential backoff timer (2s → 4s → 8s → 16s → 32s) | 1 day | Low |
| 2.4 | Implement partial failure handling: only remove succeeded operations | 1 day | Medium |
| 2.5 | Implement operation coalescing for rapid edits on same entity | 1 day | Medium |
| 2.6 | Migrate existing `PendingAction` → `SyncOperation` on first launch | 1 day | Low |
| 2.7 | Build `SyncEngine` orchestrator: drain queue, coordinate push/pull | 3 days | High — orchestration complexity |
| 2.8 | Wire `SyncEngine` into `AppViewModel`, replace `replayPendingActions()` | 2 days | Medium |
| 2.9 | Unit tests for queue, backoff, partial failure, coalescing | 2 days | Low |

**Acceptance:** Offline actions queue reliably. Failed actions retry with backoff. Partial failures don't drop succeeded operations.

### Phase 3: Conflict Resolution (Week 5-6)

**Goal:** Per-field merge for action items. Conflict detection and user-facing resolution UI.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 3.1 | Implement per-field merge logic for `ActionItem` | 2 days | Medium |
| 3.2 | Implement union merge for `acknowledgments` and `voiceReplies` | 1 day | Low |
| 3.3 | Build true conflict detection (same field, different values, close timestamps) | 1 day | Medium |
| 3.4 | Build conflict resolution sheet UI (side-by-side comparison) | 2 days | Medium — design complexity |
| 3.5 | Add conflict badges to action item cards in dashboard and note detail | 1 day | Low |
| 3.6 | Wire conflict resolution to `SyncEngine`: resolve → clear flag → re-sync | 1 day | Medium |
| 3.7 | Unit tests for merge logic, conflict detection | 2 days | Low |
| 3.8 | Integration test: two conflicting edits → merge → resolution flow | 1 day | Medium |

**Acceptance:** Non-conflicting field changes auto-merge silently. True conflicts surface with UI. User can resolve and sync.

### Phase 4: Sync State UI (Week 7)

**Goal:** Users can see sync status per-record and globally. Reconnect experience is polished.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 4.1 | Add sync status icon to `ShiftNoteCardView` | 1 day | Low |
| 4.2 | Build offline mode banner component | 0.5 day | Low |
| 4.3 | Build reconnect progress toast with operation count | 1 day | Low |
| 4.4 | Add "Sync & Storage" section to Settings | 1 day | Low |
| 4.5 | Build audit log viewer (scrollable list in Settings) | 1 day | Low |
| 4.6 | Add `syncError` display on individual failed notes with retry button | 1 day | Low |
| 4.7 | Polish: haptic feedback on sync completion, spring animations on status changes | 0.5 day | Low |

**Acceptance:** Users always know what's synced and what's pending. Reconnect experience feels seamless and trustworthy.

### Phase 5: Backend Enhancements (Week 8-9)

**Goal:** Server supports granular sync, delta pull, soft deletes, and server-side conflict detection.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 5.1 | Add `updatedAt` / `syncedAt` / `deletedAt` to all stored records | 1 day | Low |
| 5.2 | Build `getUserDataSince()` for delta sync | 2 days | Medium |
| 5.3 | Build per-record upsert endpoints (shiftNotes, actionItems) | 2 days | Medium |
| 5.4 | Add server-side conflict detection on upsert (compare `updatedAt`) | 1 day | Medium |
| 5.5 | Implement soft deletes with 30-day purge | 1 day | Low |
| 5.6 | Wire iOS `SyncEngine` to use new granular endpoints | 2 days | Medium |
| 5.7 | Integration tests: delta sync, conflict response, soft delete propagation | 2 days | Medium |

**Acceptance:** iOS client uses granular sync. Delta pull reduces bandwidth. Server detects conflicts and returns server version for client-side merge.

### Phase 6: Hardening & Edge Cases (Week 10)

**Goal:** Handle all edge cases. Stress test. Production readiness.

| # | Task | Effort | Risk |
|---|------|--------|------|
| 6.1 | Implement draft recovery for interrupted note creation | 1 day | Medium |
| 6.2 | Add clock skew detection and warning | 0.5 day | Low |
| 6.3 | Add storage pressure detection and user alerts | 0.5 day | Low |
| 6.4 | Stress test: 1000 notes, 50 pending operations, rapid connectivity toggling | 1 day | Medium |
| 6.5 | Stress test: concurrent edits simulation across multiple "clients" | 1 day | High |
| 6.6 | Audit log pruning (30-day retention) | 0.5 day | Low |
| 6.7 | End-to-end test suite: full offline journey from record → review → publish → sync | 1 day | Medium |
| 6.8 | Performance profiling: sync drain time, storage I/O, memory usage | 0.5 day | Low |

**Acceptance:** All edge cases handled. Stress tests pass. No data loss across 10,000 sync cycles.

---

## Timeline Summary

| Phase | Duration | Key Deliverable |
|-------|----------|-----------------|
| Phase 1: Record-Level Storage | Week 1-2 | Per-file note persistence with migration |
| Phase 2: Sync Queue V2 | Week 3-4 | Retry with backoff, partial failure handling |
| Phase 3: Conflict Resolution | Week 5-6 | Per-field merge, conflict UI |
| Phase 4: Sync State UI | Week 7 | Status badges, offline banner, audit viewer |
| Phase 5: Backend Enhancements | Week 8-9 | Delta sync, granular endpoints, soft deletes |
| Phase 6: Hardening | Week 10 | Edge cases, stress tests, production readiness |

**Total estimated duration: 10 weeks**

---

## Dependencies & Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Migration corrupts existing data | Critical | Low | Backup original file; rollback mechanism; phased rollout |
| Per-file storage slower than expected with 1000+ notes | High | Medium | Benchmark early in Phase 1; use in-memory index if needed |
| Conflict resolution confuses non-technical users | Medium | Medium | Clear, simple UI language; auto-resolve most cases silently |
| Delta sync introduces stale data bugs | High | Medium | Full sync fallback if delta results look inconsistent |
| Clock skew causes incorrect merge results | Medium | Low | Server timestamp for sync metadata; detect gross skew |
| Background app refresh not reliable for sync | Medium | High | Don't depend on background sync; drain queue on foreground |

---

## Out of Scope (For Now)

- **Real-time sync via WebSocket** — polling + foreground sync is sufficient for v1
- **Multi-device conflict resolution** — same user on two devices; defer to "newest wins" per device
- **Offline AI structuring** — requires on-device LLM; AI summary placeholder shown offline, backfilled on reconnect
- **Background sync via BGTaskScheduler** — unreliable; focus on foreground drain
- **Cross-organization data sharing** — not relevant to current single-org model
- **End-to-end encryption** — iOS Data Protection sufficient for v1; E2E if enterprise demands it

---

## Appendix: Glossary

| Term | Definition |
|------|------------|
| **Dirty** | A local record that has been modified since last successful sync |
| **Pending** | A sync operation that has been queued but not yet attempted |
| **In-Flight** | A sync operation currently being sent to the server |
| **Permanently Failed** | A sync operation that has exceeded max retries and requires user intervention |
| **Delta Sync** | Requesting only records changed since a given timestamp, rather than the full dataset |
| **Per-Field Merge** | Resolving conflicts by comparing individual fields independently rather than whole records |
| **True Conflict** | The same field on the same record was changed to different values by different users while both were offline |
| **Soft Delete** | Marking a record as deleted without removing it from storage, so other clients can sync the deletion |
| **Coalescing** | Combining multiple rapid edits to the same record into a single sync operation |
| **Audit Entry** | An append-only log record documenting a sync event for compliance and debugging |
