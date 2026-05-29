#version 300 es
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

float overlayOpacityForBrightness(float x) {
    // Note: range 0 to 1
    
    // Highly aggressive NaN-safe exponential curve adapted from end-4
    float base = max(0.0, x - 0.15);
    float y = (1.0 - exp(-pow(base, 0.6))) * 1.18;

    return min(max(y, 0.001), 1.0);
}

void main() {
    // 1. Get the current pixel color
    vec4 pixColor = texture(tex, v_texcoord);

    // 2. Pure Dense Gaussian Blur
    // Instead of sparse circles that cause "text leaking" via aliasing,
    // we use a dense 9x9 grid with Gaussian weighting. This safely captures the true
    // average brightness without projecting high-frequency details.
    vec3 totalRGB = vec3(0.0);
    float totalWeight = 0.0;
    
    for(float dx = -0.04; dx <= 0.041; dx += 0.01) {
        for(float dy = -0.04; dy <= 0.041; dy += 0.01) {
            vec3 sampleColor = texture(tex, v_texcoord + vec2(dx, dy)).rgb;
            
            // Spatial weight: pixels closer to the center matter more.
            float distSq = (dx*dx + dy*dy) / (0.04*0.04);
            float weight = exp(-distSq * 2.0);
            
            totalRGB += sampleColor * weight;
            totalWeight += weight;
        }
    }
    
    vec3 localAvg = totalRGB / totalWeight;
    float localBrightness = dot(localAvg, vec3(0.2126, 0.7152, 0.0722));

    // 3. Dynamic Inner-Aura Elimination (With Detail Protection)
    // We use the max() trick to eliminate the "inner aura" on bright windows, but 
    // applying it to mid-tones destroys shading on complex images (making characters look "dirty").
    // The fix: We only apply this structural boost if the pixel is almost pure white (like a window background).
    
    float pixelBrightness = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    
    // Gate 1: Must be a large bright area (protects isolated white text)
    float isLargeBrightArea = smoothstep(0.15, 0.4, localBrightness);
    
    // Gate 2: Must be a pure white/very bright pixel (protects mid-tone character details)
    float isPureWhite = smoothstep(0.8, 0.95, pixelBrightness);
    
    // Combine gates to boost ONLY the edges of large, blinding white windows
    float boostFactor = isLargeBrightArea * isPureWhite;
    
    // Apply the boost safely. Complex images bypass this and use the perfectly smooth localBrightness.
    float finalBrightness = max(localBrightness, pixelBrightness * boostFactor);

    // 4. Apply the specific opacity for this final, perfectly corrected brightness
    float opacity = overlayOpacityForBrightness(finalBrightness);

    // 5. Apply the "black overlay" effect
    vec3 outColor = mix(pixColor.rgb, vec3(0.0), opacity);

    fragColor = vec4(outColor, pixColor.a);
}
