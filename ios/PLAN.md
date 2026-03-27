# Replace Firestore with Supabase Postgres + Realtime

## Summary

Replace Firestore (database only) with Supabase Postgres for all data storage and real-time updates. Keep Firebase Auth for sign-in. Remove the Hono/tRPC backend entirely — the iOS app will talk directly to Supabase and OpenAI. Fresh start, no data migration.

---

## What Changes

### 🔑 Authentication (Stays the Same)
- Firebase Auth remains for email/password and Google Sign-In
- After Firebase sign-in, the app will use the Firebase user ID to identify rows in Supabase
- A Supabase service-role or anon key handles database access (secured by Row Level Security policies you'll set up in Supabase)

### 🗄️ Database — Firestore → Supabase Postgres
All data moves to Supabase Postgres tables:
- **users** — profile info (name, email, initials, org reference, selected location)
- **organizations** — name, owner, plan, industry type
- **locations** — name, address, timezone, shift times, linked to an organization
- **team_members** — name, email, role, linked to organization and locations
- **shift_notes** — the core data: transcript, summary, author, location, shift type, visibility, timestamps
- **categorized_items** — structured items linked to a shift note
- **action_items** — tasks linked to a shift note, with status/assignee/urgency tracking
- **acknowledgments** — who read which note
- **voice_replies** — replies on notes
- **recurring_issues** — detected patterns across notes

### 📡 Real-Time Updates — Firestore Listeners → Supabase Realtime
- Live updates for shift notes, action items, locations, team members, and organization changes
- Uses Supabase's websocket-based Realtime (Postgres changes)
- Replaces all Firestore snapshot listeners

### 🧠 AI Structuring — Backend → Direct OpenAI Calls
- The app calls the OpenAI API directly for transcript structuring (using the existing OpenAI API key from Config)
- Removes dependency on the broken Hono backend entirely
- Action item refinement also calls OpenAI directly

### 🗑️ What Gets Removed
- **FirebaseFirestore** SPM package (FirebaseAuth stays)
- **FirestoreService.swift** — replaced by SupabaseService
- **APIService.swift** — no longer needed (was talking to Hono backend)
- All sync/conflict infrastructure (PendingOpsStore, ConflictDetector, SyncState reducer, WriteFailureStore, etc.) — Supabase handles this server-side
- The entire `backend/` folder is no longer used by the iOS app

### 📦 New Dependency
- **Supabase Swift SDK** — official package for database queries, realtime subscriptions, and storage

---

## New Environment Variables Needed
You'll need to provide two values from your Supabase project:
- **SUPABASE_URL** — your project URL (e.g. `https://xxxxx.supabase.co`)
- **SUPABASE_ANON_KEY** — the public anon key

---

## Screens & Features — What Users See

Everything stays the same from a user perspective:
- **Sign In** — unchanged (Firebase Auth)
- **Onboarding** — unchanged flow, but data saves to Supabase instead of Firestore
- **Shift Feed** — live-updating list of notes, now powered by Supabase Realtime
- **Record & Review** — voice recording → transcription → AI structuring (now calls OpenAI directly)
- **Action Items Dashboard** — same filters and status updates, backed by Supabase
- **Settings** — same team/location management, backed by Supabase
- **Offline banner** — simplified (network connectivity detection remains)

---

## Implementation Order

1. **Add Supabase SDK** and configure with URL + anon key
2. **Create SupabaseService** — replaces FirestoreService with Postgres queries and Realtime subscriptions
3. **Create OpenAIService** — handles transcript structuring directly (replaces NoteStructuringService's backend calls)
4. **Update AppViewModel** — swap all Firestore calls to SupabaseService, simplify sync logic
5. **Update AuthenticationService** — remove backend token exchange (keep Firebase Auth, just save user profile to Supabase after sign-in)
6. **Remove old services** — delete FirestoreService, APIService, and all sync/conflict infrastructure
7. **Remove FirebaseFirestore package** — keep FirebaseAuth
8. **Clean up unused models** — SyncState, WriteFailure, ConflictItem, EditBaseline, PendingOps
9. **Update ShiftVoiceApp entry point** — remove backend auth flow, simplify to Firebase Auth + Supabase data loading
10. **Verify build** and test all flows

---

## Supabase Setup You'll Need to Do (in Supabase Dashboard)

Before I implement the code, you'll need to create the Postgres tables in your Supabase project. I'll provide the exact SQL schema as part of the implementation. You'll also want to set up Row Level Security (RLS) policies so users can only access their organization's data.
