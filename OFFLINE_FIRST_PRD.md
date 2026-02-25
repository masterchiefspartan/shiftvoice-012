# Offline-First Execution & Auto-Sync — Product Requirements Document (v3)

## Executive Summary

ShiftVoice already uses Firestore as the primary database. Firestore iOS SDK gives us offline cache, write queueing, retry, and reconnect sync by default.

This PRD removes redundant custom sync infrastructure and keeps only enterprise-critical work:
- Visible sync/offline state for users
- Conflict visibility for shared action items
- Removal of duplicated queue/persistence code

---

## Confirmed Baseline (Already Covered by Firestore)

- Offline reads from local cache
- Offline write queueing (`setData`, `updateData`, `deleteDocument`)
- Automatic retry on reconnect
- Persistent disk cache across app restarts
- Real-time listener updates after reconnect
- Snapshot metadata (`isFromCache`, `hasPendingWrites`)
- Atomic batched writes

### Immediate Cleanup Implication

The following are redundant and should be removed:
- `PendingAction.swift`
- `pendingActions` queue logic in `AppViewModel`
- Manual replay methods (`replayPendingActions`, related reconnect replay flow)
- Pending action persistence methods in `PersistenceService`
- Monolithic `app_data.json` sync persistence used to duplicate Firestore state

---

## Product Scope (What We Still Need)

1. User-visible offline/sync status
2. Per-note pending/synced indicators
3. Reconnect confirmation feedback
4. Action-item conflict visibility for multi-user edits
5. Codebase simplification to Firestore as single sync truth

Out of scope:
- Building a custom offline engine
- Building a custom retry queue
- Backend delta-sync endpoints for this phase

---

## Goals & Success Metrics

### Goals

| Goal | Target |
|---|---|
| Clear sync transparency | Every note exposes sync state |
| Offline confidence | Always-visible offline state when disconnected |
| Architecture simplification | Remove redundant manual sync code |
| Conflict awareness | Shared action-item conflicts are surfaced |

### Metrics

| Metric | Target |
|---|---|
| Offline state visibility | 100% of offline sessions show banner |
| Per-note sync visibility | 100% note cards show deterministic sync state |
| Pending write convergence | `hasPendingWrites` reliably returns to false after reconnect |
| Data loss incidents | 0 |

---

## User Stories

- As a shift lead, I can work offline and know changes are safe.
- As a shift lead, I can see whether each note is pending or synced.
- As a shift lead, I get confirmation when reconnect sync finishes.
- As a manager, I can see when action-item edits conflicted across users.

---

## Technical Requirements

### 1) Listener Metadata Plumbing

Enhance Firestore listeners so ViewModel receives:
- `isFromCache`
- `hasPendingWrites`
- per-document `hasPendingWrites` for note-level indicators

### 2) ViewModel Sync State

Add and maintain:
- `isDataFromCache: Bool`
- `hasPendingWrites: Bool`
- `lastSyncedFromServer: Date?`
- `pendingNoteIds: Set<String>` (derived from document metadata)

### 3) Write Path Simplification

All writes go directly to Firestore. Remove manual offline queue branching.

### 4) Conflict Awareness (Action Items)

- Keep last-write-wins baseline
- Add conflict detection heuristics for multi-user action item changes
- Surface conflict badge + detail sheet

---

## UX Requirements

### Offline Banner

When disconnected:
- Show persistent top banner: "You're offline — changes save automatically"
- If pending writes exist, show count/state (e.g., "Offline — changes waiting to sync")

### Per-Note Sync Indicator

On each note card:
- Pending: orange cloud icon
- Cache-derived non-pending state: subtle cache/refresh indicator where needed
- Clean synced state: no icon

### Reconnect Feedback

- On reconnect: "Back online — syncing..."
- On pending writes drained: "All changes synced" + success haptic

### Settings: Sync & Data Section

- Last synced timestamp
- Current data source (Server/Cache)
- Force refresh action (restart listeners)

---

## Data & Persistence Decisions

- Firestore cache is authoritative for offline sync persistence
- Keep local persistence only for non-Firestore bootstrap needs (e.g., profile bootstrap if still required)
- Remove pending queue persistence and duplicate app-data sync snapshot persistence

---

## Edge Cases

1. App kill during note creation flow:
   - Keep draft recovery flow (separate from Firestore sync)
2. Large backlog after long offline shift:
   - Rely on Firestore queue drain; track completion via metadata
3. Multi-user concurrent action-item edits:
   - Surface conflicts; do not block baseline write behavior

---

## Execution Plan

### Phase 1 — Remove Redundant Sync Infrastructure (3 days)
- Delete `PendingAction` model and queue paths
- Remove replay-on-reconnect logic
- Simplify Firestore write calls
- Remove duplicate sync persistence from `PersistenceService`
- Update tests tied to removed paths

**Exit criteria:** no custom pending queue remains; app behavior unchanged for offline reliability.

### Phase 2 — Metadata-Driven Sync State (3 days)
- Pass listener metadata from Firestore service
- Track sync state in `AppViewModel`
- Add server timestamp consistency where needed

**Exit criteria:** metadata state updates correctly in real time.

### Phase 3 — Offline/Sync UX (4 days)
- Add offline banner
- Add per-note sync indicators
- Add reconnect/sync-complete toasts
- Add Settings sync diagnostics section

**Exit criteria:** users can always identify offline, pending, and synced states.

### Phase 4 — Conflict Visibility (3 days)
- Detect action-item conflict conditions
- Add conflict badge + details UI
- Add resolve/dismiss flow

**Exit criteria:** shared action-item conflicts are visible and reviewable.

### Phase 5 — Draft Recovery + E2E Hardening (2 days)
- Ensure draft resume/recovery path works
- Validate full offline → reconnect workflows
- Polish transitions and feedback

**Exit criteria:** no data loss in tested offline lifecycle scenarios.

---

## Stage Gates (Go / No-Go)

| Gate | Criteria |
|---|---|
| Gate 1 (after Phase 1) | No data loss, no duplicate writes, no blocked offline flow |
| Gate 2 (after Phase 2) | Metadata state converges correctly after reconnect |
| Gate 3 (after Phase 3) | Pilot users can always identify sync state |
| Gate 4 (after Phase 4) | Conflicts are surfaced deterministically |
| Gate 5 (after Phase 5) | Pilot KPIs stable for 2 weeks, no Sev-1 incidents |

---

## Pilot Plan

- Pilot size: 1–2 orgs, 10–30 users
- Duration: minimum 2 weeks
- Required test scenarios:
  - Full offline create/edit/delete
  - App kill + relaunch while pending writes exist
  - Network flap during backlog drain
  - Multi-user action-item conflict case
  - Long offline shift backlog drain

Success thresholds:
- Data loss incidents = 0
- Pending writes converge reliably post-reconnect
- Conflict visibility is deterministic in tested scenarios

---

## Timeline

| Phase | Duration |
|---|---|
| Phase 1 | 3 days |
| Phase 2 | 3 days |
| Phase 3 | 4 days |
| Phase 4 | 3 days |
| Phase 5 | 2 days |

**Total: ~3 weeks**

---

## Final Scope Guardrails

We are intentionally **not** building:
- Custom sync engine
- Custom retry/backoff queue
- Parallel local record store mirroring Firestore
- Broad backend sync redesign in this phase

This keeps delivery focused, lower-risk, and aligned with what Firestore already provides.