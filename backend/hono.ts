import { trpcServer } from "@hono/trpc-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import * as crypto from "crypto";

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

app.get("/", (c) => {
  return c.json({ status: "ok", message: "ShiftVoice API is running" });
});

// --- REST endpoints for Swift client ---

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

// Auth: Register
app.post("/rest/auth/register", async (c) => {
  const body = await c.req.json();
  const { name, email, password, authMethod } = body;
  if (!name || !email || !password) {
    return c.json({ success: false, error: "Missing required fields" }, 400);
  }
  const existing = storage.getAccountByEmail(email);
  if (existing) {
    return c.json({ success: false, error: "Account already exists" });
  }
  const userId = crypto.randomUUID();
  const token = generateToken();
  storage.createAccount({
    userId,
    email: email.toLowerCase(),
    name,
    passwordHash: hashPassword(password),
    authMethod: authMethod || "email",
    createdAt: new Date().toISOString(),
  });
  storage.createSession(token, userId);
  return c.json({ success: true, userId, token, name, email: email.toLowerCase() });
});

// Auth: Login
app.post("/rest/auth/login", async (c) => {
  const body = await c.req.json();
  const { email, password } = body;
  if (!email || !password) {
    return c.json({ success: false, error: "Missing required fields" }, 400);
  }
  const account = storage.getAccountByEmail(email);
  if (!account) {
    return c.json({ success: false, error: "No account found with this email" });
  }
  if (account.passwordHash !== hashPassword(password)) {
    return c.json({ success: false, error: "Incorrect password" });
  }
  const token = generateToken();
  storage.createSession(token, account.userId);
  return c.json({ success: true, userId: account.userId, token, name: account.name, email: account.email });
});

// Auth: Google
app.post("/rest/auth/google", async (c) => {
  const body = await c.req.json();
  const { googleUserId, name, email } = body;
  if (!googleUserId || !name || !email) {
    return c.json({ success: false, error: "Missing required fields" }, 400);
  }
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

// Auth: Logout
app.post("/rest/auth/logout", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  storage.deleteSession(auth.token);
  return c.json({ success: true });
});

// Sync: Pull
app.get("/rest/sync", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const data = storage.getUserData(auth.userId);
  if (!data) {
    return c.json({ hasData: false, data: null });
  }
  return c.json({ hasData: true, data });
});

// Sync: Push
app.post("/rest/sync", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const body = await c.req.json();
  storage.setUserData(auth.userId, {
    userId: auth.userId,
    organization: body.organization,
    locations: body.locations || [],
    teamMembers: body.teamMembers || [],
    shiftNotes: body.shiftNotes || [],
    recurringIssues: body.recurringIssues || [],
    selectedLocationId: body.selectedLocationId || null,
    updatedAt: new Date().toISOString(),
  });
  return c.json({ success: true, updatedAt: new Date().toISOString() });
});

// Shift Notes: List (paginated)
app.get("/rest/shift-notes", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ notes: [], totalCount: 0, hasMore: false });

  const locationId = c.req.query("locationId") || null;
  const shiftFilter = c.req.query("shiftFilter") || null;
  const cursor = c.req.query("cursor") || null;
  const limit = Math.min(parseInt(c.req.query("limit") || "20", 10), 100);

  let notes = [...data.shiftNotes];

  if (locationId) {
    notes = notes.filter((n: any) => n.locationId === locationId);
  }
  if (shiftFilter) {
    notes = notes.filter((n: any) => {
      if (n.shiftTemplateId) return n.shiftTemplateId === shiftFilter;
      return n.shiftType === shiftFilter;
    });
  }

  notes.sort((a: any, b: any) => {
    const da = new Date(a.createdAt || 0).getTime();
    const db = new Date(b.createdAt || 0).getTime();
    return db - da;
  });

  const totalCount = notes.length;

  if (cursor) {
    const cursorIndex = notes.findIndex((n: any) => n.id === cursor);
    if (cursorIndex >= 0) {
      notes = notes.slice(cursorIndex + 1);
    }
  }

  const page = notes.slice(0, limit);
  const hasMore = notes.length > limit;
  const nextCursor = page.length > 0 ? page[page.length - 1].id : null;

  return c.json({ notes: page, totalCount, hasMore, nextCursor });
});

// Shift Notes: Create
app.post("/rest/shift-notes", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const body = await c.req.json();
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.shiftNotes.unshift(body.note);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true, noteId: body.note.id });
});

// Shift Notes: Delete
app.delete("/rest/shift-notes/:noteId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const noteId = c.req.param("noteId");
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.shiftNotes = data.shiftNotes.filter((n: any) => n.id !== noteId);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true });
});

// Locations: Create
app.post("/rest/locations", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const body = await c.req.json();
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.locations.push(body.location);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true, locationId: body.location.id });
});

// Locations: Delete
app.delete("/rest/locations/:locationId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const locationId = c.req.param("locationId");
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.locations = data.locations.filter((l: any) => l.id !== locationId);
  data.shiftNotes = data.shiftNotes.filter((n: any) => n.locationId !== locationId);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true });
});

// Team: Add
app.post("/rest/team", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const body = await c.req.json();
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.teamMembers.push(body.member);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true, memberId: body.member.id });
});

// Team: Remove
app.delete("/rest/team/:memberId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return c.json({ success: false, error: "Unauthorized" }, 401);
  const memberId = c.req.param("memberId");
  const data = storage.getUserData(auth.userId);
  if (!data) return c.json({ success: false, error: "No user data found" });
  data.teamMembers = data.teamMembers.filter((m: any) => m.id !== memberId);
  storage.setUserData(auth.userId, data);
  return c.json({ success: true });
});

export default app;
