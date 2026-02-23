import * as crypto from "crypto";

export interface UserAccount {
  userId: string;
  email: string;
  name: string;
  passwordHash: string;
  authMethod: string;
  createdAt: string;
  updatedAt: string;
}

export interface SessionData {
  userId: string;
  expiresAt: string;
  createdAt: string;
}

export interface StoredOrganization {
  id: string;
  ownerId: string;
  name: string;
  plan: string;
  industryType: string;
  createdAt: string;
  updatedAt: string;
}

export interface StoredLocation {
  id: string;
  ownerId: string;
  name: string;
  address: string;
  timezone: string;
  openingTime: string;
  midTime: string;
  closingTime: string;
  managerIds: string[];
  createdAt: string;
  updatedAt: string;
}

export interface StoredTeamMember {
  id: string;
  ownerId: string;
  name: string;
  email: string;
  role: string;
  roleTemplateId: string | null;
  locationIds: string[];
  inviteStatus: string;
  avatarInitials: string;
  createdAt: string;
  updatedAt: string;
}

export interface StoredShiftNote {
  id: string;
  ownerId: string;
  authorId: string;
  authorName: string;
  authorInitials: string;
  locationId: string;
  shiftType: string;
  shiftTemplateId: string | null;
  rawTranscript: string;
  audioUrl: string | null;
  audioDuration: number;
  summary: string;
  categorizedItems: any[];
  actionItems: any[];
  photoUrls: string[];
  acknowledgments: any[];
  voiceReplies: any[];
  createdAt: string;
  updatedAt: string;
  isSynced: boolean;
}

export interface StoredRecurringIssue {
  id: string;
  ownerId: string;
  description: string;
  category: string;
  categoryTemplateId: string | null;
  locationId: string;
  locationName: string;
  mentionCount: number;
  relatedNoteIds: string[];
  firstMentioned: string;
  lastMentioned: string;
  status: string;
  createdAt: string;
  updatedAt: string;
}

const accounts = new Map<string, UserAccount>();
const emailIndex = new Map<string, string>();
const sessions = new Map<string, SessionData>();

const organizations = new Map<string, StoredOrganization>();
const locations = new Map<string, StoredLocation>();
const teamMembers = new Map<string, StoredTeamMember>();
const shiftNotes = new Map<string, StoredShiftNote>();
const recurringIssues = new Map<string, StoredRecurringIssue>();

const userSelectedLocation = new Map<string, string>();

function now(): string {
  return new Date().toISOString();
}

export const storage = {
  // --- Accounts ---
  getAccount(userId: string): UserAccount | null {
    return accounts.get(userId) || null;
  },

  getAccountByEmail(email: string): UserAccount | null {
    const uid = emailIndex.get(email.toLowerCase());
    if (!uid) return null;
    return accounts.get(uid) || null;
  },

  createAccount(account: Omit<UserAccount, "updatedAt"> & { updatedAt?: string }): void {
    const full: UserAccount = { ...account, updatedAt: account.updatedAt || now() };
    accounts.set(full.userId, full);
    emailIndex.set(full.email.toLowerCase(), full.userId);
  },

  // --- Sessions ---
  createSession(token: string, userId: string): void {
    sessions.set(token, {
      userId,
      expiresAt: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
      createdAt: now(),
    });
  },

  validateSession(token: string): string | null {
    const session = sessions.get(token);
    if (!session) return null;
    if (new Date(session.expiresAt) < new Date()) {
      sessions.delete(token);
      return null;
    }
    return session.userId;
  },

  deleteSession(token: string): void {
    sessions.delete(token);
  },

  // --- Organizations ---
  getOrganization(userId: string): StoredOrganization | null {
    for (const org of organizations.values()) {
      if (org.ownerId === userId) return org;
    }
    return null;
  },

  upsertOrganization(org: StoredOrganization): void {
    org.updatedAt = now();
    organizations.set(org.id, org);
  },

  // --- Locations ---
  getLocations(userId: string): StoredLocation[] {
    return Array.from(locations.values()).filter((l) => l.ownerId === userId);
  },

  getLocation(id: string): StoredLocation | null {
    return locations.get(id) || null;
  },

  upsertLocation(loc: StoredLocation): void {
    loc.updatedAt = now();
    locations.set(loc.id, loc);
  },

  deleteLocation(id: string): void {
    locations.delete(id);
    for (const [noteId, note] of shiftNotes.entries()) {
      if (note.locationId === id) shiftNotes.delete(noteId);
    }
  },

  // --- Team Members ---
  getTeamMembers(userId: string): StoredTeamMember[] {
    return Array.from(teamMembers.values()).filter((m) => m.ownerId === userId);
  },

  upsertTeamMember(member: StoredTeamMember): void {
    member.updatedAt = now();
    teamMembers.set(member.id, member);
  },

  deleteTeamMember(id: string): void {
    teamMembers.delete(id);
  },

  // --- Shift Notes ---
  getShiftNotes(userId: string, opts?: {
    locationId?: string | null;
    shiftFilter?: string | null;
    cursor?: string | null;
    limit?: number;
    updatedSince?: string | null;
  }): { notes: StoredShiftNote[]; totalCount: number; hasMore: boolean; nextCursor: string | null } {
    let notes = Array.from(shiftNotes.values()).filter((n) => n.ownerId === userId);

    if (opts?.locationId) {
      notes = notes.filter((n) => n.locationId === opts.locationId);
    }
    if (opts?.shiftFilter) {
      notes = notes.filter((n) => {
        if (n.shiftTemplateId) return n.shiftTemplateId === opts.shiftFilter;
        return n.shiftType === opts.shiftFilter;
      });
    }
    if (opts?.updatedSince) {
      const since = new Date(opts.updatedSince).getTime();
      notes = notes.filter((n) => new Date(n.updatedAt).getTime() > since);
    }

    notes.sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());

    const totalCount = notes.length;
    const limit = opts?.limit || 20;

    if (opts?.cursor) {
      const idx = notes.findIndex((n) => n.id === opts.cursor);
      if (idx >= 0) notes = notes.slice(idx + 1);
    }

    const page = notes.slice(0, limit);
    const hasMore = notes.length > limit;
    const nextCursor = page.length > 0 ? page[page.length - 1].id : null;

    return { notes: page, totalCount, hasMore, nextCursor };
  },

  getShiftNote(id: string): StoredShiftNote | null {
    return shiftNotes.get(id) || null;
  },

  upsertShiftNote(note: StoredShiftNote): void {
    note.updatedAt = now();
    shiftNotes.set(note.id, note);
  },

  deleteShiftNote(id: string): void {
    shiftNotes.delete(id);
  },

  // --- Recurring Issues ---
  getRecurringIssues(userId: string): StoredRecurringIssue[] {
    return Array.from(recurringIssues.values()).filter((i) => i.ownerId === userId);
  },

  upsertRecurringIssue(issue: StoredRecurringIssue): void {
    issue.updatedAt = now();
    recurringIssues.set(issue.id, issue);
  },

  deleteRecurringIssue(id: string): void {
    recurringIssues.delete(id);
  },

  // --- User Preferences ---
  getSelectedLocationId(userId: string): string | null {
    return userSelectedLocation.get(userId) || null;
  },

  setSelectedLocationId(userId: string, locationId: string): void {
    userSelectedLocation.set(userId, locationId);
  },

  // --- Bulk Operations (for sync compatibility) ---
  getUserData(userId: string): {
    organization: StoredOrganization | null;
    locations: StoredLocation[];
    teamMembers: StoredTeamMember[];
    shiftNotes: StoredShiftNote[];
    recurringIssues: StoredRecurringIssue[];
    selectedLocationId: string | null;
    updatedAt: string;
  } | null {
    const org = this.getOrganization(userId);
    const locs = this.getLocations(userId);
    const team = this.getTeamMembers(userId);
    const notes = Array.from(shiftNotes.values())
      .filter((n) => n.ownerId === userId)
      .sort((a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime());
    const issues = this.getRecurringIssues(userId);
    const selLoc = this.getSelectedLocationId(userId);

    if (!org && locs.length === 0 && notes.length === 0) return null;

    const allDates = [
      org?.updatedAt,
      ...locs.map((l) => l.updatedAt),
      ...team.map((m) => m.updatedAt),
      ...notes.map((n) => n.updatedAt),
      ...issues.map((i) => i.updatedAt),
    ].filter(Boolean) as string[];

    const latestUpdate = allDates.length > 0
      ? allDates.sort().reverse()[0]
      : now();

    return {
      organization: org,
      locations: locs,
      teamMembers: team,
      shiftNotes: notes,
      recurringIssues: issues,
      selectedLocationId: selLoc,
      updatedAt: latestUpdate,
    };
  },

  setUserData(userId: string, data: {
    organization?: any;
    locations?: any[];
    teamMembers?: any[];
    shiftNotes?: any[];
    recurringIssues?: any[];
    selectedLocationId?: string | null;
  }): void {
    const timestamp = now();

    if (data.organization) {
      this.upsertOrganization({
        ...data.organization,
        ownerId: userId,
        createdAt: data.organization.createdAt || timestamp,
        updatedAt: timestamp,
      });
    }

    if (data.locations) {
      const existingLocs = this.getLocations(userId);
      for (const el of existingLocs) {
        if (!data.locations.find((l: any) => l.id === el.id)) {
          locations.delete(el.id);
        }
      }
      for (const loc of data.locations) {
        this.upsertLocation({
          ...loc,
          ownerId: userId,
          createdAt: loc.createdAt || timestamp,
          updatedAt: timestamp,
        });
      }
    }

    if (data.teamMembers) {
      const existingMembers = this.getTeamMembers(userId);
      for (const em of existingMembers) {
        if (!data.teamMembers.find((m: any) => m.id === em.id)) {
          teamMembers.delete(em.id);
        }
      }
      for (const member of data.teamMembers) {
        this.upsertTeamMember({
          ...member,
          ownerId: userId,
          createdAt: member.createdAt || timestamp,
          updatedAt: timestamp,
        });
      }
    }

    if (data.shiftNotes) {
      const existingNotes = Array.from(shiftNotes.values()).filter((n) => n.ownerId === userId);
      for (const en of existingNotes) {
        if (!data.shiftNotes.find((n: any) => n.id === en.id)) {
          shiftNotes.delete(en.id);
        }
      }
      for (const note of data.shiftNotes) {
        this.upsertShiftNote({
          ...note,
          ownerId: userId,
          createdAt: note.createdAt || timestamp,
          updatedAt: timestamp,
        });
      }
    }

    if (data.recurringIssues) {
      const existingIssues = this.getRecurringIssues(userId);
      for (const ei of existingIssues) {
        if (!data.recurringIssues.find((i: any) => i.id === ei.id)) {
          recurringIssues.delete(ei.id);
        }
      }
      for (const issue of data.recurringIssues) {
        this.upsertRecurringIssue({
          ...issue,
          ownerId: userId,
          createdAt: issue.createdAt || timestamp,
          updatedAt: timestamp,
        });
      }
    }

    if (data.selectedLocationId !== undefined) {
      this.setSelectedLocationId(userId, data.selectedLocationId || "");
    }
  },

  deleteUserData(userId: string): void {
    const account = accounts.get(userId);
    if (account) {
      emailIndex.delete(account.email.toLowerCase());
      accounts.delete(userId);
    }

    const org = this.getOrganization(userId);
    if (org) organizations.delete(org.id);

    for (const loc of this.getLocations(userId)) locations.delete(loc.id);
    for (const member of this.getTeamMembers(userId)) teamMembers.delete(member.id);
    for (const [id, note] of shiftNotes.entries()) {
      if (note.ownerId === userId) shiftNotes.delete(id);
    }
    for (const issue of this.getRecurringIssues(userId)) recurringIssues.delete(issue.id);
    userSelectedLocation.delete(userId);

    for (const [token, session] of sessions.entries()) {
      if (session.userId === userId) sessions.delete(token);
    }
  },

  // --- Stats (for testing/debugging) ---
  getStats(): {
    accounts: number;
    sessions: number;
    organizations: number;
    locations: number;
    teamMembers: number;
    shiftNotes: number;
    recurringIssues: number;
  } {
    return {
      accounts: accounts.size,
      sessions: sessions.size,
      organizations: organizations.size,
      locations: locations.size,
      teamMembers: teamMembers.size,
      shiftNotes: shiftNotes.size,
      recurringIssues: recurringIssues.size,
    };
  },
};
