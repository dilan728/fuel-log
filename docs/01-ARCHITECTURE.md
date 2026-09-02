# Architecture

Plain SwiftUI + Observation. No third-party packages. iOS 18.0 deployment target.
Everything that could be a network dependency has a real, working offline path.

```
Plate/
  App/           PlateApp, RootView, AppModel (the single @Observable root)
  Design/        Palette, Typography, Motion, Materials, Haptics — pure tokens
  Shaders/       Plate.metal + typed Swift wrappers
  Models/        FoodEntry, DayLog, ChatMessage, NutritionFacts, UserProfile
  Persistence/   LogStore (actor, JSON on disk), ImageCache (disk + memory)
  Services/
    Agent/       AnthropicClient (SSE), AgentTools, AgentEngine, SystemPrompt
    Nutrition/   NutritionDatabase (bundled, ~300 foods) + fuzzy match
    Imagery/     FoodImageService (Gemini / OpenAI / procedural), PromptRecipe
  Features/      DayThread, Catalog, Detail, Settings, Onboarding
  Components/    Reusable views (rings, cards, glass, streaming text, pager)
```

## Data flow

```
        user types
             │
             ▼
      ┌─────────────┐   append user turn
      │  AppModel   │──────────────────────────┐
      └─────────────┘                          ▼
             │                          ┌─────────────┐
             │  observe                 │  LogStore   │  actor, serialized
             ▼                          │  (disk JSON)│  writes, debounced
      ┌─────────────┐                   └─────────────┘
      │  DayThread  │                          ▲
      │    view     │                          │
      └─────────────┘                          │
             ▲                                 │
             │ stream events                   │ mutations
      ┌─────────────┐    tool calls     ┌──────────────┐
      │ AgentEngine │──────────────────▶│  AgentTools  │
      └─────────────┘◀──────────────────└──────────────┘
             │  SSE                            │
             ▼                                 ├── search_nutrition  → NutritionDatabase
      ┌──────────────────┐                     ├── log_food         → LogStore
      │ AnthropicClient  │                     ├── update_food      → LogStore
      └──────────────────┘                     ├── remove_food      → LogStore
                                               ├── read_day         → LogStore
                                               └── search_history   → LogStore
                                                         │
                                                         ▼
                                              ┌────────────────────┐
                                              │  FoodImageService  │ (fire & forget,
                                              └────────────────────┘  per entry)
```

### Why an actor for the store

Image generation, agent streaming, and user edits all mutate the same day log
concurrently. `LogStore` is an `actor` that owns the truth; `AppModel` holds an
`@MainActor` projection that views read. Writes are debounced (400 ms) and atomic
(write-to-temp + `replaceItemAt`), so a crash mid-write can't corrupt the log.

## The agent loop

`AgentEngine.send(_:)` runs a standard tool-use loop against `POST /v1/messages`
with `stream: true`:

1. Build request: system prompt (cached) + full day transcript + tool defs.
2. Consume SSE. `text_delta` → append to the live assistant bubble.
   `input_json_delta` → accumulate tool arguments.
3. On `stop_reason == "tool_use"`: execute every `tool_use` block **concurrently**,
   append all `tool_result` blocks in one user message, loop.
4. On `end_turn`: done.

Tool execution surfaces to the UI as a `ThoughtChip` — a one-line human-readable
label from `AgentTools.humanLabel(for:)`, never the raw JSON.

**Offline / no-key path:** `AgentEngine` is backed by an `AgentBackend` protocol.
`LocalAgentBackend` is a genuine (non-LLM) parser that handles the 80% case —
"2 eggs and toast", "remove the latte", "how am I doing?" — using the bundled
nutrition DB and a small grammar. The app is fully usable with zero configuration.

## Rendering

- Every custom effect is a Metal function in `Plate.metal`, exposed through
  `ShaderLibrary` and wrapped in a typed Swift API (`Shaders.grain(intensity:)`)
  so no view ever writes a stringly-typed shader call.
- `TimelineView(.animation)` drives time-based shaders only where visible; each
  such view is gated on `reduceMotion` and on being on-screen.
