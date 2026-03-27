import * as z from "zod";

import { createTRPCRouter, protectedProcedure } from "../create-context";
import { storage } from "../../storage";

export const locationsRouter = createTRPCRouter({
  create: protectedProcedure
    .input(z.object({ location: z.any() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.locations.push(input.location);
      storage.setUserData(ctx.userId, data);
      return { success: true, locationId: input.location.id };
    }),

  delete: protectedProcedure
    .input(z.object({ locationId: z.string() }))
    .mutation(({ ctx, input }) => {
      const data = storage.getUserData(ctx.userId);
      if (!data) {
        return { success: false, error: "No user data found" };
      }
      data.locations = data.locations.filter(
        (l: any) => l.id !== input.locationId,
      );
      data.shiftNotes = data.shiftNotes.filter(
        (n: any) => n.locationId !== input.locationId,
      );
      storage.setUserData(ctx.userId, data);
      return { success: true };
    }),
});
