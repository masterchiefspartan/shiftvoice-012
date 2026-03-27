# ShiftVoice — Comprehensive Developer Guide

> **Last Updated:** March 2026
> **Platform:** iOS 18+ (Native Swift/SwiftUI)
> **Architecture:** MVVM with @Observable
> **Backend:** Hono on Cloudflare Workers (tRPC + REST hybrid)

---

## Table of Contents

1. [Product Overview](#1-product-overview)
2. [Technical Stack](#2-technical-stack)
3. [Project Structure](#3-project-structure)
4. [Environment & Configuration](#4-environment--configuration)
5. [Authentication System](#5-authentication-system)
6. [App Entry & Navigation](#6-app-entry--navigation)
7. [Onboarding Flow (9 Screens)](#7-onboarding-flow-9-screens)
8. [Core Screens & Features](#8-core-screens--features)
9. [Data Models](#9-data-models)
10. [Services Layer](#10-services-layer)
11. [AI Structuring Pipeline](#11-ai-structuring-pipeline)
12. [Offline-First & Sync Architecture](#12-offline-first--sync-architecture)
13. [Subscription & Paywall](#13-subscription--paywall)
14. [Design System (SVTheme)](#14-design-system-svtheme)
15. [Industry Template System](#15-industry-template-system)
16. [Feature Flags](#16-feature-flags)
17. [Push Notifications](#17-push-notifications)
18. [Backend API Reference](#18-backend-api-reference)
19. [Testing](#19-testing)
20. [Build Phase Status & Roadmap](#20-build-phase-status--roadmap)
21. [Known Issues & Security Notes](#21-known-issues--security-notes)
22. [Glossary](#22-glossary)

---

## 1. Product Overview

### What is ShiftVoice?

ShiftVoice is the **operating system for frontline operations**. It replaces clipboards, walkie-talkies, WhatsApp groups, and forgotten verbal handoffs with a voice-first platform that captures, structures, assigns, and tracks everything that happens during a shift — automatically.

### Core Value Loop

```
Record → Structure → Review → Publish → Handoff → Analyze
  |          |          |         |          |          |
Voice    AI splits   User edits  Team sees  Next shift  Patterns
input    into items  categories  & acts     gets report detected
```

### Target Users

| Persona | Description | Pain Point |
|---------|-------------|------------|
| **Shift Leads / Floor Managers** | Age 25-45, always on feet, manage 5-30 staff | "I told the closing manager about the broken fryer but they forgot" |
| **General Managers / Owners** | Oversee 1-20+ locations, need visibility without being on-site | "The walk-in cooler had been flagged 4 times before it broke down" |
| **Corporate / Multi-Unit Operators** | Manage 10-100+ locations, compliance needs | "Every location runs differently and I can't compare them" |

### Supported Industries

ShiftVoice ships with pre-configured templates for 11 industries:

| Industry | Default Categories | Shift Names |
|----------|--------------------|-------------|
| Restaurant | Kitchen, FOH, Inventory, Maintenance, Staff, Health & Safety | Opening, Mid, Closing |
| Bar / Pub | Bar Ops, Floor, Stock, Maintenance, Staff, Security | Opening, Mid, Closing |
| Hotel | Rooms, Front Desk, Maintenance, Housekeeping, Guest Issues, Staff | Morning, Afternoon, Night |
| Cafe | Counter, Kitchen, Stock, Maintenance, Staff, Health & Safety | Opening, Mid, Closing |
| Retail | Sales Floor, Stockroom, Visual, Maintenance, Staff, Loss Prevention | Opening, Mid, Closing |
| Healthcare / Nursing | Patient Care, Equipment, Supplies, Maintenance, Staff, Safety | Day, Evening, Night |
| Manufacturing / Warehouse | Equipment, Production, Inventory, Safety, Shipping, Staff | Day, Swing, Night |
| Security / Facilities | HVAC, Electrical, Plumbing, Safety, Grounds, General | Day, Swing, Night |
| Property Management | Units, Common Areas, Maintenance, Landscaping, Security, Admin | Day, Evening, Night |
| Construction | Quality, Materials, Equipment, Safety, Subcontractors, General | Day, Swing |
| Other | Operations, Maintenance, Staff, Safety, Inventory, General | Morning, Afternoon, Evening |

---

## 2. Technical Stack

### iOS Client

| Component | Technology |
|-----------|------------|
| Language | Swift (strict concurrency, `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`) |
| UI Framework | SwiftUI (iOS 18+) |
| Architecture | MVVM with `@Observable` (not `ObservableObject`) |
| Audio Recording | AVFoundation (`AVAudioRecorder`) |
| Transcription | Apple Speech Framework (on-device) + OpenAI Whisper (backend) |
| Authentication | Firebase Auth (Google Sign-In + Email/Password) |
| Data Sync | Backend REST API with offline-first queue |
| Subscriptions | RevenueCat |
| Push Notifications | APNs via backend |
| Keychain | Custom `KeychainService` for token storage |
| Networking | `URLSession` via custom `APIService` |

### Backend

| Component | Technology |
|-----------|------------|
| Runtime | Hono on Cloudflare Workers |
| API Style | tRPC + REST hybrid |
| AI | OpenAI API (GPT-4o-mini for structuring, Whisper for transcription) |
| Auth | Custom JWT with bcrypt (migrating to Firebase Auth verification) |
| Storage | Cloudflare KV/R2 |

### Third-Party Dependencies (SPM)

| Package | Purpose |
|---------|---------|
| `firebase-ios-sdk` | Authentication, app configuration |
| `GoogleSignIn-iOS` | Google Sign-In flow |
| `purchases-ios-spm` (RevenueCat) | Subscription management |

---

## 3. Project Structure

```
ShiftVoice/
├── ShiftVoiceApp.swift          # @main entry point, scene routing
├── ContentView.swift            # Main tab bar container (post-auth, post-onboarding)
├── AppDelegate.swift            # UIApplicationDelegate for push notifications, Firebase
├── Config.swift                 # Environment variables (CI-injected at build time)
├── ShiftVoice.entitlements      # Push notification entitlement
│
├── Models/
│   ├── ShiftNote.swift          # Core data model: notes, action items, categorized items
│   ├── Organization.swift       # Org, Location, TeamMember, RecurringIssue models
│   ├── IndustryTemplate.swift   # Industry-specific configs (categories, shifts, terminology)
│   ├── CategoryTemplate.swift   # Dynamic category system with color/icon
│   ├── ShiftTemplate.swift      # Shift configuration templates
│   ├── RoleTemplate.swift       # Team role templates
│   ├── RecordingPrompt.swift    # Context-aware recording prompts
│   ├── ConflictItem.swift       # Sync conflict representation
│   ├── SyncState.swift          # Sync state machine and reducers
│   ├── WriteFailure.swift       # Failed write tracking
│   ├── EditBaseline.swift       # Baseline tracking for edit detection
│   ├── ReviewFlowEvent.swift    # Review flow analytics events
│   ├── PendingNoteReviewData.swift # Pending review state
│   ├── PaywallTriggerReason.swift  # Why paywall was shown
│   ├── ToastMessage.swift       # Toast notification model
│   └── TranscriptSegment.swift  # Per-segment transcription data
│
├── Views/
│   ├── Onboarding/              # 9-screen onboarding flow (see Section 7)
│   │   ├── OnboardingView.swift           # Container/router for all steps
│   │   ├── OnboardingRoleView.swift       # Step 0: Role selection
│   │   ├── OnboardingIndustryView.swift   # Step 1: Industry selection
│   │   ├── OnboardingPainPointsView.swift # Step 2: Pain point multi-select
│   │   ├── OnboardingToolMirrorView.swift # Step 3: Current tool + mirror moment
│   │   ├── OnboardingDemoSetupView.swift  # Step 4: Demo setup
│   │   ├── OnboardingLiveRecordingView.swift # Step 5: Live recording
│   │   ├── OnboardingAIRevealView.swift   # Step 6: AI structuring reveal
│   │   ├── OnboardingWorkspaceView.swift  # Step 7: Workspace setup + team invite
│   │   ├── OnboardingPaywallView.swift    # Step 8: Paywall / trial start
│   │   ├── OnboardingTeamView.swift       # Team invite sub-component
│   │   └── OnboardingCategoryPickerView.swift # Category picker sub-component
│   │
│   ├── SignInView.swift         # Email/password + Google Sign-In
│   ├── PasswordResetView.swift  # Password reset flow
│   ├── ShiftFeedView.swift      # Tab 1: Chronological note feed
│   ├── DashboardView.swift      # Tab 2: Action item kanban/dashboard
│   ├── ReviewView.swift         # Tab 3: Needs-attention review queue
│   ├── SettingsView.swift       # Tab 4: Profile, org, team, sync, notifications
│   ├── RecordView.swift         # Voice recording sheet (mic button)
│   ├── NoteReviewView.swift     # Post-recording AI review/edit screen
│   ├── ShiftNoteDetailView.swift # Full note detail with actions
│   ├── ShiftNoteCardView.swift  # Note card component for feed
│   ├── QuickAppendView.swift    # Quick voice append to existing note
│   ├── AssigneePickerView.swift # Action item assignee picker
│   ├── ConflictDetailView.swift # Sync conflict resolution UI
│   ├── FirstRunGuideView.swift  # 3-step guided intro modal
│   └── PaywallView.swift        # Subscription paywall (RevenueCat)
│
├── ViewModels/
│   ├── AppViewModel.swift       # Central app state: notes, actions, sync, org data
│   ├── OnboardingViewModel.swift # Onboarding flow state and validation
│   └── RecordingViewModel.swift # Recording session state
│
├── Services/
│   ├── APIService.swift             # HTTP client (URLSession wrapper, auth headers)
│   ├── AuthenticationService.swift  # Firebase Auth + backend token management
│   ├── AudioRecorderService.swift   # AVAudioRecorder wrapper
│   ├── TranscriptionService.swift   # Apple Speech framework transcription
│   ├── NoteStructuringService.swift # AI structuring orchestration
│   ├── StructuringValidator.swift   # Post-AI validation layer
│   ├── StructuringCache.swift       # Cache for structuring results
│   ├── SubscriptionService.swift    # RevenueCat integration
│   ├── PushNotificationService.swift # APNs registration and handling
│   ├── PersistenceService.swift     # Local disk persistence (non-API data)
│   ├── KeychainService.swift        # Keychain read/write for tokens
│   ├── NetworkMonitor.swift         # NWPathMonitor wrapper for connectivity
│   ├── FirestoreService.swift       # Firestore data operations
│   ├── FirestoreWriteClient.swift   # Firestore write abstraction
│   ├── ConflictDetector.swift       # Per-field sync conflict detection
│   ├── ConflictStore.swift          # Conflict state persistence
│   ├── PendingOpsStore.swift        # Offline pending operations queue
│   ├── EditBaselineStore.swift      # Tracks baselines for edit detection
│   ├── ConfirmationReconciler.swift # Reconciles confirmed vs pending state
│   ├── ShiftScheduleService.swift   # Current shift detection logic
│   ├── FeatureFlagService.swift     # Remote feature flag management
│   ├── ActionItemScorer.swift       # Scoring for action item prioritization
│   ├── ReviewFlowLogger.swift       # Analytics for review flow
│   ├── SyncEventLogger.swift        # Sync lifecycle event logging
│   ├── StructuringTelemetryLogger.swift # AI structuring telemetry
│   ├── UserEditTracker.swift        # Tracks user edits for AI learning signal
│   ├── WriteFailureStore.swift      # Tracks and retries failed writes
│   └── MockDataService.swift        # Demo/test data generation
│
├── Utilities/
│   ├── Theme.swift              # SVTheme: colors, typography, sizing constants
│   ├── FirebaseConfig.swift     # Firebase configuration detection
│   ├── InputValidator.swift     # Client-side form validation rules
│   ├── TranscriptCleaner.swift  # Filler word removal, normalization
│   ├── TranscriptProcessor.swift # Topic boundary detection
│   ├── WhisperPromptBuilder.swift # Builds context prompts for Whisper STT
│   ├── RoleTemplateResolver.swift # Resolves role template IDs to display info
│   ├── ShiftTemplateResolver.swift # Resolves shift template IDs to display info
│   └── [CategoryTemplateResolver, etc.]
│
├── Assets.xcassets/             # App icon, accent color
└── Preview Content/             # SwiftUI preview assets

ShiftVoice.xcodeproj/           # Xcode project
ShiftVoiceTests/                # 20+ test files, 300+ tests
ShiftVoiceUITests/              # UI test scaffolding

backend/
├── hono.ts                     # Main backend (2169 LOC) — all REST endpoints
├── storage.ts                  # Storage layer (KV/R2 operations)
└── trpc/
    ├── app-router.ts           # tRPC router composition
    ├── create-context.ts       # Auth context creation
    └── routes/                 # tRPC route handlers (5 files)
```

---

## 4. Environment & Configuration

### Config.swift

All environment variables are declared in `Config.swift` as `static let` properties with empty placeholder values. Real values are injected at build time by CI.

```swift
enum Config {
    static let EXPO_PUBLIC_PROJECT_ID = ""
    static let EXPO_PUBLIC_REVENUECAT_IOS_API_KEY = ""
    static let EXPO_PUBLIC_REVENUECAT_TEST_API_KEY = ""
    static let EXPO_PUBLIC_RORK_API_BASE_URL = ""
    static let EXPO_PUBLIC_TEAM_ID = ""
    static let EXPO_PUBLIC_TOOLKIT_URL = ""
    static let GOOGLE_CLIENT_ID = ""
    static let OPENAI_API_KEY = ""
}
```

### Environment Variables

| Variable | Purpose | Where Used |
|----------|---------|------------|
| `GOOGLE_CLIENT_ID` | Google Sign-In OAuth client ID | `AuthenticationService`, Firebase config |
| `EXPO_PUBLIC_REVENUECAT_IOS_API_KEY` | RevenueCat production API key | `SubscriptionService` |
| `EXPO_PUBLIC_REVENUECAT_TEST_API_KEY` | RevenueCat sandbox/test API key | `SubscriptionService` |
| `OPENAI_API_KEY` | OpenAI API key for structuring + Whisper | Backend `hono.ts` |
| `EXPO_PUBLIC_RORK_API_BASE_URL` | Backend API base URL | `APIService` |
| `EXPO_PUBLIC_PROJECT_ID` | Project identifier | Various services |
| `EXPO_PUBLIC_TEAM_ID` | Team identifier | Various services |
| `EXPO_PUBLIC_TOOLKIT_URL` | AI toolkit service URL | AI features |

### System Variables (Always Available)

These are automatically set by the platform:
- `EXPO_PUBLIC_RORK_DB_ENDPOINT`
- `EXPO_PUBLIC_RORK_DB_NAMESPACE`
- `EXPO_PUBLIC_RORK_DB_TOKEN`
- `EXPO_PUBLIC_RORK_API_BASE_URL`
- `EXPO_PUBLIC_TOOLKIT_URL`
- `EXPO_PUBLIC_PROJECT_ID`
- `EXPO_PUBLIC_TEAM_ID`

### Entitlements

`ShiftVoice.entitlements` currently declares:
- `aps-environment: development` (Push Notifications)

### Info.plist Keys (in project.pbxproj)

Key permissions configured via `INFOPLIST_KEY_` entries:
- `NSMicrophoneUsageDescription` — Voice recording
- `NSSpeechRecognitionUsageDescription` — On-device transcription

---

## 5. Authentication System

### Flow

```
App Launch
    ↓
AuthenticationService.validateAndRefreshSession()
    ↓
┌─ Keychain has valid token? ──→ Restore session ──→ Main App
│
└─ No token ──→ SignInView
                    ├── Email/Password (Firebase Auth)
                    ├── Google Sign-In (Firebase Auth + GIDSignIn)
                    └── Create Account (Firebase Auth)
                          ↓
                    Backend auth call (/rest/auth/firebase)
                          ↓
                    Receive backend token
                          ↓
                    Store in Keychain
                          ↓
                    Onboarding (if first time) → Main App
```

### Key Components

**`AuthenticationService`** (`@Observable`):
- `isSignedIn: Bool` — Controls app routing
- `isLoading: Bool` — Shows launch screen during session restore
- `currentUserId: String?` — Firebase UID
- `backendToken: String?` — Backend JWT stored in Keychain
- `userName: String` / `userEmail: String` — Display info
- `signInWithEmail()` / `signUpWithEmail()` — Firebase email auth
- `signInWithGoogle()` — Google Sign-In → Firebase
- `handleURL()` — Deep link handling for Google Sign-In callback
- `signOut()` — Clears Firebase session + Keychain + backend
- `validateAndRefreshSession()` — Called on app launch
- `retryBackendAuthIfNeeded()` — Recovery handler for 401 responses

**`APIService`**:
- Singleton (`APIService.shared`)
- Injects `Authorization: Bearer <token>` and `x-user-id` headers
- Has `setUnauthorizedRecoveryHandler` for automatic 401 retry
- Debounced sync (500ms) to prevent race conditions

### Security Notes

- Tokens stored in iOS Keychain (not UserDefaults)
- All API communication over HTTPS
- Backend auth endpoint `/rest/auth/firebase` has a known security issue: it accepts but does not verify the Firebase `idToken` — it trusts the posted `uid` and `email`. This is flagged for migration to server-side Firebase token verification (see `docs/firebase-auth-end-to-end-plan.md`).

---

## 6. App Entry & Navigation

### App Lifecycle (`ShiftVoiceApp.swift`)

```
@main ShiftVoiceApp
    ↓
┌── authService.isLoading? ──→ LaunchLoadingView (app icon + spinner)
│
├── !authService.isSignedIn? ──→ SignInView
│
├── appViewModel.isLoadingUserData? ──→ LaunchLoadingView
│
├── !hasCompletedOnboarding? ──→ OnboardingView (9 screens)
│
└── Ready ──→ ContentView (main app)
```

**Auto-skip onboarding:** If `appViewModel.hasExistingOrganization` becomes true (returning user with data), `hasCompletedOnboarding` is set to `true` automatically.

### Tab Bar (`ContentView.swift`)

Custom tab bar with 5 slots:

| Position | Tab | Icon | View | Badge |
|----------|-----|------|------|-------|
| 1 | Feed | `tray.fill` | `ShiftFeedView` | Unacknowledged note count |
| 2 | Actions | `bolt.fill` | `DashboardView` | — |
| 3 | Record | `mic.fill` (floating) | `RecordView` (sheet) | — |
| 4 | Review | `sparkles.rectangle.stack.fill` | `ReviewView` | Review badge count |
| 5 | Profile | `person.fill` | `SettingsView` | — |

**Implementation details:**
- **Lazy tab mounting:** Tabs are only instantiated when first visited (`tabsLoaded` set). Scroll state is preserved on tab switch.
- **Record button:** Centered, elevated circle with accent color. Opens `RecordView` as a `.large` sheet.
- **Offline banner:** Shown above tab bar when `viewModel.isOffline` is true (amber background, shows pending change count).
- **Trial banner:** Shown at top when user hasn't started their free trial.
- **Toast overlay:** Top-aligned capsule for success/error messages with auto-dismiss.

### Navigation

Each tab has its own `NavigationPath`:
- `feedNavPath` — Feed tab navigation
- `actionsNavPath` — Actions tab navigation
- `reviewNavPath` — Review tab navigation

Navigation uses type-safe destinations:
```swift
nonisolated enum AppRoute: Hashable, Sendable {
    case shiftNoteDetail(noteId: String)
}
```

---

## 7. Onboarding Flow (9 Screens)

The onboarding flow is a 9-step wizard managed by `OnboardingViewModel`. It collects user context, demonstrates the product, sets up the workspace, and presents the paywall.

### Flow Structure

```
ACT 1 — IDENTITY & PAIN (Screens 0-3)
  Screen 0: Role Selection
  Screen 1: Industry Selection
  Screen 2: Pain Point Selection
  Screen 3: Current Tool + Mirror Moment

ACT 2 — THE AHA MOMENT (Screens 4-6)
  Screen 4: Demo Setup
  Screen 5: Live Recording
  Screen 6: AI Structuring Reveal  ← THE key screen

ACT 3 — COMMITMENT & CONVERSION (Screens 7-8)
  Screen 7: Workspace Setup + Team Invite
  Screen 8: Paywall (Trial Start)
```

**Transition between acts:** Fade-through-black transition between Act 1→2 (screens 3→4).

### Screen 0: Role Selection (`OnboardingRoleView`)

- **Purpose:** First micro-commitment + user segmentation
- **UI:** 3 large cards with icons, auto-advance on tap (400ms delay)
- **Options:**
  - Shift Lead / Floor Manager (`shift_lead`)
  - General Manager / Owner (`gm_owner`)
  - Operations / Multi-Unit (`multi_unit`)
- **State:** `viewModel.selectedRole: OnboardingRole?`
- **No skip option.** Selection is the action.

### Screen 1: Industry Selection (`OnboardingIndustryView`)

- **Purpose:** Determines default categories, demo content, and terminology
- **UI:** 2-column grid of 6 industry cards, auto-advance on tap
- **Options:**
  - Restaurant / Bar (fork.knife)
  - Hotel / Hospitality (bed.double.fill)
  - Facilities / Maintenance (wrench.and.screwdriver.fill)
  - Warehouse / Logistics (shippingbox.fill)
  - Healthcare (cross.case.fill)
  - Other (square.grid.2x2.fill)
- **State:** `viewModel.selectedIndustry: OnboardingIndustry`
- **Side effect:** On selection, updates `businessType`, `selectedCategoryTemplates`, `selectedShiftTemplates`, and `availableRoleTemplates` from the industry template.

### Screen 2: Pain Point Selection (`OnboardingPainPointsView`)

- **Purpose:** Market research + psychological setup
- **UI:** 4 multi-select cards with checkboxes, "Continue" button (disabled until ≥1 selected)
- **Options:**
  - Handoffs get forgotten (`forgotten_handoffs`)
  - Info buried in texts & group chats (`buried_info`)
  - Same problems keep recurring (`recurring_issues`)
  - Too much time firefighting (`firefighting`)
- **State:** `viewModel.selectedPainPoints: [OnboardingPainPoint]`

### Screen 3: Current Tool + Mirror Moment (`OnboardingToolMirrorView`)

- **Purpose:** Capture current tool (market research) + mirror their situation back
- **UI:** Single-select list, then animated mirror text using their selections
- **Tool options:**
  - "We just talk it through"
  - "Notes app"
  - "Group chat"
  - "Paper log"
  - "Other"
- **Mirror text example:** "As a Shift Lead / Floor Manager in Restaurant, talking it through keeps creating forgotten handoffs and recurring issues."
- **CTA:** "What if capturing everything took 30 seconds?" → "Show me →"

### Screen 4: Demo Setup (`OnboardingDemoSetupView`)

- **Purpose:** Frame the demo, provide live vs sample path
- **UI:** Pulsing microphone icon, two CTA paths
- **Paths:**
  - "Start Recording" → requests mic permission → Screen 5
  - "See a sample instead" → skips to Screen 6 with industry-matched demo content
- **If mic permission denied:** Auto-falls through to sample path

### Screen 5: Live Recording (`OnboardingLiveRecordingView`)

- **Purpose:** User records a real voice note
- **UI:** Full-screen dark background, live waveform, timer, stop button
- **Rules:**
  - Min 5 seconds (message if stopped too early)
  - Max 60 seconds (auto-stop)
  - Transcription begins immediately on stop (Speech framework)
- **No progress bar** on this screen (distraction-free)

### Screen 6: AI Structuring Reveal (`OnboardingAIRevealView`)

- **Purpose:** THE aha moment — messy voice → structured intelligence
- **Animation sequence (5-6 seconds):**
  1. Raw transcript fades in
  2. Pause for reading
  3. Transcript fades to 20% opacity, slides up
  4. "ShiftVoice structured this into:" label appears
  5. Structured items build in one by one (category tag, urgency badge, content, action item)
  6. Summary stats + CTA fade in
- **Live path:** Uses actual transcript + actual AI structuring
- **Sample path:** Uses industry-matched demo content (pre-defined per industry)
- **CTA:** "Start my free trial →"

### Screen 7: Workspace Setup + Team Invite (`OnboardingWorkspaceView`)

- **Purpose:** Name workspace, configure shifts, invite team
- **UI:** Combined form with location name, shift configuration, and team invite section
- **Fields:**
  - Location name (required, placeholder from industry config)
  - Detected timezone (auto-detected, displayed)
  - Shift templates (pre-filled from industry, toggleable)
  - Category templates (pre-filled, toggleable)
  - Team invites (email/phone, role assignment, add/remove)
- **Validation:**
  - Location name: required, 2-100 characters
  - Invites: valid email or phone (7-15 digits), no duplicates
- **State:** `viewModel.locationName`, `viewModel.teamInvites`, etc.

### Screen 8: Paywall (`OnboardingPaywallView`)

- **Purpose:** Convert to paid trial
- **UI:** Monthly/Annual toggle, plan card with features, CTA
- **Pricing:**
  - $49/month or $399/year (save ~$189)
  - 7-day free trial
- **RevenueCat integration:**
  - Product IDs: `shiftvoice_pro_monthly`, `shiftvoice_pro_annual`
  - Entitlement: `pro_access`
- **Skip option:** Users can skip paywall → persistent trial banner in main app
- **On success:** Completes onboarding → main app with their structured note in feed

### Data Collected from Onboarding

All persisted via `OnboardingViewModel` and applied to `AppViewModel`:
- Role, industry, business type
- Pain points, current tool
- Location name, timezone
- Shift templates, category templates
- Team invites
- Demo path (live vs sample)
- Paywall outcome (started trial / skipped)

---

## 8. Core Screens & Features

### 8.1 Shift Feed (`ShiftFeedView`)

The primary tab — a chronological feed of all shift notes for the selected location.

**Features:**
- **Feed scope toggle:** Team notes vs Personal (private) notes
- **Location selector:** Switch between organization locations
- **Search:** 300ms debounced full-text search across transcript, summary, author, action items
- **Shift filter:** Filter by shift type (Opening, Mid, Closing, etc.)
- **Conflict banner:** Amber banner when active sync conflicts exist
- **Pagination:** 20 notes per page, infinite scroll trigger on last visible row
- **Skeleton loading:** Shimmer animation while initial data loads
- **Note cards:** Show summary, categories, urgency, action count, author, timestamp, sync status
- **Navigation:** Tap card → `ShiftNoteDetailView`

### 8.2 Action Dashboard (`DashboardView`)

Kanban-style view of all action items across notes.

**Features:**
- **Greeting header:** Time-of-day greeting with user's first name
- **Summary counts:** My Assigned, Open, Immediate, In Progress, Resolved
- **Filters:**
  - Urgency (Immediate, Next Shift, This Week, FYI)
  - Status (Open, In Progress, Resolved)
  - Location
  - Category
  - Assignee (with avatar tap filtering)
  - Date range (Today, This Week, This Month, All)
  - Scope (All, Team, Personal)
  - "Assigned to Me" toggle
- **Action item cards:** Task description, category pill, urgency dot, assignee avatar/initials, conflict indicator
- **Inline status updates:** Tap to cycle Open → In Progress → Resolved
- **Recurring issues:** Expandable section showing detected patterns

### 8.3 Review Queue (`ReviewView`)

A proactive queue of items needing attention.

**Sections (collapsible disclosure groups):**
1. **Unacknowledged** — Notes not yet acknowledged by the user
2. **Pending Confirmations** — Notes with unconfirmed changes
3. **Unassigned Actions** — Action items with no assignee
4. **Stale Actions** — Action items that haven't been updated recently

Each section shows a count badge (red if > 0). Items navigate to `ShiftNoteDetailView`.

### 8.4 Voice Recording (`RecordView`)

Presented as a sheet from the center record button.

**Features:**
- **Shift selection:** Current shift auto-detected, changeable via picker
- **Visibility toggle:** Team (public) vs Private note
- **Guided prompts:** Context-aware recording suggestions based on industry + shift + categories (rotate every few seconds)
- **Audio level indicator:** Visual confirmation mic is picking up sound
- **Recording states:**
  - Pre-recording: shift selector, visibility, guided prompts
  - Recording: pulsing animation, elapsed time, stop button
  - 30-second warning before 3-minute auto-stop (haptic feedback)
- **Post-recording:** Navigates to `NoteReviewView` with transcript
- **Subscription gating:** Checks plan limits before recording

### 8.5 Note Review (`NoteReviewView`)

Post-recording screen where AI structuring results are reviewed and edited.

**Features:**
- **Confidence-based UI:**
  - High (≥0.85): Normal display
  - Medium (0.60-0.84): Subtle "review suggested" banner
  - Low (<0.60): Prominent "had trouble" banner with yellow highlights
  - Fallback (local structuring): "Structured offline" banner
- **Editable summary:** Inline text editing
- **Categorized items:** Edit category, urgency, content; add/remove items
- **Action items:** Edit task, category, urgency; assign to team members; approve/reject
- **Warning indicators:** Items flagged by validation (possible merge, hallucination, etc.)
- **Transcript view:** Expandable raw transcript display
- **Visibility control:** Team vs Private
- **Publish button:** Validates then publishes to feed
- **Discard option:** Confirmation alert before discarding

### 8.6 Note Detail (`ShiftNoteDetailView`)

Full view of a published shift note.

**Features:**
- **Header:** Author avatar/initials, name, shift type, timestamp
- **Summary section**
- **Categorized items list:** Category pill, urgency badge, content, resolution status
- **Action items list:** Task, status (toggleable), assignee, urgency, conflict indicator
- **Audio playback:** Play/pause with progress bar (if audio URL exists)
- **Transcript toggle:** Show/hide raw transcript
- **Acknowledge button:** Mark note as read (tracked per user)
- **Quick append:** Record additional voice to add items to this note
- **Promote to team:** Convert private note to team-visible
- **Conflict sheet:** View and resolve sync conflicts
- **Assign sheet:** Assign action items to team members

### 8.7 Settings / Profile (`SettingsView`)

Comprehensive settings screen.

**Sections:**
1. **Profile:** Name, email, avatar initials
2. **Sync & Data:** Last sync time, data source, pending writes, manual sync, listener restart
3. **Notifications:** Push enabled/disabled, urgent-only filter, quiet hours
4. **Notes:** Default visibility (Team / Private / Ask each time)
5. **Organization:** Name, industry, plan
6. **Location Management:** Add/edit/remove locations (name, address, timezone, shift times)
7. **Team Management:** Invite members, assign roles, manage invitations
8. **Subscription:** Current plan, manage subscription, upgrade prompts
9. **About:** Version, privacy policy, terms of service, support links
10. **Developer (DEBUG only):** Sync diagnostics, pending ops, events, write failures, feature flags
11. **Sign Out / Delete Account**

### 8.8 Additional Views

- **`SignInView`:** Email/password form + Google Sign-In button, toggle between sign-in and sign-up, inline validation, offline indicator, password reset navigation
- **`PasswordResetView`:** Email input → Firebase password reset email
- **`PaywallView`:** RevenueCat-powered paywall with monthly/annual toggle, feature list, restore purchase, fallback pricing banner
- **`QuickAppendView`:** Mini recording sheet (30s max) to append items to an existing note
- **`AssigneePickerView`:** Team member list for assigning action items
- **`ConflictDetailView`:** Per-field conflict resolution UI (keep current / apply my update / dismiss)
- **`FirstRunGuideView`:** 3-step paged modal shown on first app open (Record → AI Structures → Team Sync)
- **`ShiftNoteCardView`:** Reusable note card component for feed display

---

## 9. Data Models

### ShiftNote (Primary Entity)

```
ShiftNote
├── id: String (UUID)
├── authorId: String
├── authorName: String
├── authorInitials: String
├── locationId: String
├── shiftType: ShiftType (.opening | .mid | .closing | .unscheduled)
├── shiftTemplateId: String? (for industry-specific shift names)
├── rawTranscript: String
├── audioUrl: String?
├── audioDuration: TimeInterval
├── summary: String
├── categorizedItems: [CategorizedItem]
│   ├── id, category: NoteCategory, categoryTemplateId: String?
│   ├── content: String, urgency: UrgencyLevel
│   ├── sourceQuote: String?, isResolved: Bool
│   ├── entityType: String?, normalizedSubject: String?, actionClass: String?
│   └── displayInfo: CategoryDisplayInfo (computed)
├── actionItems: [ActionItem]
│   ├── id, task: String, category: NoteCategory, categoryTemplateId: String?
│   ├── urgency: UrgencyLevel, status: ActionItemStatus (.open | .inProgress | .resolved)
│   ├── assignee: String?, assigneeId: String?
│   ├── updatedAt: Date, statusUpdatedAt: Date, assigneeUpdatedAt: Date
│   ├── statusUpdatedAtServer/ByUserId, assigneeUpdatedAtServer/ByUserId
│   ├── hasConflict: Bool, conflictDescription: String?
│   ├── changeHistory: [ChangeHistoryEntry]
│   ├── resolvedAt: Date?
│   └── displayInfo: CategoryDisplayInfo (computed)
├── photoUrls: [String] (field exists, not yet used)
├── acknowledgments: [Acknowledgment] (userId, userName, timestamp)
├── voiceReplies: [VoiceReply] (authorId, authorName, transcript, timestamp)
├── createdAt: Date
├── updatedAt: Date, updatedAtClient: Date?, updatedAtServer: Date?
├── updatedByUserId: String?, lastClientMutationId: String?
├── conflictState: String?, conflictSummary: String?
├── visibility: NoteVisibility (.team | .personal)
├── isSynced: Bool, isDirty: Bool
└── Computed: highestUrgency, unresolvedActionCount, resolvedActionCount, categories, syncOrderingDate
```

### Organization & Team

```
Organization
├── id, name, ownerId
├── plan: SubscriptionPlan (.free | .starter | .professional | .enterprise)
└── industryType: IndustryType

Location
├── id, name, address, timezone
├── openingTime, midTime, closingTime (String, "HH:mm" format)
└── managerIds: [String]

TeamMember
├── id, name, email
├── role: ManagerRole (.owner | .generalManager | .manager | .shiftLead)
├── roleTemplateId: String?
├── locationIds: [String]
├── inviteStatus: InviteStatus (.pending | .accepted | .deactivated)
├── avatarInitials: String (auto-generated from name)
└── updatedAt: Date

RecurringIssue
├── id, description, category, categoryTemplateId
├── locationId, locationName
├── mentionCount, relatedNoteIds
├── firstMentioned, lastMentioned
└── status: RecurringIssueStatus (.active | .acknowledged | .resolved)
```

### Enums

```swift
NoteVisibility: .team | .personal
ShiftType: .opening | .mid | .closing | .unscheduled
UrgencyLevel: .immediate | .nextShift | .thisWeek | .fyi (sorted by severity)
NoteCategory: .eightySixed | .equipment | .guestIssue | .staffNote | .reservation |
              .inventory | .maintenance | .healthSafety | .general | .incident
ActionItemStatus: .open | .inProgress | .resolved
SubscriptionPlan: .free | .starter | .professional | .enterprise
IndustryType: .restaurant | .bar | .hotel | .cafe | .catering | .other
ManagerRole: .owner | .generalManager | .manager | .shiftLead
InviteStatus: .pending | .accepted | .deactivated
```

### Sync & Conflict Models

```
ConflictItem
├── id, noteId, actionItemId
├── fieldName: String (e.g., "status", "assigneeId")
├── localIntendedValue, serverCurrentValue
├── serverUpdatedBy, serverUpdatedAt
└── resolution: ConflictResolution?

SyncState (state machine)
├── isOffline: Bool
├── hasPendingWrites: Bool
├── lastSyncedFromServer: Date?
├── pendingNoteIds: Set<String>
└── detectedConflicts: [ConflictItem]
```

---

## 10. Services Layer

### APIService

Singleton HTTP client wrapping `URLSession`. Key behaviors:
- Auto-injects `Authorization: Bearer <token>` and `x-user-id` headers
- 401 recovery handler: calls `retryBackendAuthIfNeeded()` once before failing
- Debounced sync push (500ms) to prevent race conditions
- Base URL from `Config.EXPO_PUBLIC_RORK_API_BASE_URL`

### AudioRecorderService

Wraps `AVAudioRecorder`:
- Records to local `.m4a` file
- Provides audio level metering for visual indicator
- 3-minute max duration with 30-second warning
- Validates audio file exists and has non-zero size before proceeding

### TranscriptionService

Wraps Apple's Speech framework:
- On-device transcription via `SFSpeechRecognizer`
- Captures per-segment confidence scores
- Continuation safety wrapper (prevents double-resume crash)
- Clear distinction between "transcription failed" vs "empty recording"
- Retry capability exposed to review screen

### NoteStructuringService

Orchestrates the AI structuring pipeline:
1. Clean transcript (remove fillers, normalize)
2. Send to backend `/rest/structure-transcript` endpoint
3. Backend calls OpenAI GPT-4o-mini with structured prompt
4. Validate response locally (source quote check, coverage, hallucination detection)
5. Calculate confidence score
6. Return structured items with validation warnings
7. 30-second timeout with local fallback (recursive separator-based splitting)

### SubscriptionService

RevenueCat wrapper:
- Configures SDK with API key from `Config`
- `isProUser: Bool` — active subscription or trial
- `hasTrialStarted: Bool` — whether trial has begun
- `purchase()` / `restore()` — subscription operations
- Plan limit enforcement for locations and team members

### PersistenceService

Local disk persistence for non-API data:
- Offline pending operations queue
- Draft notes
- Sync metadata
- Survives app restarts

### ConflictDetector

Detects per-field sync conflicts on action items:
- Tracks `status`, `assignee`, `priority` fields
- Compares local intended value vs server current value
- Flags conflict only when same field changed by two users
- Resolution options: keep server, apply local, dismiss

### FeatureFlagService

Remote feature flag management:
- `syncBannersEnabled` — Show/hide sync status banners
- `conflictUIEnabled` — Show/hide conflict detection UI
- Refreshed on app launch via `refreshRemoteFlags()`

---

## 11. AI Structuring Pipeline

### Overview

```
Voice → Transcript → Clean → AI Structure → Validate → Review → Publish
```

### Step 1: Transcription

Apple Speech framework on-device:
- `SFSpeechRecognizer` with `.dictation` task hint
- Captures per-segment confidence scores
- Falls back to empty with clear error state

### Step 2: Transcript Cleaning (`TranscriptCleaner`)

- Removes filler words (um, uh, like, you know, basically, etc.)
- Normalizes whitespace and punctuation
- Detects topic boundaries via transition phrases ("also", "another thing", "oh and", etc.)
- Outputs estimated topic count as a check signal for AI

### Step 3: AI Structuring (Backend)

Backend endpoint `POST /rest/structure-transcript`:
- Sends cleaned transcript + industry context to OpenAI GPT-4o-mini
- Temperature: 0.1 (deterministic output)
- Response format: JSON with `items[]`, each containing:
  - `content`, `category`, `urgency`, `action_item`, `source_quote`
- Industry context injected from templates (categories, vocabulary, categorization hints)

### Step 4: Validation (`StructuringValidator`)

Local post-processing checks:
1. **Source quote verification** — Each item's `source_quote` must fuzzy-match in the transcript
2. **Topic count match** — AI item count vs local estimate
3. **Transcript coverage** — Meaningful words accounted for (>70% target)
4. **Duplicate detection** — Cosine similarity >0.8 flags duplicates
5. **Long item detection** — >30 words suggests possible merged topics
6. **AI self-reported coverage** — "partial" flag reduces confidence

Output: `ValidationResult` with confidence score (0.0-1.0), warnings, and `needsUserReview` flag.

### Step 5: Fallback (Local)

When AI fails (timeout, bad JSON, network error):
- Recursive multi-separator splitting on topic transitions
- Sentence-level splitting on `.!?`
- Basic keyword-based categorization and urgency estimation
- Items flagged as `isFromFallback: true`

### Confidence Bands (Review Screen)

| Band | Score | UI Behavior |
|------|-------|-------------|
| High | ≥ 0.85 | Normal display, no special prompts |
| Medium | 0.60-0.84 | Subtle "review suggested" banner, warning indicators |
| Low | < 0.60 | Prominent "had trouble" banner, yellow highlights |
| Fallback | N/A | "Structured offline" banner |

---

## 12. Offline-First & Sync Architecture

### Design Philosophy

- All core features work without network
- Notes saved locally first, synced when connected
- Per-field conflict detection for collaborative action item edits
- Optimistic UI with rollback on sync failure

### Sync Flow

```
User Action (create/edit note)
    ↓
Save to local state (optimistic UI)
    ↓
Mark as isDirty = true
    ↓
Push to backend (debounced 500ms)
    ├── Success → Clear dirty flag, update timestamps
    └── Failure → Rollback from snapshot, queue for retry
```

### Offline Queue

- `PendingOpsStore` persists pending operations to disk
- Survives app restarts
- Retries up to 3x with incremented retry count
- `WriteFailureStore` tracks permanently failed writes

### Conflict Resolution

Per-field merge for action items:
- `statusUpdatedAt` and `assigneeUpdatedAt` merge independently
- Conflict flagged only when same field changed by two users
- UI: Amber "Conflict detected" banner with field-level resolution (keep current / apply my update / dismiss)
- Change history tracked per action item

### Sync Status Indicators

- **Global:** Offline banner (amber) with pending change count
- **Per-note:** Sync status on note cards (pending/synced/conflict)
- **Settings:** Sync diagnostics (last sync time, data source, pending state, manual restart)

---

## 13. Subscription & Paywall

### Plans

| Feature | Free | Starter ($39/loc/mo) | Professional ($79/loc/mo) | Enterprise (Custom) |
|---------|------|---------------------|--------------------------|-------------------|
| Locations | 1 | 5 | 20 | Unlimited |
| Team members/loc | 3 | 6 | 10 | Unlimited |
| Voice notes/month | 50 | Unlimited | Unlimited | Unlimited |
| AI structuring | Basic | Full | Full | Full |

### RevenueCat Integration

- **Product IDs:** `shiftvoice_pro_monthly` ($49/mo), `shiftvoice_pro_annual` ($399/yr)
- **Entitlement:** `pro_access`
- **Trial:** 7-day free trial on both plans
- **Configuration:** API key from `Config.EXPO_PUBLIC_REVENUECAT_IOS_API_KEY`
- **User ID:** Set to Firebase UID on sign-in

### Paywall Triggers

- Onboarding completion (Screen 8)
- Trial banner tap in main app
- Plan limit hit (locations, team members, notes)
- Feature gating (upcoming features)

### Trial Flow

- Users who skip paywall see persistent trial banner
- All features accessible during trial
- Post-trial: read-only mode (can view everything, can't create new)
- Trial expiry modal with usage stats

---

## 14. Design System (SVTheme)

### Colors

```swift
SVTheme.background          // Color(.systemBackground) — adapts to dark mode
SVTheme.surface             // Color(.secondarySystemBackground)
SVTheme.surfaceSecondary    // Color(.tertiarySystemBackground)
SVTheme.surfaceBorder       // Color(.separator)
SVTheme.divider             // Color(.separator)
SVTheme.cardBackground      // Color(.secondarySystemBackground)

SVTheme.accent              // rgb(29, 78, 216) — brand blue
SVTheme.accentGreen         // rgb(22, 163, 74)
SVTheme.urgentRed           // rgb(220, 38, 38)
SVTheme.amber               // rgb(217, 119, 6)
SVTheme.infoBlue            // rgb(37, 99, 235)
SVTheme.successGreen        // rgb(22, 163, 74)
SVTheme.mutedGray           // Color(.secondaryLabel)

SVTheme.textPrimary         // Color(.label)
SVTheme.textSecondary       // Color(.secondaryLabel)
SVTheme.textTertiary        // Color(.tertiaryLabel)
SVTheme.darkSurface         // rgb(24, 24, 27) — for dark overlays
```

### Sizing Constants

```swift
SVTheme.Sizing.buttonHeight         = 50
SVTheme.Sizing.chipHeight           = 34
SVTheme.Sizing.smallChipHeight      = 28
SVTheme.Sizing.cardCornerRadius     = 12
SVTheme.Sizing.chipCornerRadius     = 8
SVTheme.Sizing.buttonCornerRadius   = 12
SVTheme.Sizing.horizontalPadding    = 24
SVTheme.Sizing.chipHorizontalPadding = 14
SVTheme.Sizing.chipVerticalPadding  = 7
```

### Typography Patterns

- **Large titles:** `.system(.largeTitle, design: .serif, weight: .bold)` with `tracking(-0.5)`
- **Headlines:** `.system(size: 28, weight: .bold, design: .serif)`
- **Body:** `.system(size: 17)` or `.body`
- **Captions:** `.caption` / `.footnote`
- **Nav titles:** `.system(size: 17, weight: .semibold)`

### Urgency Colors

```swift
.immediate → SVTheme.urgentRed    // Red
.nextShift → SVTheme.amber        // Amber
.thisWeek  → SVTheme.infoBlue     // Blue
.fyi       → SVTheme.mutedGray    // Gray
```

### Category Colors

Each `NoteCategory` has a legacy color hex:
- Kitchen/Equipment/Inventory: amber/orange shades
- FOH/Staff: blue
- Guest Issues: pink
- Reservations: purple
- Health & Safety/Incident/86'd: red
- General: gray

Category templates (`CategoryTemplate`) define custom `colorHex` per industry.

---

## 15. Industry Template System

### Architecture

The app uses a template-based system for industry-specific configuration:

```
IndustryTemplate
├── id: String (e.g., "restaurant")
├── name: String
├── icon: String (SF Symbol)
├── defaultCategories: [CategoryTemplate]
├── defaultShifts: [ShiftTemplate]
├── defaultRoles: [RoleTemplate]
└── terminology: IndustryTerminology
    ├── shiftHandoff (e.g., "Service Handoff")
    ├── location (e.g., "Restaurant")
    ├── customer (e.g., "Guest")
    ├── outOfStock (e.g., "86'd")
    ├── roles: [String]
    ├── equipment: [String]
    └── slang: [String]
```

### Template Resolution

Display info is resolved through a template chain:
1. Check for `categoryTemplateId` → resolve via `CategoryTemplateResolver`
2. Fall back to legacy `NoteCategory` enum
3. This allows industry-specific names/colors while maintaining backward compatibility

### Recording Prompts

`RecordingPromptProvider` generates context-aware prompts based on:
- Industry template (category-specific questions)
- Current shift phase (opening/middle/closing)
- Industry terminology (uses correct language like "86'd" for restaurants)

---

## 16. Feature Flags

Managed by `FeatureFlagService`:

| Flag | Default | Purpose |
|------|---------|---------|
| `syncBannersEnabled` | `true` | Show sync status banners and indicators |
| `conflictUIEnabled` | `true` | Show conflict detection badges and resolution UI |

Refreshed on app launch via `FeatureFlagService.shared.refreshRemoteFlags()`.

---

## 17. Push Notifications

### Setup

- `AppDelegate` registers for remote notifications
- `PushNotificationService.shared` manages:
  - Authorization status checking
  - Device token handling and backend registration
  - Notification tap handling → navigates to relevant note

### Entitlement

`ShiftVoice.entitlements` includes `aps-environment: development`.

### Notification Types

- New note published by teammate
- Action item assigned to you
- Shift handoff ready (planned)
- Recurring issue alert (planned)

### User Preferences (Settings)

- Push enabled/disabled toggle
- Urgent-only filter (`@AppStorage`)
- Quiet hours with start/end time configuration

---

## 18. Backend API Reference

### REST Endpoints (`backend/hono.ts`)

**Auth:**
- `POST /rest/auth/register` — Email/password registration
- `POST /rest/auth/login` — Email/password login
- `POST /rest/auth/google` — Google Sign-In
- `POST /rest/auth/firebase` — Firebase auth token exchange
- `POST /rest/auth/logout` — Session invalidation

**Organization:**
- `GET /rest/organization` — Get org details
- `POST /rest/organization` — Create org
- `PATCH /rest/organization` — Update org

**Locations:**
- `GET /rest/locations` — List locations
- `POST /rest/locations` — Create location
- `PATCH /rest/locations/:locationId` — Update location
- `DELETE /rest/locations/:locationId` — Delete location

**Team:**
- `GET /rest/team` — List team members
- `POST /rest/team` — Invite team member
- `PATCH /rest/team/:memberId` — Update member
- `DELETE /rest/team/:memberId` — Remove member

**Shift Notes:**
- `GET /rest/shift-notes` — List notes (paginated, filtered)
- `POST /rest/shift-notes` — Create note
- `PATCH /rest/shift-notes/:noteId` — Update note
- `DELETE /rest/shift-notes/:noteId` — Delete note
- `POST /rest/shift-notes/:noteId/acknowledge` — Acknowledge note

**AI:**
- `POST /rest/structure-transcript` — AI transcript structuring
- `POST /rest/refine-action-item` — AI action item refinement

**Other:**
- `GET /rest/health` — Health check (`{ ok: true }`)
- `POST /rest/push/register` — Register push token
- `POST /rest/push/send` — Send push notification

### tRPC Routes (`backend/trpc/routes/`)

- `auth.validateSession` — Validate current session
- `shiftNotes.list` / `.create` / `.update` — Note CRUD
- `team.list` / `.invite` — Team management
- `organization.*` — Org management

---

## 19. Testing

### Test Files (20+ files, 300+ tests)

| File | Coverage Area |
|------|---------------|
| `ShiftVoiceTests.swift` | Core model tests |
| `AuthenticationTests.swift` | Auth flow, token management |
| `APIValidationTests.swift` | API request/response validation |
| `NoteReviewTests.swift` | Review flow, edit tracking |
| `TranscriptionServiceTests.swift` | Transcription pipeline |
| `TranscriptSplittingTests.swift` | Multi-topic splitting accuracy |
| `ConflictDetectionTests.swift` | Per-field conflict detection |
| `ConflictDetectorTests.swift` | Conflict detector unit tests |
| `ConflictIntegrationTests.swift` | End-to-end conflict flows |
| `ConflictResolutionTests.swift` | Resolution actions |
| `ConflictStoreTests.swift` | Conflict persistence |
| `DataSyncTests.swift` | Sync state machine, merge logic |
| `SyncStateReducerTests.swift` | Sync state transitions |
| `PendingOpsReconcilerTests.swift` | Pending operation reconciliation |
| `EditBaselineStoreTests.swift` | Baseline tracking |
| `WriteFailureTests.swift` | Failed write handling |
| `ErrorHandlingTests.swift` | Error paths |
| `ViewModelTests.swift` | ViewModel state management |
| `Phase0StructuringBaselineTests.swift` | Structuring baseline accuracy |
| `StructuringRegressionAuditTests.swift` | Structuring regression suite |

### Key Test Areas

- **Transcript splitting:** 45+ tests covering single-topic, multi-topic (2-5+), edge cases (fillers, silence, repeated mentions)
- **Sync/conflict:** 30+ tests for per-field merge, timestamp resolution, conflict detection/dismissal, offline queue, snapshot rollback
- **Auth:** Token restore, session validation, retry logic
- **Error handling:** Toast notifications, failure states, recovery paths

---

## 20. Build Phase Status & Roadmap

### Completed Phases

| Phase | Name | Status |
|-------|------|--------|
| 1 | Auth Reliability | ✅ Done |
| 2 | Transcript → Action Item Splitting | ✅ Done |
| 3 | Error Handling & User Feedback | ✅ Done |
| 4 | Data Integrity & Sync Reliability | ✅ Done |
| 5 | Recording Reliability | ✅ Done |
| 6 | Performance, Polish & Activation | ✅ Done |

### Upcoming Phases

| Phase | Name | Priority | Status | Target |
|-------|------|----------|--------|--------|
| 7 | Smart Shift Handoff Reports | Critical | Planned | Week 5-7 |
| 8 | @Mentions & Escalation | Critical | Planned | Week 7-9 |
| 9 | Recurring Issue Detection & Trend Analytics | High | Planned | Week 9-11 |
| 10 | Photo/Video Attachments | High | Planned | Week 11-12 |
| 11 | Property-Specific AI Learning | Medium | Planned | Week 13-16 |
| 12 | Enterprise API & Integrations | Medium | Planned | Week 17-19 |

### Key Upcoming Features

**Phase 7 — Shift Handoff Reports (Critical):**
- Auto-generated handoff reports at shift end
- Sections: Open Items, Resolved This Shift, New Issues, VIP/Reservations, Staff Notes
- Incoming shift "Here's what happened" summary
- Push notification to incoming shift lead
- Offline handoff generation with AI summary backfill
- Overlapping shift handling (note ownership by creation timestamp)

**Phase 8 — @Mentions & Escalation (Critical):**
- @mention team members in notes/action items
- Auto-escalation rules (e.g., Health & Safety + Immediate → notify GM)
- Read receipts on notes
- Thread replies to specific items
- Configurable notification preferences

**Phase 9 — Trend Analytics:**
- AI-powered pattern detection across notes over time
- Trend dashboard with charts
- Recurring issue smart alerts
- PDF export for management reports
- Location benchmarking

---

## 21. Known Issues & Security Notes

### Active Security Issues

1. **`POST /rest/auth/firebase`** — Accepts `idToken` but never verifies it server-side. Trusts posted `uid` and `email`. Active security vulnerability. Migration to server-side Firebase token verification is planned.

2. **`POST /rest/structure-transcript`** — Uses `x-user-id` header directly for identity without session validation. No `authMiddleware` call. Completely unprotected.

3. **`POST /rest/refine-action-item`** — Zero auth of any kind. No `authMiddleware`, no header check. Fully open.

4. **PATCH endpoints** — Mass assignment vulnerability: request body spread directly (`{ ...existing, ...body }`) without field allowlist. Clients can mutate server-controlled fields.

5. **tRPC `protectedProcedure`** — Previously only checked header presence, not token validity. Fix in progress.

### Infrastructure Issue

- Backend experienced crash-loop due to stale cached build artifact referencing deleted module `@rork-ai/toolkit-sdk`. Source code is clean — requires platform-level cache purge and rebuild. See `docs/firebase-auth-end-to-end-plan.md` for full details.

### Migration Plan

A comprehensive Firebase Auth migration plan exists at `docs/firebase-auth-end-to-end-plan.md`. This plan addresses:
- Server-side Firebase ID token verification
- Removing custom session infrastructure
- Securing unprotected endpoints
- Field allowlists for PATCH endpoints
- Cleaning up redundant tRPC validation

---

## 22. Glossary

| Term | Definition |
|------|------------|
| **86'd** | Restaurant/bar industry term for an item that's out of stock or removed from the menu |
| **Action Item** | A specific, actionable task extracted from a voice note by the AI |
| **Categorized Item** | A structured observation from a voice note (may or may not have an action item) |
| **Conflict** | When two users edit the same field on the same action item while offline |
| **Dirty Flag** | `isDirty` on a ShiftNote indicates local changes not yet synced |
| **FOH** | Front of House (restaurant term for the customer-facing area) |
| **Handoff** | The transition between shifts where information is passed to the incoming team |
| **Industry Template** | Pre-configured categories, shifts, roles, and terminology for a specific industry |
| **Mirror Moment** | Onboarding screen that reflects the user's situation back to them using their selections |
| **Optimistic UI** | Showing changes immediately in the UI before backend confirmation |
| **Pending Op** | An operation queued locally while offline, waiting to sync |
| **Rollback** | Reverting optimistic UI changes when a sync operation fails |
| **Shift Type** | Opening, Mid, Closing, or Unscheduled (varies by industry) |
| **Structuring** | The AI process of converting raw transcript text into categorized, actionable items |
| **SVTheme** | The app's design system providing colors, typography, and sizing constants |
| **Urgency Level** | Immediate, Next Shift, This Week, or FYI (determines priority ordering) |
| **Visibility** | Whether a note is visible to the whole team (`.team`) or only the author (`.personal`) |
| **Voice Reply** | A voice-based response attached to an existing note |
