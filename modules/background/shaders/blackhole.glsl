// Splice 1: #define BH_UNIFORMS, #include this file INSIDE existing buf,
// then #undef BH_UNIFORMS. Keep its instance name ubuf (bhDisk is a member).
// Splice 2: #include this file AFTER } ubuf; and BEFORE stars()/main().
// This adds layout(binding=1) uniform sampler2D bhTransfer; reserve that slot.
// ShaderEffect: supportsAtlasTextures:false. Image: smooth:false, no color tags.
#ifdef BH_UNIFORMS
    vec2 bhCentre;
    vec4 bhGeometry;
    vec4 bhDisk;
    vec4 bhLook;
    vec4 bhHalo;
    vec4 bhPhase;
    vec4 bhCaps;
#else
#ifndef BH_FUNCTIONS
#define BH_FUNCTIONS
layout(binding = 1) uniform sampler2D bhTransfer;
const float BH_PI = 3.141592653589793;
const float BH_BC = 2.598076211353316;
const float BH_FOCAL = 7.834421972380958;

float bhEase(float x) {
    if (x <= 0.0) return 0.0;
    if (x >= 1.0) return 1.0;
    x = clamp(x, 0.0, 1.0);
    return clamp(x*x*x*(10.0+x*(-15.0+6.0*x)),0.0,1.0);
}
float bhTaper(float r) {
    return 1.0-bhEase((r/ubuf.bhGeometry.x-3.2)/0.8);
}
float bhWord(vec2 texel) {
    vec2 bytes = floor(texture(bhTransfer, (texel+0.5)/vec2(1024.0,262.0)).rg*255.0+0.5);
    return (bytes.x*256.0+bytes.y)/65535.0;
}
float bhColumn(float b) {
    float t;
    if (b < 0.95*BH_BC)
        return clamp((b-0.025)/(0.95*BH_BC-0.025),0.0,1.0)*255.0;
    if (b < BH_BC) {
        t = sqrt(clamp((0.9999999-b/BH_BC)/0.0499999,0.0,1.0));
        return 256.0+(1.0-t)*255.0;
    }
    if (b < 1.25*BH_BC) {
        t = sqrt(clamp((b/BH_BC-1.0000001)/0.2499999,0.0,1.0));
        return 512.0+t*255.0;
    }
    return 768.0+clamp((b-1.25*BH_BC)/(12.0-1.25*BH_BC),0.0,1.0)*255.0;
}
float bhImpact(float r) {
    float focal = BH_FOCAL*ubuf.bhGeometry.x;
    return (20.0/sqrt(0.95))*r/sqrt(r*r+focal*focal);
}
float bhMeta(float col, float row) {
    float a = floor(col);
    return mix(bhWord(vec2(a,row)), bhWord(vec2(min(a+1.0,1023.0),row)), fract(col));
}
float bhInverseRadius(float col, float phi) {
    float y = clamp(phi/(2.0*BH_PI)*255.0,0.0,255.0);
    float x0 = floor(col), y0 = floor(y);
    float a = mix(bhWord(vec2(x0,y0)),bhWord(vec2(min(x0+1.0,1023.0),y0)),fract(col));
    float b = mix(bhWord(vec2(x0,min(y0+1.0,255.0))),bhWord(vec2(min(x0+1.0,1023.0),min(y0+1.0,255.0))),fract(col));
    return mix(a,b,fract(y));
}
// Signed radial source coordinate and background transmission. Unrepresented
// hemisphere and unresolved higher orders vanish; never repeat/clamp a source.
vec2 bhSource(float r) {
    if (r <= ubuf.bhGeometry.x) return vec2(0.0);
    float col = bhColumn(bhImpact(r)), x0 = floor(col);
    vec3 a = floor(texture(bhTransfer,vec2(x0+0.5,261.5)/vec2(1024.0,262.0)).rgb*255.0+0.5);
    vec3 b = floor(texture(bhTransfer,vec2(min(x0+1.0,1023.0)+0.5,261.5)/vec2(1024.0,262.0)).rgb*255.0+0.5);
    float projected = mix(a.r*256.0+a.g,b.r*256.0+b.g,fract(col))/65535.0*128.0-64.0;
    float valid = mix(a.b,b.b,fract(col))/255.0;
    float raw = projected*ubuf.bhGeometry.x;
    // Supported sky is the rectangle centred on bhCentre, plus renderer padding.
    float maxSource = length(ubuf.resolution);
    valid *= 1.0-bhEase((abs(raw)-maxSource*0.8)/(maxSource*0.2));
    return vec2(raw,valid);
}
vec2 bhWarpBackground(vec2 pixel, out float weight) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p);
    weight = 0.0;
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y) return pixel;
    weight = ubuf.bhHalo.w*bhTaper(r);
    float raw = bhSource(r).x;
    return ubuf.bhCentre+p*(mix(r,raw,weight)/max(r,0.0001));
}
vec2 bhWarpMaterial(vec2 pixel, out float rimLife) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p), rh = ubuf.bhGeometry.x;
    rimLife = 1.0;
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y) return pixel;
    float w = ubuf.bhHalo.w*bhTaper(r);
    rimLife = mix(1.0,smoothstep(rh,rh*1.08,r),ubuf.bhHalo.w);
    float source = sqrt(max(r*r-rh*rh,0.0));
    return ubuf.bhCentre+p*(mix(r,source,w)/max(r,0.0001));
}
// Evaluate only for a surviving far-layer star. Finite differences use physical
// pixels; radial symmetry saves two full vector mapping calls. No flux multiplier.
mat2 bhJacobian(vec2 pixel) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p);
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y || r < 0.001) return mat2(1.0);
    float h = 0.25, w;
    vec2 e = p/r;
    float a = dot(bhWarpBackground(ubuf.bhCentre+e*(r-h),w)-ubuf.bhCentre,e);
    float b = dot(bhWarpBackground(ubuf.bhCentre+e*(r+h),w)-ubuf.bhCentre,e);
    float f = dot(bhWarpBackground(pixel,w)-ubuf.bhCentre,e);
    float tangential = f/r, radial = (b-a)/(2.0*h);
    return mat2(tangential,0.0,0.0,tangential)+(radial-tangential)*mat2(e.x*e.x,e.x*e.y,e.x*e.y,e.y*e.y);
}
float bhShadowMask(vec2 pixel) {
    float r = length(pixel-ubuf.bhCentre);
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y) return 0.0;
    float transmission = smoothstep(ubuf.bhGeometry.x-0.5,ubuf.bhGeometry.x+0.5,r)*bhSource(r).y;
    return ubuf.bhHalo.w*bhTaper(r)*(1.0-transmission);
}
// Crossing helper is also exercised by the fixture: radius, azimuth, valid, phi.
vec4 bhCrossing(float col, vec2 e, float order) {
    float ca = cos(ubuf.bhDisk.z), sa = sin(ubuf.bhDisk.z);
    // Camera model is Y-up; Qt physical pixels are Y-down.
    vec2 local = vec2(ca*e.x-sa*e.y,-sa*e.x-ca*e.y);
    float phi = mod(atan(-ubuf.bhGeometry.z,ubuf.bhGeometry.w*local.y),BH_PI)+order*BH_PI;
    float u = bhInverseRadius(col,phi);
    float radius = 1.0/max(u,0.00001);
    float azimuth = atan(local.y*sin(phi)*ubuf.bhGeometry.z-cos(phi)*ubuf.bhGeometry.w,local.x*sin(phi));
    float valid = step(ubuf.bhDisk.x,radius)*(1.0-step(ubuf.bhDisk.y,radius));
    return vec4(radius,azimuth,valid,phi);
}
vec3 bhLimit(vec3 c, float limit) {
    // Leave one micro-unit for float dot-product rounding at the hard cap.
    return c*min(1.0,max(0.0,limit-0.000001)/max(dot(c,vec3(0.2126,0.7152,0.0722)),0.000001));
}
vec4 bhEmission(vec4 hit, vec2 e, float order) {
    if (hit.z < 0.5) return vec4(0.0);
    float radius = hit.x, inner = ubuf.bhDisk.x, outer = ubuf.bhDisk.y;
    // The geometric disk extends to outer. Its cold outer portion is dark:
    // a compact thermal window meets the wallpaper's strict illuminated area.
    float luminousOuter = inner+0.66*(outer-inner);
    if (radius >= luminousOuter) return vec4(0.0);
    float x = inner/radius;
    float torque = 1.0-sqrt(x);
    float profile = x*x*x*torque/0.0566527795;
    float edge = bhEase((radius-inner)/0.18)*(1.0-bhEase((radius-(luminousOuter-0.9))/0.9));
    // Adjacent integer rotation harmonics: no differential-rotation wrap seam.
    float band = clamp((radius-inner)/(outer-inner),0.0,1.0);
    float phase0 = mix(sin(24.0*hit.y-96.0*ubuf.bhPhase.x+radius*17.0),sin(24.0*hit.y-24.0*ubuf.bhPhase.x+radius*17.0),band);
    float phase1 = mix(sin(47.0*hit.y-188.0*ubuf.bhPhase.x+radius*31.0+1.7),sin(47.0*hit.y-47.0*ubuf.bhPhase.x+radius*31.0+1.7),band);
    float pattern = 1.0+min(ubuf.bhLook.w,0.08)*(0.6*phase0+0.4*phase1);
    float beam = clamp(1.0+ubuf.bhLook.z*cos(hit.y)*sqrt(3.0/radius),0.8,1.2);
    float hot = clamp(profile+0.16*(0.5-ubuf.bhLook.y)+0.05*(beam-1.0),0.0,1.0);
    // Linear-light swatches for #FFF6E6 -> #FFE0B5. Amber is confined
    // to the faint thermal edge; warmth adjusts that edge, not a brown core.
    vec3 innerGold = mix(vec3(1.0,0.745404,0.462077),vec3(1.0,0.921582,0.791298),bhEase(hot));
    float outerWarm = bhEase((band-0.38)/0.28) * (0.65+0.35*ubuf.bhLook.y);
    vec3 tint = mix(innerGold,vec3(1.0,0.428691,0.191202),outerWarm);
    tint /= dot(tint,vec3(0.2126,0.7152,0.0722));
    float haloGain = e.y < 0.0 ? ubuf.bhHalo.x : ubuf.bhHalo.y;
    float gain = order < 0.5 ? mix(haloGain,1.0,bhEase((cos(hit.w)+0.2)/0.4)) : haloGain;
    float alpha = 0.88*edge;
    vec3 colour = tint*(0.235*ubuf.bhLook.x*profile*pattern*beam*gain*alpha);
    return vec4(bhLimit(colour,ubuf.bhCaps.x),alpha);
}
vec4 bhDisk(vec2 pixel) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p), rh = ubuf.bhGeometry.x;
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y || r < 0.001) return vec4(0.0);
    // Conservative projected radial bound for r_em <= luminousOuter, D=20.
    float luminousOuter = ubuf.bhDisk.x+0.66*(ubuf.bhDisk.y-ubuf.bhDisk.x);
    float maxImpact = luminousOuter/sqrt(1.0-1.0/luminousOuter);
    float sine = maxImpact*sqrt(0.95)/20.0;
    float bound = BH_FOCAL*rh*sine/sqrt(1.0-sine*sine)+2.0;
    if (r > bound) return vec4(0.0);
    float col = bhColumn(bhImpact(r));
    vec2 e = p/r;
    vec4 nearHit = bhEmission(bhCrossing(col,e,0.0),e,0.0);
    vec4 farHit = bhEmission(bhCrossing(col,e,1.0),e,1.0);
    vec4 disk = nearHit+(1.0-nearHit.a)*farHit;
    disk.rgb = bhLimit(disk.rgb,ubuf.bhCaps.x);
    float width = max(1.0,ubuf.bhDisk.w);
    float distance = abs(r-rh-0.5*width)/width;
    float photon = (1.0-bhEase(distance/2.0))*exp(-2.0*distance*distance);
    vec3 ring = vec3(1.0,0.92,0.78)*(photon*ubuf.bhHalo.z*0.235*ubuf.bhLook.x);
    disk.rgb = bhLimit(disk.rgb+(1.0-nearHit.a)*ring, mix(ubuf.bhCaps.x,ubuf.bhCaps.y,step(0.000001,photon)));
    disk.a = max(disk.a,photon*0.3);
    return disk*(ubuf.bhHalo.w*bhTaper(r));
}
#endif
#endif
