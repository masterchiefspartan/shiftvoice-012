# ShiftVoice — Onboarding Flow Spec v2
## Implementation-Ready for Coding Agent / Rork

---

## Pricing Model

**No free tier. One plan. Full access.**

- **7-day free trial** — no credit card required to start
- **Full product access** during trial — every feature, no limits
- **After trial:** $49/mo or $399/year (save ~$189/year)
- **Team members:** Free "view & respond" access (they're not the buyer — the manager/owner is)
- **RevenueCat** handles subscription management, trial tracking, and entitlements

**Why this model:** A crippled free tier prevents team adoption, which prevents the switching cost that justifies $49/mo. Give them everything for 7 days. Let the whole team depend on it. Then the $49 is obvious.

---

## Flow Overview — 9 Screens

Stripped to essentials for 2-week launch. Every screen earns its place.

```
ACT 1 — IDENTITY & PAIN (Screens 1–4)
  Screen 1: Role Selection
  Screen 2: Industry Selection  
  Screen 3: Pain Point Selection
  Screen 4: Current Tool + Mirror Moment

ACT 2 — THE AHA MOMENT (Screens 5–7)
  Screen 5: Demo Setup
  Screen 6: Live Recording
  Screen 7: AI Structuring Reveal ← THIS IS THE SCREEN

ACT 3 — COMMITMENT & CONVERSION (Screens 8–9)
  Screen 8: Workspace Setup + Team Invite
  Screen 9: Paywall (Trial Start)
```

**Estimated completion time:** 4–6 minutes
**Progress indicator:** Thin progress bar at top of screen. No screen numbers. No "Step X of Y."

---

## Screen-by-Screen Specification

---

### SCREEN 1: Role Selection

**Purpose:** First micro-commitment. Segmentation for personalization downstream.

**Layout:**
- Top: ShiftVoice logo (centered, small)
- Below logo: Subtle animated voice waveform (looping, 3-4 seconds)
- Headline: Large, bold, centered
- Subheadline: Smaller, muted color
- Options: 3 large tap targets, vertically stacked, full-width cards
- Bottom: Progress bar (11% filled)

**Content:**
```
[ShiftVoice Logo]
[Animated waveform — subtle, represents voice]

Your shift runs on words.
Let's make sure none get lost.

What best describes your role?

┌─────────────────────────────────┐
│  Shift Lead / Floor Manager     │
│  You run the shift day-to-day   │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│  General Manager / Owner        │
│  You oversee the full operation │
└─────────────────────────────────┘
┌─────────────────────────────────┐
│  Operations / Multi-Unit        │
│  You manage across locations    │
└─────────────────────────────────┘
```

**State:**
```swift
@AppStorage("onboarding_role") var role: String = ""
// Values: "shift_lead", "gm_owner", "multi_unit"
```

**Behavior:**
- Tap a card → highlight with brand accent color → auto-advance after 400ms delay
- No "Next" button — selection IS the action
- No skip option
- Track: `analytics.onboarding_role_selected(role)`

**Transition:** Slide left to Screen 2

---

### SCREEN 2: Industry Selection

**Purpose:** Determines default categories, demo content, and terminology for the rest of the flow.

**Layout:**
- Headline centered
- 2x3 grid of industry cards with emoji icons
- Each card: emoji + label, square-ish aspect ratio
- Bottom: Progress bar (22%)

**Content:**
```
Built for operations like yours.

What's your industry?

[🍽 Restaurant    ] [🏨 Hotel        ]
[  / Bar          ] [  / Hospitality  ]

[🏗 Facilities   ] [📦 Warehouse    ]
[  / Maintenance  ] [  / Logistics    ]

[🏥 Healthcare   ] [🏢 Other        ]
```

**State:**
```swift
@AppStorage("onboarding_industry") var industry: String = ""
// Values: "restaurant", "hotel", "facilities", "warehouse", "healthcare", "other"
```

**Industry-driven configuration (set on selection):**
```swift
let industryConfig: [String: IndustrySettings] = [
  "restaurant": IndustrySettings(
    shiftNames: ["Opening", "Mid", "Closing"],
    shiftTimes: ["6:00 AM", "11:00 AM", "4:00 PM"],
    defaultCategories: ["Kitchen", "FOH", "Inventory", "Maintenance", "Staff", "Health & Safety"],
    demoTranscript: "So the walk-in cooler is making that noise again...",
    placeholderLocation: "e.g., The Blue Ox Kitchen"
  ),
  "hotel": IndustrySettings(
    shiftNames: ["Morning", "Afternoon", "Night"],
    shiftTimes: ["7:00 AM", "3:00 PM", "11:00 PM"],
    defaultCategories: ["Rooms", "Front Desk", "Maintenance", "Housekeeping", "Guest Issues", "Staff"],
    demoTranscript: "Room 412 AC is still not working, guest complained twice...",
    placeholderLocation: "e.g., Downtown Marriott"
  ),
  "facilities": IndustrySettings(
    shiftNames: ["Day", "Swing", "Night"],
    shiftTimes: ["6:00 AM", "2:00 PM", "10:00 PM"],
    defaultCategories: ["HVAC", "Electrical", "Plumbing", "Safety", "Grounds", "General"],
    demoTranscript: "The HVAC unit on the third floor is leaking again...",
    placeholderLocation: "e.g., Building A — Main Campus"
  ),
  "warehouse": IndustrySettings(
    shiftNames: ["Day", "Swing", "Night"],
    shiftTimes: ["6:00 AM", "2:00 PM", "10:00 PM"],
    defaultCategories: ["Equipment", "Inventory", "Safety", "Shipping", "Receiving", "Staff"],
    demoTranscript: "Forklift 3 is pulling to the left again, needs maintenance...",
    placeholderLocation: "e.g., West Distribution Center"
  ),
  "healthcare": IndustrySettings(
    shiftNames: ["Day", "Evening", "Night"],
    shiftTimes: ["7:00 AM", "3:00 PM", "11:00 PM"],
    defaultCategories: ["Equipment", "Patient Flow", "Supplies", "Maintenance", "Safety", "Staff"],
    demoTranscript: "The blood pressure monitor in exam room 3 needs calibration...",
    placeholderLocation: "e.g., St. Mary's — East Wing"
  ),
  "other": IndustrySettings(
    shiftNames: ["Morning", "Afternoon", "Evening"],
    shiftTimes: ["8:00 AM", "12:00 PM", "4:00 PM"],
    defaultCategories: ["Operations", "Maintenance", "Staff", "Safety", "Inventory", "General"],
    demoTranscript: "The printer on the second floor is jammed again...",
    placeholderLocation: "e.g., Main Office"
  )
]
```

**Behavior:**
- Tap card → highlight → auto-advance after 400ms
- Track: `analytics.onboarding_industry_selected(industry)`

**Transition:** Slide left to Screen 3

---

### SCREEN 3: Pain Point Selection

**Purpose:** The user actively identifies their own problems. This is your market research engine AND the psychological setup — they're building their own case for why they need this product.

**Layout:**
- Headline at top
- 4 multi-select cards, vertically stacked
- Each card: emoji + bold label + one-line description below
- Cards have checkbox-style selection (can select multiple)
- Bottom: "Continue" button (disabled until ≥1 selected) + progress bar (33%)

**Content:**
```
What keeps falling through the cracks?

Select all that apply.

☐ 📋 Handoffs get forgotten
  The next shift didn't know about the issue

☐ 📱 Info buried in texts & group chats
  Important updates lost in WhatsApp/text chaos

☐ 🔁 Same problems keep recurring
  You've flagged it before but there's no record

☐ 🔥 Too much time firefighting
  Reacting to problems instead of running operations

[Continue →]  (disabled until ≥1 selected)
```

**State:**
```swift
@AppStorage("onboarding_pain_points") var painPoints: [String] = []
// Values: "forgotten_handoffs", "buried_info", "recurring_issues", "firefighting"
```

**Behavior:**
- Multi-select: tap toggles selection state on each card
- Cards show a filled checkbox + subtle highlight when selected
- "Continue" button enables when ≥1 card is selected
- Track: `analytics.onboarding_pain_points_selected(painPoints)`

**Transition:** Slide left to Screen 4

---

### SCREEN 4: Current Tool + Mirror Moment (Combined)

**Purpose:** Two jobs in one screen — capture what they currently use (market research), then immediately mirror their full situation back to create the emotional hook before the demo.

**Layout:**
- Top section: Single-select list for current tool
- After selection: tool fades up slightly, mirror text animates in below with a typewriter effect (or line-by-line fade-in)
- CTA button appears after mirror text completes
- Progress bar (44%)

**Content — Before selection:**
```
How do you handle shift handoffs today?

○ We just talk it through
○ Paper log or whiteboard
○ WhatsApp / text group
○ Task management app (Asana, Trello, etc.)
○ We don't — it's chaos
```

**Content — After selection (animate in, 2-3 seconds):**
```
So you're a [Shift Lead] in [Restaurant] ops,
your handoffs rely on [talking it through],
and you're dealing with [forgotten handoffs]
and [recurring issues].

Every shift, critical info walks out the door
when your team clocks out.

What if capturing everything took 30 seconds?

[Show me →]
```

**Dynamic fill logic:**
```swift
let roleLabel = role == "shift_lead" ? "a Shift Lead" : role == "gm_owner" ? "a GM" : "in Operations"
let industryLabel = industry == "restaurant" ? "Restaurant" : industry == "hotel" ? "Hotel" : ...
let toolLabel = currentTool == "verbal" ? "talking it through" : currentTool == "paper" ? "paper logs" : ...
let painLabel = painPoints.map { painPointLabels[$0] }.joined(separator: " and ")
// painPointLabels: ["forgotten_handoffs": "forgotten handoffs", "buried_info": "buried messages", ...]
```

**State:**
```swift
@AppStorage("onboarding_current_tool") var currentTool: String = ""
// Values: "verbal", "paper", "whatsapp", "task_app", "nothing"
```

**Behavior:**
- Single-select list: tap one option → other options fade to lower opacity
- 300ms pause, then mirror text begins animating in line by line
- "Show me →" button fades in after mirror text completes
- No back button during mirror animation (let it land)
- Track: `analytics.onboarding_current_tool_selected(currentTool)`
- Track: `analytics.onboarding_mirror_cta_tapped()`

**Transition:** Distinctive transition to ACT 2 — fade through black (0.5s) then fade in Screen 5. This signals "something new is about to happen."

---

### SCREEN 5: Demo Setup

**Purpose:** Frame the demo. Lower the activation energy to record. Provide fallback for users who won't record.

**Layout:**
- Large animated microphone icon (pulsing gently)
- Bold headline
- Supporting text
- Primary CTA: Large "Start Recording" button
- Secondary CTA: Smaller text link "See a sample instead →"
- Progress bar (55%)

**Content:**
```
[🎙 Animated mic icon — gentle pulse]

Let's try it. Right now.

Talk for 15–30 seconds about anything
from your last shift. A broken machine.
A staff issue. Something for the next team.

Don't worry about being organized.
That's literally our job.

[🎙 Start Recording]

Or see a sample instead →
```

**Behavior:**
- "Start Recording" → request microphone permission → proceed to Screen 6 (live recording)
- "See a sample instead" → skip Screen 6, proceed directly to Screen 7 with industry-matched demo content
- If mic permission denied → automatically fall through to sample path with message: "No worries — here's what it looks like with a sample."
- Track: `analytics.onboarding_demo_path(path)` // "live_recording" or "sample"

**Transition:** Quick fade to Screen 6 (recording) or Screen 7 (sample)

---

### SCREEN 6: Live Recording

**Purpose:** The user records a real voice note. This IS the product.

**Layout:**
- Full-screen dark background
- Large animated waveform visualization (reacts to audio input)
- Timer centered below waveform
- Stop button at bottom center (large, unmistakable)
- Small hint text above stop button
- No progress bar on this screen (distraction-free)

**Content:**
```
[═══════ LIVE WAVEFORM ═══════]

0:12

Mention 2–3 different things for the best demo.

[⏹ Tap to finish]
```

**State:**
```swift
@State var recordingDuration: TimeInterval = 0
@State var audioFileURL: URL?      // local file path
@State var transcriptText: String = ""  // from Speech framework
```

**Behavior:**
- Recording starts automatically on screen appear (after mic permission granted)
- Live waveform animates with audio input levels
- Timer counts up in seconds
- Minimum 5 seconds: if they tap stop before 5s, show inline message: "A little more — even 10 seconds works great." and keep recording
- Maximum 60 seconds: auto-stop with message "Perfect, that's plenty."
- On stop: begin transcription immediately (Speech framework on-device)
- Show brief "Processing..." overlay (1 second) then transition to Screen 7
- Track: `analytics.onboarding_recording_completed(duration)`

**Transition:** Fade to Screen 7 with a brief loading shimmer

---

### SCREEN 7: AI Structuring Reveal — THE AHA MOMENT

**Purpose:** This is the most important screen in the entire onboarding. The user watches their messy voice note (or sample) transform into structured, categorized, actionable intelligence. This must feel magical.

**Layout — Phase 1 (Transcript):**
- Top section: Raw transcript text, slightly messy looking (monospace or handwriting-style font), scrolling in
- Label above: "Your recording:"

**Layout — Phase 2 (Structuring Animation):**
- Transcript fades to 20% opacity and shifts up
- Structured items build in one by one below, each with:
  - Category tag (colored pill)
  - Urgency badge (🔴 Urgent / 🟡 Normal / 🟢 Low)
  - Content text
  - Auto-generated action item below content

**Layout — Phase 3 (Result + CTA):**
- Summary stats fade in below structured items
- CTA button at bottom

**Animation Sequence (CRITICAL — pace this over 5-6 seconds even if AI is instant):**
```
0.0s  — Raw transcript fades in (0.5s)
0.5s  — Pause. Let them read it.
2.0s  — Transcript fades to 20% opacity, slides up
2.5s  — "ShiftVoice structured this into:" label fades in
3.0s  — First item builds in (category tag → content → action item)
4.0s  — Second item builds in
5.0s  — Third item builds in (if applicable)
5.5s  — Summary line fades in
6.0s  — CTA button fades in
```

**Content — Live recording path:**
Uses their actual transcript + actual AI structuring results.

**Content — Sample path (example for Restaurant):**
```
YOUR RECORDING:
"So the walk-in cooler is making that noise again
I think the compressor might be going, also we're
almost out of salmon so 86 that for tomorrow, and
tell Sarah she's training the new host on Thursday"

          ↓

  ShiftVoice structured this into:

  ┌──────────────────────────────────┐
  │ 🔧 Maintenance          🔴 Urgent│
  │                                  │
  │ Walk-in cooler compressor issue  │
  │ — recurring noise                │
  │                                  │
  │ → Schedule repair tech           │
  └──────────────────────────────────┘

  ┌──────────────────────────────────┐
  │ 🍽 Inventory            🟡 Normal│
  │                                  │
  │ Salmon 86'd for tomorrow service │
  │                                  │
  │ → Update prep sheet              │
  └──────────────────────────────────┘

  ┌──────────────────────────────────┐
  │ 👥 Staff                🟢 Normal│
  │                                  │
  │ Sarah training new host Thursday │
  │                                  │
  │ → Confirm schedule with Sarah    │
  └──────────────────────────────────┘

  30 seconds of talking.
  3 structured items. 3 action items. Zero typing.

  [Start my free trial →]
```

**Sample content per industry:**
```swift
let sampleStructuredItems: [String: [StructuredItem]] = [
  "restaurant": [
    StructuredItem(category: "Maintenance", urgency: .urgent, emoji: "🔧",
      content: "Walk-in cooler compressor issue — recurring noise",
      action: "Schedule repair tech"),
    StructuredItem(category: "Inventory", urgency: .normal, emoji: "🍽",
      content: "Salmon 86'd for tomorrow service",
      action: "Update prep sheet"),
    StructuredItem(category: "Staff", urgency: .low, emoji: "👥",
      content: "Sarah training new host Thursday",
      action: "Confirm schedule with Sarah")
  ],
  "hotel": [
    StructuredItem(category: "Rooms", urgency: .urgent, emoji: "🛏",
      content: "Room 412 AC not working — guest complained twice",
      action: "Send maintenance, offer room move"),
    StructuredItem(category: "Front Desk", urgency: .normal, emoji: "🔔",
      content: "VIP arriving tomorrow — Anderson party, suite 801",
      action: "Prep welcome amenities"),
    StructuredItem(category: "Housekeeping", urgency: .low, emoji: "🧹",
      content: "3rd floor supply closet needs restock",
      action: "Add to morning housekeeping checklist")
  ],
  "facilities": [
    StructuredItem(category: "HVAC", urgency: .urgent, emoji: "❄️",
      content: "3rd floor HVAC unit leaking — ceiling tiles damaged",
      action: "Emergency work order for HVAC repair"),
    StructuredItem(category: "Safety", urgency: .normal, emoji: "⚠️",
      content: "Exit sign out on stairwell B, 2nd floor",
      action: "Replace exit sign — compliance issue"),
    StructuredItem(category: "Grounds", urgency: .low, emoji: "🌿",
      content: "Parking lot light pole 7 flickering",
      action: "Schedule electrical check")
  ],
  "warehouse": [
    StructuredItem(category: "Equipment", urgency: .urgent, emoji: "🔧",
      content: "Forklift 3 pulling to the left — possible steering issue",
      action: "Tag out of service, schedule repair"),
    StructuredItem(category: "Receiving", urgency: .normal, emoji: "📦",
      content: "Pallet shipment from Sysco arrived short — 12 cases missing",
      action: "File shortage claim with vendor"),
    StructuredItem(category: "Safety", urgency: .low, emoji: "⚠️",
      content: "Wet floor near dock 4 — needs signage",
      action: "Place wet floor signs, check for leak source")
  ],
  "healthcare": [
    StructuredItem(category: "Equipment", urgency: .urgent, emoji: "🏥",
      content: "BP monitor in exam room 3 giving inconsistent readings",
      action: "Pull from service, send for calibration"),
    StructuredItem(category: "Supplies", urgency: .normal, emoji: "📋",
      content: "Running low on size medium gloves in Station 2",
      action: "Reorder and restock by morning shift"),
    StructuredItem(category: "Patient Flow", urgency: .low, emoji: "🚶",
      content: "Room 8 discharge expected by 2pm — needs turnover",
      action: "Assign housekeeping for 2pm turnover")
  ],
  "other": [
    StructuredItem(category: "Maintenance", urgency: .urgent, emoji: "🔧",
      content: "Printer on 2nd floor jammed — paper tray cracked",
      action: "Order replacement tray, reroute to 3rd floor printer"),
    StructuredItem(category: "Operations", urgency: .normal, emoji: "📋",
      content: "Conference room B projector bulb is dim",
      action: "Order replacement bulb"),
    StructuredItem(category: "Staff", urgency: .low, emoji: "👥",
      content: "New hire Jordan starts Monday — needs badge and laptop",
      action: "Submit IT request for equipment setup")
  ]
]
```

**State:**
```swift
@State var structuredItems: [StructuredItem] = []  // from AI or sample
@State var animationPhase: Int = 0  // 0=transcript, 1=fading, 2=items, 3=complete
// Persist the structured note — this becomes their first note in the app
@AppStorage("onboarding_note_data") var onboardingNote: Data?
```

**Behavior:**
- Animation is NOT skippable until Phase 3 (all items visible). Let it land.
- Once CTA appears, "Start my free trial →" is the only action
- The structured note is saved to local storage — it will appear in their feed after setup
- Track: `analytics.onboarding_aha_moment_completed(path, itemCount)`
- Track: `analytics.onboarding_aha_cta_tapped()`

**Transition:** Distinctive transition — scale up from center (0.4s) to Screen 8. Signals: "Now let's make this real."

---

### SCREEN 8: Workspace Setup + Team Invite (Combined)

**Purpose:** Two setup steps in one screen — name their workspace and invite teammates. This builds investment (harder to abandon) and starts the team adoption that creates lock-in during the trial.

**Layout:**
- Top section: Location setup (name + shifts)
- Divider
- Bottom section: Team invite
- Continue button at bottom
- Progress bar (77%)

**Content:**
```
Set up your workspace

LOCATION
┌─────────────────────────────────┐
│ Location name                   │
│ [e.g., "The Blue Ox Kitchen"]   │  ← placeholder from industryConfig
└─────────────────────────────────┘

SHIFTS
┌─────────────────────────────────┐
│ [Opening ✓]  [Mid ✓]  [Closing ✓]  [+ Add] │  ← pre-filled from industryConfig
│                                              │
│ Opening    6:00 AM ▾                         │
│ Mid       11:00 AM ▾                         │
│ Closing    4:00 PM ▾                         │
└──────────────────────────────────────────────┘

─────────────────────────────────

INVITE YOUR TEAM
ShiftVoice works best when your whole shift is on it.
Team members get free access to view and respond.

┌─────────────────────────────────┐
│ 📇 Add from contacts            │
├─────────────────────────────────┤
│ ✉️  Enter email or phone         │
└─────────────────────────────────┘

Added:
  👤 Marcus — Shift Lead
  👤 Priya — Shift Lead

[Skip invites for now]

[Continue →]
```

**State:**
```swift
@State var locationName: String = ""
@State var shifts: [ShiftConfig] = industryConfig[industry].defaultShifts
@State var invitedMembers: [InvitedMember] = []

struct ShiftConfig {
  var name: String
  var startTime: Date
  var isEnabled: Bool
}

struct InvitedMember {
  var name: String
  var contact: String  // email or phone
  var role: String     // "shift_lead", "manager", "staff"
}
```

**Behavior:**
- Location name is required. Shift config is pre-filled and optional to edit.
- Team invite is optional but heavily encouraged — "Skip invites for now" is small/muted text
- Invited members get a text/email: "You've been invited to [Location] on ShiftVoice. Tap to join → [deep link]"
- Invited members download the app and get read-only access (view feed, receive handoffs, respond to @mentions). They do NOT hit the paywall. They are free users forever. The buyer is the person going through this onboarding.
- "Continue" requires location name to be filled
- Track: `analytics.onboarding_workspace_created(locationName, shiftCount)`
- Track: `analytics.onboarding_invites_sent(count)`

**Transition:** Slide left to Screen 9

---

### SCREEN 9: Paywall — Trial Start

**Purpose:** Convert. This is the moment. Frame it as: you've already experienced the product, your workspace is set up, your team is invited. Now just start the trial to keep it going.

**Layout:**
- Top: Loss aversion hook (their structured note)
- Toggle: Monthly / Annual
- Single plan card (highlighted, primary)
- Feature list inside card
- Primary CTA: "Start Free Trial"
- Secondary: Fine print (trial terms)
- Progress bar (100%)

**Content:**
```
Your first note is already structured
and waiting in your feed. ✓

Keep your operations running.

[Monthly]  [Annual — save $189]
                                    ← Annual is pre-selected / highlighted

┌─────────────────────────────────────┐
│                                     │
│  ShiftVoice Pro                     │
│                                     │
│  $399/year ($33/mo)                 │  ← shows annual price by default
│  or $49/month                       │  ← smaller, below
│                                     │
│  ✅ Unlimited voice notes           │
│  ✅ AI-powered structuring          │
│  ✅ Shift handoff reports           │
│  ✅ @Mentions & escalation          │
│  ✅ Action item tracking            │
│  ✅ Unlimited team members          │
│  ✅ Offline mode — works anywhere   │
│  ✅ Full access, no limits          │
│                                     │
│  ┌───────────────────────────────┐  │
│  │   Start 7-Day Free Trial     │  │  ← Primary CTA, large, brand color
│  └───────────────────────────────┘  │
│                                     │
│  No charge for 7 days.             │
│  Cancel anytime in Settings.        │
│                                     │
└─────────────────────────────────────┘

[Restore purchase]

By continuing, you agree to our Terms of Service
and Privacy Policy.
```

**Monthly view (if toggled):**
```
│  ShiftVoice Pro                     │
│                                     │
│  $49/month                          │
│  Save $189/year with annual →       │  ← nudge back to annual
```

**RevenueCat Integration:**
```swift
// Product IDs — configure these in RevenueCat dashboard
let monthlyProductID = "shiftvoice_pro_monthly"    // $49/mo
let annualProductID = "shiftvoice_pro_annual"       // $399/yr

// Offering
let offeringID = "default"

// Trial configuration (set in App Store Connect):
// - 7-day free trial on both monthly and annual
// - No credit card required for trial (Apple handles this)
// NOTE: As of iOS 16+, Apple may require payment method for trials.
// RevenueCat handles the trial state and entitlement automatically.

// Entitlement
let entitlementID = "pro_access"

// On CTA tap:
func startTrial(isAnnual: Bool) {
    let productID = isAnnual ? annualProductID : monthlyProductID
    Purchases.shared.purchase(productID) { transaction, info, error, cancelled in
        if let info = info, info.entitlements["pro_access"]?.isActive == true {
            // Trial started successfully
            analytics.onboarding_trial_started(plan: isAnnual ? "annual" : "monthly")
            navigateToMainApp()
        } else if cancelled {
            // User cancelled — still show the app in trial-expired state
            // or let them continue to browse (you decide)
            analytics.onboarding_trial_cancelled()
        }
    }
}

// Check trial status anywhere in app:
func checkAccess() {
    Purchases.shared.getCustomerInfo { info, error in
        let isActive = info?.entitlements["pro_access"]?.isActive ?? false
        let isTrial = info?.entitlements["pro_access"]?.periodType == .trial
        // Update UI accordingly
    }
}
```

**Behavior:**
- Annual plan is pre-selected (default toggle position)
- "Start 7-Day Free Trial" triggers RevenueCat purchase flow
- Apple's native subscription confirmation sheet appears
- On success → navigate to main app. Their onboarding note is in the feed.
- On cancel/dismiss → remain on this screen. Do NOT boot them out.
- "Restore purchase" for returning users
- Track: `analytics.onboarding_paywall_seen()`
- Track: `analytics.onboarding_paywall_toggle(plan)` // each toggle between monthly/annual
- Track: `analytics.onboarding_trial_started(plan)`
- Track: `analytics.onboarding_paywall_dismissed()`

**What happens if they don't start the trial?**
- Option A (recommended for launch): Let them into the app anyway with a persistent banner: "Your trial hasn't started yet. Start your 7-day free trial to unlock all features." Every feature works, but the banner persists. This gives them more time to experience value. When they tap any core feature, soft-prompt the trial again.
- Option B (harder paywall): Block entry. Show "Start your trial to continue." with the CTA. Risk: higher drop-off, but higher intent on those who convert.
- **Recommendation:** Go with Option A for launch. You need usage data more than you need conversion right now. You can always tighten the paywall later.

**Transition:** Main app loads. Their onboarding structured note is the first item in the shift feed.

---

## Post-Onboarding: First 7 Days (Trial Period)

These nudges happen during the trial to maximize the chance of conversion at Day 7.

### Day 0 (Immediately after onboarding)
- **Feed tooltip:** "This is your shift feed. Your first note is already here — tap to see the full breakdown."
- **Recording CTA:** Floating "+" button with pulse animation for first 2 app opens

### Day 1
- **Push notification (shift start time):** "Your [Opening] shift is starting. Tap to capture your first real handoff."
- **If team members joined:** "Marcus just joined your team on ShiftVoice. Record a note to keep everyone in sync."

### Day 2
- **If 0 notes recorded post-onboarding:** "You set up ShiftVoice but haven't recorded since. One 30-second note today keeps your team aligned."
- **If 1+ notes recorded:** No push. Don't annoy active users.

### Day 3
- **Celebrate if active:** "3 days in — you've structured [X] notes. That's [X] handoffs that didn't fall through the cracks."
- **If team invites sent but not accepted:** "Your team invites to [Marcus, Priya] are still pending. Want to resend?"

### Day 5
- **Trial reminder (soft):** "Your ShiftVoice trial has 2 days left. Your team has captured [X] notes and [Y] action items so far."
- **If generating handoff reports:** "You've generated [X] shift handoffs. Your team now has a searchable record of every transition."

### Day 6
- **Trial reminder (direct):** "Your trial ends tomorrow. Subscribe to keep your [X] notes, [Y] action items, and all handoff reports."
- **Deep link to paywall** from push notification

### Day 7 (Trial expires)
- **Full-screen modal on app open:**
```
Your 7-day trial has ended.

During your trial, your team:
📝 Structured [X] voice notes
✅ Created [Y] action items
📋 Generated [Z] shift handoffs

Keep your operations running.

[Subscribe — $399/year ($33/mo)]
[Subscribe — $49/month]

Your data is saved and waiting.
```

### Post-Expiry (Days 8+)
- The app becomes read-only. They can VIEW everything — all notes, action items, handoffs — but can't record new notes or generate handoffs.
- This is intentional. Read-only access means the data is still useful, the team still references it, and the switching cost remains high. They feel the absence of new capture, not the absence of their data.
- Weekly push: "[X] shifts have happened since your trial ended. Your team's handoffs aren't being captured."

---

## Analytics Events — Full List

Track these from Day 0. Pipe to your analytics tool (Mixpanel, Amplitude, PostHog, or even a simple Firebase setup).

```swift
// Onboarding flow
analytics.onboarding_started()
analytics.onboarding_role_selected(role: String)
analytics.onboarding_industry_selected(industry: String)
analytics.onboarding_pain_points_selected(painPoints: [String])
analytics.onboarding_current_tool_selected(tool: String)
analytics.onboarding_mirror_cta_tapped()
analytics.onboarding_demo_path(path: String)              // "live_recording" or "sample"
analytics.onboarding_recording_completed(duration: Double)  // only for live path
analytics.onboarding_aha_moment_completed(path: String, itemCount: Int)
analytics.onboarding_aha_cta_tapped()
analytics.onboarding_workspace_created(location: String, shiftCount: Int)
analytics.onboarding_invites_sent(count: Int)
analytics.onboarding_paywall_seen()
analytics.onboarding_paywall_toggle(plan: String)          // "monthly" or "annual"
analytics.onboarding_trial_started(plan: String)
analytics.onboarding_paywall_dismissed()
analytics.onboarding_completed()

// Post-onboarding (trial period)
analytics.trial_note_recorded(dayOfTrial: Int)
analytics.trial_handoff_generated(dayOfTrial: Int)
analytics.trial_team_member_joined(dayOfTrial: Int)
analytics.trial_reminder_shown(dayOfTrial: Int)
analytics.trial_expired()
analytics.trial_converted(plan: String)
analytics.trial_churned()
```

---

## Data Model — What to Persist from Onboarding

```swift
struct OnboardingData: Codable {
    var role: String                    // "shift_lead", "gm_owner", "multi_unit"
    var industry: String                // "restaurant", "hotel", etc.
    var painPoints: [String]            // ["forgotten_handoffs", "recurring_issues", ...]
    var currentTool: String             // "verbal", "paper", "whatsapp", etc.
    var demoPath: String                // "live_recording" or "sample"
    var recordingDuration: Double?      // seconds (only if live)
    var structuredNote: StructuredNote  // the actual note from onboarding
    var locationName: String
    var shifts: [ShiftConfig]
    var invitedMembers: [InvitedMember]
    var trialPlan: String?              // "monthly" or "annual" (nil if not started)
    var completedAt: Date
}
```

This data serves double duty:
1. **Product:** Configures the app experience (categories, shifts, terminology)
2. **Analytics:** Every field is a data point about your market. After 100 users, you'll know exactly which roles, industries, and pain points dominate your early adopter base.

---

## Implementation Checklist for Rork

```
[ ] Screen 1 — Role selection (3 cards, auto-advance)
[ ] Screen 2 — Industry selection (6 cards grid, auto-advance)
[ ] Screen 3 — Pain point multi-select (4 cards, Continue button)
[ ] Screen 4 — Current tool select + mirror text animation
[ ] Screen 5 — Demo setup (mic icon, two CTA paths)
[ ] Screen 6 — Live recording (waveform, timer, stop button)
[ ] Screen 7 — AI structuring animation (THE screen — get this right)
[ ] Screen 8 — Workspace setup + team invite (combined form)
[ ] Screen 9 — Paywall with RevenueCat (monthly/annual toggle)
[ ] Progress bar component (thin, top of screen, animated)
[ ] Screen transitions (slide within acts, fade-through-black between acts)
[ ] Industry config data (categories, shifts, demo content per industry)
[ ] Sample structured content for all 6 industries
[ ] RevenueCat SDK integration (product IDs, entitlements, trial check)
[ ] Analytics event tracking (all events listed above)
[ ] Post-onboarding: onboarding note injected into shift feed
[ ] Post-onboarding: trial day nudges / push notifications
[ ] Trial expiry: read-only mode + conversion modal
[ ] Invited team members: deep link flow (free view-only access)
```
