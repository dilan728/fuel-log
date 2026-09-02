# Design system

## The idea

A printed page, not an app screen. Structure comes from rules, alignment and white
space — not from cards, shadows and gradients. The photographs are the only things on
the page with weight, and everything else gets out of their way.

Three rules that decide most arguments:

1. **The ground is flat.** One colour, edge to edge. The first version washed the page
   with a time-of-day gradient; measured, its margins alone held 586 distinct colours
   spanning 40 levels. A page that cannot decide what colour it is *is* what "looks
   generated" means.
2. **No shadows.** Anywhere. A white rounded rectangle with a drop shadow is the most
   generic object in mobile design, and a column of them turns a page into a feed.
3. **Tints are opaque.** Ember at 26% over near-white has almost no contrast at small
   sizes. Every tint is pre-blended toward the ground instead.

## Measure — `Metrics`

One 4pt rhythm: 2 · 4 · 8 · 12 · 16 · 24 · 32 · 48. One margin: **24pt**, used
everywhere, so every left edge in the app agrees.

`Hairline` reads `displayScale` and divides. `Divider`, and any `frame(height: 0.5)`,
lands on a half pixel at 3× and antialiases into a grey smear; a real one-pixel rule is
most of what separates a typeset page from a web page.

Photographs are rounded **3pt**. A 20pt radius reads as a UI card; print does not round
its images at all.

Named `Metrics` and not `Layout` because SwiftUI already has a `Layout` protocol, and
shadowing it silently breaks any custom layout in the module.

## Colour — `Palette`

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#FAF7F2` | `#0C0B0A` | the page, flat |
| `paperSunken` | `#F0EAE1` | `#171513` | the well an image sits in |
| `ink` | `#14120F` | `#F6F2EB` | text |
| `hairline` | ink @ 13% | ink @ 13% | one-pixel rules |
| `ember` | `#C8451F` | `#FF6B3D` | the one accent |

**Macros are separated by density, not hue** — protein is ember, carbs and fat are the
same ember pre-blended toward the ground. A screen full of food photography already has
all the colour it can handle; traffic-light macro chips would turn the catalog into a
christmas tree.

## Type — `TypeStyle`

Serif for content — food names, figures, dates. Sans for chrome — labels, buttons,
captions. That split is most of what makes the app read as a page.

**Every style carries its own tracking**, because the right value is a function of size
and it is the control most often left at zero: `masthead` is pulled in 1.4pt, `micro` is
opened out 0.85pt. Units get their own lowercase style — "164 CAL" shouts over the
figure it belongs to.

Display type is also pulled left by its side bearing (`opticalLeading`). Measured, 44pt
serif figures began 2.0pt right of their frame, so the masthead hung two points inside
every rule beneath it. Two points is invisible as a number and unmistakable as a wobble
in a left edge.

## Motion — `Motion`

Three springs — `snap` (0.32/0.86), `glide` (0.55/0.88), `bounce` (0.48/0.62) — plus
`drift` for ambient movement. Nothing cross-fades; things move, scale and blur.

`Curve.smoothstep` is the workhorse for transitions. A linear crossfade leaves both
layers at half strength in the middle and the screen reads as a smear.

## The signature interaction

Pinch to move between the Thread and the Catalog. It is a scrubbable value, not a canned
animation — push halfway, change your mind, come back.

The departing surface is captured as a **still** and warped away, while the arriving
surface animates in live. This is forced by a SwiftUI constraint (see `05-PROGRESS.md`)
and is also the faster arrangement: one texture instead of a re-rendered scrolling
hierarchy every frame.

Its timing was tuned against filmstrips, not by feel:

- The still **holds** before it drops; the catalog is fully present well before it goes.
- The lens warp **peaks at the midpoint**, not the end, where the layer carrying it is
  already invisible.
- The warp always bends **inward**, so the shader never samples past its own layer.
- Chromatic aberration is cubed in radius and gated on the blur, so it is nil across the
  central two thirds and appears only at the corners of an already-soft frame. Coloured
  fringes on 10pt letterforms read as a rendering fault however subtle they are.

## Shaders

Four in the interface — `materialize` (an image resolving out of scattered noise),
`shimmerSweep`, `pinchWarp`, `grainOverlay` — and two compute kernels for the food
renderer. Anything unreachable is deleted: `ShaderLibrary` resolves by name at runtime,
so a wrapper left behind after its shader is gone still compiles and fails silently.

## Accessibility

Reduce Motion freezes time-based shaders at a flattering frame and drops the chromatic
split. Reduce Transparency replaces materials with `paperRaised` and a hairline. Every
figure has a spelled-out accessibility label.
