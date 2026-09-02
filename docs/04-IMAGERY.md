# Imagery

## The consistency contract

A catalog of meals only reads as a catalog if every plate was shot the same way. So the
prompt in `ImagePromptRecipe` fixes everything except the food: one camera angle
(overhead), one background (warm neutral paper), one vessel (small matte off-white
ceramic), one light direction (upper-left).

That light direction is also what the procedural renderer uses, so generated and
procedural images can sit next to each other in the Catalog without the page looking
lit from two places at once.

Portions are described in words, never numbers — "3 eggs" reliably produces three
plates rather than one plate with three eggs on it.

## Providers

| Provider | Model | Why |
|---|---|---|
| Gemini | `gemini-3.1-flash-image` | Default. Current Nano Banana generalist; fast and cheap. Imagen is deprecated and deliberately unused. |
| OpenAI | `gpt-image-1-mini` | Alternative. |
| — | `proceduralPlate` | No key. Not a fallback so much as the floor. |

Keys go in the Keychain and are sent as a header, never as a URL query parameter.

## Caching, and why it is keyed by food

`ImageCache` keys on the **normalised food name**, not the entry id. That one decision
does three things at once: the same food looks identical everywhere it appears in the
Catalog, a food is only ever paid for once, and logging something you eat often is
instant from the second time onward. `FoodImageService` also de-duplicates in-flight
requests by the same key — opening a catalog of thirty days that all contain oatmeal
would otherwise fan out into thirty identical paid requests.

## The procedural renderer

`proceduralPlate` in `Plate.metal` draws a dish from a seed. Two things make it work:

**It knows three vessels** — plate, bowl, glass — chosen by `FoodForm.infer(from:)`.
Shot from overhead the vessel is most of what gives an image its shape, and a flat
white drawn as a pile of solids on a dinner plate is instantly, obviously wrong in a
way that a slightly-off brown never is.

**It draws discrete pieces, not a field.** The first version summed metaballs, and
every dish came out as a single glossy dome distinguishable only by colour. It now
tracks the *nearest* piece, which keeps pieces separate, gives each one its own surface
normal to light, and leaves a seam where two touch. The domes are flattened — a true
hemisphere makes everything look like dumplings.

Colour comes from `FoodPalette`, a keyword table. Not clever, but a lookup gets "pesto
is green" right far more reliably than any hue derived from hashing the name.
