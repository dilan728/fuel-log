# Design system

## Voice

Warm, brief, never clinical. The agent is a friend who happens to know nutrition —
not a form. It never says "logged successfully". It says "Got it — that's a solid
breakfast." Numbers appear because they're useful, not to score you.

## Color

Not a food app palette. No traffic-light macros, no green "good" / red "bad".
The ground is warm paper; the accent is a single ember.

| Token | Light | Dark | Use |
|---|---|---|---|
| `paper` | `#FBF8F4` | `#0D0C0B` | app ground |
| `paperRaised` | `#FFFFFF` | `#171614` | cards |
| `ink` | `#17151199` | `#F5F1EA` | primary text |
| `inkSoft` | 62% ink | 58% ink | secondary text |
| `inkFaint` | 34% ink | 32% ink | captions, axis |
| `ember` | `#E2542B` | `#FF6B3D` | the one accent |
| `emberSoft` | ember @ 12% | ember @ 16% | fills, chips |
| `hairline` | ink @ 8% | ink @ 10% | 0.5pt rules |

Macros are distinguished by **weight and position in the ring**, not hue:
protein = ember, carbs = ember @ 55%, fat = ember @ 28%. One family, three densities.
This is the single most important palette decision in the app — it keeps a screen
full of food photography from turning into a christmas tree.

## Type

System serif for numbers and food names (`.system(.title, design: .serif)`), system
sans for everything else. The serif is what makes it read as a magazine rather than
a dashboard.

| Role | Spec |
|---|---|
| `display` | serif, 44pt, weight .regular, tracking -1.2 — the day's calorie number |
| `title` | serif, 24pt, .regular, tracking -0.4 — food names, catalog headers |
| `body` | sans, 16pt, .regular, line spacing 5 — chat |
| `label` | sans, 13pt, .medium, tracking 0.2 |
| `caption` | sans, 11pt, .medium, tracking 0.6, uppercase — macro labels, dates |

## Motion

Three springs, used everywhere, defined once in `Motion.swift`:

| Name | Response | Damping | For |
|---|---|---|---|
| `.snap` | 0.32 | 0.86 | taps, toggles, chips |
| `.glide` | 0.55 | 0.88 | page transitions, sheet presentation |
| `.bounce` | 0.48 | 0.62 | arrival of a new food card, ring fills |

Rule: nothing cross-fades. Things move, scale, and blur into place. Any transition
that can be `matchedGeometryEffect` is one.

## Signature interactions

1. **Pinch to zoom out** (Thread → Catalog). Continuous and reversible — the chat
   bubbles scale down and blur out while the meal cards they contain fly into the
   catalog grid via `matchedGeometryEffect`. Driven by a live `MagnifyGesture`, not
   a tap. Rubber-bands past the endpoints.
2. **Day paging.** Horizontal drag, with the *header* (date + ring) moving at 0.6×
   the content's parallax and the background gradient shifting hue by time-of-day.
3. **Materialize.** A newly generated food image doesn't fade in — it resolves out
   of drifting noise via the `materialize` shader, over 900 ms, ember-tinted.
4. **Token bloom.** Streaming text has a soft ember glow on the leading ~8 characters
   that trails off behind the cursor (`tokenBloom` layer effect).

## Shader inventory (`Plate.metal`)

| Function | Kind | Where |
|---|---|---|
| `plateGrain` | colorEffect | full-screen film grain over the Catalog |
| `materialize` | layerEffect | food image reveal from noise |
| `tokenBloom` | layerEffect | streaming text leading-edge glow |
| `liquidGlass` | layerEffect | refraction + specular on floating bars |
| `emberFlow` | colorEffect | animated gradient inside the macro ring |
| `shimmerSweep` | colorEffect | placeholder card while an image generates |
| `warpZoom` | distortionEffect | barrel warp during the pinch transition |
| `softVignette` | colorEffect | catalog depth cue |

All are gated behind `Motion.reduceMotion`; when Reduce Motion is on, time-varying
shaders are evaluated at a fixed `t` (still pretty, just static).

## Accessibility

- Every macro value has an `accessibilityLabel` spelling out the unit.
- Ring and catalog tiles support Dynamic Type up to XXL before truncating.
- Reduce Motion: pinch transition becomes a 200 ms scale+opacity; no parallax.
- Reduce Transparency: glass surfaces fall back to `paperRaised` + hairline.
