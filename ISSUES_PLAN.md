# ShiftVoice Issues Plan

## Summary

Comprehensive fix plan based on full QA audit across security, data integrity, UX, and code quality. Issues are grouped by priority and ordered for safe sequential execution.

---

## Phase 1: Critical Security Fixes

### 1.1 Unauthorized team member delete
- **File:** `backend/hono.ts` — `DELETE /rest/team/:memberId`
- **Issue:** Endpoint deletes by `memberId` without verifying ownership. Any authenticated user could delete another user's team member if ID is known.
- **Fix:** Before deleting, fetch the team member and verify `member.ownerId === auth.userId`. Return 403 if not owned.

### 1.2 Unauthorized shift note delete
- **File:** `backend/hono.ts` — `DELETE /rest/shift-notes/:noteId`
- **Issue:** If note isn't found, code still calls delete and returns success. Inconsistent auth semantics.
- **Fix:** Return 404 if note not found. Verify `note.ownerId === auth.userId` before delete.

### 1.3 Mass assignment on PATCH endpoints
- **Files:** `backend/hono.ts`
  - `PATCH /rest/shift-notes/:noteId`
  - `PATCH /rest/locations/:locationId`
  - `PATCH /rest/team/:memberId`
- **Issue:** Request body is spread directly (`{ ...existing, ...body }`) with no field allowlist. Clients can mutate server-controlled fields like `ownerId`, `createdAt`, etc.
- **Fix:** Add explicit allowlists for each PATCH endpoint. Only merge allowed fields. Reject or strip unknown fields.

---

## Phase 2: High Priority Auth & Safety Fixes

### 2.1 tRPC protected procedure doesn't validate session token
- **File:** `backend/trpc/create-context.ts`
- **Issue:** `protectedProcedure` only checks header presence (`userId` + `token`), not token validity against storage.
- **Fix:** Look up session in `storage.getSession(token)` and verify it matches `userId`. Return UNAUTHORIZED if invalid.

### 2.2 tRPC shift notes routes accept untyped payloads
- **File:** `backend/trpc/routes/shift-notes.ts`
- **Issue:** `create` and `update` mutations accept `z.any()`. No schema validation on tRPC routes.
- **Fix:** Replace `z.any()` with the typed `shiftNoteSchema` (already defined in `hono.ts`). Extract shared schemas to a common file if needed.

### 2.3 Backend auth failure silently swallowed
- **File:** `ShiftVoice/Services/AuthenticationService.swift` — `authenticateWithBackend`
- **Issue:** Catch block intentionally ignores backend auth errors. User appears signed in (Firebase) but backend token may be missing, causing later "Not authenticated" errors.
- **Fix:** Store a `backendAuthFailed` flag. On subsequent API calls that fail with 401, retry `authenticateWithBackend()` once before showing error. Log the failure for debugging.

### 2.4 Debug section not gated behind #if DEBUG
- **File:** `ShiftVoice/Views/SettingsView.swift` — `debugSection` / "Load Demo Data"
- **Issue:** The debug section with "Load Demo Data" is visible to production users. Can overwrite/mix real data with demo data.
- **Fix:** Wrap `debugSection` reference and the `debugSection` computed property in `#if DEBUG ... #endif`.

---

## Phase 3: Medium Priority Fixes

### 3.1 Delete account lacks re-authentication
- **Files:** `ShiftVoice/Views/SettingsView.swift`, `ShiftVoice/Services/AuthenticationService.swift`
- **Issue:** Single confirm alert before irreversible account deletion. No re-auth flow. Risky on shared devices.
- **Fix:** Add a password confirmation field in the delete alert (for email auth) or require re-authentication via `user.reauthenticate()` before proceeding with delete.

### 3.2 Settings legal links are dead
- **File:** `ShiftVoice/Views/SettingsView.swift`
- **Issue:** "Privacy Policy" and "Terms of Service" buttons have empty actions. Broken trust/compliance UX.
- **Fix:** Add placeholder URLs (or the real ones if available) and open them via `UIApplication.shared.open()`. If no URLs exist yet, link to a generic placeholder page and add a TODO.

### 3.3 Onboarding tap gesture layout bug
- **File:** `ShiftVoice/Views/Onboarding/OnboardingTeamView.swift`
- **Issue:** `Spacer(minLength: 40)` is placed inside `.onTapGesture` closure (invalid/no-op pattern). Keyboard dismiss may not work reliably.
- **Fix:** Move the `.onTapGesture` to the outer container and use `UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), ...)` or `.scrollDismissesKeyboard(.interactively)`.

### 3.4 Form validation inconsistency between client and server
- **Files:** `ShiftVoice/Utilities/InputValidator.swift`, `backend/hono.ts`
- **Issue:** Client enforces stricter password/name rules than backend. Direct API calls can bypass client validation.
- **Fix:** Add matching validation to backend auth routes: password min 8 chars with letter+number, name min 2 chars. Align max lengths between client `InputValidator` and backend zod schemas.

---

## Phase 4: Low Priority / UX Polish

### 4.1 Subscription fallback can mask misconfig
- **File:** `ShiftVoice/Views/PaywallView.swift`
- **Issue:** If offerings load fails with a non-`SubscriptionServiceError`, UI continues with hardcoded prices. Potential mismatch between displayed price and actual purchasable state.
- **Fix:** Show a subtle banner or footnote when using fallback prices: "Prices may vary. Pull to refresh." Add a retry button.

### 4.2 Acknowledge note duplicate prevention (client-side)
- **File:** `ShiftVoice/Views/ShiftNoteDetailView.swift`
- **Issue:** The acknowledge button is hidden after ack, but tapping quickly could double-fire before the UI updates.
- **Fix:** Add `isAcknowledging` loading state and disable the button during the async operation.

---

## Execution Order & Dependencies

```
Phase 1 (Security) ─── no dependencies, do first
  1.1 → 1.2 → 1.3

Phase 2 (Auth & Safety) ─── after Phase 1
  2.1 → 2.2 (both tRPC)
  2.3 (independent)
  2.4 (independent)

Phase 3 (Medium) ─── independent of Phases 1-2
  3.1, 3.2, 3.3, 3.4 (all independent)

Phase 4 (Polish) ─── after all above
  4.1, 4.2 (all independent)
```

---

## Already Fixed (Previous Sessions)

These issues were identified and resolved in earlier work sessions:

| Issue | Status |
|-------|--------|
| `syncError` never set in `loadUserData` | Fixed |
| `forceSync()` showed static message instead of retrying | Fixed |
| Unbounded Firestore listener (no `.limit()`) | Fixed (300 cap) |
| RevenueCat `purchase()` silently returned `false` when unconfigured | Fixed |
| Backend storage linear scans (O(n) lookups) | Fixed (owner indexes) |
| Sync endpoint returned unbounded note payload | Fixed (100 cap) |
| DashboardView action items unbounded list | Fixed (pagination) |
| Search results unbounded | Fixed (50 cap) |
| No frontend input validation | Fixed (`InputValidator` created) |
| NoteReviewView publish without validation | Fixed |
| Backend `z.any()` in REST schemas | Fixed (typed schemas) |
| Offline writes not queued for replay | Fixed (`replayPendingActions`) |
| `simulatePlayback()` instead of real `AVAudioPlayer` | Fixed |
| RevenueCat tier not synced to `Organization.plan` | Fixed |
| Notification preferences lost on restart (`@State`) | Fixed (`@AppStorage`) |
| Dead `OperationState` enum never set | Fixed (removed) |
| `filteredPaginatedNotes()` ignoring its parameter | Fixed (removed) |
| Redundant `updateUnacknowledgedCount()` | Fixed (removed) |

---

## Estimated Effort

| Phase | Issues | Estimated Time |
|-------|--------|---------------|
| Phase 1 | 3 | ~30 min |
| Phase 2 | 4 | ~45 min |
| Phase 3 | 4 | ~40 min |
| Phase 4 | 2 | ~15 min |
| **Total** | **13** | **~2 hours** |
