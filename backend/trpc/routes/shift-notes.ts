import * as z from "zod";

import { createTRPCRouter, protectedProcedure } from "../create-context";
import { storage } from "../../storage";

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

const shiftNoteUpdateSchema = shiftNoteSchema.partial().omit({ id: true });

export const shiftNotesRouter = createTRPCRouter({
  create: protectedProcedure
    .input(z.object({ note: shiftNoteSchema }))
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
    .input(z.object({ noteId: z.string(), updates: shiftNoteUpdateSchema }))
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
