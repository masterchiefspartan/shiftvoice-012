import * as z from "zod";

import { createTRPCRouter, protectedProcedure } from "../create-context";
import { storage } from "../../storage";

export const shiftNotesRouter = createTRPCRouter({
  create: protectedProcedure
    .input(z.object({ note: z.any() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.shiftNotes.unshift(input.note);
      storage.setUserData(ctx.userId, data);
      return { success: true, noteId: input.note.id };
    }),

  update: protectedProcedure
    .input(z.object({ noteId: z.string(), updates: z.any() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      const index = data.shiftNotes.findIndex(
        (n: any) => n.id === input.noteId,
      );
      if (index === -1) {
        return { success: false, error: "Note not found" };
      }
      data.shiftNotes[index] = { ...data.shiftNotes[index], ...input.updates };
      storage.setUserData(ctx.userId, data);
      return { success: true };
    }),

  delete: protectedProcedure
    .input(z.object({ noteId: z.string() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.shiftNotes = data.shiftNotes.filter(
        (n: any) => n.id !== input.noteId,
      );
      storage.setUserData(ctx.userId, data);
      return { success: true };
    }),
});
