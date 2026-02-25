# Offline-First Execution & Auto-Sync — Product Requirements Document (v2)

## Executive Summary

ShiftVoice serves frontline workers in basements, kitchens, warehouses, and back-of-house environments where connectivity is unreliable. The original PRD proposed building a complete custom sync engine, record-level file storage, retry queues, and conflict resolution from scratch — a 10-week effort.

**After auditing the codebase, we already have Firestore as our primary database with real-time listeners.** Firestore's iOS SDK provides offline persistence **enabled by default** — it caches data locally, queues writes automatically, retries on reconnect, and syncs via snapshot listeners. This means **~70% of the original PRD is already handled by Firestore out of the box.**

This updated PRD focuses only on what Firestore doesn't give us for free, dramatically reducing scope and engineering effort.

---

## What Firestore Already Handles (No Work Needed)

| Capability | Firestore Behavior | Our Code |
|---|---|---|
| **Offline read access** | Serves data from local cache when offline — listeners fire with cached data | `FirestoreService` listeners already work offline |
| **Offline write queuing** | All `setData()`, `updateData()`, `deleteDocument()` calls are queued locally and replayed on reconnect | `writeShiftNote()`, `writeLocation()`, etc. already use Firestore writes |
| **Automatic retry** | Firestore SDK retries queued writes with its own backoff — no manual retry needed | N/A — built into SDK |
| **Cache persistence across restarts** | `PersistentCacheSettings` (default) persists cache to disk — survives app kill/restart | Enabled by default — no config needed |
| **Real-time sync on reconnect** | Snapshot listeners automatically receive server updates when connectivity returns | `startListeners()` in `AppViewModel` already does this |
| **Listener metadata** | `SnapshotMetadata.isFromCache` tells you if data came from cache or server | Not yet used — **opportunity** |
| **Atomic writes** | `WriteBatch` for multi-document atomic operations | `deleteLocationNotes()` already uses batched writes |

### What This Makes Redundant

These existing components are **unnecessary overhead** because Firestore handles their purpose:

| Component | Why It's Redundant |
|---|---|
| `PendingAction` model | Firestore queues writes internally — no need for a manual action queue |
| `pendingActions` array in `AppViewModel` | Same — Firestore SDK manages pending writes |
| `replayPendingActions()` | Firestore replays writes automatically on reconnect |
| `savePendingActions()` / `loadPendingActions()` / `clearPendingActions()` in `PersistenceService` | No manual queue needed |
| `PersistenceService.save()` / `load()` (monolithic `app_data.json`) | Firestore cache IS the local persistence — duplicating data to JSON is unnecessary |
| `handleNetworkReconnect()` replay logic | Firestore reconnects and syncs automatically; listeners fire with updated data |

### What This Eliminates from Original PRD

| Original PRD Component | Status |
|---|---|
| Phase 1: Record-Level Storage (OfflineStore) | **ELIMINATED** — Firestore cache is already per-document |
| Phase 2: SyncQueue V2 + SyncEngine | **ELIMINATED** — Firestore SDK handles queue/retry/backoff |
| Phase 5: Backend delta sync, granular endpoints, soft deletes | **ELIMINATED** — Firestore listeners are already real-time and incremental |
| Migration from `app_data.json` to per-file storage | **ELIMINATED** — just remove the redundant local persistence |

---

## What We Still Need to Build

Firestore handles sync mechanics, but it does NOT provide:

1. **User-visible sync status** — Firestore has `isFromCache` metadata but we don't surface it
2. **Per-record sync indicators** — Users can't see which notes are synced vs pending
3. **Offline mode banner** — No UI telling users they're offline
4. **Conflict awareness for action items** — Firestore is last-write-wins; no field-level merge
5. **Reconnect feedback** — No toast when connectivity returns
6. **Cleanup of redundant code** — `PendingAction`, monolithic persistence, manual replay

---

## Goals & Success Metrics

### Goals

| # | Goal | Measurable Target |
|---|------|-------------------|
| G1 | Transparent sync state | Every note shows sync status in UI via Firestore metadata |
| G2 | Offline confidence | Users see clear offline banner + pending write count |
| G3 | Conflict awareness | Action items edited by multiple users surface conflicts |
| G4 | Clean architecture | Remove redundant sync code; single source of truth = Firestore |
| G5 | Reconnect polish | Smooth toast feedback on reconnect with sync confirmation |

### Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| User knows they're offline | No indicator | Always visible banner |
| User knows note is synced | No indicator | Per-note sync badge |
| Redundant code removed | ~500 lines of manual sync code | 0 |
| Conflict-prone action items surfaced | 0% | 100% |

---

## User Stories

> **US-1:** As a shift lead in a basement with no signal, I want to see a clear "You're offline" banner so I know my notes will sync later.

> **US-2:** As a shift lead, I want to see a small sync icon on each note card showing whether it's synced to the server or still pending.

> **US-3:** As a shift lead, when I come back online, I want a brief toast confirming my changes synced successfully.

> **US-4:** As a GM, if two shift leads update the same action item offline, I want to see a conflict flag so I can review what happened.

> **US-5:** As a user, I want the app to work identically whether I'm online or offline — no loading spinners, no errors, just seamless operation.

---

## Technical Architecture

### How It Works with Firestore

```
┌─────────────────────────────────────────────┐
│              SwiftUI Views                   │
│  (Sync badges, offline banner, toasts)      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│              AppViewModel                    │
│  - Reads Firestore listener data            │
│  - Checks SnapshotMetadata.isFromCache      │
│  - Tracks hasPendingWrites per snapshot     │
│  - NetworkMonitor for offline banner        │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│           FirestoreService                   │
│  - Real-time listeners (existing)           │
│  - Enhanced: pass SnapshotMetadata to VM    │
│  - All writes go directly to Firestore      │
│  - Firestore SDK handles offline queue      │
└──────────────────┬──────────────────────────┘
                   │
┌──────────────────▼──────────────────────────┐
│         Firestore iOS SDK (built-in)         │
│  - PersistentCacheSettings (default)        │
│  - Offline write queue + auto-retry         │
│  - Snapshot listeners with metadata         │
│  - Automatic reconnect + sync              │
└─────────────────────────────────────────────┘
```

### Key Changes

#### 1. Enhanced Listeners with Metadata

Current listeners ignore Firestore snapshot metadata. We need to pass `isFromCache` and `hasPendingWrites` through to the ViewModel.

```swift
// FirestoreService — enhanced listener
func startShiftNotesListener(_ orgId: String, onChange: @escaping ([ShiftNote], Bool, Bool) -> Void) {
    let reg = db.collection("organizations").document(orgId).collection("shiftNotes")
        .order(by: "createdAt", descending: true)
        .limit(to: 300)
        .addSnapshotListener { snapshot, _ in
            guard let snapshot else { onChange([], false, false); return }
            let items = snapshot.documents.compactMap { try? $0.data(as: ShiftNote.self) }
            let isFromCache = snapshot.metadata.isFromCache
            let hasPendingWrites = snapshot.metadata.hasPendingWrites
            onChange(items, isFromCache, hasPendingWrites)
        }
    activeListeners.append(reg)
}
```

#### 2. Sync State in ViewModel

```swift
// AppViewModel additions
var isDataFromCache: Bool = false       // true = showing cached data
var hasPendingWrites: Bool = false      // true = local writes not yet confirmed by server
var lastSyncedFromServer: Date?         // last time we got non-cache data
```

#### 3. Remove Redundant Code

- Delete `PendingAction.swift` model
- Remove `pendingActions`, `queuePendingAction()`, `replayPendingActions()`, `clearPendingActions()`, `savePendingActionsToDisk()` from `AppViewModel`
- Remove `savePendingActions()`, `loadPendingActions()`, `clearPendingActions()`, `pendingQueueURL()` from `PersistenceService`
- Remove `save()` / `load()` monolithic `AppData` persistence (Firestore cache is the local store)
- Simplify `handleNetworkReconnect()` — just show a toast, Firestore handles the actual sync
- Simplify `writeShiftNote()` and similar methods — remove the offline queueing logic; just call Firestore directly (it queues internally)

#### 4. Simplified Write Pattern

Before (current — redundant double-queuing):
```swift
private func writeShiftNote(_ note: ShiftNote) {
    guard let orgId = organizationId else { return }
    do {
        try firestore.saveShiftNote(note, orgId: orgId)
        if isOffline { queuePendingAction(.syncNotes, payload: note.id) }  // REDUNDANT
    } catch {
        queuePendingAction(.syncNotes, payload: note.id)  // REDUNDANT
    }
}
```

After (simplified — trust Firestore):
```swift
private func writeShiftNote(_ note: ShiftNote) {
    guard let orgId = organizationId else {
        showToast("No organization found — please complete setup", isError: true)
        return
    }
    do {
        try firestore.saveShiftNote(note, orgId: orgId)
    } catch {
        showToast("Failed to save note", isError: true)
    }
}
```

Firestore `setData()` never throws for offline scenarios — it queues the write locally and resolves it when back online. The `try` only fails for encoding issues (malformed data), which is a real error worth surfacing.

#### 5. Action Item Conflict Detection

Firestore is last-write-wins at the document level. For action items where multiple users may edit concurrently, we use Firestore transactions for online edits:

```swift
func updateActionItemWithConflictCheck(noteId: String, actionItemId: String, field: String, newValue: Any, orgId: String) {
    let ref = db.collection("organizations").document(orgId)
        .collection("shiftNotes").document(noteId)
    
    db.runTransaction({ (transaction, errorPointer) -> Any? in
        let snapshot: DocumentSnapshot
        do {
            snapshot = try transaction.getDocument(ref)
        } catch {
            return nil // Offline — falls back to direct write (last-write-wins)
        }
        // Compare field timestamps, detect conflict, merge
        // ... (per-field merge logic from original PRD, Phase 3)
        return nil
    }) { _, _ in }
}
```

**Important:** Firestore transactions require network — they fail offline. For offline action item edits, we accept last-write-wins (same as current behavior) and flag potential conflicts when the listener receives the server-merged result. This is a pragmatic trade-off: true transactional conflict resolution only works online, and that's acceptable for v1.

---

## UI/UX Requirements

### 1. Offline Mode Banner

When `NetworkMonitor.isConnected == false`:
- Thin persistent banner at top: "You're offline — changes save automatically"
- `.ultraThinMaterial` background, subtle orange text
- Shows when `hasPendingWrites == true`: "Offline — 3 changes waiting to sync"
- Auto-dismisses 3 seconds after reconnect

### 2. Per-Note Sync Status

Small icon in the trailing edge of `ShiftNoteCardView`:

| State | Indicator | When |
|-------|-----------|------|
| Synced | No icon (clean state) | `isFromCache == false && hasPendingWrites == false` |
| Pending | `cloud.fill` in orange | Note was written offline, not yet confirmed |
| From cache | `arrow.clockwise` in gray | Data loaded from cache on app launch |

Implementation: Track which note IDs have pending writes by checking `documentChanges` with `hasPendingWrites` in the snapshot listener.

### 3. Reconnect Toast

On `NetworkMonitor` reconnect:
- Toast: "Back online — syncing..."
- When `hasPendingWrites` transitions from `true` to `false`: "All changes synced" with checkmark
- Auto-dismiss after 3 seconds
- Haptic: `.success` on sync complete

### 4. Sync Info in Settings

Enhance existing Settings → add section:
- "Last synced: [relative time]" (from `lastSyncedFromServer`)
- "Data source: Server / Cache" (from `isDataFromCache`)
- "Force Refresh" button (calls `firestore.stopAllListeners()` then `startListeners()`)

### 5. Conflict Badge on Action Items

When listener detects an action item changed by another user while local version was dirty:
- Yellow "Edited by [name]" badge
- Tapping shows what changed
- Uses existing `hasConflict` / `conflictDescription` fields on `ActionItem`

---

## Data Model Changes

### No Model Changes Needed for Sync

Firestore handles sync state internally. The existing `isSynced` and `isDirty` fields on `ShiftNote` become **derivable from Firestore metadata** rather than manually managed:

- `isSynced` → derived from `!snapshot.metadata.hasPendingWrites`
- `isDirty` → derived from document being in a pending write batch

These fields can remain on the model for backward compatibility but should no longer be manually set.

### PendingAction Model — DELETE

`PendingAction.swift` is fully redundant and should be deleted.

### PersistenceService — SIMPLIFY

Remove all sync-related persistence:
- Remove `AppData` save/load (monolithic JSON)
- Remove pending queue save/load
- Remove sync snapshot save/load
- **Keep:** `UserProfile` save/load (for fast app launch before Firestore loads)
- **Keep:** Email-to-userId mapping
- **Keep:** Legacy migration code (one-time)

---

## Edge Cases

### 1. App Killed During Note Creation

**Same solution as original PRD:** Save a draft after AI structuring completes. On next launch, detect orphaned drafts. This is independent of Firestore sync and still needed.

### 2. Large Offline Backlog

**Firestore handles this.** The SDK queues all writes and replays them in order. With 30+ notes from an 8-hour offline shift, Firestore drains the queue automatically. The `hasPendingWrites` metadata flag tells us when it's done.

### 3. Storage Pressure

Firestore's persistent cache has a configurable size limit (default 100MB, with LRU garbage collection). For our use case, 100MB is more than sufficient. No custom storage management needed.

### 4. Concurrent Edits (Multi-User)

For note-level data (single author): Firestore last-write-wins is fine — notes are primarily single-author documents.

For action items (multi-user): The existing `hasConflict` / `conflictDescription` fields handle this. We enhance the listener to detect when a server update overwrites local changes and flag it.

### 5. Clock Skew

Firestore uses server timestamps (`FieldValue.serverTimestamp()`) which eliminates client clock skew issues. We should use `ServerTimestamp` for `updatedAt` fields on writes.

---

## Execution Plan

### Phase 1: Code Cleanup — Remove Redundant Sync Infrastructure (3 days)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 1.1 | Remove `PendingAction.swift` model | 0.5 day | Low |
| 1.2 | Remove all `pendingAction`-related code from `AppViewModel` (`queuePendingAction`, `replayPendingActions`, `clearPendingActions`, `savePendingActionsToDisk`, `pendingActions` array) | 1 day | Medium — many call sites |
| 1.3 | Simplify all `write*()` methods to just call Firestore directly — remove offline queue branching | 0.5 day | Low |
| 1.4 | Remove monolithic `AppData` save/load from `PersistenceService` (keep UserProfile + email map) | 0.5 day | Low |
| 1.5 | Simplify `handleNetworkReconnect()` — just show toast, remove replay logic | 0.5 day | Low |
| 1.6 | Verify all existing tests still pass; update tests that reference removed code | 1 day | Medium |

**Acceptance:** App works identically. All writes go through Firestore. No manual offline queue. Tests pass.

### Phase 2: Enhanced Listeners + Sync State (3 days)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 2.1 | Update `FirestoreService` listeners to pass `SnapshotMetadata` (`isFromCache`, `hasPendingWrites`) | 1 day | Low |
| 2.2 | Add `isDataFromCache`, `hasPendingWrites`, `lastSyncedFromServer` to `AppViewModel` | 0.5 day | Low |
| 2.3 | Update `startListeners()` in `AppViewModel` to consume metadata from enhanced listeners | 1 day | Low |
| 2.4 | Add Firestore server timestamps (`FieldValue.serverTimestamp()`) for `updatedAt` on writes | 0.5 day | Low |

**Acceptance:** ViewModel accurately reflects sync state. `isDataFromCache` and `hasPendingWrites` update in real-time.

### Phase 3: Sync State UI (4 days)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 3.1 | Build offline mode banner component (thin bar, `.ultraThinMaterial`) | 0.5 day | Low |
| 3.2 | Add offline banner to `DashboardView`, `ShiftFeedView`, `RecordView` | 0.5 day | Low |
| 3.3 | Add sync status icon to `ShiftNoteCardView` (pending = orange cloud, synced = hidden) | 1 day | Low |
| 3.4 | Build reconnect toast with sync progress ("Back online — syncing..." → "All synced") | 1 day | Low |
| 3.5 | Add "Sync & Data" section to `SettingsView` (last synced, data source, force refresh) | 0.5 day | Low |
| 3.6 | Add haptic feedback on sync complete (`.success`) | 0.5 day | Low |

**Acceptance:** Users always know sync state. Offline → online transition feels polished and trustworthy.

### Phase 4: Action Item Conflict Awareness (3 days)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 4.1 | Detect action item conflicts in listener (server update differs from local pending version) | 1 day | Medium |
| 4.2 | Show conflict badge on action items in dashboard and note detail | 0.5 day | Low |
| 4.3 | Build simple conflict info sheet ("Your change" vs "Server change" with timestamps) | 1 day | Medium |
| 4.4 | Wire dismiss/resolve conflict to clear `hasConflict` flag | 0.5 day | Low |

**Acceptance:** Multi-user action item conflicts are detected and surfaced. Users can review and dismiss.

### Phase 5: Draft Recovery + Polish (2 days)

| # | Task | Effort | Risk |
|---|------|--------|------|
| 5.1 | Save draft snapshot after AI structuring, before publish | 0.5 day | Low |
| 5.2 | Detect orphaned drafts on app launch, prompt user to resume | 0.5 day | Low |
| 5.3 | End-to-end testing: offline record → review → publish → reconnect → verify synced | 0.5 day | Medium |
| 5.4 | Polish: animations on sync status transitions, spring on banner appear/dismiss | 0.5 day | Low |

**Acceptance:** No data loss on app kill during note creation. Full offline journey works flawlessly.

---

## Execution Control Plan (Risk Mitigation)

### Stage Gates (Go / No-Go)

Each phase is complete only if all gate criteria pass in staging and pilot.

| Gate | Required Evidence | Go Criteria | No-Go Trigger |
|---|---|---|---|
| Gate 1 — Foundation Stability (after Phase 1) | Regression suite + manual offline create/edit/delete test + relaunch test | Core flows work offline/online with no manual queue code, no data loss in app restart test | Any reproducible data loss, duplicate writes, or blocked offline flow |
| Gate 2 — Sync Integrity (after Phase 2) | Telemetry from metadata-driven listeners (`isFromCache`, `hasPendingWrites`) | Pending writes always converge to zero after reconnect in test matrix | Pending writes stuck, stale cache state never clears, metadata state mismatches UI |
| Gate 3 — UX Trust (after Phase 3) | Pilot walkthroughs + UX checklist | Users can always identify offline state, pending state, and sync completion | Users cannot tell if data is safe/synced, confusing status transitions |
| Gate 4 — Conflict Safety (after Phase 4) | Multi-device conflict scenarios + resolution logs | Conflicts are surfaced deterministically with clear resolution state | Silent overwrite without conflict visibility for action-item conflict paths |
| Gate 5 — Release Readiness (after Phase 5) | Pilot KPI report + crash-free report + support ticket review | KPIs hit targets for 2 consecutive weeks in pilot cohort | Any Sev-1 sync incident or repeated Sev-2 unresolved integrity issue |

### Weekly Risk KPI Scorecard

Track these KPIs weekly in staging and pilot before broad rollout.

| KPI | Definition | Target | Alert Threshold |
|---|---|---|---|
| Sync Success Rate | % of queued local writes that reach committed server state within SLA | >= 99.5% | < 99.0% |
| Duplicate Write Rate | % of user actions resulting in duplicate server-side effects | <= 0.1% | > 0.5% |
| Conflict Visibility Rate | % of detected action-item conflicts that are surfaced in UI | 100% | < 99% |
| Mean Time to Sync (MTTS) | Median time from reconnect to `hasPendingWrites = false` | <= 60s (normal backlog) | > 180s |
| Data Loss Incidents | Confirmed user-intent records not recoverable from cache/server | 0 | >= 1 |

### Risk Register (Focused)

| ID | Risk | Impact | Likelihood | Owner | Early Signal | Mitigation | Contingency |
|---|---|---|---|---|---|---|---|
| R1 | Metadata-only updates not reflected in UI quickly enough | High | Medium | iOS | `hasPendingWrites` remains true in UI after backend commit | Use listener options with metadata updates enabled and verify transition tests per screen | Show explicit "Sync status delayed" fallback state and trigger listener refresh |
| R2 | Pending writes appear stuck after reconnect due to unstable network | High | Medium | iOS + QA | MTTS exceeds threshold for same cohort/network condition | Add reconnect stabilization delay and resilient retry observation window | Provide manual "Force Refresh" action and capture diagnostics for affected org |
| R3 | Conflict behavior causes silent overwrite confusion in action items | High | Medium | Product + iOS | User reports mismatch between expected and final action-item state | Enforce deterministic conflict badge + details sheet + timestamp attribution | Add temporary server-wins policy flag for high-risk fields |
| R4 | Phase 1 cleanup removes code paths still used by tests/legacy flows | Medium | High | iOS | Failing regression tests tied to removed queue/persistence APIs | Update tests in same PR as cleanup; require green suite before merge | Hotfix adapter shim for one release if legacy call sites remain |
| R5 | Overstated "real-time" analytics while offline backlog flushes later | Medium | Medium | Product + Data | Dashboard values shift materially after reconnect | Label delayed ingestion metrics and add event-time vs ingest-time views | Communicate SLA language in customer-facing analytics docs |

### Pilot Rollout Checklist (Enterprise Risk-Controlled)

#### Pilot Scope
- 1-2 organizations
- 10-30 frontline users across poor-connectivity environments
- Minimum pilot duration: 2 weeks

#### Entry Criteria
- Gates 1-4 passed in staging
- QA matrix complete: airplane mode, app kill/relaunch, long offline window (8+ hours), network flap
- No open Sev-1 issues

#### Exit Criteria
- Gate 5 passed
- Data Loss Incidents = 0
- Sync Success Rate >= 99.5% for 2 consecutive weeks
- Duplicate Write Rate <= 0.1%
- Conflict Visibility Rate = 100%

#### Rollout Decision
- **Go broad:** all exit criteria met
- **Hold:** any threshold missed
- **Rollback:** any Sev-1 integrity incident

### Test Matrix (Minimum)

| Scenario | Expected Result |
|---|---|
| Create/edit/delete notes fully offline | UI updates immediately from cache; sync completes on reconnect |
| App terminated while offline with pending writes | Writes persist and replay after relaunch/reconnect |
| Network flaps during backlog drain | No duplicate writes; pending state eventually clears |
| Two users edit same action item during disconnect window | Conflict is surfaced with deterministic badge/details |
| Reconnect after long shift backlog (30+ writes) | Queue drains without app freeze; MTTS within threshold |

---

## Timeline Summary

| Phase | Duration | Key Deliverable |
|-------|----------|-----------------|
| Phase 1: Code Cleanup | 3 days | Remove redundant sync code; trust Firestore |
| Phase 2: Enhanced Listeners | 3 days | Sync metadata flows to ViewModel |
| Phase 3: Sync State UI | 4 days | Offline banner, sync badges, reconnect toast |
| Phase 4: Conflict Awareness | 3 days | Action item conflict detection + UI |
| Phase 5: Draft Recovery + Polish | 2 days | Crash recovery, animations, e2e testing |

**Total estimated duration: 3 weeks** (down from 10 weeks in original PRD)

---

## What We're NOT Building (Because Firestore Handles It)

| Original PRD Item | Why We Skip It |
|---|---|
| `OfflineStore` (record-level file storage) | Firestore persistent cache IS record-level storage |
| `SyncQueue` / `SyncOperation` model | Firestore SDK queues writes internally with retry + backoff |
| `SyncEngine` orchestrator | Firestore listeners + auto-sync replaces this entirely |
| Custom exponential backoff | Firestore SDK has its own retry logic |
| Per-file sync queue on disk | Firestore persists its write queue to disk automatically |
| Backend delta sync endpoint | Firestore listeners are already incremental (only changed docs fire) |
| Server-side conflict detection endpoint | Using Firestore transactions for online conflicts |
| Soft deletes with 30-day purge | Firestore `deleteDocument()` + security rules handles this |
| Record-level timestamps migration | Firestore documents already have per-document metadata |
| Feature flags for gradual rollout | Scope is small enough to ship in one release |
| Custom audit log (append-only JSONL) | Deferred — Firestore Audit Logging (GCP) available if needed for enterprise |

---

## Dependencies & Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Removing `PendingAction` breaks existing offline behavior | High | Low | Firestore already handles offline writes — we're removing redundancy, not capability |
| Firestore cache size insufficient for heavy users | Low | Very Low | Default 100MB handles thousands of documents; configurable if needed |
| Snapshot metadata not granular enough for per-note sync status | Medium | Low | Fall back to tracking dirty note IDs locally if needed |
| Firestore transactions fail offline (conflict detection) | Medium | Medium | Accept last-write-wins offline; only do transactional merge when online |
| Tests reference `PendingAction` and manual sync code | Medium | High | Update tests in Phase 1 — budget 1 day for this |

---

## Appendix: Firestore Offline Capabilities Reference

### What Firestore Does Automatically (iOS SDK)

1. **Persistent cache** — enabled by default via `PersistentCacheSettings`
2. **Offline writes** — `setData()`, `updateData()`, `deleteDocument()` succeed immediately (write to local cache) and queue for server sync
3. **Listener continuation** — snapshot listeners fire with cached data when offline
4. **Automatic reconnect** — SDK reconnects and syncs when network returns
5. **Write ordering** — queued writes are replayed in order
6. **Cache across restarts** — persisted to disk, survives app kill

### What Firestore Does NOT Do

1. Does not show UI about sync state — we must read `SnapshotMetadata`
2. Does not merge at field level — last-write-wins at document level
3. Does not detect conflicts — we must compare timestamps ourselves
4. Does not recover in-progress recordings/drafts — app-level concern
5. Does not provide audit logs natively — GCP Audit Logging is a separate product

### Key APIs We'll Use

```swift
// Snapshot metadata
snapshot.metadata.isFromCache        // true if data from local cache
snapshot.metadata.hasPendingWrites   // true if local writes not yet confirmed

// Server timestamps
import FirebaseFirestore
FieldValue.serverTimestamp()          // Use instead of Date() for updatedAt

// Per-document metadata in listener
snapshot.documentChanges.forEach { change in
    change.document.metadata.hasPendingWrites  // per-doc pending state
}
```
