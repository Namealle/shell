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

    // 2. Calculate local neighborhood brightness.
    // Instead of a full-screen grid (which causes flickering during scrolling),
    // we sample in concentric circles around the current pixel.
    // This allows us to distinguish large bright windows from small white text.
    vec3 totalRGB = pixColor.rgb;
    float samples = 1.0;
    
    float r1 = 0.015;
    for(float i = 0.0; i < 6.28318; i += 0.78539) { // 8 samples
        totalRGB += texture(tex, v_texcoord + vec2(cos(i)*r1, sin(i)*r1)).rgb;
        samples += 1.0;
    }
    
    float r2 = 0.035;
    for(float i = 0.0; i < 6.28318; i += 0.39269) { // 16 samples
        totalRGB += texture(tex, v_texcoord + vec2(cos(i)*r2, sin(i)*r2)).rgb;
        samples += 1.0;
    }
    
    float r3 = 0.055;
    for(float i = 0.0; i < 6.28318; i += 0.39269) { // 16 samples
        totalRGB += texture(tex, v_texcoord + vec2(cos(i)*r3, sin(i)*r3)).rgb;
        samples += 1.0;
    }
    
    vec3 avgColor = totalRGB / samples;
    float localBrightness = dot(avgColor, vec3(0.2126, 0.7152, 0.0722));

    // 3. Get the specific opacity for this local brightness level
    float opacity = overlayOpacityForBrightness(localBrightness);

    // 4. Modulate opacity to prevent dark auras around bright windows.
    // We only apply strong dimming if the pixel itself is also bright.
    float pixelBrightness = dot(pixColor.rgb, vec3(0.2126, 0.7152, 0.0722));
    float pixelOpacityFactor = smoothstep(0.1, 0.5, pixelBrightness);
    opacity *= pixelOpacityFactor;

    // 5. Apply the "black overlay" effect
    vec3 outColor = mix(pixColor.rgb, vec3(0.0), opacity);

    fragColor = vec4(outColor, pixColor.a);
}
