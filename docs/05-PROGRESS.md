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

**Tests** — 101, all passing. `xcodebuild test -scheme Plate`. They cover the parts
where being wrong is silent: nutrition matching and scaling, phrase parsing, intent
classification, calendar arithmetic, wire-format round trips, the tool runner against a
real store, and the catalog layout. Three of them exist because they caught real bugs
and would catch them again.

**Not done**
- The remote agent has never run against a live key (none configured). The loop, SSE
  parsing and tool dispatch are exercised only by the local backend, which shares the
  tool runner but not the wire path.
- Image generation likewise: the request shapes follow current docs but have not been
  round-tripped against either API.
- `search_history` and `update_profile` are reachable only from the remote agent; the
  local backend does not route to them.
- USDA lookup is a Settings field with no client behind it yet.

---

## How the design is audited

Screenshots are easy to eyeball and hard to judge, so three tools do the judging.
All three live in the scratchpad workflow rather than the app.

**`probe.py`** turns a screenshot into numbers: where content actually starts and stops,
the gap between bands, and the left edge of every one. Misalignment of two or three
points is invisible to the eye and glaring in a column of integers. It is what found the
586-colour background, the masthead hanging 2pt inside its column, and the top-bar glyphs
indented ten.

**A pinned-transition hook.** `PLATE_ZOOM` freezes the surface transition at an exact
progress value so it can be screenshotted step by step. Simulator screen recordings only
capture frames when the screen *changes*, which makes a 550ms transition impossible to
sample evenly; a filmstrip of exact, reproducible frames can be re-checked after every
change. Every transition timing decision comes from one.

**Contact sheets at high contrast.** Rendering every dish into one sheet makes
classification mistakes obvious at a glance, and boosting contrast 6–9x exposes banding,
seams and fringing that are invisible at 1x but are exactly what reads as "computer
generated".

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

**Units are not all the same kind of thing, and conflating them is expensive.** The
first scaling rule was "same unit → ratio, otherwise treat the amount as a count of
servings". That is right for "2 bowls" of a per-cup row and catastrophically wrong for
"200g chicken breast", which logged 46,200 calories — a real day reached 48,559 in the
simulator. Fixed by giving every row a serving mass so mass and volume convert properly,
by only multiplying a serving when the serving is itself count-like, and by clamping the
last-resort path. Three tests now guard it, including one that sweeps every row against
every unit and asserts nothing can run away.

**Trigrams cannot see a substitution in the middle of a word.** "brocoli" → "broccoli"
works (a dropped letter costs three trigrams out of fifteen); "avacado" → "avocado" does
not, because the wrong letter spoils the three trigrams containing it. Matching now
takes the better of trigram similarity and a bounded edit distance.

**Word matching needs word boundaries.** `contains` served steak in a glass, because
"s-TEA-k" contains "tea".
