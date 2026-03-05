# ShiftVoice Firebase Auth Migration — End-to-End Execution Plan

## 1. Objective

Migrate ShiftVoice authentication from custom backend sessions to Firebase Authentication with minimal risk, no API contract breakage for iOS, and a clean rollback path.

This plan is scoped to auth migration only (not Firestore/data model migration).

---

## 2. Current State (Validated from Codebase)

### Backend (Hono + tRPC)
- REST auth endpoints exist in `backend/hono.ts`:
  - `POST /rest/auth/register`
  - `POST /rest/auth/login`
  - `POST /rest/auth/google`
  - `POST /rest/auth/firebase`
  - `POST /rest/auth/logout`
- Custom sessions are currently issued/validated in `backend/storage.ts` via:
  - `createSession`
  - `validateSession`
  - `deleteSession`
- tRPC auth context (`backend/trpc/create-context.ts`) currently trusts:
  - `Authorization: Bearer <token>`
  - `x-user-id`
  - and compares against `storage.validateSession(...)`
- tRPC auth routes (`backend/trpc/routes/auth.ts`) still do password hashing + custom token generation.

### iOS
- `APIService` already uses bearer token request flow.
- This means token source can be swapped to Firebase ID token without redesigning request transport.

---

## 3. Target State

### Trust Model
1. iOS signs in using Firebase SDK (Email/Password, Google).
2. iOS sends Firebase ID token as bearer token.
3. Backend verifies ID token on every protected request.
4. Backend derives identity strictly from verified token claims (`uid`).
5. Backend no longer trusts `x-user-id` for authorization.

### Security Baselines (2026 best practice)
- Verify token signature/issuer/audience/expiration via Firebase Admin SDK.
- Optionally enable revocation checks for high-risk routes.
- Keep token verification server-side only.
- Redact tokens from logs.

---

## 4. Migration Principles

- Preserve existing REST route paths and response shape where possible.
- Keep migration incremental with staging gate between phases.
- Prefer compatibility windows over hard cutovers.
- Remove legacy custom-session trust only after client cutover verification.

---

## 5. Phase Plan

## Phase 0 — Preflight & Environment Readiness

### Tasks
- Create/validate Firebase projects: dev + prod.
- Enable providers: Email/Password and Google.
- Provision backend service account credentials.
- Add backend env vars for Firebase Admin initialization.
- Validate runtime can initialize verifier successfully.

### Exit Criteria
- Backend starts clean with Firebase verifier initialized.
- iOS can initialize Firebase config in dev/prod.

---

## Phase 1 — Backend Verification Foundation

### Tasks
- Introduce one shared token verification module for backend auth.
- Replace custom auth middleware usage with Firebase verification.
- Remove authorization trust in `x-user-id` header.
- Keep existing error response structure consistent (`401`, stable JSON shape).

### Exit Criteria
- Protected endpoints authorize using verified `uid` only.
- `x-user-id` no longer affects auth decisions.

---

## Phase 2 — REST Auth Endpoint Migration (Endpoint-by-Endpoint)

## `POST /rest/auth/register`
### Current
- Creates account with password hash and custom session token.
### Target
- Profile bootstrap/upsert only using verified Firebase identity.
- No password handling in backend.
### Compatibility
- Keep response fields currently consumed by iOS (`success`, `userId`, etc.).

## `POST /rest/auth/login`
### Current
- Email/password credential exchange + custom token issuance.
### Target
- Deprecate backend credential login path.
- Return migration-safe response indicating Firebase login is required.
### Compatibility
- Keep stable HTTP status + predictable body for old client handling.

## `POST /rest/auth/google`
### Current
- Trusts posted google user info and issues custom token.
### Target
- Verify Firebase ID token (Google provider-backed sign-in).
- Upsert profile, return compatibility response.

## `POST /rest/auth/firebase`
### Current
- Accepts posted fields and still issues backend session token.
### Target
- Canonical bootstrap endpoint for Firebase-authenticated users.
- Verify ID token, upsert profile, return compatibility response.

## `POST /rest/auth/logout`
### Current
- Deletes backend session token.
### Target
- Client-side Firebase sign-out as primary behavior.
- Optional server revocation/admin cleanup endpoint behavior.

### Exit Criteria
- No REST endpoint depends on custom session issuance for active auth.

---

## Phase 3 — tRPC Auth Migration (Procedure-by-Procedure)

## `auth.register`
- Convert to profile bootstrap semantics.
- Remove backend password hash + token issuance.

## `auth.login`
- Deprecate custom credential exchange.

## `auth.googleAuth`
- Verify Firebase token + upsert account/profile.

## `auth.logout`
- Keep logical logout behavior (client cleanup + optional revocation hook).

## `auth.validateSession`
- Replace session-table check with Firebase token verification + profile lookup.

### Exit Criteria
- No tRPC auth procedure relies on `storage.validateSession(...)`.

---

## Phase 4 — iOS Cutover

### Tasks
- Switch sign-up/sign-in flows to Firebase SDK only.
- Acquire fresh ID token from Firebase and keep using existing bearer transport path.
- Ensure token refresh before protected API calls.
- Ensure sign-out clears local session and Firebase state.

### Exit Criteria
- iOS auth flows work end-to-end with Firebase identity only.

---

## Phase 5 — Cleanup, Hardening, Rollout

### Tasks
- Remove dead custom session/password logic after confidence window.
- Add auth diagnostics and redact-sensitive logging guardrails.
- Add rate limiting for auth bootstrap endpoints.
- Execute rollback drill.

### Exit Criteria
- Production is stable with Firebase-only auth trust.

---

## 6. End-to-End Verification Checklist

## Backend Auth Verification
- [ ] Valid Firebase ID token accepted.
- [ ] Missing bearer token returns 401.
- [ ] Expired token returns 401.
- [ ] Wrong audience/issuer token returns 401.
- [ ] Revoked token behavior validated (if enabled).

## Endpoint Contract Regression
- [ ] `/rest/auth/register` response schema remains compatible.
- [ ] `/rest/auth/firebase` response schema remains compatible.
- [ ] `/rest/auth/logout` response schema remains compatible.
- [ ] Deprecated `/rest/auth/login` handled safely by client.

## iOS Integration
- [ ] Email/password Firebase signup works.
- [ ] Email/password Firebase login works.
- [ ] Google provider login works.
- [ ] Bearer token sent on all protected routes.
- [ ] Background/foreground token refresh works.
- [ ] Relaunch restores auth state correctly.

## Production Readiness
- [ ] `/api/rest/health` returns 200 post-deploy.
- [ ] Auth errors visible and diagnosable in logs.
- [ ] No raw token leakage in logs.
- [ ] Rollback procedure tested.

---

## 7. Deployment & Rollback Runbook

## Deploy Sequence
1. Deploy backend verification + compatibility behavior to staging.
2. Run full auth verification matrix.
3. Deploy iOS build with Firebase auth enabled.
4. Roll out production backend.
5. Verify `/api/rest/health` and auth smoke tests.
6. Monitor error rates for 24–48h.
7. Remove legacy auth/session code only after stable window.

## Rollback Trigger Conditions
- Auth 401 spike above agreed threshold.
- iOS sign-in success rate drops materially.
- Token verification failures due to config/runtime mismatch.

## Rollback Steps
1. Revert backend to last known-good auth release.
2. Disable new auth behavior via feature flag/version gate (if available).
3. Validate `/api/rest/health` 200 and auth smoke tests.
4. Pause rollout and patch root cause.

---

## 8. Risks and Mitigations

- **Runtime incompatibility with Firebase Admin:** preflight in staging before cutover.
- **Old/new client mix during transition:** maintain temporary compatibility semantics.
- **Contract breakage in auth responses:** lock schema checks in regression tests.
- **Security regressions:** enforce uid-from-verified-token-only policy.

---

## 9. Definition of Done

- Firebase Auth is the only active identity mechanism.
- Backend authorization uses verified Firebase token claims only.
- iOS auth flows pass with Firebase for Email/Password + Google.
- Health and smoke checks pass after production deployment.
- Legacy custom session/password code removed from active paths.
- Rollback runbook is validated and documented.
