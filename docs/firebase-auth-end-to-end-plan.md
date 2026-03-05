# ShiftVoice Firebase Auth Migration — End-to-End Execution Plan

## 1. Objective

Migrate ShiftVoice authentication from custom backend sessions to Firebase Authentication with minimal risk, no API contract breakage for iOS, and a clean rollback path.

This plan covers two independent concerns:
1. **Deployment fix** — Resolve the backend crash-loop caused by a stale cached build artifact (prerequisite for everything else).
2. **Auth migration** — Replace custom sessions with Firebase Authentication.

These are independent problems. The deployment fix must succeed first; the auth migration addresses security/architecture.

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

### Non-Auth REST Endpoints with Missing or Broken Auth
- `POST /rest/structure-transcript` (line 1540) — Uses `x-user-id` header directly for identity with **zero session validation**. No `authMiddleware` call. Completely unprotected — any request with an `x-user-id` header is accepted.
- `POST /rest/refine-action-item` (line 1696) — **Zero auth of any kind**. No `authMiddleware` call, no header check. Fully open to unauthenticated requests.

### Security Holes in Current Auth Endpoints
- `POST /rest/auth/firebase` (line 866) — Accepts `idToken` field in the schema but **never verifies it**. Blindly trusts the posted `uid` and `email` fields. Any caller can impersonate any user by posting an arbitrary `uid`. This is not a "migration gap" — it is an active security vulnerability.

### tRPC Redundancy
- `auth.validateSession` (line 137) — Already behind `protectedProcedure` which calls `storage.validateSession(ctx.token)` in `create-context.ts` (line 34). The handler then calls `storage.validateSession(ctx.token)` **again** inside the query body. This is a redundant double-check, not a security issue, but it should be cleaned up during migration.

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

## Phase -1 — Deployment Fix (Prerequisite)

### Problem
The backend is in a crash-loop. Live logs show:
```
Error loading main module: Cannot find module '@rork-ai/toolkit-sdk' imported from '/backend/hono.ts'
```
The current source code has **zero references** to `@rork-ai/toolkit-sdk`. The deployed runtime is serving a stale cached build artifact from a previous deployment.

### Root Cause
A previous code change added the import, it was deployed, then the import was removed from source — but the deployment platform continued serving the old cached bundle. Subsequent no-op redeploys did not clear the cache.

### Tasks
- [ ] Purge the backend build cache entirely at the platform level.
- [ ] Delete the current deployment artifact/bundle.
- [ ] Rebuild from current clean source with zero cache.
- [ ] Deploy the fresh build.
- [ ] Verify `GET /api/rest/health` returns `200 { ok: true }`.
- [ ] Verify at least one auth endpoint responds (e.g., `POST /rest/auth/firebase` returns a non-connection-error response).

### Why This Is Separate
This is a **platform infrastructure issue**, not a code issue. The Firebase auth migration (Phases 0–5) addresses authentication architecture. Even if every auth migration phase executes perfectly, the backend will still crash-loop if the deployment platform keeps serving the old cached bundle.

### Exit Criteria
- Backend process starts without crash.
- `/api/rest/health` returns 200.
- No `Cannot find module` errors in runtime logs.
- At least one full request/response cycle succeeds.

### Relationship to Auth Migration
- Phase -1 **must complete** before any auth migration phase can be tested or verified.
- Phase -1 does not change any code — it is a deploy-only fix.
- Auth migration (Phases 0–5) can begin development in parallel but cannot be validated until Phase -1 is resolved.

---

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
- Accepts `idToken`, `uid`, `name`, `email` fields but **never verifies `idToken`**.
- Blindly trusts the posted `uid` and `email` — any caller can impersonate any user.
- Issues a backend session token based on unverified identity.
- **This is an active security vulnerability, not just a migration gap.**
### Target
- Canonical bootstrap endpoint for Firebase-authenticated users.
- **Verify ID token server-side** using Firebase Admin SDK before any account lookup/creation.
- Derive `uid` and `email` exclusively from verified token claims — never from request body.
- Upsert profile, return compatibility response.

## `POST /rest/auth/logout`
### Current
- Deletes backend session token.
### Target
- Client-side Firebase sign-out as primary behavior.
- Optional server revocation/admin cleanup endpoint behavior.

## `POST /rest/structure-transcript`
### Current
- Uses `x-user-id` header directly for identity (line 1540).
- **No `authMiddleware` call** — no session validation whatsoever.
- Any request with an `x-user-id` header is accepted.
### Target
- Add Firebase token verification (same middleware as other protected endpoints).
- Derive `userId` from verified token claims, not from request headers.
### Compatibility
- No response schema change needed — only the auth check is added.

## `POST /rest/refine-action-item`
### Current
- **Zero authentication** — no `authMiddleware`, no header check, no session validation (line 1696).
- Fully open to unauthenticated requests.
### Target
- Add Firebase token verification.
- Gate access behind verified identity.
### Compatibility
- No response schema change needed — only the auth check is added.

### Exit Criteria
- No REST endpoint depends on custom session issuance for active auth.
- `/rest/structure-transcript` and `/rest/refine-action-item` require verified Firebase token.
- No endpoint trusts `x-user-id` header for identity.

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
- **Remove redundant double-validation**: `protectedProcedure` already calls `storage.validateSession(ctx.token)` in `create-context.ts` (line 34). The handler at line 137 calls `storage.validateSession(ctx.token)` again inside the query body. After migration, the handler should use the already-verified `ctx.userId` from the middleware — no second verification call.

### Exit Criteria
- No tRPC auth procedure relies on `storage.validateSession(...)`.
- `auth.validateSession` uses `ctx.userId` from middleware, not a redundant re-verification.

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

## Deployment Fix Verification (Phase -1)
- [ ] Backend build cache purged at platform level.
- [ ] Fresh build deployed from current clean source.
- [ ] `/api/rest/health` returns 200.
- [ ] No `Cannot find module` errors in runtime logs.
- [ ] Full request/response cycle succeeds on at least one endpoint.

## Endpoint Contract Regression
- [ ] `/rest/auth/register` response schema remains compatible.
- [ ] `/rest/auth/firebase` response schema remains compatible.
- [ ] `/rest/auth/logout` response schema remains compatible.
- [ ] Deprecated `/rest/auth/login` handled safely by client.
- [ ] `/rest/structure-transcript` rejects requests without valid Firebase token.
- [ ] `/rest/refine-action-item` rejects requests without valid Firebase token.

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

- **Backend crash-loop blocks all work:** Phase -1 deployment fix is a hard prerequisite. No auth migration phase can be tested or verified until the backend is running. If platform cache purge fails, escalate to platform support.
- **Runtime incompatibility with Firebase Admin:** preflight in staging before cutover.
- **Old/new client mix during transition:** maintain temporary compatibility semantics.
- **Contract breakage in auth responses:** lock schema checks in regression tests.
- **Security regressions:** enforce uid-from-verified-token-only policy.
- **Unprotected endpoints exploited before migration:** `/rest/structure-transcript` and `/rest/refine-action-item` are currently open. Consider adding basic `authMiddleware` as an interim fix before full Firebase migration.
- **`/rest/auth/firebase` impersonation:** The endpoint currently trusts posted `uid` without verification. Until Phase 2 lands, any caller can impersonate any user. Prioritize this endpoint in the migration sequence.

---

## 9. Definition of Done

- Backend deployment is stable — no crash-loop, `/api/rest/health` returns 200 (Phase -1).
- Firebase Auth is the only active identity mechanism.
- Backend authorization uses verified Firebase token claims only.
- **All REST endpoints** require verified Firebase token — including `/rest/structure-transcript` and `/rest/refine-action-item`.
- No endpoint trusts `x-user-id` header for identity.
- `/rest/auth/firebase` verifies ID token server-side before any account operation.
- `auth.validateSession` uses middleware-provided identity, no redundant re-verification.
- iOS auth flows pass with Firebase for Email/Password + Google.
- Health and smoke checks pass after production deployment.
- Legacy custom session/password code removed from active paths.
- Rollback runbook is validated and documented.
