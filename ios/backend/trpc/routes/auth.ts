import * as z from "zod";
import * as crypto from "crypto";

import {
  createTRPCRouter,
  publicProcedure,
  protectedProcedure,
} from "../create-context";
import { storage } from "../../storage";

function hashPassword(password: string): string {
  return crypto.createHash("sha256").update(password).digest("hex");
}

function generateToken(): string {
  return crypto.randomBytes(32).toString("base64url");
}

export const authRouter = createTRPCRouter({
  register: publicProcedure
    .input(
      z.object({
        name: z.string().min(2),
        email: z.string().email(),
        password: z.string().min(8),
        authMethod: z.enum(["email", "google"]).default("email"),
      }),
    )
    .mutation(({ input }) => {
      const existing = storage.getAccountByEmail(input.email);
      if (existing) {
        return { success: false as const, error: "Account already exists" };
      }

      const userId = crypto.randomUUID();
      const token = generateToken();

      storage.createAccount({
        userId,
        email: input.email.toLowerCase(),
        name: input.name,
        passwordHash: hashPassword(input.password),
        authMethod: input.authMethod,
        createdAt: new Date().toISOString(),
      });

      storage.createSession(token, userId);

      return {
        success: true as const,
        userId,
        token,
        name: input.name,
        email: input.email.toLowerCase(),
      };
    }),

  login: publicProcedure
    .input(
      z.object({
        email: z.string().email(),
        password: z.string(),
      }),
    )
    .mutation(({ input }) => {
      const account = storage.getAccountByEmail(input.email);
      if (!account) {
        return {
          success: false as const,
          error: "No account found with this email",
        };
      }

      if (account.passwordHash !== hashPassword(input.password)) {
        return { success: false as const, error: "Incorrect password" };
      }

      const token = generateToken();
      storage.createSession(token, account.userId);

      return {
        success: true as const,
        userId: account.userId,
        token,
        name: account.name,
        email: account.email,
      };
    }),

  googleAuth: publicProcedure
    .input(
      z.object({
        googleUserId: z.string(),
        name: z.string(),
        email: z.string().email(),
      }),
    )
    .mutation(({ input }) => {
      let account = storage.getAccountByEmail(input.email);
      const token = generateToken();

      if (!account) {
        const userId = input.googleUserId;
        storage.createAccount({
          userId,
          email: input.email.toLowerCase(),
          name: input.name,
          passwordHash: "",
          authMethod: "google",
          createdAt: new Date().toISOString(),
        });
        storage.createSession(token, userId);
        return {
          success: true as const,
          userId,
          token,
          name: input.name,
          email: input.email.toLowerCase(),
        };
      }

      storage.createSession(token, account.userId);
      return {
        success: true as const,
        userId: account.userId,
        token,
        name: account.name,
        email: account.email,
      };
    }),

  logout: protectedProcedure.mutation(({ ctx }) => {
    storage.deleteSession(ctx.token);
    return { success: true };
  }),

  validateSession: protectedProcedure.query(({ ctx }) => {
    const userId = storage.validateSession(ctx.token);
    if (!userId) {
      return { valid: false };
    }
    const account = storage.getAccount(userId);
    return {
      valid: true,
      userId,
      name: account?.name,
      email: account?.email,
    };
  }),
});
