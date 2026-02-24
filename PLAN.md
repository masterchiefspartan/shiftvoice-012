# ShiftVoice Build Plan

## Vision

Transform ShiftVoice from a voice-first shift notes tool into the **operating system for frontline operations** — a full infrastructure project management platform where voice is the primary input, AI is the structuring engine, and shift handoffs become the system of record.

---

## Completed Phases

### Phase 1: Authentication Reliability ✅
- Surfaced backend auth errors to users (was silently swallowed)
- Fixed token restore ordering (userId was nil during setAuth)
- Added retry logic for backend auth calls
- Session validation on app launch

### Phase 2: Transcript → Action Item Splitting ✅
- Recursive multi-separator splitting (was only matching first separator)
- Sentence-level splitting on `.!?` before separator detection
- Action items now generated for ALL categories (general was skipped entirely)
- AI structuring returns typed `Result<StructuringResult, StructuringError>` instead of nil
- Confidence warning when AI returns 1 item for 40+ word transcript
- 30-second processing timeout with local fallback
- 45+ unit tests

### Phase 3: Error Handling & User Feedback ✅
- Toast notification system for sync failures, push errors, offline status
- Offline pending queue indicator with count
- Publish-while-offline saves locally with PendingAction queue
- Processing view shows elapsed time, dynamic messaging, cancel button after 15s
- Sync status in feed header (last sync time, retry button on failure)
- Push-to-backend debounced (500ms) to prevent race conditions
- 30+ unit tests

---

## Remaining Stability Phases

### Phase 4: Data Integrity & Sync Reliability
**Priority:** 🟠 High | **Effort:** High | **Target:** 1-2 weeks

**Problems:**
- `pushToBackend()` overwrites ALL data every time — no conflict resolution
- If push fails, no retry queue — data stays local until next manual sync
- `mergeShiftNotes` replaces by ID without checking timestamps — stale server data overwrites newer local edits
- No `updatedAt` tracking on models

**Deliverables:**
1. Add `updatedAt: Date` field to ShiftNote, ActionItem, TeamMember models
2. Timestamp-based conflict resolution in merge helpers (newest wins)
3. Persistent offline action queue that retries on reconnect (currently in-memory only)
4. Delta sync — only push changed records, not the entire data set
5. Optimistic UI updates with rollback on sync failure
6. Sync conflict UI — show "Conflict resolved: kept your version" toast

**Tests:**
- Rapid edit debouncing verification
- Conflict resolution: newer local vs older server
- Offline queue persistence across app restarts
- Merge correctness with concurrent edits from multiple users
- Delta sync payload verification

---

### Phase 5: Recording Reliability
**Priority:** 🟡 Medium | **Effort:** Medium | **Target:** 1 week

**Problems:**
- If `transcribeAudioFile` returns nil, the note processes with empty transcript
- No audio file validation — corrupt recordings pass through
- `continuation.resume` in TranscriptionService can be called multiple times
- 3-minute auto-stop has no user warning

**Deliverables:**
1. Validate audio file exists and has non-zero size before transcribing
2. Continuation safety wrapper (track if already resumed)
3. 30-second warning before auto-stop with haptic
4. Clear distinction between "transcription failed" vs "empty recording"
5. Retry transcription button on review screen
6. Audio level indicator during recording (confirms mic is picking up)

**Tests:**
- Audio file validation (zero-size, missing file, valid file)
- Transcription failure handling paths
- Auto-stop warning timing
- Empty vs failed transcript UI state

---

### Phase 6: Performance & Polish
**Priority:** 🟡 Medium | **Effort:** Medium | **Target:** 1 week

**Problems:**
- `feedNotes` recomputes on every access
- `allActionItems` scans every note on every render
- All 3 tabs always in memory (opacity/hitTesting instead of lazy)
- `notesThisMonth` iterates all notes on every record button tap

**Deliverables:**
1. Cache computed properties, invalidate on data change
2. Lazy-load tab content (only mount active tab)
3. Proper loading skeleton states for initial data fetch
4. Incremental `unacknowledgedCount` updates
5. Pagination for feed (load 20 notes at a time, infinite scroll)
6. Search performance optimization with debounced input

**Tests:**
- Feed performance with 100+ notes
- Tab switching memory profile
- Computed property caching correctness
- Pagination boundary conditions

---

## Feature Phases (Product Expansion)

### Phase 7: Smart Shift Handoff Reports
**Priority:** 🔴 Critical (Moat) | **Effort:** High | **Target:** 2-3 weeks

**Why:** This is the single most important feature for making ShiftVoice infrastructure. Once teams rely on auto-generated handoffs, switching costs become massive.

**Deliverables:**
1. **Auto-generated handoff report** — When a shift ends (or manually triggered), compile all notes, action items, and status changes into a structured report
2. **Handoff template engine** — Sections: Open Items, Resolved This Shift, New Issues, VIP/Reservations, Staff Notes, FYI
3. **Incoming shift view** — "Here's what happened" summary screen shown when starting a new shift
4. **Handoff push notification** — Alert incoming shift leads that a handoff is ready
5. **Handoff history** — Searchable archive of all past handoffs per location
6. **Handoff acknowledgment** — Incoming lead marks handoff as "reviewed" with optional voice reply
7. **Backend: Handoff model & API** — New `ShiftHandoff` entity, generation endpoint, storage

**Data Model:**
```
ShiftHandoff {
  id, locationId, shiftType, createdBy,
  generatedAt, acknowledgedBy, acknowledgedAt,
  summary (AI-generated),
  openActionItems: [ActionItem],
  resolvedThisShift: [ActionItem],
  newIssues: [CategorizedItem],
  noteIds: [String],
  status: .pending | .acknowledged | .expired
}
```

**Tests:**
- Handoff generation from shift notes
- Correct filtering of notes by shift window
- Acknowledgment flow
- Push notification trigger
- Empty shift handoff (no notes)

---

### Phase 8: Real-Time Shift Feed with @Mentions & Escalation
**Priority:** 🔴 Critical (Moat) | **Effort:** High | **Target:** 2-3 weeks

**Why:** Replaces walkie-talkie chaos with structured, searchable, accountable communication.

**Deliverables:**
1. **Live activity feed** — Real-time updates when teammates post notes (polling or WebSocket)
2. **@Mention system** — Tag team members in notes/action items, trigger push notification
3. **Escalation rules** — Auto-escalate based on category + urgency (e.g., health/safety + immediate → notify GM)
4. **Priority levels on action items** — Visual distinction (red pulse for immediate, amber for next shift)
5. **Read receipts** — See who has viewed a note
6. **Thread replies** — Reply to specific categorized items (voice or text)
7. **Notification preferences** — Per-user control: all notes, mentions only, escalations only

**Backend:**
- WebSocket or polling endpoint for live feed
- @mention resolution and notification routing
- Escalation rule engine (configurable per org)
- Read receipt tracking

**Tests:**
- @Mention parsing and notification delivery
- Escalation rule matching
- Feed ordering and real-time updates
- Notification preference filtering

---

### Phase 9: Recurring Issue Detection & Trend Analytics
**Priority:** 🟠 High (Moat) | **Effort:** High | **Target:** 2-3 weeks

**Why:** Turns raw shift notes into operational intelligence. Managers stop firefighting and start preventing.

**Deliverables:**
1. **Pattern detection engine** — AI scans notes over time for recurring themes (e.g., "Room 204 has had 3 plumbing issues this month")
2. **Trend dashboard** — Visual analytics: issues by category over time, location comparison, resolution time
3. **Recurring issue cards** — Dedicated UI showing pattern, frequency, affected location, first/last mention
4. **Smart alerts** — Push when a pattern is detected: "Fryer issues reported 4 times in 2 weeks"
5. **Resolution tracking** — Mark recurring issues as resolved, track if they resurface
6. **Export/share** — Generate PDF or share link for management reports
7. **Location benchmarking** — Compare issue rates across locations

**Backend:**
- Batch analysis endpoint (runs nightly or on-demand)
- Trend aggregation queries
- Alert generation and delivery
- PDF report generation

**Existing Foundation:** The app already has a `RecurringIssue` model and basic recurring issue detection in the dashboard. This phase extends it with AI-powered pattern detection and rich analytics.

**Tests:**
- Pattern detection accuracy (similar issues across notes)
- Trend aggregation correctness
- Alert threshold triggers
- Resolution and resurfacing tracking

---

### Phase 10: Photo/Video Attachment on Voice Notes
**Priority:** 🟠 High | **Effort:** Medium | **Target:** 1-2 weeks

**Why:** "Crack in ceiling of room 312" is 10x more useful with a photo. Creates a visual audit trail for maintenance, insurance, and compliance.

**Deliverables:**
1. **Camera capture during recording** — Snap photos mid-recording without stopping audio
2. **Photo review on note review screen** — View, reorder, delete attached photos before publishing
3. **Photo viewer on note detail** — Full-screen viewer with zoom, swipe between photos
4. **Image compression & upload** — Resize to reasonable quality, upload to backend storage
5. **Thumbnail generation** — Show thumbnails on note cards in feed
6. **Offline photo queue** — Store photos locally, upload when reconnected

**Technical:**
- Camera permission + proxy pattern (existing CameraProxyView)
- Image storage on backend (R2 or similar)
- Photo URLs stored in `ShiftNote.photoUrls` (field already exists but unused)

**Tests:**
- Photo attachment during active recording
- Image compression quality/size
- Offline photo queue persistence
- Photo display in note detail

---

### Phase 11: Property-Specific AI Learning
**Priority:** 🟡 Medium (Moat) | **Effort:** High | **Target:** 3-4 weeks

**Why:** Creates compounding value — the longer a team uses ShiftVoice, the more accurate it becomes. Natural lock-in.

**Deliverables:**
1. **Custom vocabulary** — Learn property-specific room numbers, equipment names, menu items
2. **Category fine-tuning** — Adjust category weights based on correction history (if users keep re-categorizing, learn from it)
3. **Autocomplete suggestions** — Suggest likely categories and urgency based on past patterns
4. **Custom category creation** — Let orgs add their own categories beyond the default set
5. **AI prompt personalization** — Include org-specific context in structuring prompts
6. **Correction feedback loop** — When users edit AI output on review screen, feed corrections back to improve future structuring

**Backend:**
- Per-org vocabulary store
- Correction tracking and aggregation
- Dynamic prompt construction with org context
- Category customization API

**Tests:**
- Vocabulary learning from corrections
- Custom category CRUD
- Prompt personalization output quality
- Correction feedback persistence

---

## Phase Summary & Timeline

| Phase | Name | Status | Priority | Effort | Target |
|-------|------|--------|----------|--------|--------|
| 1 | Auth Reliability | ✅ Done | Critical | Medium | — |
| 2 | Transcript Splitting | ✅ Done | Critical | Medium | — |
| 3 | Error Handling | ✅ Done | High | Low-Med | — |
| 4 | Data Sync Integrity | 🔲 Next | High | High | Week 1-2 |
| 5 | Recording Reliability | 🔲 | Medium | Medium | Week 3 |
| 6 | Performance & Polish | 🔲 | Medium | Medium | Week 4 |
| 7 | Shift Handoff Reports | 🔲 | Critical | High | Week 5-7 |
| 8 | @Mentions & Escalation | 🔲 | Critical | High | Week 7-9 |
| 9 | Trend Analytics | 🔲 | High | High | Week 9-11 |
| 10 | Photo Attachments | 🔲 | High | Medium | Week 11-12 |
| 11 | AI Learning | 🔲 | Medium | High | Week 13-16 |

**Total estimated timeline: ~16 weeks to full platform**

---

## Success Metrics

| Metric | Current | Target (Post Phase 11) |
|--------|---------|----------------------|
| Notes per user per shift | ~2 | 5+ |
| Action items resolved within shift | Unknown | >70% |
| Handoff adoption rate | N/A | >80% of shifts |
| Recurring issues caught proactively | 0 | 10+ per month per location |
| User retention (30-day) | Unknown | >85% |
| Expansion (locations per org) | 1 | 3+ |

---

## Risk & Dependencies

| Risk | Mitigation |
|------|-----------|
| AI structuring quality plateaus | Phase 11 correction feedback loop; allow manual override |
| Real-time feed scalability | Start with polling (30s), migrate to WebSocket when needed |
| Photo storage costs | Aggressive compression, tiered storage by plan |
| Offline-first complexity | Phase 4 lays the foundation; each subsequent phase builds on it |
| Team adoption friction | Handoff reports (Phase 7) create natural pull; @mentions (Phase 8) create daily engagement |
