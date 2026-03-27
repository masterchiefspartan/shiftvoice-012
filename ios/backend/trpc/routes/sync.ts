import * as z from "zod";

import { createTRPCRouter, protectedProcedure } from "../create-context";
import { storage } from "../../storage";

export const syncRouter = createTRPCRouter({
  pull: protectedProcedure.query(({ ctx }) => {
    const data = storage.getUserData(ctx.userId);
    if (!data) {
      return { hasData: false, data: null };
    }
    return { hasData: true, data };
  }),

  push: protectedProcedure
    .input(
      z.object({
        organization: z.any(),
        locations: z.array(z.any()),
        teamMembers: z.array(z.any()),
        shiftNotes: z.array(z.any()),
        recurringIssues: z.array(z.any()),
        selectedLocationId: z.string().nullable(),
      }),
    )
    .mutation(({ ctx, input }) => {
      storage.setUserData(ctx.userId, {
        userId: ctx.userId,
        organization: input.organization,
        locations: input.locations,
        teamMembers: input.teamMembers,
        shiftNotes: input.shiftNotes,
        recurringIssues: input.recurringIssues,
        selectedLocationId: input.selectedLocationId,
        updatedAt: new Date().toISOString(),
      });
      return { success: true, updatedAt: new Date().toISOString() };
    }),
});
