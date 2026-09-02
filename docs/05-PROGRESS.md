# Progress

## State

Builds and runs on iOS 26.5 simulator. Verified by driving the app, not by reading it:
onboarding, logging through the local agent, day paging, the pinch in both directions,
the catalog, the entry sheet, light and dark.

**Done**
- Design system, data model, persistence, bundled nutrition DB
- Agent: streaming client, tool loop, seven tools, remote + local backends
- Imagery: Gemini/OpenAI providers, food-keyed cache, procedural renderer
- Surfaces: Thread, Catalog, Entry detail, Settings, Onboarding
- Metal: eleven stitchable entry points

**Not done**
- The remote agent has never run against a live key (none configured). The loop, SSE
  parsing and tool dispatch are exercised only by the local backend, which shares the
  tool runner but not the wire path.
- Image generation likewise: the request shapes follow current docs but have not been
  round-tripped against either API.
- No tests. For a codebase this size that is the largest gap.
- `search_history` and `update_profile` are reachable only from the remote agent; the
  local backend does not route to them.
- USDA lookup is a Settings field with no client behind it yet.

---

## SwiftUI constraints discovered the hard way

Each of these cost a build-and-look cycle, and each shaped the architecture. Worth
knowing before touching the rendering code.

**A shader or blur on an ancestor of a `ScrollView` suppresses its content entirely.**
Correct frame, correct background, correct overlay — and nothing drawn inside. This
killed the whole thread body and took a bisect (sentinel text, a solid rectangle, a
control view outside the scroll view) to isolate. Consequences:
- The zoom transition captures the departing surface as a still (`SurfaceSnapshot`) and
  warps *that*, while the arriving surface animates in live. Also the faster
  arrangement: one texture instead of a re-rendered scrolling hierarchy per frame.
- Grain and vignette are transparent overlays (`SurfaceOverlays`), never colour effects
  on the scrolling content.
- Scale and opacity are fine on a scroll view. Blur and shaders are not.

**A `layerEffect` over a system material samples an empty layer.** SwiftUI does not
composite a backdrop material into a shader's offscreen layer, so `layer.sample`
returns nothing and the pane renders black. Real refraction of a backdrop is not
available this way; `glassRim` computes rim lighting analytically instead and is drawn
over a genuine `.ultraThinMaterial`.

**Never put animating shapes inside a `TimelineView` closure.** `MacroRing` originally
applied its flow shader through a `ViewModifier` whose `content` was used inside the
timeline. That re-evaluated the trimmed arcs every frame, their animation restarted
continuously, and the ring rendered as three stranded ticks. The timeline now contains
only a static rectangle, and the arcs mask it.

**Mutating observed state from a view body is dropped.** `AppModel.session(for:)` is
called from `body` and lazily inserts into a dictionary; while that dictionary was
observed, SwiftUI discarded the update and the thread rendered blank.
`@ObservationIgnored` on every non-UI stored property.

**`GeometryReader` sizes its content to *ideal*, not to fill.** The day pager's pages
collapsed to the height of their headers, so the scrolling body had nowhere to go.

## Other bugs worth remembering

**`URL.path()` percent-encodes by default.** The container path always contains
"Application Support", so every `contentsOfDirectory(atPath:)` silently returned
nothing and the Catalog was permanently empty. Would have failed identically on device.
Use URL-based `FileManager` APIs, or `path(percentEncoded: false)`.

**Alpha tints do not survive small sizes.** Macro colours were ember at 55% and 26%
opacity; over the near-white ring track at a 10%-filled ring they had almost no
contrast and the ring read as disconnected ticks. They are now opaque colours
pre-blended toward the ground.

**A bare count reads as an ID.** `2 · Breakfast` scans as a row number, not a quantity.
It is now `×2`.
