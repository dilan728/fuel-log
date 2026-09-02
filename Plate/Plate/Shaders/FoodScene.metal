//  FoodScene.metal
//
//  An offline path-marched renderer for a plated dish.
//
//  Why this exists: the first procedural renderer composited 2D metaballs, and every
//  dish came out looking like plasticine — smooth gradients, no real shadow, no sense
//  of anything sitting on anything. The tell was that light was *painted on* rather
//  than computed.
//
//  This renders an actual 3D scene: signed-distance geometry, a three-point studio
//  setup, distance-field soft shadows, ambient occlusion, a GGX specular lobe, and a
//  depth-of-field pass. It is far too expensive to run per frame — which is fine,
//  because it runs exactly once per food and the result is cached to disk as a JPEG,
//  exactly like a generated photograph would be.
//
//  Conventions: Y is up, the plate sits at the origin with radius ~1, and the camera
//  looks straight down. Flat-lay is deliberate — it composes in a grid at any tile size
//  without perspective distortion, and it matches the prompt used for real photography.

#include <metal_stdlib>
using namespace metal;

// MARK: - Parameters

struct FoodSceneParams {
    float2 resolution;
    float  seed;
    int    vessel;        // 0 plate · 1 bowl · 2 glass
    int    texture;       // 0 chunks · 1 grains · 2 leaves · 3 layered · 4 liquid
    int    pieceCount;
    float4 foodPrimary;
    float4 foodSecondary;
    float4 ground;
    float4 baseColour;
    float  roughness;
    float  subsurface;
    float  focusBlur;
    float  grain;
};

// Pre-normalised on purpose. Metal rejects a `constant` initialised by a function call
// — it would need a global constructor, and air-lld refuses to link one.
constant float3 kKeyLight    = float3(-0.6201f,  0.7401f, -0.2601f);   // upper-left, front
constant float3 kFillLight   = float3( 0.8520f,  0.3976f,  0.3408f);   // bounce card, right
constant float3 kRimLight    = float3( 0.1004f, -0.1505f,  0.9835f);   // separation
constant float  kPlateRadius = 1.00f;

// MARK: - Hashing and noise

static float hash11(float p) {
    p = fract(p * 0.1031f);
    p *= p + 33.33f;
    p *= p + p;
    return fract(p);
}

static float3 hash31(float p) {
    float3 q = fract(float3(p) * float3(0.1031f, 0.1030f, 0.0973f));
    q += dot(q, q.yzx + 33.33f);
    return fract((q.xxy + q.yzz) * q.zyx);
}

static float hash13(float3 p) {
    p = fract(p * 0.1031f);
    p += dot(p, p.zyx + 31.32f);
    return fract((p.x + p.y) * p.z);
}

/// 3D value noise, quintic-interpolated so its gradient is smooth — which matters,
/// because we displace surfaces with it and then take numerical normals.
static float noise3(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * f * (f * (f * 6.0f - 15.0f) + 10.0f);

    float n000 = hash13(i + float3(0, 0, 0));
    float n100 = hash13(i + float3(1, 0, 0));
    float n010 = hash13(i + float3(0, 1, 0));
    float n110 = hash13(i + float3(1, 1, 0));
    float n001 = hash13(i + float3(0, 0, 1));
    float n101 = hash13(i + float3(1, 0, 1));
    float n011 = hash13(i + float3(0, 1, 1));
    float n111 = hash13(i + float3(1, 1, 1));

    return mix(mix(mix(n000, n100, u.x), mix(n010, n110, u.x), u.y),
               mix(mix(n001, n101, u.x), mix(n011, n111, u.x), u.y), u.z);
}

static float fbm3(float3 p, int octaves) {
    float sum = 0.0f;
    float amplitude = 0.5f;
    for (int i = 0; i < octaves; ++i) {
        sum += amplitude * noise3(p);
        p *= 2.03f;
        amplitude *= 0.5f;
    }
    return sum;
}

// MARK: - Distance primitives

static float sdSphere(float3 p, float r) { return length(p) - r; }

static float sdEllipsoid(float3 p, float3 r) {
    float k0 = length(p / r);
    float k1 = length(p / (r * r));
    return k0 * (k0 - 1.0f) / max(k1, 1e-5f);
}

static float sdRoundBox(float3 p, float3 b, float r) {
    float3 q = abs(p) - b + r;
    return length(max(q, 0.0f)) + min(max(q.x, max(q.y, q.z)), 0.0f) - r;
}

/// Flat disc with a rounded edge — the base for plates, liquid surfaces and slabs.
static float sdRoundedDisc(float3 p, float radius, float halfHeight, float round_) {
    float2 d = float2(length(p.xz) - radius + round_, abs(p.y) - halfHeight + round_);
    return min(max(d.x, d.y), 0.0f) + length(max(d, 0.0f)) - round_;
}

static float opSmoothUnion(float a, float b, float k) {
    float h = clamp(0.5f + 0.5f * (b - a) / k, 0.0f, 1.0f);
    return mix(b, a, h) - k * h * (1.0f - h);
}

static float opSmoothSubtract(float a, float b, float k) {
    float h = clamp(0.5f - 0.5f * (b + a) / k, 0.0f, 1.0f);
    return mix(b, -a, h) + k * h * (1.0f - h);
}

// MARK: - Scene
//
// Materials: 0 backdrop · 1 vessel · 2 food · 3 liquid

struct Hit {
    float distance;
    int material;
    // Carried through so shading can vary across a single piece without re-deriving
    // which piece it belongs to.
    float variation;
};

static Hit closer(Hit a, Hit b) { return a.distance < b.distance ? a : b; }

/// Where the i-th piece of food sits, how big it is, and how it is coloured.
///
/// `tone` blends the two palette colours. It is deterministic rather than random for
/// layered food, because a slice of toast is a bread-coloured base with a differently
/// coloured topping on it, and that ordering is the whole reason it reads as toast.
static void pieceTransform(int index, constant FoodSceneParams &params,
                           thread float3 &centre, thread float3 &radii,
                           thread float &spin, thread float &tone, thread int &shape) {
    float fi = float(index);
    float3 h = hash31(params.seed * 7.31f + fi * 13.77f);
    float3 h2 = hash31(params.seed * 3.17f + fi * 5.11f + 91.0f);

    shape = 0;   // 0 ellipsoid · 1 rounded slab
    tone = h2.z;

    if (params.texture == 3 || params.texture == 5) {
        // Layered: a base slab with a topping on it. A slab is the same geometry with
        // only the one piece — a bar of chocolate is not bread with chocolate on it.
        shape = 1;
        bool isBase = (params.texture == 3) && (index == 0);
        if (params.texture == 5) {
            radii = float3(0.56f, 0.085f, 0.56f * (0.86f + h.x * 0.22f));
            centre = float3((h.x - 0.5f) * 0.05f, 0.075f + 0.085f, (h.z - 0.5f) * 0.05f);
            spin = (h2.x - 0.5f) * 0.6f;
            tone = h2.z;
            return;
        }
        float half_ = isBase ? 0.58f : 0.50f;
        radii = float3(half_, isBase ? 0.075f : 0.045f, half_ * (0.90f + h.x * 0.16f));
        centre = float3((h.x - 0.5f) * 0.05f, 0.0f, (h.z - 0.5f) * 0.05f);
        centre.y = 0.075f + (isBase ? radii.y : 0.15f + radii.y);
        spin = (h2.x - 0.5f) * 0.5f;
        tone = isBase ? 0.92f : 0.06f;
        return;
    }

    // Sunflower placement: a golden-angle spiral, jittered. Pure random placement clumps
    // badly at these counts and reads as a mistake rather than as an arrangement.
    float golden = 2.39996323f;
    float angle = fi * golden + h.x * 0.7f;
    float spread = (params.texture == 1) ? 0.60f : (params.texture == 2 ? 0.56f : 0.46f);
    float radius = sqrt((fi + 0.35f) / float(max(params.pieceCount, 1))) * spread;
    radius *= 0.84f + h.y * 0.32f;

    centre = float3(cos(angle) * radius, 0.0f, sin(angle) * radius);

    float scale = 1.0f;
    switch (params.texture) {
        case 0: scale = 0.19f + h2.x * 0.15f; break;   // chunks, deliberately uneven
        case 1: scale = 0.052f + h2.x * 0.034f; break; // grains
        case 2: scale = 0.19f + h2.x * 0.12f; break;   // leaves
        default: scale = 0.18f; break;
    }

    if (params.texture == 2) {
        // Leaves want to be thin, wide and clearly separate. Fused together they read as
        // a single scoop of guacamole rather than as salad.
        radii = float3(scale, scale * (0.10f + h2.y * 0.05f), scale * (0.62f + h2.z * 0.34f));
    } else {
        radii = float3(scale,
                       scale * (0.58f + h2.y * 0.26f),
                       scale * (0.82f + h2.z * 0.30f));
    }

    // Rest the piece on the floor of the vessel rather than intersecting it. Bowls have
    // a curved floor, so pieces further from the centre sit higher.
    float floorHeight = 0.075f;
    if (params.vessel == 1) {
        float r = length(centre.xz);
        floorHeight = 0.16f + r * r * 0.42f;
    }
    centre.y = floorHeight + radii.y * 0.88f;
    spin = h2.z * 6.2831853f;
}

static float3 rotateY(float3 p, float angle) {
    float s = sin(angle), c = cos(angle);
    return float3(c * p.x - s * p.z, p.y, s * p.x + c * p.z);
}

static float3 rotateZ(float3 p, float angle) {
    float s = sin(angle), c = cos(angle);
    return float3(c * p.x - s * p.y, s * p.x + c * p.y, p.z);
}

static Hit mapVessel(float3 p, constant FoodSceneParams &params) {
    if (params.vessel == 1) {
        // Bowl: a thick shell, opened by intersecting with the half-space *below* the
        // rim. The first version used the half-space above it, which kept the dome and
        // threw away the bowl — every bowl rendered as a featureless white sphere.
        float outer = sdSphere(p - float3(0.0f, 0.70f, 0.0f), 0.86f);
        float inner = sdSphere(p - float3(0.0f, 0.74f, 0.0f), 0.795f);
        float shell = max(outer, -inner);
        return Hit{ max(shell, p.y - 0.50f), 1, 0.0f };
    }
    if (params.vessel == 2) {
        // Cup: a wall with a rounded lip, hollow inside.
        float outer = sdRoundedDisc(p - float3(0.0f, 0.26f, 0.0f), 0.60f, 0.26f, 0.06f);
        float inner = sdRoundedDisc(p - float3(0.0f, 0.36f, 0.0f), 0.525f, 0.26f, 0.04f);
        return Hit{ max(outer, -inner), 1, 0.0f };
    }

    // Plate: a shallow disc with a gently dished well and a raised rim.
    float body = sdRoundedDisc(p - float3(0.0f, 0.045f, 0.0f), kPlateRadius, 0.045f, 0.030f);
    float well = sdSphere(p - float3(0.0f, 2.42f, 0.0f), 2.36f);
    return Hit{ opSmoothSubtract(well, body, 0.05f), 1, 0.0f };
}

static Hit mapFood(float3 p, constant FoodSceneParams &params) {
    Hit best{ 1e9f, 2, 0.0f };
    // `material` is overwritten per piece below; 2 is plain food, 4 is the base of a
    // topped item (the bread under the avocado), which is a different colour entirely.

    if (params.texture == 4) {
        // Liquid: a surface disc with a meniscus lifting at the vessel wall.
        float surfaceRadius = (params.vessel == 2) ? 0.525f : (params.vessel == 1 ? 0.70f : 0.74f);
        float height = (params.vessel == 2) ? 0.44f : (params.vessel == 1 ? 0.40f : 0.16f);
        float rise = smoothstep(surfaceRadius * 0.80f, surfaceRadius, length(p.xz)) * 0.022f;
        float disc = sdRoundedDisc(p - float3(0.0f, height - 0.06f + rise, 0.0f), surfaceRadius, 0.06f, 0.012f);
        return Hit{ disc, 3, 0.0f };
    }

    // Cheap bounding test: the food never leaves this sphere, and skipping the loop
    // outside it roughly halves the cost of every ray that misses.
    float bound = sdSphere(p - float3(0.0f, 0.30f, 0.0f), 1.05f);
    if (bound > 0.25f) { return Hit{ bound, 2, 0.0f }; }

    for (int i = 0; i < 24; ++i) {
        if (i >= params.pieceCount) { break; }

        float3 centre, radii;
        float spin, tone;
        int shape;
        pieceTransform(i, params, centre, radii, spin, tone, shape);

        float3 local = rotateY(p - centre, spin);
        // Tilt leaves so they lean on one another the way salad actually sits.
        if (params.texture == 2) {
            local = rotateZ(local, (hash11(params.seed + float(i) * 4.9f) - 0.5f) * 0.9f);
        }
        float d = shape == 1
            ? sdRoundBox(local, radii, min(radii.x, radii.z) * 0.30f)
            : sdEllipsoid(local, radii);

        // Only perturb where it matters. Evaluating fbm for every piece on every step
        // is the single most expensive thing in this shader.
        //
        // Amplitude is per-texture and mostly *absolute*, not proportional to the piece.
        // Scaling it by radius meant a wide flat slab got displacement two thirds of its
        // own thickness — a bar of chocolate came out as a churned canyon.
        if (d < 0.10f) {
            float freq, amplitude;
            switch (params.texture) {
                case 0:  freq = 11.0f; amplitude = radii.x * 0.15f; break;  // chunks
                case 1:  freq = 24.0f; amplitude = radii.x * 0.20f; break;  // grains
                case 2:  freq =  9.0f; amplitude = radii.x * 0.08f; break;  // leaves
                case 3:  freq = 30.0f; amplitude = 0.009f; break;           // topping crumb
                case 5:  freq = 26.0f; amplitude = 0.008f; break;           // slab crumb
                default: freq = 12.0f; amplitude = radii.x * 0.12f; break;
            }
            float bumps = fbm3(local * freq + params.seed * 3.3f, 3) - 0.5f;
            d -= bumps * amplitude;
        }

        if (d < best.distance) {
            best.distance = d;
            best.variation = tone;
            best.material = (params.texture == 3 && i == 0) ? 4 : 2;
        }
    }

    // Fuse touching pieces very slightly, so a pile reads as a pile and not as a
    // collection of separate objects that happen to be near one another.
    return best;
}

static Hit mapScene(float3 p, constant FoodSceneParams &params) {
    Hit backdrop{ p.y, 0, 0.0f };
    Hit vessel = mapVessel(p, params);
    Hit food = mapFood(p, params);

    Hit result = closer(backdrop, vessel);
    if (food.distance < result.distance) { result = food; }
    return result;
}

static float3 sceneNormal(float3 p, constant FoodSceneParams &params) {
    const float2 e = float2(1.0f, -1.0f) * 0.0024f;
    return normalize(
        e.xyy * mapScene(p + e.xyy, params).distance +
        e.yyx * mapScene(p + e.yyx, params).distance +
        e.yxy * mapScene(p + e.yxy, params).distance +
        e.xxx * mapScene(p + e.xxx, params).distance
    );
}

// MARK: - Visibility

static Hit march(float3 origin, float3 direction, constant FoodSceneParams &params) {
    float t = 0.0f;
    Hit hit{ -1.0f, -1, 0.0f };
    for (int i = 0; i < 150; ++i) {
        float3 p = origin + direction * t;
        Hit sample = mapScene(p, params);
        if (sample.distance < 0.0006f * t + 0.0004f) {
            hit = sample;
            hit.distance = t;
            return hit;
        }
        // Step conservatively: the noise displacement above breaks the strict Lipschitz
        // bound a sphere-tracer assumes, and full steps produce surface acne.
        t += sample.distance * 0.62f;
        if (t > 9.0f) { break; }
    }
    return hit;
}

/// Distance-field soft shadow.
///
/// The naive estimator — `min(k * d / t)` sampled along the ray — leaves concentric
/// contour bands on a flat backdrop, which at 6x contrast look exactly like the rings on
/// a topographic map and are the clearest single tell that an image was computed rather
/// than photographed. This uses the improved form that interpolates between successive
/// samples to approximate the true closest approach, which removes them.
static float softShadow(float3 origin, float3 direction, float k, constant FoodSceneParams &params) {
    float result = 1.0f;

    // Dither the starting phase. The march samples at discrete positions, so every pixel
    // stepping in lockstep quantises the penumbra into terraces — smooth arcs near the
    // object and a jagged contour-map further out, which is exactly what a backdrop
    // should never have. Offsetting each ray by a hash of its own origin decorrelates
    // neighbours and turns the banding into noise the film grain then absorbs.
    float t = 0.035f + hash13(origin * 91.7f) * 0.030f;
    float previous = 1e20f;

    for (int i = 0; i < 64; ++i) {
        float h = mapScene(origin + direction * t, params).distance;

        float y = h * h / (2.0f * previous);
        float d = sqrt(max(h * h - y * y, 0.0f));
        result = min(result, k * d / max(t - y, 1e-4f));
        previous = h;

        t += clamp(h, 0.004f, 0.085f);
        // Reach far enough that the cast shadow ends because the light stops being
        // occluded, not because the ray ran out of budget — a fixed cutoff left a
        // straight edge across the backdrop where shadowing abruptly ceased.
        if (result < 0.002f || t > 6.5f) { break; }
    }
    // Smootherstep the result: a linear penumbra still reads as a gradient ramp rather
    // than as light falling off around an object.
    result = clamp(result, 0.0f, 1.0f);
    return result * result * (3.0f - 2.0f * result);
}

static float ambientOcclusion(float3 p, float3 n, constant FoodSceneParams &params) {
    float occlusion = 0.0f;
    float scale = 1.0f;
    float phase = hash13(p * 57.3f);
    for (int i = 0; i < 5; ++i) {
        float h = 0.012f + 0.052f * (float(i) + phase * 0.7f);
        float d = mapScene(p + n * h, params).distance;
        occlusion += (h - d) * scale;
        scale *= 0.72f;
    }
    return clamp(1.0f - 2.4f * occlusion, 0.0f, 1.0f);
}

// MARK: - Shading

static float distributionGGX(float3 n, float3 h, float roughness) {
    float a = roughness * roughness;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0f);
    float denom = ndoth * ndoth * (a2 - 1.0f) + 1.0f;
    return a2 / max(3.14159265f * denom * denom, 1e-5f);
}

static float geometrySmith(float3 n, float3 v, float3 l, float roughness) {
    float k = (roughness + 1.0f) * (roughness + 1.0f) / 8.0f;
    float ndotv = max(dot(n, v), 0.0f);
    float ndotl = max(dot(n, l), 0.0f);
    float gv = ndotv / (ndotv * (1.0f - k) + k);
    float gl = ndotl / (ndotl * (1.0f - k) + k);
    return gv * gl;
}

static float3 shade(float3 p, float3 n, float3 view, Hit hit, constant FoodSceneParams &params) {
    float3 albedo;
    float roughness;
    float specularStrength;
    float subsurface = 0.0f;

    if (hit.material == 0) {
        // Fall the backdrop off away from the subject, as a real light with a real
        // distance does. A purely directional light leaves a plane perfectly uniform,
        // which is most of why the first render looked like a diagram.
        float falloff = 1.0f - smoothstep(0.7f, 2.6f, length(p.xz)) * 0.30f;
        albedo = params.ground.rgb * falloff;
        roughness = 0.94f;
        specularStrength = 0.015f;
    } else if (hit.material == 1) {
        // Glazed ceramic: near-white, slightly warm, quite smooth.
        albedo = float3(0.902f, 0.892f, 0.874f);
        roughness = 0.30f;
        specularStrength = 0.42f;
    } else if (hit.material == 3) {
        albedo = params.foodPrimary.rgb;
        roughness = 0.09f;
        specularStrength = 0.90f;
    } else if (hit.material == 4) {
        // Bread, dough, pastry — the thing the topping sits on.
        float grain = fbm3(p * 26.0f + params.seed, 3);
        albedo = params.baseColour.rgb * (0.90f + grain * 0.18f);
        roughness = 0.68f;
        specularStrength = 0.16f;
        subsurface = 0.44f;
    } else {
        // Food: mix the two palette colours by a per-piece constant and a fine grain,
        // so no two pieces are the same flat colour and no single piece is uniform.
        float grain = fbm3(p * 22.0f + params.seed, 3);
        float blend = clamp(hit.variation * 0.65f + grain * 0.55f, 0.0f, 1.0f);
        albedo = mix(params.foodPrimary.rgb, params.foodSecondary.rgb, blend);
        albedo *= 0.93f + grain * 0.14f;
        roughness = clamp(params.roughness + (grain - 0.5f) * 0.16f, 0.06f, 0.98f);
        specularStrength = 0.34f;
        subsurface = params.subsurface;
    }

    float3 f0 = mix(float3(0.04f), albedo, 0.0f) + specularStrength * 0.08f;

    // Key light, with a soft shadow.
    // A generous bias along the normal. The displaced surfaces are not strict distance
    // fields, so a shadow ray launched from within a hair of one immediately reports a
    // hit on the surface it started from — which is what put hard black patches on the
    // *lit* side of every almond.
    float shadow = softShadow(p + n * 0.022f, kKeyLight, 5.5f, params);
    float ndotl = max(dot(n, kKeyLight), 0.0f);
    float3 halfway = normalize(kKeyLight + view);
    float ndf = distributionGGX(n, halfway, roughness);
    float geometry = geometrySmith(n, view, kKeyLight, roughness);
    float3 specular = f0 * ndf * geometry / max(4.0f * max(dot(n, view), 0.0f) * ndotl + 0.001f, 1e-4f);

    float3 colour = albedo * ndotl * shadow * 1.32f;
    colour += specular * ndotl * shadow * specularStrength * 2.4f;

    // Fill: broad, cool, unshadowed — a bounce card rather than a second lamp.
    float fill = max(dot(n, kFillLight), 0.0f);
    colour += albedo * fill * 0.26f * float3(0.94f, 0.96f, 1.02f);

    // Rim: separates the silhouette from the backdrop, which is most of what stops a
    // top-down render from reading as flat.
    float rim = pow(1.0f - max(dot(n, view), 0.0f), 3.0f);
    colour += albedo * rim * max(dot(n, kRimLight), 0.0f) * 0.20f;

    // Wrapped diffuse standing in for subsurface scattering — bread and fruit are not
    // opaque, and a hard terminator on them looks like plastic.
    if (subsurface > 0.0f) {
        float wrapped = max((dot(n, kKeyLight) + 0.55f) / 1.55f, 0.0f);
        colour += albedo * wrapped * subsurface * 0.34f;
    }

    // Ambient, occluded.
    float ao = ambientOcclusion(p, n, params);
    colour += albedo * ao * 0.20f;
    colour *= mix(0.72f, 1.0f, ao);

    return colour;
}

// MARK: - Pass one: render

kernel void foodSceneRender(texture2d<float, access::write> output [[texture(0)]],
                            constant FoodSceneParams &params [[buffer(0)]],
                            uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }

    float2 uv = (float2(gid) + 0.5f) / params.resolution;
    float2 ndc = (uv - 0.5f) * 2.0f;
    ndc.y = -ndc.y;

    // A long lens looking straight down: almost orthographic, with just enough
    // perspective that the rim of the plate has depth.
    const float cameraHeight = 7.2f;
    const float frame = 1.20f;
    // Nudge the framing per dish. Every plate landing dead centre with an identical
    // shadow is the giveaway that these are generated rather than shot.
    float3 jitter = hash31(params.seed * 1.77f) - 0.5f;
    float2 offset = jitter.xy * 0.09f;

    float3 origin = float3((ndc.x * frame + offset.x) * 0.06f, cameraHeight,
                           (-ndc.y * frame + offset.y) * 0.06f);
    float3 target = float3(ndc.x * frame + offset.x, 0.0f, -ndc.y * frame + offset.y);
    float3 direction = normalize(target - origin);

    Hit hit = march(origin, direction, params);

    float3 colour;
    float depth;
    if (hit.material < 0) {
        colour = params.ground.rgb * 0.96f;
        depth = 12.0f;
    } else {
        float3 p = origin + direction * hit.distance;
        float3 n = sceneNormal(p, params);
        colour = shade(p, n, -direction, hit, params);
        depth = hit.distance;
    }

    output.write(float4(colour, depth), gid);
}

// MARK: - Pass two: resolve
//
// Downsamples the supersampled render, applies depth of field, grades, and adds grain.
// Doing this as a second pass is what buys real antialiasing: the first pass runs at
// twice the output resolution and this averages it down.

kernel void foodSceneResolve(texture2d<float, access::read>  source [[texture(0)]],
                             texture2d<float, access::write> output [[texture(1)]],
                             constant FoodSceneParams &params [[buffer(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) { return; }

    const uint scale = source.get_width() / output.get_width();
    uint2 base = gid * scale;

    // The focal plane sits on top of the food, so the plate rim and the backdrop fall
    // gently out of focus — the single strongest cue that this is a photograph.
    const float focalDistance = 6.95f;

    float3 accumulated = 0.0f;
    float weightSum = 0.0f;
    float centreDepth = source.read(base).a;
    float circleOfConfusion = clamp(abs(centreDepth - focalDistance) * params.focusBlur, 0.0f, 3.4f);
    int radius = int(ceil(circleOfConfusion));

    for (int dy = -radius; dy <= radius; ++dy) {
        for (int dx = -radius; dx <= radius; ++dx) {
            float2 offset = float2(dx, dy);
            float distance_ = length(offset);
            if (distance_ > circleOfConfusion + 0.5f) { continue; }

            int2 coordinate = int2(base) + int2(dx, dy) * int(scale);
            coordinate = clamp(coordinate, int2(0), int2(source.get_width() - 1, source.get_height() - 1));
            float4 sample = source.read(uint2(coordinate));

            // Weight by a disc rather than a gaussian: real lens bokeh has an edge.
            float weight = smoothstep(circleOfConfusion + 0.5f, circleOfConfusion - 0.5f, distance_);
            // Never let a sharp foreground bleed onto a blurred background.
            if (sample.a < centreDepth - 0.25f) { weight *= 0.25f; }

            accumulated += sample.rgb * weight;
            weightSum += weight;
        }
    }

    // Box-average the supersample block for antialiasing.
    float3 crisp = 0.0f;
    for (uint sy = 0; sy < scale; ++sy) {
        for (uint sx = 0; sx < scale; ++sx) {
            crisp += source.read(min(base + uint2(sx, sy),
                                     uint2(source.get_width() - 1, source.get_height() - 1))).rgb;
        }
    }
    crisp /= float(scale * scale);

    float3 colour = weightSum > 0.0f ? mix(crisp, accumulated / weightSum, smoothstep(0.0f, 1.2f, circleOfConfusion))
                                     : crisp;

    // --- Grade.
    // Filmic curve: lifts the shadows slightly and rolls the highlights, which is what
    // keeps a bright ceramic plate from clipping to a flat white disc.
    colour = max(colour, 0.0f);
    colour = (colour * (2.51f * colour + 0.03f)) / (colour * (2.43f * colour + 0.59f) + 0.14f);
    colour = pow(colour, float3(0.94f));

    // Desaturate. The tonemap above pushes chroma hard, and left alone a tomato came out
    // fire-engine red and an avocado came out highlighter green.
    float luma = dot(colour, float3(0.2126f, 0.7152f, 0.0722f));
    colour = mix(float3(luma), colour, 0.74f);

    colour *= float3(1.014f, 1.0f, 0.982f);   // a touch of warmth, as tungsten film has

    // Vignette, elliptical and very slight.
    float2 uv = (float2(gid) + 0.5f) / float2(output.get_width(), output.get_height());
    float2 centred = uv - 0.5f;
    colour *= 1.0f - smoothstep(0.48f, 1.02f, length(centred)) * 0.07f;

    // Grain, luminance-dependent as silver halide is.
    float luminance = dot(colour, float3(0.2126f, 0.7152f, 0.0722f));
    float noise = hash13(float3(float2(gid), params.seed)) - 0.5f;
    colour += noise * params.grain * (0.35f + smoothstep(1.0f, 0.1f, luminance) * 0.65f);

    output.write(float4(clamp(colour, 0.0f, 1.0f), 1.0f), gid);
}
