import * as z from "zod";

import { createTRPCRouter, protectedProcedure } from "../create-context";
import { storage } from "../../storage";

export const teamRouter = createTRPCRouter({
  add: protectedProcedure
    .input(z.object({ member: z.any() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.teamMembers.push(input.member);
      storage.setUserData(ctx.userId, data);
      return { success: true, memberId: input.member.id };
    }),

  remove: protectedProcedure
    .input(z.object({ memberId: z.string() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.teamMembers = data.teamMembers.filter(
        (m: any) => m.id !== input.memberId,
      );
      storage.setUserData(ctx.userId, data);
      return { success: true };
    }),
});
