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

### Phase 4: Data Integrity & Sync Reliability ✅
**Priority:** 🟠 High | **Effort:** High | **Target:** 1-2 weeks

- Added `updatedAt` to ShiftNote, ActionItem, TeamMember models (backwards-compatible Codable)
- Timestamp-based conflict resolution in all merge helpers (newest wins for notes)
- Per-field merge for action items — `statusUpdatedAt` and `assigneeUpdatedAt` merge independently; conflict flagged only when same field changed by two users at identical timestamps
- Persistent offline action queue — saves to disk via PersistenceService, survives app restarts, retries up to 3x with incremented retry count
- Delta sync — dirty flag tracking (`isDirty` on ShiftNote), only dirty records pushed; `dirtyNoteIds` set cleared after successful push
- Optimistic UI with rollback — snapshot saved before push, `rollbackFromSnapshot()` restores state on failure
- Sync conflict UI — amber "Conflict detected" banner on ActionItemRow with description and dismiss button
- 30+ unit tests covering per-field merge, timestamp resolution, conflict detection/dismissal, offline queue persistence, snapshot round-trip, and backwards-compatible Codable decoding

---

### Phase 5: Recording Reliability
**Priority:** 🟡 Medium | **Effort:** Medium | **Target:** 1 week

**Problems:**
- If `transcribeAudioFile` returns nil, the note processes with empty transcript
- No audio file validation — corrupt recordings pass through
- `continuation.resume` in TranscriptionService can be called multiple times
- 3-minute auto-stop has no user warning

**Deliverables:**
- [x] Validate audio file exists and has non-zero size before transcribing
- [ ] Continuation safety wrapper (track if already resumed)
- [x] 30-second warning before auto-stop with haptic
- [x] Clear distinction between "transcription failed" vs "empty recording"
- [x] Retry transcription button on review screen
- [x] Audio level indicator during recording (confirms mic is picking up)
- [x] Backend transcription guardrails (auth required, 25MB max file, 3-minute max duration)
- [x] OpenAI Whisper error mapping (rate limit/quota) surfaced to iOS with user-friendly retry guidance

**Tests:**
- [x] Audio file validation (zero-size, missing file, valid file)
- [x] Transcription failure handling paths
- [x] Auto-stop warning timing
- [x] Empty vs failed transcript UI state
- [x] Build verification after transcription safety/cost-control changes
- [ ] End-to-end failure-path integration tests for backend `STT_*` error code mapping

---

### Phase 6: Performance, Polish & Activation ✅
**Priority:** 🟡 Medium | **Effort:** Medium | **Target:** 1 week

**Delivered:**
- `feedNotes`, `allActionItemsWithDate`, `notesThisMonth`, `unacknowledgedCount` all cached as stored properties — invalidated via `didSet` on `shiftNotes` and `selectedLocationId`
- Lazy tab mounting — tabs only instantiated when first visited; scroll state preserved on return
- Client-side pagination — 20 notes per page, infinite scroll trigger on last visible row, auto-refreshes on Firestore updates
- Search with 300ms debounce — full-text across transcript, summary, author, and action items; bypasses pagination to search all `feedNotes`
- Skeleton loading rows with shimmer animation while initial Firestore data loads
- `isInitialLoading` flag cleared on first Firestore snapshot
- **Guided first-run experience** — 3-step paged modal (Record → AI Structures → Team Sync) shown once on first app open, CTA launches recorder directly; tracked with `@AppStorage`

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
8. **Offline handoff generation** — Generate structured handoff (Open Items, Resolved, New Issues) from local data without AI summary; show placeholder "AI summary will generate when you're back online"; backfill AI summary on reconnect and push updated notification
9. **Overlapping shift handling** — Note ownership resolved by creation timestamp (not shift window); prompt user if shift runs 2+ hours past end; generate "No activity" handoff for skipped shifts (silence is ambiguous)

**Data Model:**
```
ShiftHandoff {
  id, locationId, shiftType, createdBy,
  generatedAt, acknowledgedBy, acknowledgedAt,
  summary (AI-generated, nullable for offline),
  openActionItems: [ActionItem],
  resolvedThisShift: [ActionItem],
  newIssues: [CategorizedItem],
  noteIds: [String],
  status: .pending | .acknowledged | .expired,
  isOfflineGenerated: Bool
}
```

**Acceptance Criteria:**
- Handoff includes all notes from the shift window (±30 min buffer)
- Open action items carry forward automatically
- Incoming shift lead sees handoff on app open
- Handoff generation takes <5 seconds
- 0 data loss: every note from the shift appears in the handoff
- Offline-generated handoffs include all structured sections; AI summary backfills on reconnect
- Overlapping shift windows resolve note ownership by creation timestamp
- "No activity" handoff generated for shifts with zero notes

**Tests:**
- Handoff generation from shift notes
- Correct filtering of notes by shift window
- Acknowledgment flow
- Push notification trigger
- Empty shift handoff (no notes → "No activity" report)
- Offline handoff generation (structured sections without AI summary)
- AI summary backfill on reconnect
- Overlapping shift window note ownership resolution
- Extended shift prompt logic (2+ hours past end)

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

**Acceptance Criteria:**
- @mention resolves to correct user and delivers push within 30 seconds
- Escalation fires within 60 seconds of note publish
- Users can configure: All notes / Mentions only / Escalations only / Off
- Read receipt shows who viewed and when

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

## Review Hub & Agentic Workflow Map (Added)

### Purpose
Review is the command center where the agent proposes structured changes and users approve, edit, or reject before publish.

### Information Architecture
- **Capture:** `RecordView`
- **Propose + Reconcile:** `NoteReviewView` / conflict surfaces
- **Publish + Monitor:** `DashboardView`, `ShiftFeedView`

### Core Review Sub-Features
1. **Draft Summary**
   - Agent-generated shift summary
   - Confidence + missing-information flags
2. **Structured Extraction**
   - Proposed fields (owner, priority, due date, incidents, handoff items)
   - Per-field accept/edit/reject
3. **Change Proposals Queue**
   - Diff-style before/after presentation
   - Bulk approve for safe deterministic edits
4. **Conflict Resolution**
   - Side-by-side conflict context
   - Recommended resolution + one-tap apply
5. **Action Item Assignment**
   - Auto-generated tasks with suggested assignee and urgency
6. **Follow-up Questions**
   - High-value clarifying prompts only
   - Answer now or defer
7. **Approval Workflow**
   - Approve all / section / item
   - Commit gate with audit trail
8. **Learning Loop**
   - Feedback on bad suggestions
   - Org/location preference memory

### New Bottom Tab Recommendation
Add a dedicated **Review** tab (using the open slot near Profile) to host the agent inbox and pending decisions.

### Execution Order (MVP → Expansion)
1. Workspace/session memory stabilization (prevent re-onboarding)
2. Review queue + approvals
3. Conflict diff + bulk resolve
4. Daily brief + proactive triggers
5. Review tab polish + metrics

### Screen-by-Screen Build Map

#### A) Review Tab (New)
Sections:
- Needs Acknowledgment
- Pending Confirmations
- Unassigned Action Items
- Stale/Overdue Items

Primary CTAs:
- Approve Safe Changes
- Resolve Conflicts
- Open Note Detail

#### B) Note Review View (Existing, Enhanced)
Sections:
- Summary Draft Card
- Structured Fields Card
- Proposed Changes Card
- Follow-up Questions Card

Primary CTAs:
- Accept Field
- Edit Field
- Reject Proposal
- Commit Changes

#### C) Conflict Detail View (Existing, Enhanced)
Sections:
- Why conflict happened
- Before/After values
- Recommended resolution

Primary CTAs:
- Accept Current
- Apply Recommendation
- Manual Edit + Save

#### D) Dashboard/Feed Integration
- Surface “changes published from review” markers
- Surface review-generated action items with owner + due state

### Success Metrics
- Time to publish reviewed note
- % of notes resolved without manual rewrite
- Conflict resolution time
- Re-onboarding rate after relogin

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
7. **Split confidence scoring** — Per-item confidence score; if AI is <70% confident it split correctly, flag for user review with "Did we get this right?" prompt (from PRD devil's advocate)
8. **"Tap to split" gesture** — First-class interaction on review screen for splitting incorrectly grouped items; captures training signal for structuring improvement

**Backend:**
- Per-org vocabulary store
- Correction tracking and aggregation
- Dynamic prompt construction with org context
- Category customization API
- Structuring test suite: 100+ real-world recordings across industries, run on every AI prompt change to catch regressions

**Tests:**
- Vocabulary learning from corrections
- Custom category CRUD
- Prompt personalization output quality
- Correction feedback persistence
- Split confidence scoring accuracy
- Structuring regression suite (100+ recordings)

---

### Phase 12: Enterprise API & Integrations
**Priority:** 🟡 Medium | **Effort:** High | **Target:** 2-3 weeks

**Why:** Enterprise tier promises "API access" — this scopes and delivers it. Without a defined surface area, enterprise prospects fill the gap with custom requests.

**Deliverables:**
1. **Public REST API** with scoped endpoints:
   - `GET /notes` — paginated notes by location, date range, category
   - `GET /action-items` — filtered by status, assignee, urgency
   - `GET /handoffs` — shift handoff reports by date/location
   - `GET /analytics` — trend data, recurring issues, resolution times
2. **Webhooks** for real-time events:
   - `note.created`, `action_item.updated`, `handoff.generated`
3. **API key management** — Keys scoped per organization with rate limiting
4. **API documentation** — OpenAPI spec, interactive docs
5. **Integration examples** — Slack webhook, email digest, PMS system template

**Tests:**
- API endpoint response correctness and pagination
- Rate limiting enforcement
- Webhook delivery and retry logic
- API key scoping (org A can't access org B data)

---

## Phase Summary & Timeline

| Phase | Name | Status | Priority | Effort | Target |
|-------|------|--------|----------|--------|--------|
| 1 | Auth Reliability | ✅ Done | Critical | Medium | — |
| 2 | Transcript Splitting | ✅ Done | Critical | Medium | — |
| 3 | Error Handling | ✅ Done | High | Low-Med | — |
| 4 | Data Sync Integrity | ✅ Done | High | High | — |
| 5 | Recording Reliability | 🟨 In Progress | Medium | Medium | Week 3 |
| 6 | Performance, Polish & Activation | ✅ Done | Medium | Medium | — |
| 7 | Shift Handoff Reports | 🔲 | Critical | High | Week 5-7 |
| 8 | @Mentions & Escalation | 🔲 | Critical | High | Week 7-9 |
| 9 | Trend Analytics | 🔲 | High | High | Week 9-11 |
| 10 | Photo Attachments | 🔲 | High | Medium | Week 11-12 |
| 11 | AI Learning | 🔲 | Medium | High | Week 13-16 |
| 12 | Enterprise API | 🔲 | Medium | High | Week 17-19 |

**Total estimated timeline: ~19 weeks to full platform**

---

## Success Metrics

| Metric | Current | Target (Post Phase 12) |
|--------|---------|----------------------|
| Time to first structured note | Unknown | <3 minutes |
| Activation rate (3+ notes in 7 days) | Unknown | >30% |
| Notes per user per shift | ~2 | 5+ |
| Action items resolved within shift | Unknown | >70% |
| Handoff adoption rate | N/A | >80% of shifts |
| Recurring issues caught proactively | 0 | 10+ per month per location |
| User retention (30-day) | Unknown | >85% |
| Expansion (locations per org) | 1 | 3+ |
| DAU/MAU | Unknown | >40% |
| NPS | Unknown | >50 |
| Churn (monthly, paying locations) | Unknown | <5% |

---

## Risk & Dependencies

| Risk | Mitigation |
|------|-----------|
| AI structuring quality plateaus | Phase 11 correction feedback loop + structuring test suite; split confidence scoring catches bad splits early |
| AI structuring reliability (core risk) | Define failure modes explicitly (merged items, hallucinated items, dropped items) — each gets a different recovery UX; build 100+ recording regression suite |
| Sync conflicts on action items | Phase 4 per-field merge strategy; conflict detection banner with change history |
| Real-time feed scalability | Start with polling (30s), migrate to WebSocket when needed |
| Photo storage costs | Aggressive compression, tiered storage by plan |
| Offline-first complexity | Phase 4 lays the foundation; each subsequent phase builds on it |
| Offline handoff generation | Structured sections generated locally; AI summary backfills on reconnect (Phase 7) |
| Team adoption friction | Handoff reports (Phase 7) create natural pull; @mentions (Phase 8) create daily engagement |
| Free-to-paid conversion gap | Raised Free tier to 5 members / 50 notes; gate on features not team size |
| Activation drop-off | Phase 6 guided first-run experience; track time-to-first-structured-note |
| Android market share loss | Decision point: if >30% of waitlist requests Android by Month 3, begin cross-platform evaluation |
| Enterprise API scope creep | Phase 12 defines explicit surface area upfront; prevents blank-check custom requests |

---

## Open Decisions (from PRD)

1. **Real-time vs polling:** Start with 30s polling, measure demand for WebSocket
2. **Multi-language support:** Spanish transcription is high demand for hospitality — timing TBD
3. **Hardware integrations:** Two-way radio integration as a "channel" — feasibility TBD
4. **Apple Watch companion:** Quick record from wrist — ROI evaluation after Phase 9
5. **Android:** Hard decision point at Month 3 based on waitlist demand (>30% threshold)
6. **Compliance certifications:** HIPAA / SOC 2 timeline depends on enterprise pipeline
7. **Solo pricing tier ($19/loc/mo):** Evaluate after Free tier expansion data comes in
