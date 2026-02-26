# Offline-First Execution & Auto-Sync PRD (v4)

## 1. Executive Summary

ShiftVoice already runs on Firestore, which provides offline persistence, local write queueing, and automatic sync on reconnect for iOS.

This plan focuses on **enterprise-grade reliability without overbuilding**:
- Keep Firestore as the single sync engine
- Remove custom duplicate queue/replay logic
- Add deterministic sync visibility and conflict handling
- Add strict phase gates and testing between phases to reduce release risk

---

## 2. Product Goals

1. Workers can complete shift work fully offline with no blocked flows.
2. Users always see sync state (offline, pending, synced, conflicted).
3. Reconnect behavior is predictable and transparent.
4. Multi-user conflicts are surfaced and auditable.
5. Architecture is simplified (lower operational risk, lower maintenance cost).

### Non-Goals
- Building a custom sync engine
- Building a second local database mirroring Firestore
- Replacing Firestore conflict semantics globally

---

## 3. Current Baseline (Firestore-Backed)

Already available through Firestore iOS SDK:
- Disk-backed offline cache
- Offline writes queued locally and retried automatically
- Real-time listener reconciliation after reconnect
- Snapshot metadata for sync state (`isFromCache`, `hasPendingWrites`)
- Atomic batched writes and transaction support where needed

### Immediate Simplification Scope
Redundant custom sync code to remove:
- `Models/PendingAction.swift`
- `pendingActions` queue logic in `ViewModels/AppViewModel.swift`
- Replay flow (`replayPendingActions` and related reconnect queue playback)
- Pending queue persistence in `Services/PersistenceService.swift`
- Any duplicate “sync snapshot” persistence used as parallel sync truth

---

## 4. User Problems We Are Solving

- "Did my changes save while offline?"
- "Are my notes synced yet?"
- "What happened when two people edited the same action item?"
- "Can I trust this app in low-connectivity shifts?"

---

## 5. Functional Requirements

### 5.1 Offline/Sync Visibility
- Global offline banner when disconnected
- Pending sync banner/state while local writes exist
- Success confirmation when pending writes drain

### 5.2 Per-Note Sync State
Each note card must deterministically show one of:
- Pending local write
- Synced
- Conflict flagged (if applicable)

### 5.3 Conflict Visibility (Action Items)
- Keep Firestore last-write-wins base behavior
- Add app-level conflict detection for high-risk fields (status, assignee, due state)
- Show conflict badge + conflict details sheet
- Allow explicit resolve/dismiss action with audit fields

### 5.4 Diagnostics
Settings > Sync & Data must show:
- Last successful server sync timestamp
- Data source signal (cache/server)
- Pending write state
- Manual listener restart action

---

## 6. Data & Conflict Strategy (Conflict-Safe)

### 6.1 Write Model
- All writes go directly to Firestore
- No separate custom replay queue
- Use `serverTimestamp` for authoritative mutation timing fields

### 6.2 Conflict Detection Scope
Apply conflict detection to mutable collaborative fields only (action items):
- `status`
- `assigneeId`
- `priority`

### 6.3 Metadata Fields (per action item)
- `updatedAtServer`
- `updatedByUserId`
- `statusUpdatedAtServer`
- `statusUpdatedByUserId`
- `assigneeUpdatedAtServer`
- `assigneeUpdatedByUserId`
- `conflictState` (`none | detected | resolved`)
- `conflictSummary` (short string)

### 6.4 Deterministic Conflict Rule
Conflict is detected when:
- remote update changes same tracked field
- local unsynced change exists or two competing updates occur in same reconciliation window
- final value differs from local intended value

Resolution policy:
- persisted value remains Firestore result
- conflict is surfaced to user
- user can accept current value or apply explicit correction (new write)

### 6.5 Concurrency Hotspots
Use Firestore transactions for true read-modify-write hotspots only (if introduced), not for routine note saves.

---

## 7. UX Requirements

### 7.1 Banner States
1. **Offline:** “You’re offline — changes save automatically.”
2. **Reconnect syncing:** “Back online — syncing changes…”
3. **Complete:** “All changes synced.”

### 7.2 Note Card Indicators
- Pending: orange cloud icon
- Conflict: amber warning badge
- Synced clean: no badge

### 7.3 Conflict Detail Sheet
- Field changed
- Your intended value vs current value
- Updated by + time
- Actions: “Keep Current” / “Apply My Update”

---

## 8. Architecture & Code Plan

### 8.1 FirestoreService
- Add listener APIs that return both decoded documents and snapshot metadata
- Enable metadata updates (`includeMetadataChanges: true`) where sync state is tracked

### 8.2 AppViewModel
Add state:
- `isDataFromCache: Bool`
- `hasPendingWrites: Bool`
- `lastSyncedFromServer: Date?`
- `pendingNoteIds: Set<String>`
- `detectedConflicts: [ConflictItem]`

### 8.3 PersistenceService
- Remove pending queue persistence APIs
- Keep only non-Firestore persistence needed for app bootstrap/drafts

### 8.4 Models
- Remove `PendingAction`
- Ensure conflict metadata is Codable-safe and backward compatible

---

## 9. Phased Execution Plan (with Test Gates)

## Phase 1 — Remove Redundant Sync Infrastructure (3 days)
**Build**
- Delete `PendingAction` model and all queue/replay usage
- Remove pending queue persistence methods
- Keep existing Firestore write paths functional

**Verification**
- Unit tests compile and pass after removal
- Offline create/edit/delete still works through Firestore SDK queueing

**Gate 1 (Go/No-Go)**
- No duplicate writes
- No blocked offline publishing
- No regression in note creation/edit flow

---

## Phase 2 — Metadata-Driven Sync State (3 days)
**Build**
- Wire snapshot metadata from listeners into ViewModel
- Track app-level and per-note pending state
- Track last server-synced timestamp

**Verification**
- Simulated offline/online toggles update state correctly
- `hasPendingWrites` transitions true -> false after reconnect

**Gate 2 (Go/No-Go)**
- Metadata state converges correctly in repeated reconnect cycles
- No stale pending indicators

---

## Phase 3 — User-Facing Sync UX (4 days)
**Build**
- Add banners, note badges, and success feedback
- Add Sync & Data diagnostics section in Settings

**Verification**
- UI tests for banner visibility and transitions
- Accessibility checks (VoiceOver labels for sync badges)

**Gate 3 (Go/No-Go)**
- Users can always identify offline/pending/synced states
- Zero ambiguous sync state in test scenarios

---

## Phase 4 — Conflict Visibility & Resolution (4 days)
**Build**
- Add conflict metadata fields + conflict detector
- Add conflict badge and detail sheet
- Add explicit resolve actions and persistence

**Verification**
- Multi-client conflict simulation (same action item field edits)
- Deterministic conflict surfacing and dismissal

**Gate 4 (Go/No-Go)**
- Conflicts are surfaced deterministically
- Resolution actions always result in a valid final state

---

## Phase 5 — Hardening, Pilot, and Rollout Controls (3 days + pilot)
**Build**
- Instrument sync lifecycle metrics
- Add runbook + support diagnostics
- Feature-flag conflict UI for staged rollout

**Verification**
- End-to-end reliability suite
- Long-offline backlog drain tests
- App kill + relaunch while pending writes exist

**Gate 5 (Go/No-Go)**
- Pilot completes with no Sev-1/Sev-2 sync incidents
- Data loss incidents = 0

---

## 10. Testing Strategy (Required Between Every Phase)

### 10.1 Automated
- Unit tests: merge/conflict logic, metadata reducers
- ViewModel tests: state transitions for offline -> reconnect -> synced
- UI tests: banner/badge rendering and action flows

### 10.2 Manual Scenario Matrix
1. Full offline shift (create/edit/delete/acknowledge)
2. App force-close with pending writes
3. Network flap during backlog drain
4. Concurrent edits on same action item field
5. Cross-device same-user and multi-user behavior

### 10.3 Release Qualification
A phase cannot close unless:
- Test suite passes
- Gate criteria pass
- No unresolved Sev-1/Sev-2 defects in changed scope

---

## 11. Rollout & Risk Mitigation

### 11.1 Rollout Sequence
1. Internal team
2. Pilot orgs (10–30 users)
3. 25% rollout
4. 100% rollout

### 11.2 Kill Switches
- Remote flag to hide conflict UI if needed
- Remote flag to disable diagnostics-only additions if instability appears

### 11.3 Key Risks & Mitigations
- **Risk:** stale auth during reconnect drain  
  **Mitigation:** enforce auth refresh checks + clear user-facing recovery path
- **Risk:** false-positive conflict noise  
  **Mitigation:** scope detection only to high-contention fields first
- **Risk:** UX confusion from too many states  
  **Mitigation:** strict state model and copy consistency

---

## 12. Success Metrics

- Offline sessions with visible state: **100%**
- Pending writes converging after reconnect: **>= 99.9%** in pilot
- Data loss incidents: **0**
- Conflict events with deterministic UI outcome: **100%**
- Sync-related support tickets: downward trend post rollout

---

## 13. Final Scope Guardrails

We will **not** build in this initiative:
- Custom offline database mirroring Firestore
- Custom retry/backoff sync engine
- Broad backend sync redesign
- Real-time analytics guarantees that ignore offline delay realities

This keeps the implementation comprehensive, conflict-safe, and shippable with minimal architectural risk.