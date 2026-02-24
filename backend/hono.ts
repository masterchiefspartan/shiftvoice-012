import { trpcServer } from "@hono/trpc-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import * as crypto from "crypto";
import * as z from "zod";
import { generateObject } from "@rork-ai/toolkit-sdk";

import { appRouter } from "./trpc/app-router";
import { createContext } from "./trpc/create-context";
import { storage } from "./storage";

const app = new Hono();

app.use("*", cors());

app.use(
  "/trpc/*",
  trpcServer({
    endpoint: "/api/trpc",
    router: appRouter,
    createContext,
  }),
);

// --- Rate Limiting ---

const rateLimitStore = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 120;

function checkRateLimit(identifier: string): { allowed: boolean; remaining: number; resetAt: number } {
  const now = Date.now();
  const entry = rateLimitStore.get(identifier);

  if (!entry || now > entry.resetAt) {
    const resetAt = now + RATE_LIMIT_WINDOW_MS;
    rateLimitStore.set(identifier, { count: 1, resetAt });
    return { allowed: true, remaining: RATE_LIMIT_MAX - 1, resetAt };
  }

  entry.count++;
  if (entry.count > RATE_LIMIT_MAX) {
    return { allowed: false, remaining: 0, resetAt: entry.resetAt };
  }
  return { allowed: true, remaining: RATE_LIMIT_MAX - entry.count, resetAt: entry.resetAt };
}

app.use("/rest/*", async (c, next) => {
  const ip = c.req.header("x-forwarded-for") || c.req.header("x-real-ip") || "unknown";
  const userId = c.req.header("x-user-id") || ip;
  const result = checkRateLimit(userId);

  c.header("X-RateLimit-Limit", String(RATE_LIMIT_MAX));
  c.header("X-RateLimit-Remaining", String(result.remaining));
  c.header("X-RateLimit-Reset", String(Math.ceil(result.resetAt / 1000)));

  if (!result.allowed) {
    return c.json({ success: false, error: "Rate limit exceeded. Try again later.", code: "RATE_LIMITED" }, 429);
  }
  await next();
});

// --- Validation Schemas ---

const registerSchema = z.object({
  name: z.string().min(2, "Name must be at least 2 characters"),
  email: z.string().email("Invalid email address"),
  password: z.string().min(8, "Password must be at least 8 characters"),
  authMethod: z.enum(["email", "google"]).default("email"),
});

const loginSchema = z.object({
  email: z.string().email("Invalid email address"),
  password: z.string().min(1, "Password is required"),
});

const googleAuthSchema = z.object({
  googleUserId: z.string().min(1),
  name: z.string().min(1),
  email: z.string().email(),
});

const shiftNoteSchema = z.object({
  id: z.string().min(1),
  authorId: z.string().optional(),
  authorName: z.string().optional(),
  authorInitials: z.string().optional(),
  locationId: z.string().optional(),
  shiftType: z.string().optional(),
  shiftTemplateId: z.string().nullable().optional(),
  rawTranscript: z.string().optional(),
  audioUrl: z.string().nullable().optional(),
  audioDuration: z.number().min(0).optional(),
  summary: z.string().optional(),
  categorizedItems: z.array(z.any()).optional(),
  actionItems: z.array(z.any()).optional(),
  photoUrls: z.array(z.string()).optional(),
  acknowledgments: z.array(z.any()).optional(),
  voiceReplies: z.array(z.any()).optional(),
  createdAt: z.string().optional(),
  isSynced: z.boolean().optional(),
});

const locationSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1, "Location name is required"),
  address: z.string().optional().default(""),
  timezone: z.string().optional().default("America/New_York"),
  openingTime: z.string().optional().default("06:00"),
  midTime: z.string().optional().default("14:00"),
  closingTime: z.string().optional().default("22:00"),
  managerIds: z.array(z.string()).optional().default([]),
});

const teamMemberSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(1, "Name is required"),
  email: z.string().email("Invalid email"),
  role: z.string().optional().default("Manager"),
  roleTemplateId: z.string().nullable().optional(),
  locationIds: z.array(z.string()).optional().default([]),
  inviteStatus: z.string().optional().default("Pending"),
  avatarInitials: z.string().optional(),
});

const actionItemUpdateSchema = z.object({
  status: z.enum(["Open", "In Progress", "Resolved"]),
});

const syncPushSchema = z.object({
  organization: z.any().optional(),
  locations: z.array(z.any()).optional(),
  teamMembers: z.array(z.any()).optional(),
  shiftNotes: z.array(z.any()).optional(),
  recurringIssues: z.array(z.any()).optional(),
  selectedLocationId: z.string().nullable().optional(),
});

// --- Helpers ---

function hashPassword(password: string): string {
  return crypto.createHash("sha256").update(password).digest("hex");
}

function generateToken(): string {
  return crypto.randomBytes(32).toString("base64url");
}

function authMiddleware(c: any): { userId: string; token: string } | null {
  const authHeader = c.req.header("authorization");
  const token = authHeader?.replace("Bearer ", "");
  const userId = c.req.header("x-user-id");
  if (!token || !userId) return null;
  const validUserId = storage.validateSession(token);
  if (!validUserId || validUserId !== userId) return null;
  return { userId, token };
}

function validateBody<T>(schema: z.ZodType<T>, data: unknown): { success: true; data: T } | { success: false; error: string; details: any[] } {
  const result = schema.safeParse(data);
  if (result.success) {
    return { success: true, data: result.data };
  }
  const details = result.error.issues.map((i: any) => ({
    path: i.path.join("."),
    message: i.message,
  }));
  return { success: false, error: details[0]?.message || "Validation failed", details };
}

function errorResponse(c: any, status: number, error: string, code?: string) {
  return c.json({ success: false, error, code: code || "ERROR" }, status);
}

// --- Health ---

app.get("/", (c) => {
  return c.json({ status: "ok", message: "ShiftVoice API is running", stats: storage.getStats() });
});

// --- Auth Endpoints ---

app.post("/rest/auth/register", async (c) => {
  const body = await c.req.json();
  const validation = validateBody(registerSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }
  const { name, email, password, authMethod } = validation.data;

  const existing = storage.getAccountByEmail(email);
  if (existing) {
    return c.json({ success: false, error: "Account already exists", code: "ACCOUNT_EXISTS" });
  }

  const userId = crypto.randomUUID();
  const token = generateToken();
  storage.createAccount({
    userId,
    email: email.toLowerCase(),
    name,
    passwordHash: hashPassword(password),
    authMethod,
    createdAt: new Date().toISOString(),
  });
  storage.createSession(token, userId);
  return c.json({ success: true, userId, token, name, email: email.toLowerCase() });
});

app.post("/rest/auth/login", async (c) => {
  const body = await c.req.json();
  const validation = validateBody(loginSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }
  const { email, password } = validation.data;

  const account = storage.getAccountByEmail(email);
  if (!account) {
    return c.json({ success: false, error: "No account found with this email", code: "NOT_FOUND" });
  }
  if (account.passwordHash !== hashPassword(password)) {
    return c.json({ success: false, error: "Incorrect password", code: "INVALID_PASSWORD" });
  }
  const token = generateToken();
  storage.createSession(token, account.userId);
  return c.json({ success: true, userId: account.userId, token, name: account.name, email: account.email });
});

app.post("/rest/auth/google", async (c) => {
  const body = await c.req.json();
  const validation = validateBody(googleAuthSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }
  const { googleUserId, name, email } = validation.data;

  let account = storage.getAccountByEmail(email);
  const token = generateToken();
  if (!account) {
    storage.createAccount({
      userId: googleUserId,
      email: email.toLowerCase(),
      name,
      passwordHash: "",
      authMethod: "google",
      createdAt: new Date().toISOString(),
    });
    storage.createSession(token, googleUserId);
    return c.json({ success: true, userId: googleUserId, token, name, email: email.toLowerCase() });
  }
  storage.createSession(token, account.userId);
  return c.json({ success: true, userId: account.userId, token, name: account.name, email: account.email });
});

app.post("/rest/auth/logout", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");
  storage.deleteSession(auth.token);
  return c.json({ success: true });
});

// --- Sync Endpoints (backward compatible + delta) ---

app.get("/rest/sync", async (c) => {
  try {
    const auth = authMiddleware(c);
    if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

    const updatedSince = c.req.query("updatedSince") || null;
    const data = storage.getUserData(auth.userId);

    if (!data) {
      return c.json({ hasData: false, data: null });
    }

    if (updatedSince) {
      const since = new Date(updatedSince).getTime();
      const filteredData = {
        ...data,
        locations: (data.locations || []).filter((l) => {
          try { return new Date(l.updatedAt).getTime() > since; } catch { return true; }
        }),
        teamMembers: (data.teamMembers || []).filter((m) => {
          try { return new Date(m.updatedAt).getTime() > since; } catch { return true; }
        }),
        shiftNotes: (data.shiftNotes || []).filter((n) => {
          try { return new Date(n.updatedAt).getTime() > since; } catch { return true; }
        }),
        recurringIssues: (data.recurringIssues || []).filter((i) => {
          try { return new Date(i.updatedAt).getTime() > since; } catch { return true; }
        }),
      };
      return c.json({ hasData: true, data: filteredData, isDelta: true });
    }

    return c.json({ hasData: true, data });
  } catch (error: any) {
    console.error("Sync pull error:", error?.message || error);
    return errorResponse(c, 500, "Sync failed", "SYNC_ERROR");
  }
});

app.post("/rest/sync", async (c) => {
  try {
    const auth = authMiddleware(c);
    if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

    const body = await c.req.json();
    const validation = validateBody(syncPushSchema, body);
    if (!validation.success) {
      return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
    }

    storage.setUserData(auth.userId, validation.data);
    return c.json({ success: true, updatedAt: new Date().toISOString() });
  } catch (error: any) {
    console.error("Sync push error:", error?.message || error);
    return errorResponse(c, 500, "Sync failed", "SYNC_ERROR");
  }
});

// --- Shift Notes: Paginated List ---

app.get("/rest/shift-notes", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const locationId = c.req.query("locationId") || null;
  const shiftFilter = c.req.query("shiftFilter") || null;
  const cursor = c.req.query("cursor") || null;
  const limit = Math.min(parseInt(c.req.query("limit") || "20", 10), 100);
  const updatedSince = c.req.query("updatedSince") || null;

  const result = storage.getShiftNotes(auth.userId, { locationId, shiftFilter, cursor, limit, updatedSince });
  return c.json(result);
});

// --- Shift Notes: Create ---

app.post("/rest/shift-notes", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const body = await c.req.json();
  const validation = validateBody(z.object({ note: shiftNoteSchema }), body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const note = validation.data.note;
  storage.upsertShiftNote({
    ...note,
    ownerId: auth.userId,
    authorId: note.authorId || auth.userId,
    authorName: note.authorName || "",
    authorInitials: note.authorInitials || "",
    locationId: note.locationId || "",
    shiftType: note.shiftType || "Closing",
    shiftTemplateId: note.shiftTemplateId || null,
    rawTranscript: note.rawTranscript || "",
    audioUrl: note.audioUrl || null,
    audioDuration: note.audioDuration || 0,
    summary: note.summary || "",
    categorizedItems: note.categorizedItems || [],
    actionItems: note.actionItems || [],
    photoUrls: note.photoUrls || [],
    acknowledgments: note.acknowledgments || [],
    voiceReplies: note.voiceReplies || [],
    createdAt: note.createdAt || new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    isSynced: note.isSynced ?? true,
  });

  return c.json({ success: true, noteId: note.id });
});

// --- Shift Notes: Update ---

app.patch("/rest/shift-notes/:noteId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const noteId = c.req.param("noteId");
  const existing = storage.getShiftNote(noteId);
  if (!existing || existing.ownerId !== auth.userId) {
    return errorResponse(c, 404, "Note not found", "NOT_FOUND");
  }

  const body = await c.req.json();
  const updated = { ...existing, ...body, id: noteId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
  storage.upsertShiftNote(updated);

  return c.json({ success: true, noteId });
});

// --- Shift Notes: Update Action Item Status ---

app.patch("/rest/shift-notes/:noteId/action-items/:actionItemId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const noteId = c.req.param("noteId");
  const actionItemId = c.req.param("actionItemId");

  const note = storage.getShiftNote(noteId);
  if (!note || note.ownerId !== auth.userId) {
    return errorResponse(c, 404, "Note not found", "NOT_FOUND");
  }

  const body = await c.req.json();
  const validation = validateBody(actionItemUpdateSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const itemIndex = note.actionItems.findIndex((a: any) => a.id === actionItemId);
  if (itemIndex === -1) {
    return errorResponse(c, 404, "Action item not found", "NOT_FOUND");
  }

  note.actionItems[itemIndex].status = validation.data.status;
  storage.upsertShiftNote(note);

  return c.json({ success: true, noteId, actionItemId, status: validation.data.status });
});

// --- Shift Notes: Add Acknowledgment ---

app.post("/rest/shift-notes/:noteId/acknowledge", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const noteId = c.req.param("noteId");
  const note = storage.getShiftNote(noteId);
  if (!note || note.ownerId !== auth.userId) {
    return errorResponse(c, 404, "Note not found", "NOT_FOUND");
  }

  const body = await c.req.json();
  const alreadyAcked = note.acknowledgments.some((a: any) => a.userId === body.userId);
  if (alreadyAcked) {
    return c.json({ success: true, noteId, message: "Already acknowledged" });
  }

  note.acknowledgments.push({
    id: body.id || crypto.randomUUID(),
    userId: body.userId || auth.userId,
    userName: body.userName || "",
    timestamp: body.timestamp || new Date().toISOString(),
  });
  storage.upsertShiftNote(note);

  return c.json({ success: true, noteId });
});

// --- Shift Notes: Delete ---

app.delete("/rest/shift-notes/:noteId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const noteId = c.req.param("noteId");
  const note = storage.getShiftNote(noteId);
  if (note && note.ownerId !== auth.userId) {
    return errorResponse(c, 403, "Forbidden", "FORBIDDEN");
  }

  storage.deleteShiftNote(noteId);
  return c.json({ success: true });
});

// --- Locations: Create ---

app.post("/rest/locations", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const body = await c.req.json();
  const validation = validateBody(z.object({ location: locationSchema }), body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const loc = validation.data.location;
  storage.upsertLocation({
    ...loc,
    ownerId: auth.userId,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });

  return c.json({ success: true, locationId: loc.id });
});

// --- Locations: Update ---

app.patch("/rest/locations/:locationId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const locationId = c.req.param("locationId");
  const existing = storage.getLocation(locationId);
  if (!existing || existing.ownerId !== auth.userId) {
    return errorResponse(c, 404, "Location not found", "NOT_FOUND");
  }

  const body = await c.req.json();
  const updated = { ...existing, ...body, id: locationId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
  storage.upsertLocation(updated);

  return c.json({ success: true, locationId });
});

// --- Locations: Delete ---

app.delete("/rest/locations/:locationId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const locationId = c.req.param("locationId");
  const existing = storage.getLocation(locationId);
  if (existing && existing.ownerId !== auth.userId) {
    return errorResponse(c, 403, "Forbidden", "FORBIDDEN");
  }

  storage.deleteLocation(locationId);
  return c.json({ success: true });
});

// --- Team: Add ---

app.post("/rest/team", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const body = await c.req.json();
  const validation = validateBody(z.object({ member: teamMemberSchema }), body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const member = validation.data.member;
  storage.upsertTeamMember({
    ...member,
    ownerId: auth.userId,
    roleTemplateId: member.roleTemplateId || null,
    avatarInitials: member.avatarInitials || member.name.split(" ").map((p: string) => p[0]).join("").slice(0, 2).toUpperCase(),
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });

  return c.json({ success: true, memberId: member.id });
});

// --- Team: Update ---

app.patch("/rest/team/:memberId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const memberId = c.req.param("memberId");
  const members = storage.getTeamMembers(auth.userId);
  const existing = members.find((m) => m.id === memberId);
  if (!existing) {
    return errorResponse(c, 404, "Team member not found", "NOT_FOUND");
  }

  const body = await c.req.json();
  const updated = { ...existing, ...body, id: memberId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
  storage.upsertTeamMember(updated);

  return c.json({ success: true, memberId });
});

// --- Team: Remove ---

app.delete("/rest/team/:memberId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const memberId = c.req.param("memberId");
  storage.deleteTeamMember(memberId);
  return c.json({ success: true });
});

// --- AI Transcript Structuring ---

const structureTranscriptSchema = z.object({
  transcript: z.string().min(1, "Transcript is required"),
  businessType: z.string().optional().default("restaurant"),
  availableCategories: z.array(z.string()).optional(),
});

const structuredNoteSchema = z.object({
  summary: z.string().describe("A concise 1-2 sentence summary of the entire recording"),
  items: z.array(
    z.object({
      content: z.string().describe("The specific issue or observation described, in clear actionable language"),
      category: z.enum([
        "86'd Items", "Equipment", "Guest Issues", "Staff Notes",
        "Reservations/VIP", "Inventory", "Maintenance", "Health & Safety",
        "General", "Incident Report"
      ]).describe("The most appropriate category for this item"),
      urgency: z.enum(["Immediate", "Next Shift", "This Week", "FYI"]).describe("How urgent this item is"),
      actionRequired: z.boolean().describe("Whether this item needs someone to take action"),
      actionTask: z.string().optional().describe("If actionRequired is true, a specific task description for what needs to be done"),
    })
  ).describe("Each distinct issue, observation, or handoff item mentioned in the transcript. Split into SEPARATE items - one per distinct topic. Do NOT group multiple topics together."),
});

app.post("/rest/structure-transcript", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const body = await c.req.json();
  const validation = validateBody(structureTranscriptSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const { transcript, businessType } = validation.data;

  try {
    const result = await generateObject({
      messages: [
        {
          role: "user",
          content: `You are an expert shift handoff assistant for a ${businessType} business. Your job is to take a raw voice transcript from a shift worker and structure it into separate, actionable items.

CRITICAL RULES:
1. Split the transcript into INDIVIDUAL items - one per distinct topic, issue, or observation
2. If someone mentions 3 different things (e.g. a broken fryer, low napkin stock, and a guest complaint), create 3 SEPARATE items
3. Each item's "content" should be a clear, specific description of that one issue - NOT the entire transcript
4. Assign the most accurate category and urgency level to each item independently
5. If an item needs follow-up action, set actionRequired to true and write a specific actionTask
6. The summary should cover ALL items briefly in 1-2 sentences
7. Never combine unrelated topics into a single item
8. Use the worker's actual words/details, don't genericize them

Here is the transcript to structure:

"${transcript}"`
        }
      ],
      schema: structuredNoteSchema,
    });

    return c.json({ success: true, structured: result });
  } catch (error: any) {
    console.error("AI structuring failed:", error?.message || error);
    return c.json({ success: false, error: "AI structuring unavailable", code: "AI_ERROR" }, 500);
  }
});

export default app;
