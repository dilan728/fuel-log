# The agent

## Two backends, one sink

`AgentBackend` has two implementations and both drive the same `AgentSink`, so the UI
cannot tell them apart — including the activity chips, because the local backend really
does perform lookups and writes.

| | `RemoteAgentBackend` | `LocalAgentBackend` |
|---|---|---|
| Needs | An Anthropic key | Nothing |
| Model | `claude-opus-5` | A phrase parser |
| Handles | Anything | Logging, removing, day summaries, setting a target |
| Nutrition | The same bundled DB, via the same tools | Same |

The local backend replies one word at a time on purpose. Not to imitate a model, but
because the streaming presentation *is* the app's reading rhythm; a reply that appears
all at once feels like a different product.

## Request shape

`POST /v1/messages`, streaming. Notable choices:

- **`output_config.effort: "low"`.** This is arithmetic over a lookup table, not a
  reasoning problem. Low effort keeps replies fast and the tone conversational; high
  effort produced noticeably more preamble.
- **Adaptive thinking with `display: "summarized"`**, so "thinking" is a real state
  rather than a spinner over dead air.
- **The system prompt is split** into a frozen half and a per-request half. The frozen
  half carries the `cache_control` breakpoint and must never contain the date or the
  day being discussed, or every request pays full price.
- **`max_tokens: 8000`**, well above any real reply, because hitting the cap truncates
  mid-sentence.

## The loop

Standard: stream → on `stop_reason == "tool_use"`, run every call **concurrently**, put
all results in **one** user message, repeat. Splitting tool results across messages
teaches the model to stop batching its calls. Capped at six round trips.

`ContentBlock.opaque` preserves any block type we don't model — thinking blocks, and
whatever ships next — as raw JSON, so they replay byte-identically. Modelling them
field-by-field would break the moment the shape changed.

## Tools

Seven, deliberately coarse. `log_food` takes an array because "eggs, toast and a
coffee" is one thought and should be one call.

`search_nutrition` · `log_food` · `update_food` · `remove_food` · `read_day` ·
`search_history` · `update_profile`

Results are terse JSON with short keys: every tool result is replayed on every
subsequent request, so a chatty result is a tax paid once per turn for the rest of
the day.

**`AgentTools.activityLabel(for:input:)` is the only place tool plumbing becomes human
text.** If a tool name ever reaches the screen, it came from a path that skipped it.
Chips start vague ("Looking something up") because a tool's name arrives before its
arguments do, and are refined once the block closes.
