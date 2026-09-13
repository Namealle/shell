// Splice 1: #define BH_UNIFORMS, #include this file INSIDE existing buf,
// then #undef BH_UNIFORMS. Keep its instance name ubuf (bhDisk is a member).
// Splice 2: #include this file AFTER } ubuf; and BEFORE stars()/main().
// Samplers: binding 1 bhTransfer (nearest), binding 2 bhNoise (linear).
// Binding 3 belongs to particles. ShaderEffect: supportsAtlasTextures:false.
// Both Images are untagged data, mipmap:false; never convert their colour space.
#ifdef BH_UNIFORMS
    vec2 bhCentre;
    vec4 bhGeometry;
    vec4 bhDisk;
    vec4 bhLook;
    vec4 bhHalo;
    vec4 bhPhase;
    vec4 bhCaps;
    vec4 bhDetail;
    vec4 bhStreaks;
    vec4 bhKnots;
    vec4 bhEmbers;
    vec4 bhDoppler;
    vec4 bhHue;
    vec4 bhGlow;
    vec4 bhPhoton;
    vec4 bhDetailPhase;
    vec4 bhArcs;
#else
#ifndef BH_FUNCTIONS
#define BH_FUNCTIONS
layout(binding = 1) uniform sampler2D bhTransfer;
layout(binding = 2) uniform sampler2D bhNoise;
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
float bhOuter() { return ubuf.bhDisk.x+0.66*(ubuf.bhDisk.y-ubuf.bhDisk.x); }
float bhProfile(float r) {
    float x = clamp(ubuf.bhDisk.x/r,0.0,1.0);
    return x*x*x*(1.0-sqrt(x))/0.0566527795;
}
float bhEdge(float r) {
    return bhEase((r-ubuf.bhDisk.x)/0.18)*(1.0-bhEase((r-(bhOuter()-0.9))/0.9));
}
// Physical-pixel footprints; unit-circle differentiation is continuous at +/-pi.
// Call before divergent validity/brightness exits, including on the photon path.
vec2 bhFootprint(vec4 hit) {
    vec2 cs = vec2(cos(hit.y),sin(hit.y));
    vec2 dx = dFdx(cs), dy = dFdy(cs);
    return max(vec2(length(vec2(dFdx(hit.x),dFdy(hit.x))),
        length(vec2(cs.x*dx.y-cs.y*dx.x,cs.x*dy.y-cs.y*dy.x))),vec2(0.000001));
}
float bhCycles(float r) {
    float x = ubuf.bhDisk.x/max(r,ubuf.bhDisk.x);
    return floor(ubuf.bhStreaks.y*x*sqrt(x)+0.5);
}
float bhChannel(vec3 v, float octave) {
    return octave < 0.5 ? v.r : (octave < 1.5 ? v.g : v.b);
}
float bhNoiseRow(float j, float phi, float radial, float angular, float octave) {
    float r = ubuf.bhDisk.x+j*(bhOuter()-ubuf.bhDisk.x)/radial;
    float phase = mod(ubuf.bhDetail.z*bhCycles(r)*ubuf.bhDetailPhase.x,1.0);
    float a = angular*mod(phi/(2.0*BH_PI)-phase,1.0);
    float k = floor(a), t = bhEase(fract(a));
    float x = mod(k+ubuf.bhDetail.y*(octave*7.0+3.0),angular);
    float y = mod(j+ubuf.bhDetail.y*(octave*5.0+1.0),127.0);
    // Hardware linear interpolation of bytes, with an explicitly quintic weight.
    return bhChannel(texture(bhNoise,vec2(x+t+0.5,y+0.5)/128.0).rgb,octave);
}
vec2 bhNoiseOctave(float v, float phi, vec2 footprint, float octave) {
    float radial = (octave < 0.5 ? 32.0 : (octave < 1.5 ? 64.0 : 128.0))*ubuf.bhStreaks.x;
    float angular = octave < 0.5 ? 32.0 : (octave < 1.5 ? 64.0 : 127.0);
    float y = radial*v, j = floor(y);
    float r = ubuf.bhDisk.x+j*(bhOuter()-ubuf.bhDisk.x)/radial;
    float rowStep = (bhOuter()-ubuf.bhDisk.x)/radial;
    float motion = mix(bhCycles(r),bhCycles(r+rowStep),bhEase(fract(y)))*ubuf.bhDetailPhase.y/4096.0;
    float width = max(radial*footprint.x/(bhOuter()-ubuf.bhDisk.x),angular*(footprint.y/(2.0*BH_PI)+motion));
    float lod = 1.0-bhEase((width-0.5)/0.85);
    if (lod <= 0.0) return vec2(0.5,0.0);
    return vec2(mix(bhNoiseRow(j,phi,radial,angular,octave),
        bhNoiseRow(j+1.0,phi,radial,angular,octave),bhEase(fract(y))),lod);
}
float bhRidge(float n) {
    float ridge = smoothstep(0.38,0.76,n);
    return 0.12+2.6*ridge*ridge;
}
// Means from tools/blackhole_noise.py, 524288 deterministic source/phase samples.
float bhFilaments(float r, float phi, vec2 footprint, float octaves) {
    float v = (r-ubuf.bhDisk.x)/(bhOuter()-ubuf.bhDisk.x);
    vec2 n0 = bhNoiseOctave(v,phi,footprint,0.0);
    float shaped = bhRidge(n0.x)/0.960401143495;
    if (octaves > 1.5 && n0.y > 0.0) {
        float warped = v+(n0.x-0.5)*2.0*ubuf.bhStreaks.z/(32.0*ubuf.bhStreaks.x);
        vec2 n1 = bhNoiseOctave(warped,phi,footprint,1.0);
        shaped = mix(shaped,bhRidge(0.67*n0.x+0.33*n1.x)/0.804861351448,n1.y);
    }
    shaped = mix(1.0,shaped,n0.y);
    if (octaves > 2.5) {
        vec2 n2 = bhNoiseOctave(v,phi,footprint,2.0);
        shaped *= 1.0+min(ubuf.bhStreaks.w,0.08)*(2.0*n2.x-1.0)*n2.y;
    }
    return mix(1.0,shaped,ubuf.bhDetail.x);
}
vec3 bhRandom(float radialId, float angularId) {
    return texture(bhNoise,(vec2(mod(angularId+3.0*ubuf.bhDetail.y,127.0),
        mod(radialId+ubuf.bhDetail.y,127.0))+0.5)/128.0).rgb;
}
float bhKernel(float x) {
    float p = max(0.0,1.0-x*x);
    return p*p*p;
}
// Returns kernel and stable ID+1 (zero means no source knot). No screen hash.
vec2 bhKnot(float r, float phi, vec2 footprint) {
    float v = (r-ubuf.bhDisk.x)/(bhOuter()-ubuf.bhDisk.x)*16.0;
    float j = floor(v);
    float rowR = ubuf.bhDisk.x+(j+0.5)*(bhOuter()-ubuf.bhDisk.x)/16.0;
    float a = 48.0*mod(phi/(2.0*BH_PI)-ubuf.bhDetail.z*bhCycles(rowR)*ubuf.bhDetailPhase.x,1.0);
    float k = floor(a);
    vec3 rnd = bhRandom(j,k);
    if (rnd.b >= ubuf.bhKnots.x) return vec2(0.0);
    vec2 centre = 0.35+0.3*rnd.rg;
    float along = (fract(a)-centre.y)*ubuf.bhDetail.z;
    float kernel = bhKernel((fract(v)-centre.x)/0.2)*bhKernel(along/(along < 0.0 ? 0.3 : 0.08));
    float lod = 1.0-bhEase((16.0*footprint.x/(bhOuter()-ubuf.bhDisk.x)-0.12)/0.5);
    return vec2(kernel*lod,j*48.0+k+1.0);
}
// Two candidates on the nearest integer-frequency orbit. Underside parity is
// exclusively the lens mapping. Positive sign always leaves the trail at -phi.
vec2 bhEmber(float r, float phi, vec2 footprint) {
    float innerCycles = ubuf.bhStreaks.y;
    float orbitCount = floor(0.5*ubuf.bhEmbers.x);
    float n = bhCycles(r);
    if (n < innerCycles-orbitCount || n >= innerCycles || orbitCount < 1.0) return vec2(0.0);
    float orbitR = ubuf.bhDisk.x*pow(innerCycles/n,2.0/3.0);
    float gap = orbitR*2.0/(3.0*n);
    float support = min(ubuf.bhEmbers.y,0.24*gap);
    // Cubic compact kernel FWHM = .9084*support. Bound the resolved head
    // axes to .60–1.20 px; subpixel broadening conserves radial energy.
    float wr = clamp(support,0.661*footprint.x,1.321*footprint.x);
    float radial = bhKernel((r-orbitR)/wr)*min(1.0,support/wr);
    float lod = 1.0-bhEase((footprint.x/support-1.5)/3.0);
    if (radial*lod <= 0.0) return vec2(0.0);
    float orbitId = n-(innerCycles-orbitCount);
    vec3 rnd = bhRandom(orbitId+31.0,17.0);
    float head = mod(phi/(2.0*BH_PI)-ubuf.bhDetail.z*n*ubuf.bhDetailPhase.x-rnd.b,1.0);
    float id = floor(mod(head+0.25,1.0)*2.0);
    float delta = (mod(head-0.5*id+0.5,1.0)-0.5)*2.0*BH_PI*ubuf.bhDetail.z;
    float wa = clamp(support/orbitR,0.661*footprint.y,1.321*footprint.y);
    float tail = n*2.0*BH_PI*ubuf.bhEmbers.z/4096.0;
    float angular = delta < 0.0 ? bhKernel(delta/max(tail+wa,0.00001)) : bhKernel(delta/wa);
    return vec2(radial*angular*lod,orbitId*2.0+id+1.0);
}
vec2 bhDopplerFactors(float r, vec2 e, float impact) {
    float localX = cos(ubuf.bhDisk.z)*e.x-sin(ubuf.bhDisk.z)*e.y;
    float lambda = -impact*ubuf.bhGeometry.w*localX;
    float omega = ubuf.bhDetail.z/sqrt(2.0*r*r*r);
    float g = sqrt(max(0.0001,(1.0-1.5/r)/0.95))/max(0.01,1.0-omega*lambda);
    float gs = pow(g,ubuf.bhDoppler.y);
    vec2 result = vec2(gs*gs*gs*gs,gs);
    if (ubuf.bhDoppler.x < 0.5) result = clamp(result,vec2(0.65,0.90),vec2(1.5,1.12));
    return result;
}
vec3 bhTemperature(float logT) {
    // CPU sRGB -> linear constants, interpolated in log temperature.
    vec3 red = vec3(0.174647,0.039546,0.024158);
    vec3 amber = vec3(0.838799,0.327778,0.070360);
    vec3 gold = vec3(1.0,0.637597,0.258183);
    vec3 white = vec3(1.0,0.904661,0.775822);
    vec3 c = mix(red,amber,clamp((logT-7.43838353)/(7.93737470-7.43838353),0.0,1.0));
    c = mix(c,gold,clamp((logT-7.93737470)/(8.34283980-7.93737470),0.0,1.0));
    c = mix(c,white,clamp((logT-8.34283980)/(8.77955746-8.34283980),0.0,1.0));
    return c/max(dot(c,vec3(0.2126,0.7152,0.0722)),0.000001);
}
vec3 bhShadeField(vec4 hit, vec2 e, float impact, vec2 footprint, float octaves, float textureStrength) {
    float profile = bhProfile(hit.x);
    float detailWork = bhEase((0.13*ubuf.bhLook.x*profile-0.001)/0.002);
    float filaments = 1.0, knot = 0.0, ember = 0.0;
    if (detailWork > 0.0) {
        filaments = mix(1.0,bhFilaments(hit.x,hit.y,footprint,octaves),textureStrength*detailWork);
        if (ubuf.bhKnots.y > 0.0) knot = bhKnot(hit.x,hit.y,footprint).x;
        if (ubuf.bhEmbers.w > 0.0) ember = bhEmber(hit.x,hit.y,footprint).x;
    }
    vec2 doppler = bhDopplerFactors(hit.x,e,impact);
    float v = clamp((hit.x-ubuf.bhDisk.x)/(bhOuter()-ubuf.bhDisk.x),0.0,1.0);
    float logT = mix(ubuf.bhHue.x,ubuf.bhHue.y,v)+log(doppler.y)+(0.5-ubuf.bhHue.z)*0.22;
    logT += 0.03*knot+0.025*ember;
    float base = 0.13*ubuf.bhLook.x*profile*filaments*doppler.x;
    // Pointwise knot energy <=20% of (base+knot), also after positive filtering.
    float knots = base*min(0.25,ubuf.bhKnots.y*knot)*detailWork;
    float light = base+knots+min(ubuf.bhEmbers.w,0.06)*ember*detailWork;
    // Gentle film highlight shoulder; physical preset retains the hard cap only.
    // Shoulder knee/span follow the disk cap: at cap .25 these are exactly the
    // frozen .18/.06 (both factors scale by a power of two), so the default is
    // bit-identical, and a raised cap actually reaches its new headroom.
    float knee = 0.72*ubuf.bhCaps.x, span = 0.24*ubuf.bhCaps.x;
    if (ubuf.bhDoppler.x < 0.5 && light > knee) light = knee+span*(1.0-exp(-(light-knee)/span));
    vec3 tint = bhTemperature(logT);
    // Highlight desaturation: material near the cap burns toward white while dim
    // material keeps its temperature colour. Both ends carry luminance 1, so this
    // never changes emitted energy, and whiteness 0 leaves the four anchors exact.
    if (ubuf.bhHue.w > 0.0)
        tint = mix(tint,vec3(1.0),ubuf.bhHue.w*bhEase(light/max(ubuf.bhCaps.x,0.000001)));
    return tint*light;
}
vec4 bhEmissionAt(vec4 hit, vec2 e, float order, float impact, vec2 footprint) {
    float glowRadius = min(ubuf.bhGlow.y,2.5)*footprint.x;
    if (hit.z < 0.5 || hit.x >= bhOuter()+glowRadius) return vec4(0.0);
    float edge = bhEdge(hit.x);
    float haloGain = e.y < 0.0 ? ubuf.bhHalo.x : ubuf.bhHalo.y;
    float gain = order < 0.5 ? mix(haloGain,1.0,bhEase((cos(hit.w)+0.2)/0.4)) : haloGain;
    float octaves = e.y > 0.0 && order > 0.5 ? 1.0 : ubuf.bhDetail.w;
    vec3 colour = bhShadeField(hit,e,impact,footprint,octaves,1.0)*(0.88*edge*gain);
    float d = min(abs(hit.x-(ubuf.bhDisk.x+0.18)),abs(hit.x-(bhOuter()-0.9)))/max(glowRadius,0.00001);
    float glow = min(ubuf.bhGlow.x,0.008)*bhProfile(hit.x)*bhKernel(d)*edge;
    colour += bhTemperature(ubuf.bhHue.y)*glow;
    return vec4(bhLimit(colour,ubuf.bhCaps.x),0.88*edge);
}
// Preview compatibility helper. Production supplies impact and footprints once.
vec4 bhEmission(vec4 hit, vec2 e, float order) {
    return bhEmissionAt(hit,e,order,BH_BC,bhFootprint(hit));
}
float bhDiskBound() {
    float outer = bhOuter();
    float maxImpact = outer/sqrt(1.0-1.0/outer);
    float sine = maxImpact*sqrt(0.95)/20.0;
    return BH_FOCAL*ubuf.bhGeometry.x*sine/sqrt(1.0-sine*sine)+3.0;
}
// Outer concentric arcs. A true order>=2 image lands at b_c*(1+3.4823*exp(-2pi)),
// i.e. 0.65% outside Rh, inside the photon thread: these wider bands are an
// ART-DIRECTED stand-in for that unresolved light plus outer halo material,
// matching the owner's target still. They are not traced geodesics.
float bhArcReach() {
    if (ubuf.bhArcs.x <= 0.0 || ubuf.bhArcs.w < 0.5) return 0.0;
    float outer = ubuf.bhArcs.y+(ubuf.bhArcs.w-1.0)*ubuf.bhArcs.z;
    return ubuf.bhGeometry.x*outer*1.2;
}
vec3 bhOuterArcs(float r, vec4 hit, vec2 footprint) {
    float support = 0.0;
    for (float i = 0.0; i < 2.0; i += 1.0) {
        if (i >= ubuf.bhArcs.w) break;
        float centre = ubuf.bhGeometry.x*(ubuf.bhArcs.y+i*ubuf.bhArcs.z);
        support += bhKernel((r-centre)/max(0.05*centre,1.0))/(1.0+i);
    }
    if (support <= 0.0) return vec3(0.0);
    // Same source field, same clock: the bands shear with the disk material.
    float source = mix(ubuf.bhDisk.x,bhOuter(),0.5);
    float texture = clamp(bhFilaments(source,hit.y,vec2(0.004,footprint.y),2.0),0.0,2.4);
    float light = min(ubuf.bhArcs.x,0.02)*support*mix(0.3,1.0,0.5*texture);
    return bhTemperature(mix(ubuf.bhHue.x,ubuf.bhHue.y,0.45))*light;
}
// Actual compact disk coverage weighted by the normalized inner emissivity.
// Does not include the shadow or photon thread; particles outside the disk get 0.
float bhDiskAbsorb(vec2 pixel) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p);
    if (ubuf.bhHalo.w <= 0.0 || r > bhDiskBound() || r < 0.001) return 0.0;
    float col = bhColumn(bhImpact(r));
    vec4 a = bhCrossing(col,p/r,0.0), b = bhCrossing(col,p/r,1.0);
    float nearA = a.z*bhEdge(a.x)*bhEase(bhProfile(a.x)/0.85);
    float farA = b.z*bhEdge(b.x)*bhEase(bhProfile(b.x)/0.85);
    return (nearA+(1.0-nearA)*farA)*ubuf.bhHalo.w*bhTaper(r);
}
vec4 bhDisk(vec2 pixel) {
    vec2 p = pixel-ubuf.bhCentre;
    float r = length(p), rh = ubuf.bhGeometry.x;
    if (ubuf.bhHalo.w <= 0.0 || r >= ubuf.bhGeometry.y || r < 0.001
        || r > max(bhDiskBound(),bhArcReach())) return vec4(0.0);
    float impact = bhImpact(r), col = bhColumn(impact);
    vec2 e = p/r;
    vec4 hit0 = bhCrossing(col,e,0.0), hit1 = bhCrossing(col,e,1.0);
    vec2 fp0 = bhFootprint(hit0), fp1 = bhFootprint(hit1);
    vec4 nearHit = bhEmissionAt(hit0,e,0.0,impact,fp0);
    vec4 farHit = bhEmissionAt(hit1,e,1.0,impact,fp1);
    vec4 disk = nearHit+(1.0-nearHit.a)*farHit;
    // Faint bands sit behind the material and never reach the thread's radius.
    if (bhArcReach() > 0.0)
        disk.rgb += bhOuterArcs(r,hit0,fp0)*(1.0-disk.a);
    disk.rgb = bhLimit(disk.rgb,ubuf.bhCaps.x);
    float width = ubuf.bhPhoton.x;
    float d = r-rh-0.5*width;
    float coverage = clamp(d+0.5*width+0.5,0.0,1.0)-clamp(d-0.5*width+0.5,0.0,1.0);
    if (coverage > 0.0 && ubuf.bhPhoton.w > 0.0) {
        // Azimuth at psi+2pi equals order zero in the Schwarzschild ray plane.
        vec4 ringHit = vec4(49.0*ubuf.bhDisk.x/36.0,hit0.y,1.0,hit0.w);
        vec2 ringFootprint = vec2(0.018*162.0/rh,fp0.y);
        vec3 ring = bhShadeField(ringHit,e,impact,ringFootprint,ubuf.bhDetail.w,ubuf.bhPhoton.z);
        ring *= coverage*ubuf.bhPhoton.y*(1.0-nearHit.a)*(1.0-farHit.a);
        disk.rgb = bhLimit(disk.rgb+ring,ubuf.bhCaps.y);
        disk.a = max(disk.a,coverage*0.3);
    }
    return disk*(ubuf.bhHalo.w*bhTaper(r));
}
#endif
#endif
