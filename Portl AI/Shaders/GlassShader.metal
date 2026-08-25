#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

[[stitchable]] half4 glassEffect(
    float2 position,
    SwiftUI::Layer layer,
    float2 size,
    float2 center,
    float radius,
    float refraction,
    float frostAmount
) {
    // Early-out when radius is effectively zero (bubble shrink animation ending)
    if (radius < 1.0) {
        return layer.sample(position);
    }

    float2 delta = position - center;
    float dist = length(delta);
    float norm = dist / radius;

    // ── Outside bubble: subtle bottom-right shadow (fades when frosted) ──
    if (norm > 1.0) {
        half4 bg = layer.sample(position);
        float shadowFade = 1.0 - frostAmount;
        if (shadowFade > 0.01) {
            float2 shadowOffset = float2(4.0, 6.0);
            float2 shadowDelta = position - (center + shadowOffset);
            float shadowDist = length(shadowDelta) - radius;
            float shadow = exp(-shadowDist * shadowDist * 0.001) * 0.04;
            bg.rgb *= half3(1.0 - shadow * shadowFade);
        }
        return bg;
    }

    // ── Refraction (scale toward center — clean middle, warped edges) ──
    float baseWarp = pow(norm, 3.0) * refraction * 0.85;
    float scale = 1.0 - baseWarp;

    float2 refractedPos = center + (position - center) * scale;

    // Clamp to screen bounds
    refractedPos = clamp(refractedPos, float2(0.0), size - float2(1.0));

    half4 color = layer.sample(refractedPos);

    // ── Frosted glass tint (only when frostAmount > 0, i.e. morph to pill) ──
    if (frostAmount > 0.001) {
        half3 cream = half3(1.0, 1.0, 1.0);
        color.rgb = mix(color.rgb, cream, half(clamp(frostAmount, 0.0, 1.0)));
    }

    return color;
}
