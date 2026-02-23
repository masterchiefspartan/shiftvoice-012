import { createTRPCRouter } from "./create-context";
import { authRouter } from "./routes/auth";
import { syncRouter } from "./routes/sync";
import { shiftNotesRouter } from "./routes/shift-notes";
import { locationsRouter } from "./routes/locations";
import { teamRouter } from "./routes/team";

export const appRouter = createTRPCRouter({
  auth: authRouter,
  sync: syncRouter,
  shiftNotes: shiftNotesRouter,
  locations: locationsRouter,
  team: teamRouter,
});

export type AppRouter = typeof appRouter;
