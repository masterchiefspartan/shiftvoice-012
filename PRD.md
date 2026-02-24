# ShiftVoice — Product Requirements Document

## Product Vision

**ShiftVoice is the operating system for frontline operations.**

We replace clipboards, walkie-talkies, WhatsApp groups, and forgotten verbal handoffs with a voice-first platform that captures, structures, assigns, and tracks everything that happens during a shift — automatically.

The insight: the people who actually do the work have their hands full. They can't stop to type into Asana or Monday.com. Voice is the unlock. AI structuring is the engine. Shift handoffs are the system of record.

---

## Market Position

### The Problem

Frontline operations teams (hotels, restaurants, bars, facilities, warehouses) rely on:
- Verbal handoffs that get forgotten
- Paper logs that nobody reads
- WhatsApp/text chaos with no structure or accountability
- Enterprise PM tools (Asana, Monday, Trello) designed for desk workers

**Result:** Information falls through the cracks between shifts. Issues recur because nobody tracks patterns. Managers spend 30% of their time firefighting problems that could have been prevented.

### The Solution

ShiftVoice turns a 30-second voice recording into:
- Structured, categorized action items
- Assigned tasks with urgency and ownership
- Auto-generated shift handoff reports
- Pattern detection across weeks/months of operational data
- A searchable, auditable record of everything that happened

### Competitive Landscape

| Competitor | Strength | Weakness |
|-----------|----------|----------|
| Asana/Monday | Rich PM features | Requires typing, desktop-first, not shift-aware |
| Slack/Teams | Real-time comms | Unstructured, unsearchable, no task tracking |
| Paper logs | Zero friction | No searchability, no analytics, gets lost |
| WhatsApp groups | Universal adoption | No structure, no accountability, no analytics |
| HotSOS (hotel ops) | Industry-specific | Legacy UI, expensive, no voice input |

**ShiftVoice's moat:** Voice-first capture → AI structuring → shift-aware organization → compounding intelligence. The longer you use it, the smarter it gets about your property.

---

## Target Users

### Primary: Shift Leads & Floor Managers
- Age 25-45, always on their feet
- Manage 5-30 staff per shift
- Need to capture issues in real-time without stopping work
- Hand off to the next shift 1-3x daily
- **Pain:** "I told the closing manager about the broken fryer but they forgot"

### Secondary: General Managers & Owners
- Oversee 1-20+ locations
- Need operational visibility without being on-site
- Care about trends, not individual notes
- **Pain:** "I didn't know the walk-in cooler had been flagged 4 times this month until it broke down"

### Tertiary: Corporate/Multi-Unit Operators
- Manage 10-100+ locations
- Need standardized reporting and benchmarking
- Compliance and audit requirements
- **Pain:** "Every location runs differently and I can't compare them"

---

## Product Architecture

### Core Loop

```
Record → Structure → Review → Publish → Handoff → Analyze
  |          |          |         |          |          |
Voice    AI splits   User edits  Team sees  Next shift  Patterns
input    into items  categories  & acts     gets report detected
```

### Information Hierarchy

```
Organization
  └── Locations
       └── Shifts (Opening / Mid / Closing)
            └── Shift Notes (voice recordings)
                 ├── Categorized Items (structured data)
                 │    └── Category, Content, Urgency
                 ├── Action Items (tasks)
                 │    └── Task, Assignee, Status, Priority
                 └── Shift Handoff Report (auto-generated)
                      └── Summary, Open Items, Resolved, New Issues
```

---

## Feature Requirements

### Tier 1: Core Platform (Current + In Progress)

#### 1.1 Voice Capture & AI Structuring
**Status:** Implemented, recently improved

- Record voice notes up to 3 minutes
- On-device transcription via Speech framework
- AI-powered structuring into categorized items
- Local fallback with recursive separator detection
- Confidence warnings when AI may have missed items

**Requirements:**
- Transcription accuracy: >90% for clear speech in English
- Structuring latency: <15 seconds (30s timeout with fallback)
- Must handle multi-topic recordings (3+ distinct issues)
- Must correctly split items that share a single recording

#### 1.2 Note Review & Editing
**Status:** Implemented

- Edit summary, categories, urgency levels post-transcription
- Add/remove/reorder categorized items
- Add/remove action items with task descriptions
- Assign action items to team members
- Split items that were incorrectly grouped
- Structuring warning banner when AI fallback was used

#### 1.3 Shift Feed (Inbox)
**Status:** Implemented

- Chronological feed of all notes for a location
- Filter by category, urgency, shift type, date range
- Note cards showing summary, categories, urgency, action count
- Tap to view full note detail
- Acknowledge notes to mark as read
- Sync status indicator and retry on failure

#### 1.4 Action Item Dashboard
**Status:** Implemented

- Kanban-style view of all action items across notes
- Filter by urgency, status, location, category, date range
- Inline status updates (Open → In Progress → Resolved)
- Urgency counts (Immediate, Open, In Progress, Resolved)
- Recurring issue detection (basic)

#### 1.5 Team & Organization Management
**Status:** Implemented

- Organization creation with industry type
- Multi-location support
- Team member invites with role-based permissions (Owner, GM, Manager, Shift Lead)
- Customizable shift schedules per location
- Customizable categories per industry

#### 1.6 Authentication & Data Sync
**Status:** Implemented, being hardened (Phases 4-6)

- Email/password authentication with Keychain storage
- Google Sign-In
- Backend sync with offline-first architecture
- Pending offline queue with reconnect sync
- Subscription management via RevenueCat

---

### Tier 2: Operational Intelligence (Phases 7-9)

#### 2.1 Smart Shift Handoff Reports
**Priority:** Critical — this is the feature that makes ShiftVoice infrastructure

**User Story:** "As a closing shift lead, I want to tap one button and have a complete handoff report generated for the opening team, so nothing falls through the cracks overnight."

**Requirements:**
- Auto-generate handoff when shift ends (or on-demand)
- Sections: Open Items, Resolved This Shift, New Issues, VIP/Reservations, Staff Notes, FYI
- AI-generated executive summary (2-3 sentences)
- Push notification to incoming shift lead
- "Mark as reviewed" acknowledgment with optional voice reply
- Handoff history searchable by date, shift, location
- Works offline — generate locally, sync when connected

**Acceptance Criteria:**
- Handoff includes all notes from the shift window (±30 min buffer)
- Open action items carry forward automatically
- Incoming shift lead sees handoff on app open
- Handoff generation takes <5 seconds
- 0 data loss: every note from the shift appears in the handoff

#### 2.2 @Mentions, Escalation & Real-Time Feed
**Priority:** Critical — creates daily engagement loop

**User Story:** "As a shift lead, I want to tag my GM when I find a safety issue, so they get an immediate notification and the issue is tracked with accountability."

**Requirements:**
- @mention team members in notes and action items
- Mentioned users receive push notification
- Escalation rules: category + urgency → auto-notify specified roles
  - Example: Health & Safety + Immediate → notify GM and Owner
- Configurable per-organization notification preferences
- Real-time feed updates (polling initially, WebSocket later)
- Read receipts on notes
- Thread replies to specific categorized items (voice or text)

**Acceptance Criteria:**
- @mention resolves to correct user and delivers push within 30 seconds
- Escalation fires within 60 seconds of note publish
- Users can configure: All notes / Mentions only / Escalations only / Off
- Read receipt shows who viewed and when

#### 2.3 Trend Analytics & Pattern Detection
**Priority:** High — justifies the tool to the person paying (management)

**User Story:** "As a GM overseeing 3 locations, I want to see which issues keep recurring so I can fix root causes instead of firefighting the same problems every week."

**Requirements:**
- AI-powered pattern detection across notes over time
- Trend dashboard: issues by category over time, resolution time, location comparison
- Recurring issue alerts: push when a pattern is detected (e.g., "Fryer flagged 4x in 2 weeks")
- Location benchmarking: compare issue rates across properties
- Exportable reports (PDF) for management meetings
- Date range selection: This week / This month / This quarter / Custom

**Acceptance Criteria:**
- Detects recurring issues with 3+ mentions of similar topics in 30 days
- Trend charts update within 24 hours of new data
- PDF export includes charts, issue list, and recommendations
- Pattern detection works across different authors (same issue, different people)

---

### Tier 3: Rich Media & Intelligence (Phases 10-11)

#### 3.1 Photo/Video Attachments
**Priority:** High — table stakes for credibility

**User Story:** "As a maintenance manager, I want to attach a photo of the ceiling crack so the repair team knows exactly what they're dealing with."

**Requirements:**
- Capture photos during active recording (without stopping audio)
- Attach up to 5 photos per note
- Photo review, reorder, delete on review screen
- Full-screen viewer with zoom on note detail
- Compressed upload (max 1MB per photo)
- Offline queue — store locally, upload on reconnect
- Thumbnail display on note cards in feed

**Acceptance Criteria:**
- Photo capture doesn't interrupt audio recording
- Photos persist through offline/online transitions
- Image quality sufficient to identify issues (equipment damage, labels, etc.)
- Total upload per note < 5MB

#### 3.2 Property-Specific AI Learning
**Priority:** Medium — creates long-term competitive moat

**User Story:** "As a hotel GM, I want the AI to learn our room numbers, equipment names, and common issues so transcription and categorization get more accurate over time."

**Requirements:**
- Learn property vocabulary from corrections (room numbers, equipment, menu items)
- Category weight adjustment from user editing patterns
- Autocomplete suggestions based on past patterns
- Custom category creation beyond default set
- AI prompt personalization with org-specific context
- Correction feedback loop — edits on review screen improve future output

**Acceptance Criteria:**
- After 50+ notes, AI accuracy improves measurably for org-specific terms
- Custom categories appear in all category pickers and filters
- Vocabulary suggestions surface within 2 weeks of first use
- No regression on general structuring quality

---

## Non-Functional Requirements

### Performance
- App launch to interactive: <2 seconds
- Recording start latency: <500ms
- Note structuring: <15 seconds (30s hard timeout)
- Feed scroll: 60fps with 100+ notes
- Sync: background push within 500ms of data change (debounced)

### Reliability
- Offline-first: all core features work without network
- Zero data loss: notes never lost, even on crash during recording
- Sync conflict resolution: newest-wins with user notification
- 99.9% API uptime target

### Security
- Auth tokens stored in Keychain (not UserDefaults)
- API communication over HTTPS only
- No PII in local logs or analytics
- Role-based access: shift leads see their location, GMs see all locations

### Scalability
- Support 1-100+ locations per organization
- Support 1-50 team members per location
- Support 10,000+ notes per location per year
- Feed pagination (20 notes per page)

---

## Subscription Tiers

| Feature | Free | Starter ($39/loc/mo) | Professional ($79/loc/mo) | Enterprise (Custom) |
|---------|------|---------------------|--------------------------|-------------------|
| Locations | 1 | 5 | 20 | Unlimited |
| Team members/loc | 3 | 6 | 10 | Unlimited |
| Voice notes/month | 30 | Unlimited | Unlimited | Unlimited |
| AI structuring | Basic | Full | Full | Full |
| Shift handoff reports | — | ✓ | ✓ | ✓ |
| @Mentions & escalation | — | ✓ | ✓ | ✓ |
| Trend analytics | — | — | ✓ | ✓ |
| Photo attachments | 3/note | 5/note | 5/note | 10/note |
| AI learning | — | — | ✓ | ✓ |
| PDF exports | — | — | ✓ | ✓ |
| Location benchmarking | — | — | — | ✓ |
| API access | — | — | — | ✓ |
| Priority support | — | — | ✓ | ✓ |

---

## Technical Architecture

### Client (iOS)
- **Language:** Swift 6, SwiftUI
- **Architecture:** MVVM with @Observable
- **Persistence:** Local JSON via PersistenceService (offline-first)
- **Auth:** Keychain + backend JWT tokens
- **Audio:** AVFoundation recording, Speech framework transcription
- **Payments:** RevenueCat

### Backend
- **Runtime:** Hono on Cloudflare Workers
- **API:** tRPC + REST hybrid
- **AI:** OpenAI API for transcript structuring
- **Auth:** Custom JWT with bcrypt password hashing
- **Storage:** Cloudflare KV/R2

### Data Flow
```
iOS App ←→ Hono API ←→ Storage (KV/R2)
                ↓
         OpenAI (structuring)
```

---

## Go-To-Market Strategy

### Phase 1: Single-Property Operators (Now - Month 4)
- Target: Independent restaurants, bars, boutique hotels
- Channel: Direct outreach, industry subreddits, trade shows
- Hook: "Replace your paper log in 30 seconds"
- Goal: 100 active properties, validate handoff feature

### Phase 2: Multi-Unit Operators (Month 4 - Month 8)
- Target: Restaurant groups (5-20 locations), hotel management companies
- Channel: Case studies from Phase 1, sales outreach, partnerships
- Hook: "See what's happening across all your locations without being there"
- Goal: 10 multi-unit accounts, validate trend analytics

### Phase 3: Enterprise & Facilities (Month 8 - Month 12)
- Target: Hospital facilities, university campuses, commercial property management
- Channel: Enterprise sales, integrations (Slack, email, PMS systems)
- Hook: "Compliance-ready operational intelligence"
- Goal: 5 enterprise accounts, validate API/integration demand

---

## Key Metrics

| Metric | Definition | Target |
|--------|-----------|--------|
| DAU/MAU | Daily active / monthly active ratio | >40% |
| Notes per user per shift | Average recordings per active session | >3 |
| Handoff completion rate | % of shifts with a generated handoff | >80% |
| Action item resolution time | Median time from creation to resolved | <8 hours |
| Recurring issue detection | Issues caught proactively per location/month | >5 |
| NPS | Net Promoter Score | >50 |
| Revenue per location | Monthly recurring revenue per active location | >$50 |
| Expansion rate | Avg locations added per org after month 3 | >1.5 |
| Churn (monthly) | % of paying locations that cancel | <5% |

---

## Open Questions

1. **Real-time vs polling:** WebSocket support adds complexity. Start with 30s polling, measure demand.
2. **Multi-language support:** Voice transcription in Spanish is high demand for hospitality. When to add?
3. **Hardware integrations:** Some facilities use two-way radios. Can we integrate as a "channel"?
4. **Apple Watch companion:** Quick record from wrist. When does ROI justify the effort?
5. **Android:** How much market share are we leaving on the table? When to build?
6. **Compliance certifications:** HIPAA for healthcare facilities, SOC 2 for enterprise. Timeline?
