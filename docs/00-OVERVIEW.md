# Plate — a conversational calorie tracker

**One idea:** every day is a conversation. You talk to a friendly agent about what you
ate; it looks food up, does the math, and quietly keeps the ledger. Pinch out and the
conversation dissolves into a magazine — every meal you've ever logged, as a
consistently-styled studio photograph, scrolling back through time.

## The three surfaces

| Surface | What it is | How you get there |
|---|---|---|
| **Thread** | One day = one chat thread with the agent. Food entries appear inline as cards. | Home |
| **Catalog** | A magazine/lookbook timeline of every meal, grouped by day. | Pinch out from Thread (or tap the day rail) |
| **Detail** | One meal, full-bleed image, macro breakdown, edit affordances. | Tap a card in either surface |

Horizontal paging across days works in both Thread and Catalog, and the two stay in
sync — pinch out on Tuesday, you land on Tuesday in the Catalog.

## Non-negotiables (the reason this app exists)

1. **Nothing technical leaks.** No JSON, no "tool call", no token counts, no model
   names anywhere in the main flow. The agent's tool use is rendered as small,
   human sentences ("looking up chicken shawarma…").
2. **Numbers are ambient, not nagging.** One ring, one number, at the top. Everything
   else is on demand.
3. **Every food has a picture.** Consistent lighting, consistent surface, consistent
   crop. A log that looks like a design object is a log you keep.
4. **Motion is the product.** Every state change is a spring, not a cut.

## Documents

- `01-ARCHITECTURE.md` — module map, data flow, agent loop
- `02-DESIGN.md` — color, type, motion, materials, shader inventory
- `03-AGENT.md` — system prompt, tool schemas, streaming protocol
- `04-IMAGERY.md` — image generation pipeline and the consistency contract
- `05-PROGRESS.md` — running build log / what's done / what's next
- `06-SETUP.md` — how to build and run it
