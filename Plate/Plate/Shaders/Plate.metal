//  Plate.metal
//
//  Every custom visual effect in Plate. All entry points are [[stitchable]] and are
//  reached from Swift through `PlateShaders`, never by raw string name.
//
//  Conventions
//  -----------
//  * `position` is in the effect's user-space points (not normalized). Every function
//    takes `size` so it can normalize itself; SwiftUI does not provide it implicitly.
//  * Time is passed in explicitly as `time` (seconds). When Reduce Motion is on, Swift
//    passes a frozen value rather than a running clock, so these functions never need
//    to know about accessibility.
//  * Colors arriving from Swift are already in the display color space; we do not
//    gamma-correct here.

#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>

using namespace metal;

// MARK: - Noise primitives

static float hash11(float p) {
    p = fract(p * 0.1031f);
    p *= p + 33.33f;
    p *= p + p;
    return fract(p);
}

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031f);
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.x + p3.y) * p3.z);
}

static float2 hash22(float2 p) {
    float3 p3 = fract(float3(p.xyx) * float3(0.1031f, 0.1030f, 0.0973f));
    p3 += dot(p3, p3.yzx + 33.33f);
    return fract((p3.xx + p3.yz) * p3.zy);
}

/// Value noise with quintic interpolation — smoother derivatives than smoothstep,
/// which matters because we take differences of this field in `materialize`.
static float valueNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    float2 u = f * f * f * (f * (f * 6.0f - 15.0f) + 10.0f);

    float a = hash12(i);
    float b = hash12(i + float2(1.0f, 0.0f));
    float c = hash12(i + float2(0.0f, 1.0f));
    float d = hash12(i + float2(1.0f, 1.0f));

    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// Four-octave fbm. Four is the point where adding more stops being visible at
/// the sizes we draw at.
static float fbm(float2 p) {
    float sum = 0.0f;
    float amp = 0.5f;
    float2 shift = float2(37.0f, 17.0f);
    const float2x2 rot = float2x2(0.80f, 0.60f, -0.60f, 0.80f);
    for (int i = 0; i < 4; ++i) {
        sum += amp * valueNoise(p);
        p = rot * p * 2.02f + shift;
        amp *= 0.5f;
    }
    return sum;
}

static float luminance(half3 c) {
    return dot(float3(c), float3(0.2126f, 0.7152f, 0.0722f));
}

// MARK: - plateGrain (colorEffect)
//
// Film grain over the Catalog. Two things make this read as *film* rather than as
// TV static: the grain is luminance-dependent (shadows are grainier than highlights,
// as with real silver halide), and it is monochrome, applied as a luminance offset
// rather than per-channel noise.

[[ stitchable ]] half4 plateGrain(float2 position,
                                  half4 color,
                                  float2 size,
                                  float time,
                                  float intensity) {
    if (color.a < 0.001h) { return color; }

    // Animate by jumping the sample lattice each frame rather than scrolling it,
    // so the grain shimmers in place instead of appearing to drift.
    float2 seedPos = position + float2(hash11(floor(time * 24.0f)) * 512.0f,
                                       hash11(floor(time * 24.0f) + 7.0f) * 512.0f);
    float n = hash12(seedPos) - 0.5f;

    // Silver-halide response: peak grain in the midtones-to-shadows.
    float lum = luminance(color.rgb / max(color.a, 0.001h));
    float response = smoothstep(1.0f, 0.15f, lum) * 0.75f + 0.25f;

    half offset = half(n * intensity * response);
    half3 grained = clamp(color.rgb + offset * color.a, 0.0h, color.a);
    return half4(grained, color.a);
}

// MARK: - materialize (layerEffect)
//
// A generated food image resolving out of noise. The reveal is not a fade: unrevealed
// pixels are *scattered* — sampled from a displaced position — so the image looks like
// it is condensing rather than dissolving in. A bright ember wavefront rides the
// threshold, which is what sells it as generative rather than as a wipe.
//
// progress: 0 (pure noise) → 1 (clean image).

[[ stitchable ]] half4 materialize(float2 position,
                                   SwiftUI::Layer layer,
                                   float2 size,
                                   float progress,
                                   float seed,
                                   half4 tint) {
    float2 uv = position / max(size, float2(1.0f));

    // The threshold field. Low-frequency fbm biased so the reveal starts near the
    // centre and spreads outward — a plate resolving from its middle.
    float radial = length(uv - 0.5f) * 1.15f;
    float field = fbm(uv * 3.2f + seed * 13.7f) * 0.62f + radial * 0.38f;

    // Widen the transition band so the wavefront is visible.
    const float band = 0.16f;
    float p = mix(-band, 1.0f + band, clamp(progress, 0.0f, 1.0f));
    float revealed = smoothstep(field - band, field + band, p);

    // Scatter unrevealed pixels along a noise-driven direction. The displacement is
    // largest at the wavefront and zero once revealed, so grains appear to fly into place.
    float2 dir = normalize(hash22(floor(position / 6.0f) + seed) - 0.5f + 1e-4f);
    float scatter = (1.0f - revealed) * 46.0f;
    half4 sampled = layer.sample(position + dir * scatter);

    // The wavefront itself: a thin ember ridge at field ≈ p.
    float ridge = exp(-pow((field - p) / 0.055f, 2.0f));

    half4 outColor = sampled * half(revealed);
    outColor += tint * half(ridge * 0.85f * (1.0f - revealed * 0.35f));

    // Unrevealed area keeps a faint dust of the tint so the frame is never empty.
    float dust = hash12(position * 0.7f + seed) * (1.0f - revealed) * 0.09f;
    outColor += tint * half(dust);

    return clamp(outColor, 0.0h, 1.0h);
}

// MARK: - tokenBloom (layerEffect)
//
// Streaming text. Characters near the write head get a warm bloom that trails off
// behind them and a sub-pixel upward lift, so text appears to *settle* as it arrives.
// Applied to the whole text layer; `head` is the caret position in the same space.

[[ stitchable ]] half4 tokenBloom(float2 position,
                                  SwiftUI::Layer layer,
                                  float2 head,
                                  float radius,
                                  float strength,
                                  half4 tint) {
    // Distance measured with a squashed metric: the bloom should reach back along the
    // line much further than it reaches across lines.
    float2 d = position - head;
    float dist = length(float2(d.x * 0.42f, d.y * 1.6f));
    float falloff = 1.0f - smoothstep(0.0f, max(radius, 1.0f), dist);

    // Only trail *behind* the head (to the left / above), never ahead of it.
    float behind = smoothstep(radius * 0.55f, -radius * 0.1f, d.x) * 0.7f + 0.3f;
    float amount = falloff * behind * strength;

    // Lift: glyphs near the head are sampled from slightly below, so they read as
    // rising into position. Sub-pixel, deliberately — you feel it, you don't see it.
    half4 base = layer.sample(position + float2(0.0f, amount * 1.4f));

    // Cheap 4-tap bloom, only paid for where amount > 0.
    half4 glow = 0.0h;
    if (amount > 0.01f) {
        const float r = 2.5f;
        glow += layer.sample(position + float2(r, 0.0f));
        glow += layer.sample(position + float2(-r, 0.0f));
        glow += layer.sample(position + float2(0.0f, r));
        glow += layer.sample(position + float2(0.0f, -r));
        glow *= 0.25h;
    }

    half4 bloomed = base + tint * glow.a * half(amount * 0.9f);
    return clamp(bloomed, 0.0h, 1.0h);
}

// MARK: - Glass
//
// Two functions, because two different jobs turned out to need two different tools.
//
// `liquidGlass` (layerEffect) genuinely refracts: it offsets the sample position along
// the shape's surface normal near the rim. It requires content that actually rasterizes
// into the layer — an image, a card, a view hierarchy. It does NOT work over a system
// material: SwiftUI does not composite a backdrop material into the offscreen layer a
// shader reads from, so `layer.sample` returns nothing and the pane renders black.
// (Learned the hard way; the first build of the composer was a black slab.)
//
// `glassRim` (colorEffect) is what floating bars use. It computes rim lighting and
// specular analytically from the same signed distance field, samples nothing, and is
// drawn *over* a real `.ultraThinMaterial` — so the blur is genuine even though the
// highlight is computed. Cheaper, and correct in the case that actually ships.

static float roundedBoxSDF(float2 p, float2 halfSize, float radius) {
    float2 q = abs(p) - halfSize + radius;
    return length(max(q, 0.0f)) + min(max(q.x, q.y), 0.0f) - radius;
}

[[ stitchable ]] half4 liquidGlass(float2 position,
                                   SwiftUI::Layer layer,
                                   float2 size,
                                   float cornerRadius,
                                   float thickness,
                                   float lightAngle,
                                   half4 specular) {
    float2 half_ = size * 0.5f;
    float2 p = position - half_;
    float d = roundedBoxSDF(p, half_, cornerRadius);

    // Numerical gradient of the SDF = outward surface normal.
    const float eps = 1.0f;
    float2 normal = normalize(float2(
        roundedBoxSDF(p + float2(eps, 0.0f), half_, cornerRadius) - roundedBoxSDF(p - float2(eps, 0.0f), half_, cornerRadius),
        roundedBoxSDF(p + float2(0.0f, eps), half_, cornerRadius) - roundedBoxSDF(p - float2(0.0f, eps), half_, cornerRadius)
    ) + 1e-5f);

    // Refraction ramps up only within `thickness` of the edge — the middle of the
    // panel stays undistorted so text laid over it remains readable.
    float edge = 1.0f - smoothstep(-thickness, 0.0f, d);
    float bend = pow(edge, 2.2f) * thickness * 0.85f;

    half4 refracted = layer.sample(position - normal * bend);

    // Specular: a directional rim highlight, brightest where the normal faces the light.
    float2 lightDir = float2(cos(lightAngle), sin(lightAngle));
    float facing = max(dot(normal, lightDir), 0.0f);
    float rim = pow(edge, 3.0f) * pow(facing, 2.5f);

    // A second, tighter highlight on the opposite rim reads as the glass's far wall.
    float backRim = pow(edge, 6.0f) * pow(max(-dot(normal, lightDir), 0.0f), 3.0f) * 0.45f;

    half4 result = refracted + specular * half(rim * 0.85f + backRim);

    // Very slight brightening across the whole pane, as glass is never perfectly clear.
    result += specular * 0.03h * result.a;

    return clamp(result, 0.0h, 1.0h);
}

/// Rim lighting for a pane of glass, drawn over a real material.
///
/// Output is premultiplied and mostly transparent — this is an overlay, not a fill.
[[ stitchable ]] half4 glassRim(float2 position,
                                half4 color,
                                float2 size,
                                float cornerRadius,
                                float thickness,
                                float lightAngle,
                                half4 specular) {
    if (color.a < 0.001h) { return half4(0.0h); }

    float2 half_ = size * 0.5f;
    float2 p = position - half_;
    float d = roundedBoxSDF(p, half_, cornerRadius);

    const float eps = 1.0f;
    float2 normal = normalize(float2(
        roundedBoxSDF(p + float2(eps, 0.0f), half_, cornerRadius) - roundedBoxSDF(p - float2(eps, 0.0f), half_, cornerRadius),
        roundedBoxSDF(p + float2(0.0f, eps), half_, cornerRadius) - roundedBoxSDF(p - float2(0.0f, eps), half_, cornerRadius)
    ) + 1e-5f);

    float edge = 1.0f - smoothstep(-thickness, 0.0f, d);

    float2 lightDir = float2(cos(lightAngle), sin(lightAngle));
    float facing = max(dot(normal, lightDir), 0.0f);

    // The lit rim, and a tighter counter-highlight reading as the far wall of the pane.
    float rim = pow(edge, 2.4f) * pow(facing, 1.8f);
    float backRim = pow(edge, 7.0f) * pow(max(-dot(normal, lightDir), 0.0f), 3.0f) * 0.55f;

    // A broad sheen falling from the light side across the face, which is what stops
    // the middle of the pane from reading as flat plastic.
    float sheen = clamp(0.5f - dot(p / max(size, float2(1.0f)), lightDir), 0.0f, 1.0f);
    float face = sheen * sheen * 0.085f;

    float alpha = clamp(rim * 0.95f + backRim + face, 0.0f, 1.0f) * float(color.a);
    half a = half(alpha);
    return half4(specular.rgb * a, a);
}

// MARK: - emberFlow (colorEffect)
//
// The animated fill inside the macro ring. Rather than a static stroke color, energy
// flows around the arc — slow, low-contrast, and only visible if you look. Applied to
// a stroked shape, so `color.a` already carries the stroke's antialiasing.

[[ stitchable ]] half4 emberFlow(float2 position,
                                 half4 color,
                                 float2 size,
                                 float time,
                                 half4 warm,
                                 half4 cool) {
    if (color.a < 0.001h) { return color; }

    float2 uv = (position - size * 0.5f) / max(size.x, 1.0f);
    float angle = atan2(uv.y, uv.x);

    // Two counter-rotating bands at incommensurate speeds — never visibly repeats.
    float a = sin(angle * 2.0f - time * 0.55f);
    float b = sin(angle * 3.0f + time * 0.31f + 1.7f);
    float mixAmount = clamp((a * 0.6f + b * 0.4f) * 0.5f + 0.5f, 0.0f, 1.0f);

    half3 flowed = mix(half3(cool.rgb), half3(warm.rgb), half(mixAmount));

    // Preserve the incoming alpha (the stroke mask) and its premultiplication.
    return half4(flowed * color.a, color.a);
}

// MARK: - shimmerSweep (colorEffect)
//
// The placeholder while an image generates. A soft diagonal sheen crossing a card.
// Slower and lower-contrast than the usual skeleton shimmer — this is a thing being
// made, not a thing being loaded.

[[ stitchable ]] half4 shimmerSweep(float2 position,
                                    half4 color,
                                    float2 size,
                                    float time,
                                    half4 sheen) {
    if (color.a < 0.001h) { return color; }

    float2 uv = position / max(size, float2(1.0f));
    // Diagonal coordinate, travelling from lower-left to upper-right.
    float t = (uv.x * 0.75f + uv.y * 0.65f);
    float sweep = fract(time * 0.32f);
    // Map the sweep across a range wider than [0,1] so there is a pause between passes.
    float head = sweep * 2.2f - 0.6f;

    float band = exp(-pow((t - head) / 0.16f, 2.0f));
    // A trailing secondary band, dimmer, gives the sheen some body.
    band += exp(-pow((t - head + 0.22f) / 0.26f, 2.0f)) * 0.35f;

    // A slow breathing noise underneath so the card is never completely static.
    float breathe = fbm(uv * 2.4f + time * 0.06f) * 0.06f;

    half4 result = color + sheen * half((band * 0.5f + breathe) * float(color.a));
    return clamp(result, 0.0h, 1.0h);
}

// MARK: - pinchWarp (layerEffect)
//
// The Thread → Catalog pinch. A barrel/pincushion warp with per-channel divergence,
// so the frame feels like it is being pulled through a lens. `amount` is signed:
// negative pulls in (zooming out to the Catalog), positive pushes out.
//
// This is a layerEffect rather than a distortionEffect specifically so the channels
// can separate — a distortionEffect returns one position for all three.

[[ stitchable ]] half4 pinchWarp(float2 position,
                                 SwiftUI::Layer layer,
                                 float2 size,
                                 float amount,
                                 float chroma) {
    float2 center = size * 0.5f;
    float2 d = position - center;
    float maxR = length(center);
    float r = length(d) / max(maxR, 1.0f);

    // Barrel term. r^2 keeps the centre nearly still and bends the corners most.
    float k = amount * 0.55f;
    float scale = 1.0f + k * r * r;

    float2 base = center + d * scale;

    // Channel divergence grows with radius and with |amount|.
    float sep = chroma * abs(amount) * r * 9.0f;
    float2 dir = normalize(d + 1e-5f);

    half4 cr = layer.sample(base + dir * sep);
    half4 cg = layer.sample(base);
    half4 cb = layer.sample(base - dir * sep);

    // Average the alphas rather than taking green's, or edges fringe on transparency.
    half alpha = (cr.a + cg.a + cb.a) / 3.0h;
    return half4(cr.r, cg.g, cb.b, alpha);
}

// MARK: - softVignette (colorEffect)
//
// Depth cue for the Catalog. Elliptical, following the aspect ratio, so it doesn't
// look like a circle stamped on a tall screen.

[[ stitchable ]] half4 softVignette(float2 position,
                                    half4 color,
                                    float2 size,
                                    float strength,
                                    float radius) {
    float2 uv = (position / max(size, float2(1.0f))) - 0.5f;
    // Normalize by the shorter side so the falloff is elliptical, not circular.
    float aspect = size.x / max(size.y, 1.0f);
    uv.x *= aspect;
    float r = length(uv) / max(radius, 0.01f);

    float v = 1.0f - smoothstep(0.55f, 1.15f, r) * strength;
    return half4(color.rgb * half(v), color.a);
}

// MARK: - proceduralPlate (colorEffect)
//
// The zero-configuration food image. With no image backend available this draws a
// plausible dish from a seed: a vessel under raking studio light, with food in it.
//
// It knows three vessels — plate, bowl, glass — because drawing a flat white as a pile
// of solids on a dinner plate was the single most obviously wrong thing about the first
// version. `form` picks the vessel; `hueA`/`hueB` come from the food's own name, so this
// shader never needs to know anything about food.
//
// The key light is upper-left, matching `ImagePromptRecipe`, so procedurally-drawn and
// generated images can sit side by side in the Catalog without the page looking lit
// from two directions.

[[ stitchable ]] half4 proceduralPlate(float2 position,
                                       half4 color,
                                       float2 size,
                                       float seed,
                                       float form,
                                       half4 hueA,
                                       half4 hueB,
                                       half4 ground) {
    float2 uv = position / max(size, float2(1.0f));
    float2 p = uv - 0.5f;
    float aspect = size.x / max(size.y, 1.0f);
    p.x *= aspect;

    // --- Backdrop: a wide, gentle sweep. Deliberately shallow — a steep falloff reads
    // as a vignette rather than as a lit surface, and made the first version murky.
    float sweep = 1.0f - length(p - float2(-0.24f, -0.28f)) * 0.30f;
    half3 col = half3(ground.rgb) * half(clamp(sweep, 0.86f, 1.06f));
    col *= half(0.985f + fbm(p * 7.0f + seed) * 0.03f);   // paper tooth

    // --- Vessel geometry.
    float vesselR, foodR;
    if (form < 0.5f)      { vesselR = 0.400f; foodR = 0.205f; }  // plate
    else if (form < 1.5f) { vesselR = 0.345f; foodR = 0.160f; }  // bowl
    else                  { vesselR = 0.270f; foodR = 0.208f; }  // glass or cup

    float vd = length(p);

    // Contact shadow, offset away from the key light.
    float shadow = 1.0f - smoothstep(vesselR * 0.98f, vesselR * 1.34f, length(p - float2(0.038f, 0.046f)));
    col *= half(1.0f - shadow * 0.13f);

    // Vessel body.
    float vessel = 1.0f - smoothstep(vesselR - 0.005f, vesselR + 0.005f, vd);
    half3 ceramic = half3(0.960h, 0.950h, 0.932h) * half(clamp(sweep + 0.10f, 0.78f, 1.12f));
    col = mix(col, ceramic, half(vessel));

    // Rim catch — a bright ring just inside the edge, brightest toward the light.
    float rimBand = smoothstep(vesselR * 0.87f, vesselR * 0.98f, vd)
                  * (1.0f - smoothstep(vesselR - 0.004f, vesselR + 0.004f, vd));
    float rimLight = clamp(dot(normalize(p + 1e-5f), float2(-0.66f, -0.75f)) * 0.5f + 0.5f, 0.0f, 1.0f);
    col += half3(rimBand * (0.05f + rimLight * 0.09f));

    if (form >= 1.5f) {
        // --- Glass or cup: a disc of liquid with a meniscus and a specular crescent.
        float liquid = 1.0f - smoothstep(foodR - 0.004f, foodR + 0.004f, vd);
        if (liquid > 0.001f) {
            float depth = smoothstep(foodR, foodR * 0.25f, vd);        // darker toward centre
            half3 drink = mix(half3(hueB.rgb), half3(hueA.rgb), half(depth * 0.85f));

            // Crema / foam: a soft mottled lightening on top for anything milky.
            float foam = fbm(p * 11.0f + seed * 3.0f);
            drink = mix(drink, drink + half3(0.10h), half(clamp(foam - 0.45f, 0.0f, 1.0f) * 0.55f));

            // Meniscus — the liquid climbing the vessel wall.
            float meniscus = smoothstep(foodR * 0.86f, foodR, vd);
            drink += half3(meniscus * 0.09f);

            col = mix(col, drink, half(liquid));

            // A tight elliptical highlight where the window reflects.
            float2 h = (p - float2(-0.07f, -0.085f)) * float2(1.0f, 1.9f);
            col += half3(pow(clamp(1.0f - length(h) * 6.2f, 0.0f, 1.0f), 2.2f) * 0.30f * liquid);
        }
    } else {
        // --- Plate or bowl: overlapping metaballs, clustered in the well.
        float field = 0.0f;
        float2 flow = float2(0.0f);
        for (int i = 0; i < 7; ++i) {
            float fi = float(i);
            float2 h = hash22(float2(seed + fi * 3.13f, seed * 0.7f + fi));
            float ang = h.x * 6.2831853f;
            float rad = sqrt(h.y) * foodR;                  // area-uniform within the well
            float2 c = float2(cos(ang), sin(ang)) * rad;
            float rr = foodR * (0.42f + hash11(seed + fi * 7.7f) * 0.34f);
            float contribution = rr * rr / max(dot(p - c, p - c), 1e-4f);
            field += contribution;
            flow += (p - c) * contribution;
        }

        float mask = smoothstep(0.78f, 1.12f, field) * vessel;

        if (mask > 0.001f) {
            // Break the silhouette so it reads as food rather than as bubbles.
            float texture_ = fbm(p * 16.0f + seed * 5.0f);
            float coverage = clamp(mask * (0.9f + texture_ * 0.28f), 0.0f, 1.0f);

            // The metaball flow vector stands in for a surface normal, so colour shifts
            // across each form and picks up the same key light as the vessel.
            float shade = clamp(dot(normalize(flow + 1e-5f), float2(-0.62f, -0.78f)) * 0.5f + 0.5f, 0.0f, 1.0f);
            half3 food = mix(half3(hueA.rgb), half3(hueB.rgb), half(shade * 0.7f + texture_ * 0.3f));

            // Ambient occlusion where food meets the vessel, before the specular so the
            // sheen is not dimmed by it.
            float contact = (1.0f - smoothstep(0.78f, 1.35f, field)) * 0.34f;
            food *= half(1.0f - contact);

            // Sheen: oil, glaze, moisture. Tight, and offset toward the light.
            float sheen = pow(clamp(1.0f - length(p - float2(-0.06f, -0.08f)) * 3.1f, 0.0f, 1.0f), 5.0f);
            food += half3(sheen * 0.26f);

            col = mix(col, food, half(coverage));
        }
    }

    // --- Grade: a gentle S-curve and a touch of warmth, as a studio shot would have.
    col = clamp(col, 0.0h, 1.0h);
    col = col * col * (3.0h - 2.0h * col) * 0.42h + col * 0.58h;
    col *= half3(1.015h, 1.0h, 0.988h);

    return half4(col * color.a, color.a);
}

// MARK: - Overlay effects
//
// `plateGrain` and `softVignette` above are colorEffects applied *to* a view. That
// works on ordinary content, but a shader (or a blur) applied to an ancestor of a
// ScrollView suppresses the scroll view's content entirely — SwiftUI cannot rasterize
// live scrolling content into the offscreen layer a shader reads from, and you get a
// correctly-sized, completely empty scroll view.
//
// So anything that needs to sit over a scrolling surface is drawn as a transparent
// overlay instead: these two write premultiplied colour with their own alpha onto a
// plain filled rectangle, which composites over the scroll view without touching it.

[[ stitchable ]] half4 grainOverlay(float2 position,
                                    half4 color,
                                    float2 size,
                                    float time,
                                    float intensity) {
    float2 jitter = float2(hash11(floor(time * 24.0f)) * 512.0f,
                           hash11(floor(time * 24.0f) + 7.0f) * 512.0f);
    float n = hash12(position + jitter) - 0.5f;

    // Signed noise becomes alternating light and dark specks rather than a haze.
    half a = half(fabs(n) * intensity * 2.0f) * color.a;
    half3 tone = n > 0.0f ? half3(1.0h) : half3(0.0h);
    return half4(tone * a, a);
}

[[ stitchable ]] half4 vignetteOverlay(float2 position,
                                       half4 color,
                                       float2 size,
                                       float strength,
                                       float radius) {
    float2 uv = (position / max(size, float2(1.0f))) - 0.5f;
    uv.x *= size.x / max(size.y, 1.0f);
    float r = length(uv) / max(radius, 0.01f);

    half a = half(smoothstep(0.55f, 1.15f, r) * strength) * color.a;
    return half4(0.0h, 0.0h, 0.0h, a);   // premultiplied black
}
