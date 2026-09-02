# Imagery

Every logged food has a real image file behind it — a generated photograph if a key is
configured, a locally path-marched render of the same dish if not. Both are cached JPEGs,
so nothing downstream needs a special case.

## The renderer — `FoodScene.metal`

Not a 2D effect. It renders an actual scene: signed-distance geometry, a three-point
studio setup, distance-field soft shadows, ambient occlusion, a GGX specular lobe,
wrapped diffuse standing in for subsurface scattering, and a depth-of-field pass driven
by a real depth channel. It supersamples 2× and resolves down, so edges are properly
antialiased.

Far too expensive per frame — which is the point. It runs **once per food**, off the main
actor, and the result is cached exactly like a photograph. That budget is what buys the
quality.

Flat-lay is deliberate: it composes in a grid at any tile size without perspective
distortion, and it matches the prompt used for real photography, so generated and
rendered images sit together without the page looking lit from two directions.

## Classification

Three independent questions, all answered by `KeywordMatch` (whole words, with a bonus
for the head noun — dish names lead with their main ingredient):

| | Values | Why it matters |
|---|---|---|
| `FoodForm` | plate · bowl · glass | Shot from overhead, the vessel is most of what gives an image its shape |
| `FoodTexture` | chunks · grains · leaves · topped · slab · liquid | Stops every dish being the same pile of pebbles in a different colour |
| `FoodPalette` | keyword → two colours | Pesto is green and a burger is brown |

`topped` is a base with a topping on it. Toast is bread with something on it, and that
ordering is the entire reason it reads as toast.

Palette colours are pulled toward the middle before the renderer sees them. The palette
is tuned for flat 2D fills; run through a physical shading model and a filmic tonemap
those same values come out lurid — the first pass had a highlighter-green avocado and a
fire-engine tomato. Drinks keep more of their chroma, because on an espresso the colour
*is* the subject. Flavoured dairy is pulled toward cream, because blueberry yogurt is
lilac rather than the colour of a blueberry.

## Caching

Keyed by the **normalised food name**, not the entry id. That one decision does three
things: the same food looks identical everywhere in the catalog, it is only ever paid for
once, and logging something you eat often is instant from the second time. In-flight
requests are de-duplicated by the same key — a catalog of thirty days that all contain
oatmeal would otherwise fan out into thirty identical requests.

`FoodSceneRenderer.version` is part of the key, so changing the shader supersedes old
renders instead of leaving them next to new ones in the same catalog.

## Providers

| Provider | Model |
|---|---|
| Gemini | `gemini-3.1-flash-image` — current Nano Banana generalist. Imagen is deprecated and deliberately unused. |
| OpenAI | `gpt-image-1-mini` |
| — | the local renderer |

Keys go in the Keychain and are sent as a header, never as a URL query parameter.

## Defects worth remembering

Every one of these was found by rendering contact sheets and looking at them, several
only at 6–9× contrast:

- **Every bowl was a featureless white sphere.** The half-space that opens the shell was
  inverted, so it kept the dome and discarded the bowl.
- **Concentric contour bands across the backdrop** — the naive soft-shadow estimator.
  Then, after fixing that, *terraces*, because every pixel marched in lockstep; dithering
  each ray's start phase turns the banding into noise the film grain absorbs.
- **Hard black patches on the lit side of every piece** — shadow acne. Displaced surfaces
  are not strict distance fields, and the ray began within a hair of the surface it was
  testing.
- **A bar of chocolate came out as a churned canyon.** Displacement amplitude was
  proportional to piece radius, so a wide flat slab got displacement two thirds of its own
  thickness. It is absolute for flat food now.
- **A straight seam across the backdrop** where the shadow ray hit a fixed distance limit
  and abruptly stopped occluding.
- **Every drink was a flat disc of paint.** A mirror-smooth horizontal surface under one
  directional light shows its specular at exactly one point, which from overhead is
  usually off the plate. A hundredth of a unit of ripple breaks the highlight across the
  surface.
- **Ramen was served as a bowl of milk.** "ramen" appeared in two palette rows with
  identical scores, and ties go to declaration order. There is now a test for that.
