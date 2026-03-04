import { trpcServer } from "@hono/trpc-server";
import { Hono } from "hono";
import { cors } from "hono/cors";
import * as crypto from "crypto";
import * as z from "zod";
import { generateObject, generateText } from "@rork-ai/toolkit-sdk";

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
  name: z.string().min(2, "Name must be at least 2 characters").max(100, "Name must be under 100 characters"),
  email: z.string().email("Invalid email address"),
  password: z.string()
    .min(8, "Password must be at least 8 characters")
    .refine((p) => /[a-zA-Z]/.test(p), { message: "Password must contain at least one letter" })
    .refine((p) => /[0-9]/.test(p), { message: "Password must contain at least one number" }),
  authMethod: z.enum(["email", "google"]).default("email"),
});

const loginSchema = z.object({
  email: z.string().email("Invalid email address"),
  password: z.string().min(1, "Password is required"),
});

const googleAuthSchema = z.object({
  googleUserId: z.string().min(1),
  name: z.string().min(2, "Name must be at least 2 characters").max(100, "Name must be under 100 characters"),
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
  visibility: z.enum(["team", "private"]).optional().default("team"),
  isSynced: z.boolean().optional(),
});

const locationSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(2, "Name must be at least 2 characters").max(100, "Name must be under 100 characters"),
  address: z.string().optional().default(""),
  timezone: z.string().optional().default("America/New_York"),
  openingTime: z.string().optional().default("06:00"),
  midTime: z.string().optional().default("14:00"),
  closingTime: z.string().optional().default("22:00"),
  managerIds: z.array(z.string()).optional().default([]),
});

const teamMemberSchema = z.object({
  id: z.string().min(1),
  name: z.string().min(2, "Name must be at least 2 characters").max(100, "Name must be under 100 characters"),
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

// --- Seed Data ---

function seedDemoData() {
  const demoUserId = "demo_user_001";
  const existing = storage.getAccountByEmail("demo@shiftvoice.app");
  if (existing) return;

  storage.createAccount({
    userId: demoUserId,
    email: "demo@shiftvoice.app",
    name: "Marcus Rivera",
    passwordHash: hashPassword("demo1234"),
    authMethod: "email",
    createdAt: new Date().toISOString(),
  });

  const locIds = ["loc_001", "loc_002", "loc_003"];
  const locNames = ["The Ember Room", "Saltwater Kitchen", "Rooftop Social"];
  const locAddresses = ["234 W 4th St, New York, NY", "89 Ocean Ave, Brooklyn, NY", "1200 Broadway, New York, NY"];

  const teamData = [
    { id: "user_001", name: "Marcus Rivera", email: "marcus@riverahg.com", role: "Owner", initials: "MR", locs: locIds },
    { id: "user_002", name: "Sarah Chen", email: "sarah@riverahg.com", role: "General Manager", initials: "SC", locs: ["loc_001"] },
    { id: "user_003", name: "Devon Williams", email: "devon@riverahg.com", role: "Manager", initials: "DW", locs: ["loc_001"] },
    { id: "user_004", name: "Ava Torres", email: "ava@riverahg.com", role: "Shift Lead", initials: "AT", locs: ["loc_001"] },
    { id: "user_005", name: "James Park", email: "james@riverahg.com", role: "General Manager", initials: "JP", locs: ["loc_002"] },
    { id: "user_006", name: "Nia Johnson", email: "nia@riverahg.com", role: "Manager", initials: "NJ", locs: ["loc_002"] },
    { id: "user_007", name: "Carlos Mendez", email: "carlos@riverahg.com", role: "Manager", initials: "CM", locs: ["loc_003"] },
  ];

  storage.upsertOrganization({
    id: "org_001",
    ownerId: demoUserId,
    name: "Rivera Hospitality Group",
    plan: "Professional",
    industryType: "Restaurant",
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  });

  for (let i = 0; i < locIds.length; i++) {
    storage.upsertLocation({
      id: locIds[i],
      ownerId: demoUserId,
      name: locNames[i],
      address: locAddresses[i],
      timezone: "America/New_York",
      openingTime: "06:00",
      midTime: "14:00",
      closingTime: "22:00",
      managerIds: teamData.filter((t) => t.locs.includes(locIds[i])).map((t) => t.id),
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
  }

  for (const t of teamData) {
    storage.upsertTeamMember({
      id: t.id,
      ownerId: demoUserId,
      name: t.name,
      email: t.email,
      role: t.role,
      roleTemplateId: null,
      locationIds: t.locs,
      inviteStatus: "Accepted",
      avatarInitials: t.initials,
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    });
  }

  const now = Date.now();
  const h = (hours: number) => new Date(now - hours * 3600_000).toISOString();

  const notes: Array<{
    id: string; author: typeof teamData[0]; loc: number; shift: string; hours: number;
    transcript: string; duration: number; summary: string;
    items: Array<{ cat: string; content: string; urgency: string }>;
    actions: Array<{ task: string; cat: string; urgency: string; status?: string; assignee?: string }>;
    acks?: Array<{ userId: string; userName: string; hoursAgo: number }>;
    replies?: Array<{ authorId: string; authorName: string; text: string; hoursAgo: number }>;
  }> = [
    {
      id: "note_001", author: teamData[2], loc: 0, shift: "Closing", hours: 3, duration: 47,
      transcript: "Alright closing notes for tonight. We 86'd the salmon around 8pm, supplier shorted us again. Walk-in compressor is making that noise again, third time this week. Had a comp on table 14, guest found hair in their pasta, comped the whole table's entrees. Big night though, 247 covers. Also the POS terminal at station 3 is frozen again, needs a full restart. Oh and heads up, we have a 20-top VIP coming in tomorrow at 7, it's the Brennan anniversary party, they want the private dining room set with candles and the special menu.",
      summary: "Busy closing with 247 covers. Salmon 86'd due to supplier shortage. Walk-in compressor issue recurring (3rd time). Comped table 14 for hair in pasta. POS station 3 frozen. VIP 20-top Brennan party tomorrow at 7pm.",
      items: [
        { cat: "86'd Items", content: "Salmon — supplier shorted delivery, 86'd at 8pm", urgency: "Next Shift" },
        { cat: "Equipment", content: "Walk-in compressor making noise again — 3rd time this week", urgency: "Immediate" },
        { cat: "Equipment", content: "POS terminal station 3 frozen, needs full restart", urgency: "Next Shift" },
        { cat: "Guest Issues", content: "Table 14 — hair in pasta, comped all entrees", urgency: "FYI" },
        { cat: "Reservations/VIP", content: "Brennan anniversary party — 20-top VIP, tomorrow 7pm, private dining room", urgency: "Immediate" },
      ],
      actions: [
        { task: "Call seafood supplier re: salmon shortage", cat: "86'd Items", urgency: "Next Shift", assignee: "Sarah Chen" },
        { task: "Schedule walk-in compressor repair — recurring issue", cat: "Equipment", urgency: "Immediate" },
        { task: "Restart POS terminal station 3", cat: "Equipment", urgency: "Next Shift" },
        { task: "Set up private dining room for Brennan party — candles, special menu", cat: "Reservations/VIP", urgency: "Immediate" },
      ],
      acks: [{ userId: "user_002", userName: "Sarah Chen", hoursAgo: 1 }],
    },
    {
      id: "note_002", author: teamData[1], loc: 0, shift: "Mid", hours: 8, duration: 32,
      transcript: "Mid shift update. Lunch was solid, 89 covers. The new server Kayla is doing great, really picking up the floor fast. FYI the ice machine is leaking again by the service station, put a bucket under it for now. Health inspector is scheduled for next Tuesday, need to make sure all temp logs are current. Also restocked the bar with the wine delivery that came in.",
      summary: "Solid lunch with 89 covers. New server Kayla performing well. Ice machine leaking at service station. Health inspector Tuesday — ensure temp logs current. Wine delivery restocked.",
      items: [
        { cat: "Staff Notes", content: "New server Kayla doing great, picking up the floor quickly", urgency: "FYI" },
        { cat: "Maintenance", content: "Ice machine leaking at service station — bucket placed temporarily", urgency: "This Week" },
        { cat: "Health & Safety", content: "Health inspector scheduled next Tuesday — temp logs must be current", urgency: "This Week" },
        { cat: "Inventory", content: "Wine delivery received and restocked at bar", urgency: "FYI" },
      ],
      actions: [
        { task: "Fix ice machine leak at service station", cat: "Maintenance", urgency: "This Week" },
        { task: "Verify all temperature logs are current before Tuesday inspection", cat: "Health & Safety", urgency: "This Week", status: "In Progress", assignee: "Devon Williams" },
      ],
      acks: [
        { userId: "user_003", userName: "Devon Williams", hoursAgo: 5 },
        { userId: "user_004", userName: "Ava Torres", hoursAgo: 4 },
      ],
    },
    {
      id: "note_003", author: teamData[3], loc: 0, shift: "Opening", hours: 14, duration: 28,
      transcript: "Opening notes. Everything looks good from last night's close, Devon did a great job. Fryer oil in station 2 needs to be changed, it's getting dark. We're low on to-go containers, the medium ones. Produce delivery came in fine, everything looks fresh. Reminder that the Brennan party is tonight so we need all hands on deck.",
      summary: "Clean open after last night. Fryer oil station 2 needs changing. Low on medium to-go containers. Produce delivery good. Brennan VIP party tonight.",
      items: [
        { cat: "Equipment", content: "Fryer oil station 2 getting dark — needs changing", urgency: "Next Shift" },
        { cat: "Inventory", content: "Low on medium to-go containers", urgency: "This Week" },
        { cat: "General", content: "Produce delivery received, all fresh", urgency: "FYI" },
        { cat: "Reservations/VIP", content: "Brennan VIP party tonight — all hands on deck", urgency: "Immediate" },
      ],
      actions: [
        { task: "Change fryer oil at station 2", cat: "Equipment", urgency: "Next Shift" },
        { task: "Order medium to-go containers", cat: "Inventory", urgency: "This Week" },
      ],
    },
    {
      id: "note_004", author: teamData[4], loc: 1, shift: "Closing", hours: 2, duration: 41,
      transcript: "Closing at Saltwater. Wild night, 198 covers for a Wednesday. We ran out of the lobster bisque by 7:30, had to 86 it. Two comps tonight, table 6 had an undercooked steak sent back twice, table 22 birthday dessert was forgotten. Dishwasher running slow, drain may need cleaning. Back door lock sticking again.",
      summary: "Busy Wednesday with 198 covers. Lobster bisque 86'd at 7:30. Two comps (undercooked steak, missed birthday). Dishwasher slow. Back door lock sticking.",
      items: [
        { cat: "86'd Items", content: "Lobster bisque ran out by 7:30pm", urgency: "Next Shift" },
        { cat: "Guest Issues", content: "Table 6 — undercooked steak sent back twice, comped meals", urgency: "FYI" },
        { cat: "Guest Issues", content: "Table 22 — forgot birthday dessert, comped champagne", urgency: "FYI" },
        { cat: "Equipment", content: "Dishwasher running slow — drain may need cleaning", urgency: "This Week" },
        { cat: "Maintenance", content: "Back door lock sticking again", urgency: "This Week" },
      ],
      actions: [
        { task: "Prep extra lobster bisque for tomorrow", cat: "86'd Items", urgency: "Next Shift" },
        { task: "Clean dishwasher drain", cat: "Equipment", urgency: "This Week" },
        { task: "Fix back door lock", cat: "Maintenance", urgency: "This Week" },
      ],
    },
    {
      id: "note_005", author: teamData[6], loc: 2, shift: "Closing", hours: 1, duration: 25,
      transcript: "Rooftop closing notes. Slow night due to rain, only 67 covers. Outdoor heaters on the east side are out. Beer delivery was short, missing the IPA kegs. Had to cut Happy Hour early, out of well tequila. Clean close otherwise.",
      summary: "Slow rainy night, 67 covers. Two east-side heaters out. Missing IPA kegs. Well tequila ran out early.",
      items: [
        { cat: "Equipment", content: "Two outdoor heaters (east side) won't ignite", urgency: "Next Shift" },
        { cat: "Inventory", content: "Beer delivery short — missing IPA kegs", urgency: "Next Shift" },
        { cat: "86'd Items", content: "Well tequila ran out, cut Happy Hour early", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Service east-side outdoor heaters", cat: "Equipment", urgency: "Next Shift" },
        { task: "Follow up with beer distributor re: missing IPA kegs", cat: "Inventory", urgency: "Next Shift" },
        { task: "Restock well tequila", cat: "Inventory", urgency: "Next Shift" },
      ],
    },
    {
      id: "note_006", author: teamData[2], loc: 0, shift: "Closing", hours: 27, duration: 38,
      transcript: "Another solid closing tonight. 212 covers, good energy. The flat top on station 1 has a hot spot on the left side, burns anything you put there. Server Marco called out sick for tomorrow morning, need someone to cover. The draft system on tap 4 is pouring foamy, needs to be rebalanced. Also we got a 5-star review from the couple on table 9, they loved the tasting menu.",
      summary: "212 covers. Flat top station 1 has hot spot. Marco out tomorrow AM — need cover. Tap 4 draft foamy. 5-star review from tasting menu couple.",
      items: [
        { cat: "Equipment", content: "Flat top station 1 has a hot spot on left side — burning food", urgency: "Immediate" },
        { cat: "Staff Notes", content: "Server Marco called out sick tomorrow AM — need coverage", urgency: "Immediate" },
        { cat: "Equipment", content: "Draft tap 4 pouring foamy — needs rebalancing", urgency: "Next Shift" },
        { cat: "General", content: "5-star review from table 9 couple — loved tasting menu", urgency: "FYI" },
      ],
      actions: [
        { task: "Get flat top station 1 inspected — hot spot issue", cat: "Equipment", urgency: "Immediate" },
        { task: "Find AM coverage for Marco's shift tomorrow", cat: "Staff Notes", urgency: "Immediate" },
        { task: "Rebalance draft system on tap 4", cat: "Equipment", urgency: "Next Shift" },
      ],
      acks: [{ userId: "user_002", userName: "Sarah Chen", hoursAgo: 25 }],
    },
    {
      id: "note_007", author: teamData[1], loc: 0, shift: "Opening", hours: 38, duration: 22,
      transcript: "Morning update. Walk-in temp was at 41 degrees when I checked, should be 38. Moved it down. Bread delivery came in short — only got 40 baguettes instead of 60. Prepped extra risotto base since we ran out last Friday. New host training starts at 11.",
      summary: "Walk-in temp high (41°F, adjusted). Bread delivery short by 20 baguettes. Extra risotto base prepped. New host training at 11.",
      items: [
        { cat: "Health & Safety", content: "Walk-in temperature at 41°F — adjusted to 38°F target", urgency: "Immediate" },
        { cat: "Inventory", content: "Bread delivery short — 40 baguettes instead of 60", urgency: "Next Shift" },
        { cat: "General", content: "Extra risotto base prepped after last Friday's shortage", urgency: "FYI" },
        { cat: "Staff Notes", content: "New host training starts at 11am", urgency: "FYI" },
      ],
      actions: [
        { task: "Monitor walk-in temperature — log readings every 2 hours", cat: "Health & Safety", urgency: "Immediate" },
        { task: "Contact bakery about bread shortage", cat: "Inventory", urgency: "Next Shift" },
      ],
      acks: [
        { userId: "user_003", userName: "Devon Williams", hoursAgo: 36 },
        { userId: "user_004", userName: "Ava Torres", hoursAgo: 35 },
      ],
    },
    {
      id: "note_008", author: teamData[3], loc: 0, shift: "Mid", hours: 32, duration: 19,
      transcript: "Quick mid update. We're running low on gluten-free pasta, maybe 6 portions left. The espresso machine pressure is dropping, might need descaling. Had a walkout on table 3, party of 4, no payment. Got their faces on camera though.",
      summary: "Low on GF pasta (6 portions). Espresso machine pressure dropping. Walkout table 3 party of 4 — on camera.",
      items: [
        { cat: "Inventory", content: "Gluten-free pasta running low — ~6 portions remaining", urgency: "Next Shift" },
        { cat: "Equipment", content: "Espresso machine pressure dropping — may need descaling", urgency: "This Week" },
        { cat: "Incident Report", content: "Walkout on table 3, party of 4 — captured on security camera", urgency: "Immediate" },
      ],
      actions: [
        { task: "Order gluten-free pasta — emergency restock", cat: "Inventory", urgency: "Next Shift" },
        { task: "Schedule espresso machine descaling", cat: "Equipment", urgency: "This Week" },
        { task: "File incident report for table 3 walkout — pull camera footage", cat: "Incident Report", urgency: "Immediate", status: "In Progress", assignee: "Devon Williams" },
      ],
    },
    {
      id: "note_009", author: teamData[5], loc: 1, shift: "Mid", hours: 10, duration: 35,
      transcript: "Saltwater mid shift. Lunch patio was packed, 94 covers before 2pm. The oyster delivery came in and 2 dozen were already dead, sent them back. Line cook Ricky cut his finger, minor, first aid applied and he's back on the line. The hood vent over station 3 isn't pulling well, getting smoky. We need to reprint the dessert menus, several are stained.",
      summary: "Packed patio lunch, 94 covers. Bad oysters returned (2 dozen). Minor cut for Ricky — first aid done. Hood vent station 3 weak. Dessert menus need reprinting.",
      items: [
        { cat: "Inventory", content: "2 dozen dead oysters in delivery — sent back to supplier", urgency: "Next Shift" },
        { cat: "Health & Safety", content: "Line cook Ricky minor finger cut — first aid applied, back on line", urgency: "FYI" },
        { cat: "Equipment", content: "Hood vent station 3 not pulling properly — getting smoky", urgency: "This Week" },
        { cat: "General", content: "Dessert menus stained — need reprinting", urgency: "This Week" },
      ],
      actions: [
        { task: "File complaint with oyster supplier — 2 dozen dead on arrival", cat: "Inventory", urgency: "Next Shift" },
        { task: "Schedule hood vent cleaning/inspection for station 3", cat: "Equipment", urgency: "This Week" },
        { task: "Reprint dessert menus", cat: "General", urgency: "This Week" },
      ],
    },
    {
      id: "note_010", author: teamData[4], loc: 1, shift: "Opening", hours: 56, duration: 20,
      transcript: "Saltwater opening. Floors were sticky near the bar, closing crew didn't mop properly. Dairy delivery is late, still waiting. The outdoor umbrellas need new fabric, two are torn. Reservation system shows we're booked solid for Saturday brunch, 120 covers expected.",
      summary: "Sticky floors near bar (closing crew). Dairy delivery late. Two outdoor umbrellas torn. Saturday brunch booked solid — 120 covers.",
      items: [
        { cat: "General", content: "Floors sticky near bar — closing crew didn't mop properly", urgency: "Next Shift" },
        { cat: "Inventory", content: "Dairy delivery late — still waiting", urgency: "Immediate" },
        { cat: "Maintenance", content: "Two outdoor umbrellas have torn fabric", urgency: "This Week" },
        { cat: "Reservations/VIP", content: "Saturday brunch booked solid — 120 covers expected", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Follow up on dairy delivery status", cat: "Inventory", urgency: "Immediate", status: "Resolved" },
        { task: "Order replacement umbrella fabric", cat: "Maintenance", urgency: "This Week" },
        { task: "Prep extra brunch items for Saturday's 120-cover booking", cat: "Reservations/VIP", urgency: "Next Shift" },
      ],
    },
    {
      id: "note_011", author: teamData[6], loc: 2, shift: "Opening", hours: 50, duration: 18,
      transcript: "Rooftop opening. Sound system speaker on the west side is blown. Need to order new cocktail napkins with the updated logo. The elevator inspection certificate expired last week, need to get that renewed ASAP. Otherwise clean open.",
      summary: "West speaker blown. Need new logo cocktail napkins. Elevator inspection certificate expired — renew urgently.",
      items: [
        { cat: "Equipment", content: "Sound system speaker (west side) blown out", urgency: "Next Shift" },
        { cat: "Inventory", content: "Need new cocktail napkins with updated logo", urgency: "This Week" },
        { cat: "Health & Safety", content: "Elevator inspection certificate expired last week", urgency: "Immediate" },
      ],
      actions: [
        { task: "Replace west-side speaker", cat: "Equipment", urgency: "Next Shift" },
        { task: "Order cocktail napkins with new logo", cat: "Inventory", urgency: "This Week" },
        { task: "Schedule elevator inspection renewal — certificate expired", cat: "Health & Safety", urgency: "Immediate" },
      ],
    },
    {
      id: "note_012", author: teamData[2], loc: 0, shift: "Mid", hours: 56, duration: 26,
      transcript: "Mid shift. Slow lunch, only 52 covers but we made up for it with high ticket averages. The exhaust fan in the prep area is vibrating badly. Catering order for the Thompson wedding Saturday is confirmed — 150 guests, need to start prep Thursday. Bartender Lisa wants to introduce a new fall cocktail menu, she's got some great ideas.",
      summary: "Slow lunch, 52 covers but high averages. Prep area exhaust fan vibrating. Thompson wedding catering Saturday (150 guests). Lisa proposing fall cocktail menu.",
      items: [
        { cat: "Equipment", content: "Prep area exhaust fan vibrating badly", urgency: "This Week" },
        { cat: "Reservations/VIP", content: "Thompson wedding catering Saturday — 150 guests, start prep Thursday", urgency: "Next Shift" },
        { cat: "Staff Notes", content: "Bartender Lisa wants to introduce fall cocktail menu — has ideas ready", urgency: "FYI" },
      ],
      actions: [
        { task: "Get exhaust fan in prep area inspected", cat: "Equipment", urgency: "This Week" },
        { task: "Begin Thompson wedding prep Thursday — 150 guests", cat: "Reservations/VIP", urgency: "Next Shift" },
        { task: "Schedule tasting session for Lisa's fall cocktail menu", cat: "Staff Notes", urgency: "This Week" },
      ],
    },
    {
      id: "note_013", author: teamData[3], loc: 0, shift: "Closing", hours: 51, duration: 44,
      transcript: "Big closing tonight. 278 covers, new record for a Thursday. We ran through all the ribeye by 8:45, also low on the duck confit. Bathroom on the second floor has a running toilet, super loud. Two servers got into an argument during service, pulled them aside after — it's handled but worth noting. Celebrity diner tonight, won't say who but they requested total privacy and tipped 40 percent.",
      summary: "Record Thursday: 278 covers. Ribeye sold out 8:45pm, duck confit low. 2nd floor toilet running. Server conflict handled. Celebrity diner — privacy, 40% tip.",
      items: [
        { cat: "86'd Items", content: "Ribeye sold out by 8:45pm — 278-cover night", urgency: "Next Shift" },
        { cat: "86'd Items", content: "Duck confit running very low", urgency: "Next Shift" },
        { cat: "Maintenance", content: "Second floor bathroom toilet running — very loud", urgency: "This Week" },
        { cat: "Staff Notes", content: "Two servers had argument during service — pulled aside, resolved", urgency: "FYI" },
        { cat: "Reservations/VIP", content: "Celebrity diner requested total privacy — 40% tip", urgency: "FYI" },
      ],
      actions: [
        { task: "Order extra ribeye for weekend — Thursday sold out", cat: "86'd Items", urgency: "Next Shift" },
        { task: "Prep additional duck confit", cat: "86'd Items", urgency: "Next Shift" },
        { task: "Fix running toilet — 2nd floor bathroom", cat: "Maintenance", urgency: "This Week", assignee: "Devon Williams" },
      ],
      acks: [
        { userId: "user_001", userName: "Marcus Rivera", hoursAgo: 49 },
        { userId: "user_002", userName: "Sarah Chen", hoursAgo: 48 },
      ],
    },
    {
      id: "note_014", author: teamData[4], loc: 1, shift: "Closing", hours: 26, duration: 30,
      transcript: "Saltwater closing. 156 covers, solid Tuesday. The raw bar display fridge temp is fluctuating between 36 and 42, not consistent. Manager special board is running low on dry erase markers. Server Taylor's last day is Friday, we should do something. Had a dine-and-dash attempt but the hostess caught them at the door.",
      summary: "156 covers. Raw bar fridge temp fluctuating (36-42°F). Dry erase markers low. Taylor's last day Friday. Dine-and-dash attempt caught.",
      items: [
        { cat: "Equipment", content: "Raw bar display fridge temp fluctuating 36-42°F — inconsistent", urgency: "Immediate" },
        { cat: "Inventory", content: "Specials board running low on dry erase markers", urgency: "This Week" },
        { cat: "Staff Notes", content: "Server Taylor's last day is Friday — plan something", urgency: "This Week" },
        { cat: "Incident Report", content: "Dine-and-dash attempt — hostess caught them at door", urgency: "FYI" },
      ],
      actions: [
        { task: "Get raw bar fridge serviced — temp fluctuating dangerously", cat: "Equipment", urgency: "Immediate" },
        { task: "Order dry erase markers", cat: "Inventory", urgency: "This Week", status: "Resolved" },
        { task: "Plan farewell for Taylor — last day Friday", cat: "Staff Notes", urgency: "This Week" },
      ],
    },
    {
      id: "note_015", author: teamData[5], loc: 1, shift: "Opening", hours: 80, duration: 15,
      transcript: "Quick opening notes. Everything looked clean. The fish delivery is coming at 10 instead of 8 today. We're out of lemons completely. New table numbers arrived, need to swap them out before lunch.",
      summary: "Clean open. Fish delivery delayed to 10am. Out of lemons. New table numbers arrived.",
      items: [
        { cat: "Inventory", content: "Fish delivery delayed — coming at 10am instead of 8am", urgency: "Next Shift" },
        { cat: "Inventory", content: "Completely out of lemons", urgency: "Immediate" },
        { cat: "General", content: "New table numbers arrived — need to swap before lunch", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Emergency lemon run — we're completely out", cat: "Inventory", urgency: "Immediate", status: "Resolved" },
        { task: "Swap out old table numbers before lunch service", cat: "General", urgency: "Next Shift", status: "Resolved" },
      ],
    },
    {
      id: "note_016", author: teamData[6], loc: 2, shift: "Closing", hours: 25, duration: 52,
      transcript: "Long closing at Rooftop. 189 covers, great night. We had a large bachelorette party, 16 people, they were loud but tipped well. The rooftop railing on the north side has a loose bolt, safety concern. Restroom soap dispensers are both empty downstairs. The DJ equipment needs a new cable, the left channel is cutting out. Closing inventory shows we're critically low on vodka and gin.",
      summary: "189 covers, great night. Bachelorette party of 16. North railing loose bolt (safety). Soap dispensers empty. DJ left channel cutting out. Low on vodka and gin.",
      items: [
        { cat: "Reservations/VIP", content: "Bachelorette party of 16 — loud but great tips", urgency: "FYI" },
        { cat: "Health & Safety", content: "North side rooftop railing has a loose bolt — safety hazard", urgency: "Immediate" },
        { cat: "Maintenance", content: "Downstairs restroom soap dispensers both empty", urgency: "Next Shift" },
        { cat: "Equipment", content: "DJ equipment left channel cutting out — needs new cable", urgency: "This Week" },
        { cat: "Inventory", content: "Critically low on vodka and gin", urgency: "Immediate" },
      ],
      actions: [
        { task: "Fix loose bolt on north railing ASAP — safety issue", cat: "Health & Safety", urgency: "Immediate" },
        { task: "Refill soap dispensers in downstairs restrooms", cat: "Maintenance", urgency: "Next Shift" },
        { task: "Order replacement DJ cable", cat: "Equipment", urgency: "This Week" },
        { task: "Emergency spirits order — vodka and gin critically low", cat: "Inventory", urgency: "Immediate" },
      ],
      replies: [
        { authorId: "user_001", authorName: "Marcus Rivera", text: "I'll call the contractor about the railing first thing tomorrow. Don't let anyone lean on that section tonight.", hoursAgo: 24 },
      ],
    },
    {
      id: "note_017", author: teamData[1], loc: 0, shift: "Closing", hours: 75, duration: 33,
      transcript: "Closing update. 185 covers. The pasta maker is jamming on the linguine setting, works fine for everything else. We're almost out of truffle oil, maybe 2 services worth. Got a complaint from the building about our dumpster area, says it's attracting rats. Need to address that. The new menu cards look great, customers are responding well.",
      summary: "185 covers. Pasta maker jamming on linguine. Low truffle oil (2 services). Building complaint about dumpster/rats. New menu cards well received.",
      items: [
        { cat: "Equipment", content: "Pasta maker jamming on linguine setting — other settings fine", urgency: "This Week" },
        { cat: "Inventory", content: "Truffle oil nearly out — ~2 services remaining", urgency: "Next Shift" },
        { cat: "Health & Safety", content: "Building management complaint: dumpster area attracting rats", urgency: "Immediate" },
        { cat: "General", content: "New menu cards getting positive customer feedback", urgency: "FYI" },
      ],
      actions: [
        { task: "Service pasta maker — linguine setting jamming", cat: "Equipment", urgency: "This Week" },
        { task: "Order truffle oil — 2 services left", cat: "Inventory", urgency: "Next Shift", assignee: "Ava Torres" },
        { task: "Clean dumpster area and schedule pest control", cat: "Health & Safety", urgency: "Immediate" },
      ],
      acks: [{ userId: "user_003", userName: "Devon Williams", hoursAgo: 73 }],
    },
    {
      id: "note_018", author: teamData[2], loc: 0, shift: "Opening", hours: 62, duration: 24,
      transcript: "Opening. Everything's prepped well from last night. The CO2 tank for the soda system is getting low, probably one more day. Two reservations cancelled for tonight's chef's table. The AC unit in the private dining room is blowing warm air. Also reminder: staff meeting Monday at 3pm.",
      summary: "Good prep from last night. CO2 tank low (1 day). Two chef's table cancellations. PDR AC blowing warm. Staff meeting Monday 3pm.",
      items: [
        { cat: "Inventory", content: "CO2 tank for soda system getting low — ~1 day remaining", urgency: "Next Shift" },
        { cat: "Reservations/VIP", content: "Two chef's table reservations cancelled for tonight", urgency: "FYI" },
        { cat: "Equipment", content: "Private dining room AC blowing warm air", urgency: "Immediate" },
        { cat: "Staff Notes", content: "Staff meeting Monday at 3pm", urgency: "FYI" },
      ],
      actions: [
        { task: "Order CO2 tank replacement — 1 day left on soda system", cat: "Inventory", urgency: "Next Shift" },
        { task: "Fix AC in private dining room — blowing warm", cat: "Equipment", urgency: "Immediate" },
      ],
    },
    {
      id: "note_019", author: teamData[4], loc: 1, shift: "Mid", hours: 34, duration: 29,
      transcript: "Saltwater mid update. Brunch was insane, 142 covers. Bottomless mimosa promo is too popular, we went through 9 cases of prosecco. The patio awning is stuck halfway, can't retract fully. One of the bartenders dropped a full bottle of Hendrick's, that's 80 bucks gone. Server scheduling for next week needs attention, we're understaffed Saturday.",
      summary: "Insane brunch, 142 covers. Mimosa promo used 9 cases prosecco. Patio awning stuck. Dropped Hendrick's bottle ($80). Saturday understaffed.",
      items: [
        { cat: "Inventory", content: "Bottomless mimosa promo burned through 9 cases of prosecco", urgency: "Next Shift" },
        { cat: "Maintenance", content: "Patio awning stuck halfway — can't fully retract", urgency: "This Week" },
        { cat: "Incident Report", content: "Bartender dropped full Hendrick's bottle — $80 loss", urgency: "FYI" },
        { cat: "Staff Notes", content: "Saturday schedule understaffed — need more coverage", urgency: "Immediate" },
      ],
      actions: [
        { task: "Order extra prosecco for mimosa promo", cat: "Inventory", urgency: "Next Shift" },
        { task: "Get patio awning mechanism serviced", cat: "Maintenance", urgency: "This Week" },
        { task: "Fill Saturday schedule gaps — need 2 more servers", cat: "Staff Notes", urgency: "Immediate" },
      ],
    },
    {
      id: "note_020", author: teamData[3], loc: 0, shift: "Mid", hours: 8, duration: 21,
      transcript: "Quick mid update Ember Room. Lunch was 76 covers. The reservation system went down for about 20 minutes around noon, we used the paper backup. All good now. Prep cook Miguel is requesting next Friday off. The wine by the glass Chardonnay is almost kicked.",
      summary: "76 covers. Reservation system down 20 min (paper backup used). Miguel requesting Friday off. Chardonnay BTG almost out.",
      items: [
        { cat: "Equipment", content: "Reservation system went down ~20 min at noon — paper backup used", urgency: "This Week" },
        { cat: "Staff Notes", content: "Prep cook Miguel requesting next Friday off", urgency: "This Week" },
        { cat: "Inventory", content: "Chardonnay by-the-glass almost kicked", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Check reservation system stability — had 20-min outage", cat: "Equipment", urgency: "This Week" },
        { task: "Process Miguel's Friday PTO request", cat: "Staff Notes", urgency: "This Week" },
        { task: "Swap Chardonnay BTG keg — almost empty", cat: "Inventory", urgency: "Next Shift" },
      ],
    },
    {
      id: "note_021", author: teamData[5], loc: 1, shift: "Closing", hours: 50, duration: 37,
      transcript: "Saltwater closing. 171 covers, strong Monday. The grease trap is backing up, starting to smell. We absolutely need to get that cleaned this week. Hostess stand iPad screen is cracked, still works but looks bad. Had two food allergy incidents tonight — both handled properly with the allergy protocol. Remind the team to ALWAYS ask about allergies.",
      summary: "171 covers. Grease trap backing up/smelling. Hostess iPad cracked. Two allergy incidents — protocol followed.",
      items: [
        { cat: "Maintenance", content: "Grease trap backing up and starting to smell", urgency: "Immediate" },
        { cat: "Equipment", content: "Hostess stand iPad screen cracked — functional but looks bad", urgency: "This Week" },
        { cat: "Health & Safety", content: "Two food allergy incidents tonight — allergy protocol followed correctly", urgency: "FYI" },
        { cat: "Staff Notes", content: "Remind team to ALWAYS ask about allergies upfront", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Schedule grease trap cleaning THIS WEEK — backing up", cat: "Maintenance", urgency: "Immediate" },
        { task: "Replace hostess stand iPad or get screen fixed", cat: "Equipment", urgency: "This Week" },
        { task: "Send allergy protocol reminder to all staff", cat: "Health & Safety", urgency: "Next Shift" },
      ],
    },
    {
      id: "note_022", author: teamData[6], loc: 2, shift: "Mid", hours: 73, duration: 15,
      transcript: "Rooftop mid shift. Light crowd, 38 covers, typical weekday lunch. The water feature fountain pump died. Plants on the south terrace need watering badly. Otherwise quiet.",
      summary: "Light lunch, 38 covers. Fountain pump died. South terrace plants need watering.",
      items: [
        { cat: "Maintenance", content: "Water feature fountain pump died", urgency: "This Week" },
        { cat: "Maintenance", content: "South terrace plants wilting — need watering urgently", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Replace fountain pump", cat: "Maintenance", urgency: "This Week" },
        { task: "Water south terrace plants — they're wilting", cat: "Maintenance", urgency: "Next Shift", status: "Resolved" },
      ],
    },
    {
      id: "note_023", author: teamData[1], loc: 0, shift: "Mid", hours: 56, duration: 42,
      transcript: "Ember Room mid shift. 98 covers for lunch, above average. The hand dryer in the men's room stopped working. We received the new glassware shipment but 12 of the wine glasses arrived broken. Need to file a claim. Line cook position still open, we've had 3 interviews but no one's been right. The community board inspector stopped by and our permit is up to date, so that's good.",
      summary: "98 covers lunch. Men's room hand dryer broken. 12 wine glasses arrived broken — file claim. Line cook position still open. Permit confirmed current.",
      items: [
        { cat: "Maintenance", content: "Men's room hand dryer stopped working", urgency: "This Week" },
        { cat: "Inventory", content: "12 wine glasses from new shipment arrived broken — need claim", urgency: "Next Shift" },
        { cat: "Staff Notes", content: "Line cook position open — 3 interviews done, no hire yet", urgency: "This Week" },
        { cat: "General", content: "Community board inspector confirmed permit is current", urgency: "FYI" },
      ],
      actions: [
        { task: "Fix men's room hand dryer", cat: "Maintenance", urgency: "This Week" },
        { task: "File damage claim for 12 broken wine glasses", cat: "Inventory", urgency: "Next Shift" },
        { task: "Schedule more line cook interviews — still need to fill position", cat: "Staff Notes", urgency: "This Week" },
      ],
    },
    {
      id: "note_024", author: teamData[2], loc: 0, shift: "Closing", hours: 99, duration: 31,
      transcript: "Ember Room Friday closing. Incredible night, 301 covers. Set a new all-time record. Kitchen handled it like champs. We did run out of the chocolate lava cake and the sea bass. The printer at station 2 ran out of paper mid-rush, chaos for about 10 minutes. Grease on the floor near the fryer station, someone almost slipped. Cleaned it up immediately. Private event inquiry for December 15th, 80 guests.",
      summary: "ALL-TIME RECORD: 301 covers! 86'd chocolate lava cake & sea bass. Station 2 printer out of paper mid-rush. Grease spill near fryer (cleaned). Dec 15 private event inquiry, 80 guests.",
      items: [
        { cat: "86'd Items", content: "Chocolate lava cake sold out — record 301-cover night", urgency: "Next Shift" },
        { cat: "86'd Items", content: "Sea bass sold out", urgency: "Next Shift" },
        { cat: "Equipment", content: "Station 2 printer ran out of paper mid-rush — 10 min disruption", urgency: "Next Shift" },
        { cat: "Health & Safety", content: "Grease spill near fryer — someone nearly slipped, cleaned immediately", urgency: "FYI" },
        { cat: "Reservations/VIP", content: "Private event inquiry: December 15th, 80 guests", urgency: "This Week" },
      ],
      actions: [
        { task: "Double prep on chocolate lava cake and sea bass for next weekend", cat: "86'd Items", urgency: "Next Shift", status: "Resolved" },
        { task: "Stock extra printer paper at all stations", cat: "Equipment", urgency: "Next Shift", status: "Resolved" },
        { task: "Follow up on December 15th private event — 80 guests", cat: "Reservations/VIP", urgency: "This Week" },
      ],
      acks: [
        { userId: "user_001", userName: "Marcus Rivera", hoursAgo: 97 },
        { userId: "user_002", userName: "Sarah Chen", hoursAgo: 96 },
        { userId: "user_004", userName: "Ava Torres", hoursAgo: 95 },
      ],
    },
    {
      id: "note_025", author: teamData[4], loc: 1, shift: "Closing", hours: 74, duration: 28,
      transcript: "Saltwater Thursday closing. 167 covers. The clam chowder batch was off today, pulled it from the menu at 6pm. Wine fridge door seal is coming loose on the left side. The new cocktail menu is a hit, especially the smoked old fashioned. Server training session needed on the new POS update that's coming Monday.",
      summary: "167 covers. Clam chowder pulled at 6pm (off batch). Wine fridge door seal loose. New cocktail menu popular. POS training needed for Monday update.",
      items: [
        { cat: "86'd Items", content: "Clam chowder pulled from menu at 6pm — off batch", urgency: "Next Shift" },
        { cat: "Equipment", content: "Wine fridge left door seal coming loose", urgency: "This Week" },
        { cat: "General", content: "New cocktail menu a hit — smoked old fashioned very popular", urgency: "FYI" },
        { cat: "Staff Notes", content: "POS update Monday — staff needs training session", urgency: "Next Shift" },
      ],
      actions: [
        { task: "Review clam chowder recipe/process — batch was off", cat: "86'd Items", urgency: "Next Shift" },
        { task: "Fix wine fridge door seal — left side", cat: "Equipment", urgency: "This Week" },
        { task: "Schedule POS update training before Monday", cat: "Staff Notes", urgency: "Next Shift" },
      ],
    },
  ];

  for (const n of notes) {
    const noteTimestamp = h(n.hours);
    storage.upsertShiftNote({
      id: n.id,
      ownerId: demoUserId,
      authorId: n.author.id,
      authorName: n.author.name,
      authorInitials: n.author.initials,
      locationId: locIds[n.loc],
      shiftType: n.shift,
      shiftTemplateId: null,
      rawTranscript: n.transcript,
      audioUrl: null,
      audioDuration: n.duration,
      summary: n.summary,
      categorizedItems: n.items.map((item, idx) => ({
        id: `${n.id}_ci_${idx}`,
        category: item.cat,
        categoryTemplateId: null,
        content: item.content,
        urgency: item.urgency,
        isResolved: false,
      })),
      actionItems: n.actions.map((action, idx) => ({
        id: `${n.id}_ai_${idx}`,
        task: action.task,
        category: action.cat,
        categoryTemplateId: null,
        urgency: action.urgency,
        status: action.status || "Open",
        assignee: action.assignee || null,
        assigneeId: action.assignee ? teamData.find((t) => t.name === action.assignee)?.id || null : null,
        updatedAt: noteTimestamp,
        statusUpdatedAt: noteTimestamp,
        assigneeUpdatedAt: noteTimestamp,
        hasConflict: false,
        conflictDescription: null,
      })),
      photoUrls: [],
      acknowledgments: (n.acks || []).map((ack, idx) => ({
        id: `${n.id}_ack_${idx}`,
        userId: ack.userId,
        userName: ack.userName,
        timestamp: h(ack.hoursAgo),
      })),
      voiceReplies: (n.replies || []).map((reply, idx) => ({
        id: `${n.id}_reply_${idx}`,
        authorId: reply.authorId,
        authorName: reply.authorName,
        transcript: reply.text,
        timestamp: h(reply.hoursAgo),
        parentItemId: null,
      })),
      createdAt: noteTimestamp,
      updatedAt: noteTimestamp,
      isSynced: true,
    });
  }

  const recurringIssuesData = [
    { desc: "Walk-in compressor making noise", cat: "Equipment", locIdx: 0, mentions: 4, daysFirst: 12, hoursLast: 3 },
    { desc: "Ice machine leaking at service station", cat: "Maintenance", locIdx: 0, mentions: 3, daysFirst: 9, hoursLast: 8 },
    { desc: "Back door lock sticking", cat: "Maintenance", locIdx: 1, mentions: 3, daysFirst: 14, hoursLast: 2 },
    { desc: "Outdoor heaters failing to ignite", cat: "Equipment", locIdx: 2, mentions: 2, daysFirst: 7, hoursLast: 1 },
    { desc: "POS terminal station 3 freezing", cat: "Equipment", locIdx: 0, mentions: 5, daysFirst: 21, hoursLast: 3 },
  ];

  for (let i = 0; i < recurringIssuesData.length; i++) {
    const ri = recurringIssuesData[i];
    storage.upsertRecurringIssue({
      id: `ri_${i + 1}`,
      ownerId: demoUserId,
      description: ri.desc,
      category: ri.cat,
      categoryTemplateId: null,
      locationId: locIds[ri.locIdx],
      locationName: locNames[ri.locIdx],
      mentionCount: ri.mentions,
      relatedNoteIds: [],
      firstMentioned: new Date(now - ri.daysFirst * 86400_000).toISOString(),
      lastMentioned: h(ri.hoursLast),
      status: "Active",
      createdAt: new Date(now - ri.daysFirst * 86400_000).toISOString(),
      updatedAt: h(ri.hoursLast),
    });
  }

  storage.setSelectedLocationId(demoUserId, "loc_001");
  console.log("Seed data populated: 25 notes, 3 locations, 7 team members, 5 recurring issues");
}

seedDemoData();

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

const firebaseAuthSchema = z.object({
  idToken: z.string().min(1),
  uid: z.string().min(1),
  name: z.string().min(2, "Name must be at least 2 characters").max(100, "Name must be under 100 characters"),
  email: z.string().email(),
});

app.post("/rest/auth/firebase", async (c) => {
  const body = await c.req.json();
  const validation = validateBody(firebaseAuthSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }
  const { uid, name, email } = validation.data;

  let account = storage.getAccountByEmail(email);
  const token = generateToken();

  if (!account) {
    storage.createAccount({
      userId: uid,
      email: email.toLowerCase(),
      name,
      passwordHash: "",
      authMethod: "firebase",
      createdAt: new Date().toISOString(),
    });
    storage.createSession(token, uid);
    return c.json({ success: true, userId: uid, token, name, email: email.toLowerCase() });
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

    const maxSyncNotes = 100;
    if (data.shiftNotes && data.shiftNotes.length > maxSyncNotes) {
      data.shiftNotes = data.shiftNotes.slice(0, maxSyncNotes);
    }

    return c.json({ hasData: true, data, totalNotes: data.shiftNotes?.length || 0 });
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
  const requestedScope = c.req.query("visibilityScope");
  const visibilityScope = requestedScope === "private" ? "private" : "team";

  const result = storage.getShiftNotes(auth.userId, {
    locationId,
    shiftFilter,
    cursor,
    limit,
    updatedSince,
    visibilityScope,
    authorId: auth.userId,
  });
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
    visibility: note.visibility ?? "team",
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
  const allowedNoteFields = [
    "authorId", "authorName", "authorInitials", "locationId", "shiftType",
    "shiftTemplateId", "rawTranscript", "audioUrl", "audioDuration", "summary",
    "categorizedItems", "actionItems", "photoUrls", "acknowledgments",
    "voiceReplies", "visibility", "isSynced",
  ];
  const sanitized: Record<string, any> = {};
  for (const key of allowedNoteFields) {
    if (key in body) sanitized[key] = body[key];
  }
  if ("visibility" in sanitized) {
    const requestedVisibility = sanitized.visibility === "private" ? "private" : "team";
    const currentVisibility = existing.visibility === "private" ? "private" : "team";
    if (requestedVisibility === "private" && currentVisibility === "team") {
      return errorResponse(c, 403, "Team notes cannot be converted to private", "FORBIDDEN");
    }
    if (requestedVisibility === "team" && currentVisibility === "private" && existing.authorId !== auth.userId) {
      return errorResponse(c, 403, "Only the note author can share a private note with the team", "FORBIDDEN");
    }
    sanitized.visibility = requestedVisibility;
  }
  const updated = { ...existing, ...sanitized, id: noteId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
  storage.upsertShiftNote(updated);

  return c.json({ success: true, noteId });
});

// --- Shift Notes: Promote Private Note To Team ---

app.post("/rest/shift-notes/:noteId/promote-to-team", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const noteId = c.req.param("noteId");
  const note = storage.getShiftNote(noteId);
  if (!note || note.ownerId !== auth.userId) {
    return errorResponse(c, 404, "Note not found", "NOT_FOUND");
  }
  if (note.authorId !== auth.userId) {
    return errorResponse(c, 403, "Only the note author can share a private note with the team", "FORBIDDEN");
  }
  if (note.visibility !== "private") {
    return c.json({ success: true, noteId, visibility: "team" });
  }

  note.visibility = "team";
  note.updatedAt = new Date().toISOString();
  storage.upsertShiftNote(note);

  return c.json({ success: true, noteId, visibility: "team" });
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
  if (!note) {
    return errorResponse(c, 404, "Note not found", "NOT_FOUND");
  }
  if (note.ownerId !== auth.userId) {
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
  const allowedLocationFields = [
    "name", "address", "timezone", "openingTime", "midTime", "closingTime", "managerIds",
  ];
  const sanitized: Record<string, any> = {};
  for (const key of allowedLocationFields) {
    if (key in body) sanitized[key] = body[key];
  }
  const updated = { ...existing, ...sanitized, id: locationId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
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
  const allowedMemberFields = [
    "name", "email", "role", "roleTemplateId", "locationIds", "inviteStatus", "avatarInitials",
  ];
  const sanitized: Record<string, any> = {};
  for (const key of allowedMemberFields) {
    if (key in body) sanitized[key] = body[key];
  }
  const updated = { ...existing, ...sanitized, id: memberId, ownerId: auth.userId, updatedAt: new Date().toISOString() };
  storage.upsertTeamMember(updated);

  return c.json({ success: true, memberId });
});

// --- Team: Remove ---

app.delete("/rest/team/:memberId", async (c) => {
  const auth = authMiddleware(c);
  if (!auth) return errorResponse(c, 401, "Unauthorized", "UNAUTHORIZED");

  const memberId = c.req.param("memberId");
  const members = storage.getTeamMembers(auth.userId);
  const existing = members.find((m) => m.id === memberId);
  if (!existing) {
    return errorResponse(c, 404, "Team member not found", "NOT_FOUND");
  }
  if (existing.ownerId !== auth.userId) {
    return errorResponse(c, 403, "Forbidden", "FORBIDDEN");
  }

  storage.deleteTeamMember(memberId);
  return c.json({ success: true });
});

// --- Audio Transcription (Whisper) ---

app.post("/rest/transcribe", async (c) => {
  const userId = c.req.header("x-user-id") || c.req.header("x-forwarded-for") || "anonymous";
  if (!userId) return errorResponse(c, 400, "User identifier required", "BAD_REQUEST");

  try {
    const formData = await c.req.formData();
    const audioFile = formData.get("audio");
    if (!audioFile || !(audioFile instanceof File)) {
      return errorResponse(c, 400, "Audio file is required", "VALIDATION_ERROR");
    }

    const language = formData.get("language") as string | null;

    const sttFormData = new FormData();
    sttFormData.append("audio", audioFile);
    if (language) {
      sttFormData.append("language", language);
    }

    const sttResponse = await fetch("https://toolkit.rork.com/stt/transcribe/", {
      method: "POST",
      body: sttFormData,
    });

    if (!sttResponse.ok) {
      const errorText = await sttResponse.text().catch(() => "Unknown error");
      console.error("STT API error:", sttResponse.status, errorText);
      return errorResponse(c, 502, "Transcription service unavailable", "STT_ERROR");
    }

    const result = await sttResponse.json() as { text: string; language: string };
    return c.json({ success: true, text: result.text, language: result.language });
  } catch (error: any) {
    console.error("Transcription failed:", error?.message || error);
    return errorResponse(c, 500, "Transcription failed", "STT_ERROR");
  }
});

// --- AI Transcript Structuring ---

const structureTranscriptSchema = z.object({
  transcript: z.string().min(1, "Transcript is required"),
  businessType: z.string().optional().default("restaurant"),
  availableCategories: z.array(z.string()).optional(),
  industryVocabulary: z.array(z.string()).optional(),
  categorizationHints: z.array(z.string()).optional(),
  estimatedTopicCount: z.number().int().min(1).max(30).optional(),
  averageSegmentConfidence: z.number().min(0).max(1).optional(),
  lowConfidencePhrases: z.array(z.string()).optional(),
  industryRoles: z.array(z.string()).optional(),
  industryEquipment: z.array(z.string()).optional(),
  industrySlang: z.array(z.string()).optional(),
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
      source_quote: z.string().describe("A short exact quote from the transcript that supports this item"),
    })
  ).describe("Each distinct issue, observation, or handoff item mentioned in the transcript. Split into SEPARATE items - one per distinct topic. Do NOT group multiple topics together."),
});

function estimateExpectedItemCount(transcript: string): number {
  const lower = transcript.toLowerCase();
  let cues = 0;

  const explicitCounts = lower.match(/\b(two|three|four|five|six|seven|eight|nine|ten|\d+)\s+(things?|items?|issues?|points?|notes?)\b/);
  if (explicitCounts) {
    const numWords: Record<string, number> = { two: 2, three: 3, four: 4, five: 5, six: 6, seven: 7, eight: 8, nine: 9, ten: 10 };
    const parsed = numWords[explicitCounts[1]] || parseInt(explicitCounts[1], 10);
    if (parsed && parsed >= 2) return parsed;
  }

  const ordinals = lower.match(/\b(first|second|third|fourth|fifth|number one|number two|number three)\b/g);
  if (ordinals) cues = Math.max(cues, new Set(ordinals).size);

  const numberedList = lower.match(/(?:^|\n|\. )\d+[\.\)\:]/g);
  if (numberedList) cues = Math.max(cues, numberedList.length);

  const transitions = (lower.match(/\b(also|and then|next|another thing|on top of that|additionally|oh and|plus|as well|besides that)\b/g) || []).length;
  cues = Math.max(cues, transitions + 1);

  const imperatives = (lower.match(/\b(check|fix|order|replace|clean|call|tell|restock|notify|schedule|follow up|make sure|need to|needs to|have to|has to)\b/g) || []).length;
  if (imperatives >= 3) cues = Math.max(cues, Math.ceil(imperatives * 0.6));

  return Math.max(2, cues);
}

app.post("/rest/structure-transcript", async (c) => {
  const userId = c.req.header("x-user-id") || c.req.header("x-forwarded-for") || "anonymous";
  if (!userId) return errorResponse(c, 400, "User identifier required", "BAD_REQUEST");

  const body = await c.req.json();
  const validation = validateBody(structureTranscriptSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const {
    transcript,
    businessType,
    estimatedTopicCount,
    availableCategories,
    industryVocabulary,
    categorizationHints,
    averageSegmentConfidence,
    lowConfidencePhrases,
    industryRoles,
    industryEquipment,
    industrySlang,
  } = validation.data;

  try {
    const firstPass = await generateObject({
      messages: [
        {
          role: "user",
          content: `You are an expert shift handoff assistant for a ${businessType} business. Your job is to take a raw voice transcript from a shift worker and structure it into separate, actionable items.

EXTRACTION PROCESS (follow these steps in order):

STEP 1 — SEGMENT: Read the entire transcript. Identify every distinct topic, issue, task, or observation. Look for:
- Numbered items ("first", "second", "number one", "1.", "2.")
- Transition words ("also", "and then", "next", "another thing", "on top of that", "additionally", "oh and", "plus", "besides that")
- Imperative verbs that signal separate tasks ("check", "fix", "order", "replace", "clean", "call", "tell", "restock", "notify", "schedule", "follow up", "make sure", "need to", "needs to")
- Topic shifts (switching from equipment to staff, from inventory to guests, etc.)
- Compound sentences with "and" that contain TWO different actions (e.g. "fix the fryer and restock napkins" = 2 items)

STEP 2 — COUNT: Count how many distinct items you identified. If the speaker said "three things" or listed numbered items, your count MUST match or exceed that number. Each imperative verb acting on a different object = separate item.
- Client-side topic estimate hint: at least ${estimatedTopicCount ?? 1} distinct items are likely present.

STEP 3 — CREATE: For EACH distinct item, create a separate entry with:
- "content": A clear, specific description using the worker's actual words/details
- "category": The most accurate category
- "urgency": How urgent this specific item is
- "actionRequired": true if someone needs to take action
- "actionTask": If actionRequired, a specific task description starting with an imperative verb (e.g. "Replace the broken ice machine filter", "Call vendor to reorder chicken breast")
- "source_quote": A short exact quote from the transcript that proves this item is grounded in source audio

FEW-SHOT EXAMPLES:

Example transcript: "Hey so the walk-in cooler is making a weird noise again, I think the compressor needs to be looked at. Also we're almost out of chicken breast and salmon, need to call the vendor first thing tomorrow. Oh and table 12 complained about their steak being overcooked, I comped their dessert."

Correct extraction (3 items):
1. Equipment issue: Walk-in cooler compressor making weird noise, needs inspection → actionTask: "Inspect walk-in cooler compressor and schedule repair if needed"
2. Inventory: Running low on chicken breast and salmon → actionTask: "Call vendor to reorder chicken breast and salmon"
3. Guest issue: Table 12 complained about overcooked steak, dessert was comped → actionTask: "Follow up on table 12 steak complaint and review grill station"

WRONG extraction (1 item): Combining all three into "Multiple issues including cooler, inventory, and guest complaint" — this loses all detail.

CRITICAL RULES:
- NEVER combine unrelated topics into a single item — one topic per item
- NEVER skip an item because it seems minor — capture everything mentioned
- If in doubt whether something is one item or two, ALWAYS split into two
- Each item's content should describe ONE issue, not summarize the whole transcript
- The summary should briefly cover ALL items in 1-2 sentences
- Use the worker's actual words and details, don't genericize
- actionTask MUST start with an imperative verb and be specific enough to act on without re-reading the transcript
- If a sentence mentions two different things to do ("fix X and order Y"), create TWO items
- source_quote MUST be present for every item and MUST be copied verbatim from the transcript

TRANSCRIPT CORRECTION (apply BEFORE structuring):
This transcript came from speech-to-text and may contain misheard industry terms. Before extracting items, mentally correct likely transcription errors using the industry vocabulary below. For example:
- "bar backs" or "barbacks" → barback (a job position that assists bartenders)
- "eighty six" or "86" → 86'd (item is unavailable)
- "bus sir" or "buster" → busser (a job position that clears tables)
- "expo" → expeditor (coordinates food leaving the kitchen)
- "cambro" → Cambro (an insulated food transport container)
- "mis en plas" or "meez" → mise en place
Always interpret ambiguous words in favor of known industry terms listed below.

INDUSTRY CONTEXT:
- Business type: ${businessType}
- Preferred categories: ${availableCategories?.join(", ") || "Use the default categories in schema"}
- Categorization hints: ${categorizationHints?.join(" | ") || "N/A"}

INDUSTRY KNOWLEDGE BASE (use these to interpret transcript correctly):
- Job positions/roles: ${industryRoles?.join(", ") || industryVocabulary?.join(", ") || "N/A"}
- Equipment/tools: ${industryEquipment?.join(", ") || "N/A"}
- Industry slang/jargon: ${industrySlang?.join(", ") || "N/A"}

When the transcript mentions a person by role (e.g. "tell the barbacks", "have the busser", "let the expo know"), this is a STAFFING item and likely needs an action item assigned to that role. Treat role mentions as references to specific people — they ARE actionable.

TRANSCRIPT QUALITY:
- Average confidence: ${averageSegmentConfidence ?? 1}. If low, rely strictly on exact quoted evidence.
- Potentially misheard phrases: ${lowConfidencePhrases?.join(" | ") || "None"}
- General vocabulary hints: ${industryVocabulary?.join(", ") || "N/A"}

Here is the transcript to structure:

"${transcript}"`
        }
      ],
      schema: structuredNoteSchema,
    });

    const extractedCount = firstPass.items?.length ?? 0;
    const expectedMin = Math.max(estimateExpectedItemCount(transcript), estimatedTopicCount ?? 1);

    if (extractedCount < expectedMin && extractedCount > 0) {
      try {
        const existingItems = firstPass.items.map((i: any) => i.content).join("\n- ");
        const recoveryPass = await generateObject({
          messages: [
            {
              role: "user",
              content: `You are reviewing a shift handoff transcript for a ${businessType} business. A first pass already extracted some items, but it may have MISSED some.

Here is the original transcript:
"${transcript}"

Here are the items already extracted:
- ${existingItems}

The transcript contains cues suggesting there should be MORE items than the ${extractedCount} already found (e.g. numbered lists, transition words like "also"/"next"/"another thing", or multiple imperative verbs).

Your job: Find ANY items from the transcript that are NOT already covered above. Only return NEW items that were missed. If nothing was missed, return an empty items array and keep the same summary.

Rules:
- Do NOT duplicate items already extracted
- Each new item must describe a DISTINCT topic not covered above
- Use the worker's actual words and details`
            }
          ],
          schema: structuredNoteSchema,
        });

        if (recoveryPass.items?.length > 0) {
          firstPass.items.push(...recoveryPass.items);
          if (recoveryPass.summary) {
            firstPass.summary = recoveryPass.summary;
          }
        }
      } catch (recoveryError: any) {
        console.warn("Recovery pass failed, using first pass only:", recoveryError?.message);
      }
    }

    return c.json({ success: true, structured: firstPass });
  } catch (error: any) {
    console.error("AI structuring failed:", error?.message || error);
    return c.json({ success: false, error: "AI structuring unavailable", code: "AI_ERROR" }, 500);
  }
});

const refineActionItemSchema = z.object({
  text: z.string().min(1).max(1000),
});

app.post("/rest/refine-action-item", async (c) => {
  const body = await c.req.json();
  const validation = validateBody(refineActionItemSchema, body);
  if (!validation.success) {
    return errorResponse(c, 400, validation.error, "VALIDATION_ERROR");
  }

  const { text } = validation.data;

  try {
    const refined = await generateText({
      messages: [
        {
          role: "user",
          content: `Rewrite this shift handoff action item to be professional, clear, and actionable. Keep it concise (one sentence, starting with an imperative verb). Do not add information that wasn't in the original. Only return the rewritten text, nothing else.\n\nOriginal: "${text}"`
        }
      ]
    });

    return c.json({ success: true, refined: refined.trim() });
  } catch (error: any) {
    console.error("AI refinement failed:", error?.message || error);
    return c.json({ success: false, error: "AI refinement unavailable" }, 500);
  }
});

export default app;
