export interface UserData {
  userId: string;
  organization: any;
  locations: any[];
  teamMembers: any[];
  shiftNotes: any[];
  recurringIssues: any[];
  selectedLocationId: string | null;
  updatedAt: string;
}

export interface UserAccount {
  userId: string;
  email: string;
  name: string;
  passwordHash: string;
  authMethod: string;
  createdAt: string;
}

const userData = new Map<string, UserData>();
const userAccounts = new Map<string, UserAccount>();
const emailToUserId = new Map<string, string>();
const sessionTokens = new Map<string, { userId: string; expiresAt: string }>();

export const storage = {
  getUserData(userId: string): UserData | null {
    return userData.get(userId) || null;
  },

  setUserData(userId: string, data: UserData): void {
    data.updatedAt = new Date().toISOString();
    userData.set(userId, data);
  },

  getAccount(userId: string): UserAccount | null {
    return userAccounts.get(userId) || null;
  },

  getAccountByEmail(email: string): UserAccount | null {
    const uid = emailToUserId.get(email.toLowerCase());
    if (!uid) return null;
    return userAccounts.get(uid) || null;
  },

  createAccount(account: UserAccount): void {
    userAccounts.set(account.userId, account);
    emailToUserId.set(account.email.toLowerCase(), account.userId);
  },

  createSession(token: string, userId: string): void {
    const expiresAt = new Date(
      Date.now() + 30 * 24 * 60 * 60 * 1000,
    ).toISOString();
    sessionTokens.set(token, { userId, expiresAt });
  },

  validateSession(token: string): string | null {
    const session = sessionTokens.get(token);
    if (!session) return null;
    if (new Date(session.expiresAt) < new Date()) {
      sessionTokens.delete(token);
      return null;
    }
    return session.userId;
  },

  deleteSession(token: string): void {
    sessionTokens.delete(token);
  },

  deleteUserData(userId: string): void {
    userData.delete(userId);
    const account = userAccounts.get(userId);
    if (account) {
      emailToUserId.delete(account.email.toLowerCase());
      userAccounts.delete(userId);
    }
  },
};
