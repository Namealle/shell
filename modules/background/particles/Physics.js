// Physical-pixel, pause-safe particle dynamics. QML importable; no wall clock.
// v10: `capacity` is the population ceiling PLUS the transient reserve, so an
// event's debris can never take a slot a star was going to be born into.
// `population` is still capped at 3200; `debrisAlive[1]` is the reserve on top.
var BOUNDS = {
    capacity: 3680, population: [0, 3200], radialSpeed: [0, 26], vref: [10, 600], epsilonRh: [0.01, 0.2],
    substeps: [4, 32], betaBound: [0.1, 0.99], betaUnbound: [1.001, 2],
    captureRadius: [0.8, 6], gamma: [0, 2], spiralSec: [5, 240],
    safetyLifeSec: [30, 600], sizePx: [0.25, 12], exposureSec: [0, 0.1], maxPx: [0, 32], publishHz: [10, 30],
    flareShare: [0, 0.5], flareMaxAlive: [0, 64], capturedLight: [0, 1],
    // ---- the event -> particle interface (v10) ----
    debrisAlive: [0, 480],    // transient particles alive at once, atlas-reserved
    burstCount: [0, 480],     // one spawnBurst() call
    impulsePx: [0, 6000],     // px/s, the largest velocity any one kick may add
    glows: 4                  // live brightenNear() sources
};

function number(value, fallback, lo, hi) {
    return typeof value === 'number' && isFinite(value) ? Math.max(lo, Math.min(hi, value)) : fallback;
}
function range(value, fallback, bounds) {
    if (!Array.isArray(value) || value.length !== 2) return fallback.slice();
    var a = number(value[0], fallback[0], bounds[0], bounds[1]);
    var b = number(value[1], fallback[1], bounds[0], bounds[1]);
    return [Math.min(a, b), Math.max(a, b)];
}
function defaults() {
    return {population: {near: 120, middle: 480}, stressPreset: false, vref: 120,
        launch: {plunge: 0.35, miss: 0.55, wide: 0.10, betaBound: [0.65, 0.90],
            unboundShare: 0.2, betaUnbound: [1.02, 1.12], handedness: 0.85},
        capture: {radius: [1.0, 1.3], gamma: 0.25, spiralSec: [20, 60]},
        epsilonRh: 0.05, substeps: 4,
        streak: {exposureSec: 0.035, maxPx: 20, bendExposureSec: 0.26, bendMaxPx: 64, bendRadiusRd: 0.70, bendMaxAlive: 200},
        sizes: {nearPx: [2.4, 4.8], middlePx: [0.9, 1.7], capturedPx: [1.2, 2.2]},
        flare: {share: 0.085, maxAlive: 10, capturedLight: 0.7}, publishHz: 30, mass: 1,
        depth: {frontShare: 0.12, binaryMaxAlive: 40},
        clustering: {share: 0.72, streams: 5, streamLifeSec: 150, burstDepth: 0.55},
        dust: {farFlow: 24, parallaxPx: 250, clusterGain: 1, clusterCells: 16, voidCells: 44, cellScale: 0.77},
        // The transient reserve. It is unconditional, like the tidal-disruption
        // ceiling, because the atlas is allocated once per configuration and a
        // resize of the sampled texture cost 13 ms -> 6700 ms per frame on
        // llvmpipe and never recovered. 400 covers the supernova's 150-400
        // debris plus a comet nucleus, its shed motes and a fireball's spray.
        debris: {maxAlive: 400, relaxSec: 1.6},
        safetyLifeSec: [180, 240]};
}
function validate(raw) {
    var d = defaults(), r = raw || {}, p = r.population || {}, l = r.launch || {};
    var c = r.capture || {}, z = r.sizes || {}, t = r.streak || {}, fl = r.flare || {};
    d.stressPreset = r.stressPreset === true;
    d.population.near = Math.round(number(p.near, d.stressPreset ? 600 : 120, 0, 3200));
    d.population.middle = Math.round(number(p.middle, d.stressPreset ? 1500 : 480, 0, 3200));
    var total = d.population.near + d.population.middle;
    if (total > 3200) {
        d.population.near = Math.round(d.population.near * 3200 / total);
        d.population.middle = 3200 - d.population.near;
    }
    d.vref = number(r.vref, d.vref, 10, 600);
    var sum = 0, names = ['plunge', 'miss', 'wide'];
    for (var i = 0; i < names.length; ++i) {
        var name = names[i]; d.launch[name] = number(l[name], d.launch[name], 0, 1); sum += d.launch[name];
    }
    if (sum > 0) for (i = 0; i < names.length; ++i) d.launch[names[i]] /= sum;
    else { d.launch.plunge = 0.35; d.launch.miss = 0.55; d.launch.wide = 0.10; }
    d.launch.betaBound = range(l.betaBound, d.launch.betaBound, BOUNDS.betaBound);
    d.launch.betaUnbound = range(l.betaUnbound, d.launch.betaUnbound, BOUNDS.betaUnbound);
    d.launch.unboundShare = number(l.unboundShare, 0.2, 0, 1);
    d.launch.handedness = number(l.handedness, 0.85, 0, 1);
    d.capture.radius = range(c.radius, d.capture.radius, BOUNDS.captureRadius);
    d.capture.gamma = number(c.gamma, 0.25, 0, 2);
    d.capture.spiralSec = range(c.spiralSec, d.capture.spiralSec, BOUNDS.spiralSec);
    d.epsilonRh = number(r.epsilonRh, 0.05, 0.01, 0.2);
    d.substeps = Math.round(number(r.substeps, 4, 4, 32));
    d.streak.exposureSec = number(t.exposureSec, 0.035, 0, 0.1);
    d.streak.maxPx = number(t.maxPx, 20, 0, 32);
    d.streak.bendExposureSec = number(t.bendExposureSec, 0.26, 0, 1);
    d.streak.bendMaxPx = number(t.bendMaxPx, 64, 0, 120);
    d.streak.bendRadiusRd = number(t.bendRadiusRd, 0.70, 0, 4);
    d.streak.bendMaxAlive = Math.round(number(t.bendMaxAlive, 200, 0, 3200));
    d.sizes.nearPx = range(z.nearPx, d.sizes.nearPx, BOUNDS.sizePx);
    d.sizes.middlePx = range(z.middlePx, d.sizes.middlePx, BOUNDS.sizePx);
    d.sizes.capturedPx = range(z.capturedPx, d.sizes.capturedPx, BOUNDS.sizePx);
    d.flare.share = number(fl.share, 0.085, 0, 0.5);
    d.flare.maxAlive = Math.round(number(fl.maxAlive, 10, 0, 64));
    d.flare.capturedLight = number(fl.capturedLight, 0.7, 0, 1);
    d.mass = number(r.mass, 1, 0.5, 3);
    var dp = r.depth || {}, cl = r.clustering || {}, du = r.dust || {};
    d.depth.frontShare = number(dp.frontShare, 0.12, 0, 0.5);
    d.depth.binaryMaxAlive = Math.round(number(dp.binaryMaxAlive, 40, 0, 3200));
    d.clustering.share = number(cl.share, 0.72, 0, 1);
    d.clustering.streams = Math.round(number(cl.streams, 5, 1, 12));
    d.clustering.streamLifeSec = number(cl.streamLifeSec, 150, 20, 600);
    d.clustering.burstDepth = number(cl.burstDepth, 0.55, 0, 1);
    d.dust.farFlow = number(du.farFlow, 24, 1, 64);
    d.dust.parallaxPx = number(du.parallaxPx, 250, 0, 800);
    d.dust.clusterGain = number(du.clusterGain, 1, 0, 1);
    d.dust.clusterCells = Math.round(number(du.clusterCells, 16, 2, 64));
    d.dust.voidCells = Math.round(number(du.voidCells, 44, 4, 192));
    d.dust.cellScale = number(du.cellScale, 0.77, 0.4, 2);
    var db = r.debris || {};
    d.debris.maxAlive = Math.round(number(db.maxAlive, 400, BOUNDS.debrisAlive[0], BOUNDS.debrisAlive[1]));
    d.debris.relaxSec = number(db.relaxSec, 1.6, 0.05, 12);
    d.publishHz = Math.round(number(r.publishHz, 30, 10, 30));
    d.safetyLifeSec = range(r.safetyLifeSec, d.safetyLifeSec, BOUNDS.safetyLifeSec);
    return d;
}
function random(s) {
    var x = s.randomState | 0; x ^= x << 13; x ^= x >>> 17; x ^= x << 5;
    s.randomState = x >>> 0; return s.randomState / 4294967296;
}
function between(s, r) { return r[0] + random(s) * (r[1] - r[0]); }
function smooth(a, b, x) {
    if (a === b) return x >= b ? 1 : 0;
    var t = Math.max(0, Math.min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t);
}
// ---- The three radii of the drawn hole --------------------------------------
// Rh is the DYNAMICAL scale: mu goes as rh^3, and it is also the screen radius
// where the impact parameter reaches b_c, i.e. the SHADOW and the photon ring.
// It is not how big the hole looks: the drawn object runs out to the disk's
// material rim and, fainter still, to the outer arcs. Three radii, three jobs,
// and picking the wrong one is visible either way:
//
//   shadow  the black core. A star that falls in vanishes HERE and nowhere
//           else, and nothing is ever drawn inside it.
//   disk    the disk's emissive material rim (bhOuter). The captured ring
//           orbits just outside this; wide passes graze it; the tide is
//           normalised to it.
//   arcs    the art-directed outer bands. Drawn, but nothing a star reacts to.
//
// v7 killed stars at max(disk, arcs) and he rejected it the same day (ledger
// 2282): "now the stars disappear too far from the hole, they are disappearing
// somewhere close to the rings, don't think that is right." The original
// complaint (2281) was stars drawn ON TOP of the disk, which is a compositing
// job - see particleDiskAbsorb in shaders/starfield.frag - not a reason to stop
// the flow at the rim. Stars cross the disk band alive and DEPTH-ORDERED.
//
// These MIRROR bhOuter()/bhImpact()/bhArcReach() in shaders/blackhole.glsl and
// must be changed with them; test-particles.mjs pins the constants.
var BH_FOCAL = 7.834421972380958, BH_K = 20 / Math.sqrt(0.95);
// Screen radius of the direct image of a circular orbit at `rs` Schwarzschild
// radii: b = rs/sqrt(1-1/rs), inverted through bhImpact().
function screenRadius(rs, rh) {
    if (!(rs > 1.0001) || !(rh > 0)) return 0;
    var sine = rs / Math.sqrt(1 - 1 / rs) / BH_K;
    if (!(sine < 1)) return Infinity;
    return BH_FOCAL * rh * sine / Math.sqrt(1 - sine * sine);
}
// geom mirrors the hole's published uniforms: bhDisk.x/.y and bhArcs.x/.y/.z/.w.
// Omitted, it falls back to the v4 default disk, which is what the node tests
// and any consumer without a hole see.
function visibleRadius(rh, geom) {
    var g = geom || {};
    var inner = number(g.innerRs, 3, 3, 7);
    var outer = Math.max(inner + 0.5, number(g.outerRs, 8, 3.5, 11));
    var material = screenRadius(inner + 0.66 * (outer - inner), rh);
    var count = Math.round(number(g.arcCount, 0, 0, 4));
    var arcs = number(g.arcGain, 0, 0, 0.02) > 0 && count >= 1
        ? rh * (number(g.arcRadiusRh, 1.75, 1.2, 2.6)
            + (count - 1) * number(g.arcSpacingRh, 0.6, 0.2, 1)) * 1.2
        : 0;
    if (!isFinite(material) || !(material > rh)) material = rh;
    return {shadow: rh, disk: material, arcs: Math.max(arcs, material)};
}
// ---- Camera fly-through -----------------------------------------------------
// The other regime. With the black hole off there is no mass to fall into, so
// the stars hold still in space and the CAMERA moves: forward along its own
// axis, toward the centre of the screen. A star at 3-D depth `z` and screen
// radius `r` projects at r = f*rho/z, so moving the camera by dz scales every
// screen position about the centre by z/(z-dz) and nothing else. That one
// multiplication IS the whole regime: it is exact, it needs no integration, it
// is exactly invertible (which is what makes reverse playback reverse), and it
// reproduces perspective for free -- dr/dt = r*w/z grows with radius, and two
// stars at the same radius separate by depth, which is the parallax.
//
// `z` is dimensionless, 1 at the near plane and `camera.depth` at the far one.
// Forward, a star is born at the far plane and leaves at a screen edge; reverse
// runs the same trajectories backwards, so a star arrives at an edge and
// dissolves at the far plane. Densities come out uniform in both directions
// because births are the time-reverse of deaths (see cameraLaunch).
var CAMERA_NEAR = 1;
function cameraOn(s) {
    var b = s.cameraBlend;
    return b > 0 && isFinite(b) ? (b < 1 ? b : 1) : 0;
}
function cameraFar(s) {
    var d = s.cameraDepth;
    return d >= 2 && isFinite(d) ? (d > 64 ? 64 : d) : 16;
}
// A depth for a star that has none yet: every particle alive when the camera
// engages needs one, and drawing it from the simulation's RNG would shift the
// stream and change the orbital regime's stars. This is a pure hash of the slot
// and its generation, so the orbital path is byte-identical to before.
function cameraDepthOf(s, i) {
    var z = s.depthZ[i];
    var far = cameraFar(s);
    if (z >= CAMERA_NEAR && z <= far) return z;
    var n = (Math.imul(i + 1, 374761393) + Math.imul(s.generation[i] + 1, 2654435761)) >>> 0;
    n ^= n >>> 15; n = Math.imul(n, 2246822519) >>> 0; n ^= n >>> 13;
    z = CAMERA_NEAR + (far - CAMERA_NEAR) * ((n >>> 8) / 16777216);
    s.depthZ[i] = z;
    return z;
}
function configure(s, width, height, rh, raw, geom) {
    s.config = validate(raw); s.width = Math.max(1, width); s.height = Math.max(1, height);
    s.rh = Math.max(0.1, rh); s.padding = Math.max(32, 0.25 * s.rh);
    s.epsilon = s.config.epsilonRh * s.rh;
    var v = s.config.vref * s.rh / 162;
    s.muBase = v * v * (20 / 3) * s.rh * s.config.mass;
    s.muTarget = s.muBase * s.k * s.k;
    if (geom !== undefined) s.geometry = geom;
    var radii = visibleRadius(s.rh, s.geometry);
    s.shadow = radii.shadow; s.diskRim = radii.disk; s.arcRim = radii.arcs;
    // The capture band is the DISK's rim scaled by the configured pair, so the
    // ring queues up at the edge of the material it is about to join. A heavier
    // hole reaches further, so the band's STANDOFF above that rim - not the rim
    // itself, which is drawn and does not move - carries the mass, on the same
    // cbrt(mass) convention the tidal reach uses.
    var cbm = Math.pow(Math.max(0.5, Math.min(3, s.config.mass)), 1 / 3);
    var c = s.config.capture.radius;
    s.captureInner = s.diskRim * (1 + (c[0] - 1) * cbm);
    s.captureOuter = s.diskRim * (1 + (c[1] - 1) * cbm);
    // The drag is a WINDOW, not everything inside the outer edge. Filling it
    // inward meant a star dragged past the band kept being damped all the way
    // down and circularised wherever it ran out of speed - measured at 0.54 of
    // the disk rim, i.e. a captured ring sitting inside the material, which is
    // half of what he reported in 2281. Below the floor a star is on a free
    // orbit and simply falls to the shadow. The floor is half a band-width
    // under the rim, so circularisation can only happen at the rim itself.
    s.captureFloor = Math.max(s.shadow, s.captureInner - 0.5 * (s.captureOuter - s.captureInner));
    // A launch needs a birth radius greater than its pericentre or it is
    // geometrically impossible and launch() burns sixteen retries losing the
    // birth. The shortest birth radius is the short edge's midpoint.
    s.qCap = 0.98 * (Math.min(s.width, s.height) / 2 + s.padding);
    s.targetPopulation = s.config.population.near + s.config.population.middle;
    s.birthRate = s.targetPopulation / s.meanLifetime;
}
function create(width, height, rh, seed, raw, birthCallback, geom) {
    var s = {capacity: BOUNDS.capacity, aliveCount: 0, randomState: (seed >>> 0) || 1,
        clock: 0, accumulator: 0, birthAccumulator: 0, nextSlot: 0, k: 1,
        centreX: width / 2, centreY: height / 2, rotationSign: 1, absorb: 1,
        // Camera regime, all runtime state like `absorb`: the renderer writes
        // them every frame. blend 0 is the pure orbital regime.
        cameraBlend: 0, cameraDir: 1, cameraDepth: 16, cameraRate: 0, cameraRoll: 0, cameraRegime: 0, refillFor: 0,
        meanLifetime: 30, lifetimeSamples: 0, lifetimeSum: 0, burstPhase: ((seed >>> 0) % 6283)/1000,
        // v10, the event -> particle interface. `kickAlive` is how many live
        // particles carry a peculiar velocity; while it is zero the hot loop
        // pays one hoisted boolean and nothing else. `transientCount` is how
        // many of `aliveCount` are event debris, which the population target
        // and the lifetime estimator both subtract out.
        kickAlive: 0, transientCount: 0, glows: [], cloud: null, nova: null,
        birthCallback: birthCallback, counters: {births: 0, deaths: 0, absorbed: 0,
            escapes: 0, safety: 0, captures: 0, passed: 0, steps: 0,
            debris: 0, impulses: 0, kicked: 0}};
    s.alive = new Uint8Array(s.capacity); s.generation = new Uint32Array(s.capacity);
    s.transient = new Uint8Array(s.capacity);
    // Dense list of occupied slots. step() compacts it, launch() appends to it,
    // so no consumer ever walks the 3200 capacity slots to find 600 particles.
    s.live = new Int32Array(s.capacity); s.liveCount = 0;
    var fields = ['x','y','vx','vy','age','entryTime','circularSince','captureExposure','spiralRate',
        'radiusAtCapture','captureTime','launchClass','pericentre','safetyLife','spiralSec','depth',
        'r','g','b','size','capturedSize','luminosity','archetype','p0','p1','p2','p3','phase','seed',
        'depthZ',
        // The peculiar-velocity channel. It is added to the POSITION after the
        // camera's magnification rather than to the velocity, because at
        // cameraBlend 1 the stored velocity is overwritten by the magnification
        // every substep and a velocity impulse would be discarded on the frame
        // it landed. kickDrag is the decay exponent p in v = v0*(t0/t)^p, so
        // p = 0.6 gives r ~ t^0.4 -- the same Sedov law the shell sprite draws
        // -- and p = 0 is a body under its own proper motion that never slows.
        'kickX','kickY','kickAge','kickDrag'];
    for (var j = 0; j < fields.length; ++j) s[fields[j]] = new Float64Array(s.capacity);
    configure(s, width, height, rh, raw, geom); s.mu = s.muBase;
    return s;
}
// Unit conversion only (DPR change). A speed/config edit must never call this.
function rescale(s, factor) {
    if (!(factor > 0) || !isFinite(factor)) return;
    var scalar = ['width','height','rh','shadow','diskRim','arcRim','captureInner','captureOuter','captureFloor','qCap','epsilon','padding','centreX','centreY'];
    var arrays = ['x','y','vx','vy','radiusAtCapture','pericentre','size','capturedSize','kickX','kickY'];
    for (var g=0; g<s.glows.length; ++g) { s.glows[g].x*=factor; s.glows[g].y*=factor; s.glows[g].radius*=factor; }
    if (s.cloud) { s.cloud.x*=factor; s.cloud.y*=factor; s.cloud.radius*=factor; }
    for (var j=0;j<scalar.length;++j) s[scalar[j]]*=factor;
    for (j=0;j<arrays.length;++j) {
        var a=s[arrays[j]];
        for (var i=0;i<s.capacity;++i) if (s.alive[i]) a[i]*=factor;
    }
    var cube=factor*factor*factor;s.mu*=cube;s.muBase*=cube;s.muTarget*=cube;
}
function energy(s, i) {
    var x = s.x[i] - s.centreX, y = s.y[i] - s.centreY;
    return 0.5 * (s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]) - s.mu / Math.sqrt(x*x+y*y+s.epsilon*s.epsilon);
}
function angularMomentum(s, i) {
    return (s.x[i]-s.centreX)*s.vy[i]-(s.y[i]-s.centreY)*s.vx[i];
}
// Each launch class is anchored to the radius that gives it its meaning, not to
// one shared scale: plunge and miss are about hitting or missing the SHADOW, so
// they are pericentres in shadow radii; a wide pass is about grazing the DISK,
// so it is in disk-rim radii. Against the target preset's 3.567 Rh rim these
// reproduce the v6 ladder (0.05-0.60, 1.15-1.80 and 2.5-4.5 Rh) exactly, and on
// any other disk the three classes keep their meaning instead of all three
// landing inside the material. Every class crosses the disk band on the way in.
var LAUNCH_Q = [[0.05,0.60],[1.15,1.80],[0.70,1.30]], LAUNCH_ANCHOR = [0,0,1];
function pericentre(s, cls, f) {
    var q = f * (LAUNCH_ANCHOR[cls] ? s.diskRim : s.shadow);
    return q > s.qCap ? s.qCap : q;
}
// Everything a birth owns that is not its position, its velocity or its depth,
// in the exact draw order the orbital launch has always used: the camera birth
// shares it so the two regimes cannot drift apart. Position and velocity must
// already be written.
function finishBirth(s, i, cls, q, depthOverride) {
    if (!s.alive[i]) { ++s.aliveCount; s.live[s.liveCount++]=i; }
    s.alive[i]=1; ++s.generation[i]; ++s.counters.births;
    if (s.transient[i]) { s.transient[i]=0; if (s.transientCount>0) --s.transientCount; }
    if (s.kickX[i] || s.kickY[i]) { s.kickX[i]=0; s.kickY[i]=0; if (s.kickAlive>0) --s.kickAlive; }
    s.kickAge[i]=0; s.kickDrag[i]=0;
    s.age[i]=0; s.circularSince[i]=-1; s.captureExposure[i]=0;
    var x=s.x[i], y=s.y[i];
    s.entryTime[i]=x>=0 && x<=s.width && y>=0 && y<=s.height ? s.clock : -1;
    s.spiralRate[i]=0; s.radiusAtCapture[i]=0; s.captureTime[i]=-1;
    s.launchClass[i]=cls; s.pericentre[i]=q;
    s.safetyLife[i]=between(s,s.config.safetyLifeSec); s.spiralSec[i]=between(s,s.config.capture.spiralSec);
    s.depth[i]=depthOverride === undefined ? (random(s)*s.targetPopulation < s.config.population.near ? 1 : 0) : depthOverride;
    s.seed[i]=random(s); s.phase[i]=random(s)*Math.PI*2;
    s.size[i]=between(s,s.depth[i] ? s.config.sizes.nearPx : s.config.sizes.middlePx);
    s.capturedSize[i]=between(s,s.config.sizes.capturedPx);
    s.r[i]=1; s.g[i]=1; s.b[i]=1; s.luminosity[i]=1;
    s.archetype[i]=0; s.p0[i]=0; s.p1[i]=0; s.p2[i]=0; s.p3[i]=0;
    return true;
}
// A camera birth and a camera death are time-reverses of each other, which is
// the whole reason the density stays uniform in both directions.
//
//   forward  born at the FAR plane, anywhere on the padded screen (uniform per
//            unit area -- a uniform 3-D field crossing a plane is uniform on
//            the screen), dies where its magnified radius leaves the screen.
//   reverse  the SAME far-plane draw, read as the point where the star will
//            dissolve: run it back out along its own ray to the edge it came
//            in through and start it there, at the depth it crossed at.
function cameraLaunch(s, i) {
    var far = cameraFar(s), rate = s.cameraRate > 0 ? s.cameraRate : 0;
    var dir = s.cameraDir < 0 ? -1 : 1;
    var hx = 0.5*s.width+s.padding, hy = 0.5*s.height+s.padding;
    // Where the star sits at the FAR plane: uniform over the padded rectangle
    // around the camera's own axis. Forward that is its birth; in reverse it is
    // where it will dissolve, and the two draws are the same draw.
    var px = (2*random(s)-1)*hx, py = (2*random(s)-1)*hy, z = far;
    if (dir < 0) {
        // Exact time-reverse of a forward life rather than a guess at the
        // distribution deaths arrive with: run that far-plane point back out
        // along its own ray to the edge it came in through, and take the depth
        // it crossed at. Arc-length or flux weighting of the perimeter both
        // measured a thinner field than forward; this one cannot, because it is
        // the forward construction read backwards.
        var reach = Math.max(Math.abs(px)/hx, Math.abs(py)/hy);
        z = far*reach;
        if (!(z > CAMERA_NEAR)) z = CAMERA_NEAR;
        else if (z > far) z = far;
        var m = far/z;
        px *= m; py *= m;
    }
    var x = s.centreX+px, y = s.centreY+py;
    s.x[i]=x; s.y[i]=y;
    // The screen velocity of a still star under a moving camera: radial, and
    // proportional to the radius over the depth. Everything the star does for
    // the rest of its life follows from these three numbers.
    var scale = dir*rate/z;
    s.vx[i]=(x-s.centreX)*scale; s.vy[i]=(y-s.centreY)*scale;
    s.depthZ[i]=z;
    return finishBirth(s, i, 1, s.qCap);
}
function launch(s, i, options) {
    var o = options || {};
    // Guarded so that with the camera off not one draw is taken from the stream
    // and the orbital regime is byte-identical to v7.
    var blend = cameraOn(s);
    if (blend > 0 && o.q === undefined && o.x === undefined && o.y === undefined
        && o.edge === undefined && o.launchClass === undefined && random(s) < blend)
        return cameraLaunch(s, i);
    var l = s.config.launch, draw = random(s);
    var cls = o.launchClass === undefined ? (draw < l.plunge ? 0 : draw < l.plunge+l.miss ? 1 : 2) : o.launchClass;
    var q = o.q === undefined ? pericentre(s, cls, between(s, LAUNCH_Q[cls])) : o.q;
    var beta = o.beta === undefined ? between(s, cls === 1 && random(s) < l.unboundShare ? l.betaUnbound : l.betaBound) : o.beta;
    var w = s.width+2*s.padding, h = s.height+2*s.padding;
    var perimeter = 2*(w+h);
    // Births arrive along a few slowly drifting streams rather than as uniform
    // rain, so the infall reads as tributaries. Stream identity is re-rolled on
    // its own lifetime; the draw order is unchanged when clustering is off.
    var edge = random(s)*perimeter;
    if (o.edge !== undefined) edge = o.edge;
    else if (s.config.clustering.share > 0 && random(s) < s.config.clustering.share) {
        var streams = streamTable(s, perimeter);
        var pickRaw = random(s)*streams.weight, pick = 0, acc = 0;
        for (var t = 0; t < streams.count; ++t) { acc += streams.w[t]; if (pickRaw < acc) { pick = t; break; } pick = t; }
        // Triangular scatter around the stream centre: dense core, finite tails.
        var jitter = (random(s)+random(s)-1)*streams.width[pick];
        edge = ((streams.at[pick]+jitter) % perimeter + perimeter) % perimeter;
    }
    var x, y;
    if (edge < w) { x = edge-s.padding; y = -s.padding; }
    else if (edge < w+h) { x = s.width+s.padding; y = edge-w-s.padding; }
    else if (edge < 2*w+h) { x = edge-w-h-s.padding; y = s.height+s.padding; }
    else { x = -s.padding; y = edge-2*w-h-s.padding; }
    if (o.x !== undefined) x = o.x;
    if (o.y !== undefined) y = o.y;
    var dx = x-s.centreX, dy = y-s.centreY, r = Math.sqrt(dx*dx+dy*dy);
    var phi = -s.mu/Math.sqrt(r*r+s.epsilon*s.epsilon);
    var v2 = beta*beta*2*s.muTarget/Math.sqrt(r*r+s.epsilon*s.epsilon);
    var e = v2/2+phi, h2 = 2*q*q*(e+s.mu/Math.sqrt(q*q+s.epsilon*s.epsilon));
    // Reject geometrically inaccessible combinations instead of clamping angular momentum.
    if (!(r > q && h2 >= 0 && h2/(r*r) <= v2)) {
        if (o.q !== undefined || o.x !== undefined || o.y !== undefined) return false;
        var attempt=(o.attempt || 0)+1;
        if (attempt>=16) return false;
        return launch(s, i, {launchClass: cls, beta: beta, attempt: attempt});
    }
    var sign = o.handedness === undefined ? (random(s) < l.handedness ? s.rotationSign : -s.rotationSign) : o.handedness;
    var vt = sign*Math.sqrt(h2)/r, vr = -Math.sqrt(Math.max(0,v2-vt*vt));
    s.x[i]=x; s.y[i]=y; s.vx[i]=(vr*dx-vt*dy)/r; s.vy[i]=(vr*dy+vt*dx)/r;
    s.depthZ[i]=0;
    var ok = finishBirth(s, i, cls, q, o.depth);
    // Mid-crossfade, a share of births still arrives on an orbit. Give it the
    // velocity the crossfade is about to give it anyway, instead of a pure
    // orbital one it loses on its first step: at blend 0.88 that snap was a
    // 264 -> 38 px/s change in one frame and an 8 px jump in the rendered
    // streak, on a star the 0.35 s entrance fade still had at 3 % light.
    if (ok && blend > 0) {
        var z = cameraDepthOf(s, i);
        var scale = (s.cameraDir < 0 ? -1 : 1)*(s.cameraRate > 0 ? s.cameraRate : 0)/z;
        s.vx[i] += blend*((x-s.centreX)*scale-s.vx[i]);
        s.vy[i] += blend*((y-s.centreY)*scale-s.vy[i]);
    }
    return ok;
}
// ---- Tidal disruption (phenomena.tde) ---------------------------------------
// One doomed particle is stretched into a long stream as it falls through
// pericentre, then splits into siblings that spiral in on their ordinary
// capture time and feed the disk. No slot, no uniform, no shader change: the
// rendering is entirely the packed streak field, which particles/Appearance.js
// ramps. The only cost is a handful of extra particles for a minute.
function freeSlot(s) {
    var searched = 0;
    while (s.alive[s.nextSlot] && searched < s.capacity) { s.nextSlot = (s.nextSlot + 1) % s.capacity; ++searched; }
    if (searched === s.capacity) return -1;
    var i = s.nextSlot; s.nextSlot = (s.nextSlot + 1) % s.capacity; return i;
}
// A sibling is placed on the victim's own state, not launched from an edge, so
// it inherits the orbit instead of arriving as a fresh infall.
function inject(s, x, y, vx, vy, depth, birthCallback) {
    var i = freeSlot(s);
    if (i < 0) return -1;
    s.x[i] = x; s.y[i] = y; s.vx[i] = vx; s.vy[i] = vy; s.depthZ[i] = 0;
    if (!s.alive[i]) { ++s.aliveCount; s.live[s.liveCount++] = i; }
    s.alive[i] = 1; ++s.generation[i]; ++s.counters.births;
    if (s.transient[i]) { s.transient[i]=0; if (s.transientCount>0) --s.transientCount; }
    if (s.kickX[i] || s.kickY[i]) { s.kickX[i]=0; s.kickY[i]=0; if (s.kickAlive>0) --s.kickAlive; }
    s.kickAge[i]=0; s.kickDrag[i]=0;
    s.age[i] = 0; s.circularSince[i] = -1; s.captureExposure[i] = 0;
    s.entryTime[i] = x >= 0 && x <= s.width && y >= 0 && y <= s.height ? s.clock : -1;
    s.spiralRate[i] = 0; s.radiusAtCapture[i] = 0; s.captureTime[i] = -1;
    var dx = x - s.centreX, dy = y - s.centreY;
    s.launchClass[i] = 0;
    s.pericentre[i] = Math.min(Math.sqrt(dx * dx + dy * dy), 0.6 * s.shadow);
    s.safetyLife[i] = between(s, s.config.safetyLifeSec);
    s.spiralSec[i] = between(s, s.config.capture.spiralSec);
    s.depth[i] = depth;
    s.seed[i] = random(s); s.phase[i] = random(s) * Math.PI * 2;
    s.size[i] = between(s, depth ? s.config.sizes.nearPx : s.config.sizes.middlePx);
    s.capturedSize[i] = between(s, s.config.sizes.capturedPx);
    s.r[i] = 1; s.g[i] = 1; s.b[i] = 1; s.luminosity[i] = 1;
    s.archetype[i] = 0; s.p0[i] = 0; s.p1[i] = 0; s.p2[i] = 0; s.p3[i] = 0;
    if (birthCallback) birthCallback(s, i);
    return i;
}
// Choose a victim: alive, not already captured, still outside the capture
// radius and on an orbit that actually reaches deep. Nearest to its pericentre
// wins, so the stretch and the closest approach line up.
function doom(s, options) {
    var o = options || {};
    var best = -1, bestScore = Infinity;
    // Bounds are against the shadow, like the v6 victim test; the near gate is
    // the capture band, which the victim must still be outside of.
    var inner = s.captureOuter, deep = 6 * s.shadow, far = 12 * s.shadow;
    for (var k = 0; k < s.liveCount; ++k) {
        var i = s.live[k];
        if (!s.alive[i] || s.radiusAtCapture[i] > 0 || s.transient[i]) continue;
        if (novaStar(s) === i) continue;
        if (s.pericentre[i] > deep) continue;
        var dx = s.x[i] - s.centreX, dy = s.y[i] - s.centreY;
        var r = Math.sqrt(dx * dx + dy * dy);
        if (r < inner || r > far) continue;
        // Inbound only: a receding particle would stretch on its way out.
        if (dx * s.vx[i] + dy * s.vy[i] >= 0) continue;
        var score = r - s.pericentre[i];
        if (score < bestScore) { bestScore = score; best = i; }
    }
    if (best < 0) return false;
    s.tde = {index: best, generation: s.generation[best], start: s.clock,
        stretchSec: Math.max(0.5, o.stretchSec === undefined ? 9 : o.stretchSec),
        // 120 px, not the service's 160: that is what the packed streak byte
        // carries (120/255 per code), and the atlas is sized for the same
        // number. A larger request is met with the longest trail that exists.
        streakPx: Math.max(0, Math.min(120, o.streakPx === undefined ? 100 : o.streakPx)),
        fragments: Math.max(1, Math.min(16, Math.round(o.fragments === undefined ? 6 : o.fragments))),
        // After the split the victim is one head of its own stream, so its
        // trail eases back to its natural length instead of snapping.
        fadeSec: 6,
        splitAt: -1,
        split: false};
    return true;
}
// Alive and still the same particle: a victim that died or was recycled leaves
// the descriptor behind, and every consumer tests through this.
function doomed(s, i) {
    var t = s.tde;
    return !!t && t.index === i && t.generation === s.generation[i] && s.alive[i] > 0;
}
function tdeStep(s, birthCallback) {
    var t = s.tde;
    if (!t) return;
    var i = t.index;
    if (!doomed(s, i)) { s.tde = null; return; }
    var age = s.clock - t.start;
    if (t.split) {
        // Hold the descriptor through the fade so the victim's own trail eases
        // back rather than snapping to its natural length on one frame.
        if (s.clock - t.splitAt >= t.fadeSec) s.tde = null;
        return;
    }
    if (age < t.stretchSec) return;
    t.split = true;
    t.splitAt = s.clock;
    // Siblings are spread ALONG the orbit, which is what a disrupted stream
    // looks like: a spread in specific energy, not a spray of directions.
    var vx = s.vx[i], vy = s.vy[i];
    var speed = Math.sqrt(vx * vx + vy * vy);
    if (speed < 1e-6) return;
    var ux = vx / speed, uy = vy / speed;
    var made = 0;
    for (var n = 0; n < t.fragments; ++n) {
        var along = (n + 1) / (t.fragments + 1) - 0.5;
        var lead = along * t.streakPx * 1.6;
        var scale = 1 + along * 0.16;
        if (inject(s, s.x[i] + ux * lead, s.y[i] + uy * lead,
            vx * scale - uy * along * speed * 0.05,
            vy * scale + ux * along * speed * 0.05,
            s.depth[i], birthCallback) >= 0) ++made;
    }
    s.counters.tde = (s.counters.tde || 0) + 1;
    s.counters.tdeFragments = (s.counters.tdeFragments || 0) + made;
}
// ---- v10: the event -> particle interface -----------------------------------
// Until v9 an event was a sprite scheduled BESIDE the sky: a supernova faded in
// and out where no star had ever been, and a comet drifted at the field's own
// speed with its tail pointing the wrong way. His report (ledger 2285) is one
// sentence: "right now everything feels like separate pieces, not part of one
// system." These four calls are that system. Everything an event does to the
// field goes through them, so a sprite and the material it is made of share
// one position, one velocity and one clock by construction rather than by two
// pieces of code being kept in step.
//
//   applyImpulse   a radial shove on the particles that are already there
//   spawnBurst     new material born at a point, integrated like everything else
//   brightenNear   a transient luminosity lift on the stars around a flash
//   pickStar       the existing particle an event is going to happen TO
//
// Debris lives in the same atlas as every other particle, so it gets the
// lensing, the depth ordering, the disk occlusion and the tidal treatment for
// free and costs no uniform, no slot and no shader change.

// How much of a kick belongs in the velocity and how much in the peculiar
// channel. With the hole on the velocity IS the dynamics, so a shove changes
// the orbit and gravity answers it. With the camera on the stored velocity is
// overwritten by the magnification every substep (see step()), so a velocity
// kick is discarded on the frame it lands and the shove has to ride the
// peculiar channel instead, where it decays back into the flow.
function deliver(s, i, vx, vy, drag) {
    var blend = cameraOn(s);
    if (blend < 1) { s.vx[i] += (1 - blend) * vx; s.vy[i] += (1 - blend) * vy; }
    if (blend > 0) {
        var had = s.kickX[i] !== 0 || s.kickY[i] !== 0;
        s.kickX[i] += blend * vx; s.kickY[i] += blend * vy;
        // A fresh kick restarts the decay clock; an existing one keeps its own,
        // so a particle caught by two shocks does not have the first undone.
        if (!had) { s.kickAge[i] = 0.02; s.kickDrag[i] = drag; ++s.kickAlive; }
    }
    ++s.counters.kicked;
}
// A radial push with falloff, centred on (x, y).
//
//   profile 'blast'  (default) strongest at the centre, zero at radiusPx
//   profile 'shell'  a band at radiusPx: the shock front passing through
//   profile 'front'  the ANNULUS [o.fromPx, radiusPx] only, weighted by how
//                    far out it is against o.maxPx. Called once a frame with
//                    the front's own advancing radius this kicks each particle
//                    exactly once, as the shock reaches it, which is the
//                    difference between a shell that passes through the field
//                    and one drawn over the top of it.
//   profile 'flat'   uniform inside radiusPx
//
// `profile` may also be an object {kind, widthPx, skip, drag, includeTransient}.
// Bounded by construction: no particle receives more than `strength` px/s, so
// the total momentum delivered is at most strength * (particles in reach), and
// the return value reports both so a caller and a test can check it.
function applyImpulse(s, x, y, strength, radiusPx, profile) {
    var o = typeof profile === 'string' ? {kind: profile} : (profile || {});
    var kind = o.kind || 'blast';
    var v0 = number(strength, 0, 0, BOUNDS.impulsePx[1]);
    var reach = number(radiusPx, 0, 0, 8 * Math.max(s.width, s.height));
    var out = {count: 0, momentum: 0, peak: 0};
    if (!(v0 > 0) || !(reach > 0)) return out;
    var band = Math.max(1, number(o.widthPx, 0.22 * reach, 0.5, reach));
    var skip = o.skip === undefined ? -1 : o.skip;
    // A shoved star relaxes back into the flow: the exponent is the one that
    // leaves it at 1 % of the kick after `debris.relaxSec`, so one configured
    // number owns how long the jolt is visible.
    var relax = s.config.debris.relaxSec;
    var drag = number(o.drag, Math.max(0.2, Math.min(4, Math.log(100) / Math.log(Math.max(1.5, relax / 0.02)))), 0, 4);
    var all = o.includeTransient === true;
    var from = number(o.fromPx, 0, 0, 8 * Math.max(s.width, s.height));
    var maxReach = Math.max(reach, number(o.maxPx, reach, 0, 8 * Math.max(s.width, s.height)));
    var inner = kind === 'shell' ? Math.max(0, reach - 2.5 * band) : (kind === 'front' ? from : 0);
    var outer2 = kind === 'shell' ? (reach + 2.5 * band) * (reach + 2.5 * band) : reach * reach;
    if (kind === 'front' && !(reach > from)) return out;
    for (var k = 0; k < s.liveCount; ++k) {
        var i = s.live[k];
        if (!s.alive[i] || i === skip) continue;
        if (!all && s.transient[i]) continue;
        var dx = s.x[i] - x, dy = s.y[i] - y, r2 = dx * dx + dy * dy;
        if (r2 > outer2) continue;
        var r = Math.sqrt(r2);
        if (r < 1e-4) { dx = 1; dy = 0; r = 1; }
        var w;
        if (kind === 'flat') w = 1;
        else if (kind === 'front') {
            if (r < inner) continue;
            var f = r / maxReach;
            if (f >= 1) continue;
            // A blast of fixed energy drives less and less material the further
            // out it gets: full shove beside the star, nothing at the rim.
            w = (1 - f) * (1 - f) * (1 + f);
        } else if (kind === 'shell') {
            if (r < inner) continue;
            var t = (r - reach) / band;
            w = Math.exp(-t * t);
        } else {
            var u = r / reach;
            w = (1 - u) * (1 - u) * (1 + u);   // 1 at the centre, 0 at the reach
        }
        if (!(w > 0.002)) continue;
        var speed = v0 * w;
        deliver(s, i, speed * dx / r, speed * dy / r, drag);
        ++out.count; out.momentum += speed;
        if (speed > out.peak) out.peak = speed;
    }
    ++s.counters.impulses;
    return out;
}
// How many transient slots are left. The reserve is what the atlas was
// allocated for; the second term is the hard slot count, which a stress preset
// could otherwise walk into.
function debrisRoom(s) {
    var reserve = s.config.debris.maxAlive - s.transientCount;
    var slots = s.capacity - s.aliveCount - 8;
    return Math.max(0, Math.min(reserve, slots));
}
// A transient particle: same arrays, same integration, same atlas, but it does
// not count toward the population target and it does not feed the lifetime
// estimator. `traits` owns everything a birth callback would otherwise own,
// because event debris takes its colour from the physics of the event and not
// from his palette.
function spawnAt(s, x, y, vx, vy, kx, ky, traits) {
    var t = traits || {};
    var i = freeSlot(s);
    if (i < 0) return -1;
    if (!s.alive[i]) { ++s.aliveCount; s.live[s.liveCount++] = i; }
    s.alive[i] = 1; ++s.generation[i]; ++s.counters.births;
    if (!s.transient[i]) { s.transient[i] = 1; ++s.transientCount; }
    s.x[i] = x; s.y[i] = y; s.vx[i] = vx; s.vy[i] = vy;
    s.age[i] = 0; s.circularSince[i] = -1; s.captureExposure[i] = 0;
    s.entryTime[i] = x >= 0 && x <= s.width && y >= 0 && y <= s.height ? s.clock : -1;
    s.spiralRate[i] = 0; s.radiusAtCapture[i] = 0; s.captureTime[i] = -1;
    s.launchClass[i] = 1;
    s.pericentre[i] = s.qCap;
    s.safetyLife[i] = Math.max(0.5, number(t.lifeSec, 30, 0.5, 600));
    s.spiralSec[i] = between(s, s.config.capture.spiralSec);
    s.depth[i] = t.depth === undefined ? 1 : t.depth;
    s.depthZ[i] = cameraOn(s) > 0 ? number(t.depthZ, 0, 0, 64) : 0;
    if (!(s.depthZ[i] >= CAMERA_NEAR)) s.depthZ[i] = 0;
    s.seed[i] = random(s); s.phase[i] = random(s) * Math.PI * 2;
    s.size[i] = number(t.sizePx, 2.4, 0.25, 12);
    s.capturedSize[i] = s.size[i];
    var c = t.colour || [1, 1, 1];
    s.r[i] = number(c[0], 1, 0, 1); s.g[i] = number(c[1], 1, 0, 1); s.b[i] = number(c[2], 1, 0, 1);
    s.luminosity[i] = number(t.lum, 2.6, 0, 8);
    s.archetype[i] = t.archetype === undefined ? 7 : t.archetype;
    s.p0[i] = s.safetyLife[i]; s.p1[i] = number(t.fast, 0, 0, 1);
    s.p2[i] = number(t.group, 0, 0, 255); s.p3[i] = 0;
    s.kickX[i] = 0; s.kickY[i] = 0; s.kickAge[i] = 0; s.kickDrag[i] = 0;
    if (kx || ky) {
        s.kickX[i] = kx; s.kickY[i] = ky;
        s.kickAge[i] = number(t.t0, 0.02, 0.002, 4);
        s.kickDrag[i] = number(t.drag, 0.6, 0, 4);
        ++s.kickAlive;
    }
    // Appearance owns exposure, the streak ceiling, the tidal traits and the
    // ember's end colour; Physics must not reach into its arrays, so the
    // renderer hands it in the way it hands in `birthCallback`. Without one the
    // particle still integrates correctly, it just keeps the previous
    // occupant's optical traits, which is what the node fixtures see.
    if (s.transientBirth) s.transientBirth(s, i, t);
    return i;
}
// Debris born at a point with radial velocities. The speeds are the speeds at
// t0 (the first 0.02 s), and `drag` is the exponent p in v = v0*(t0/t)^p: at the
// default 0.6 the displacement is r ~ t^0.4, which is the SAME Sedov law the
// shell sprite draws, so the rim runs through the middle of its own debris
// instead of beside it.
function spawnBurst(s, x, y, count, speedRange, traits) {
    var t = traits || {};
    var want = Math.round(number(count, 0, 0, BOUNDS.burstCount[1]));
    var room = debrisRoom(s);
    var n = Math.min(want, room);
    if (!(n > 0)) return 0;
    var sr = Array.isArray(speedRange) && speedRange.length === 2
        ? [number(speedRange[0], 0, 0, BOUNDS.impulsePx[1]), number(speedRange[1], 0, 0, BOUNDS.impulsePx[1])]
        : [60, 240];
    var lo = Math.min(sr[0], sr[1]), hi = Math.max(sr[0], sr[1]);
    var sizes = Array.isArray(t.sizePx) && t.sizePx.length === 2 ? t.sizePx : [1.1, 3.2];
    var lives = Array.isArray(t.lifeSec) && t.lifeSec.length === 2 ? t.lifeSec : [20, 60];
    var lums = Array.isArray(t.lum) && t.lum.length === 2 ? t.lum : [2.2, 4.2];
    var fastShare = number(t.fastShare, 0.07, 0, 0.35);
    var fastGain = number(t.fastGain, 2.6, 1, 8);
    var spread = number(t.spreadSec, 0, 0, 4);
    var made = 0;
    for (var j = 0; j < n; ++j) {
        // A shell is a sphere seen flat, so the speeds are not uniform on the
        // screen: the material moving across the line of sight shows its full
        // speed and the material coming at us shows a fraction of it. sqrt of a
        // uniform draw is that projection, and it is what stops the burst from
        // reading as a ring with a hole in the middle.
        var angle = random(s) * Math.PI * 2;
        var project = Math.sqrt(random(s));
        var fast = random(s) < fastShare;
        // Uniform in the requested range, so the MEDIAN ejecta speed is the
        // midpoint times the projection's 0.707 and the caller can solve for
        // the reach it wants. A skewed draw here would quietly put the whole
        // cloud inside the rim the sprite is drawing.
        var base = lo + (hi - lo) * random(s);
        var speed = base * project * (fast ? fastGain : 1);
        if (speed > BOUNDS.impulsePx[1]) speed = BOUNDS.impulsePx[1];
        var life = lives[0] + (lives[1] - lives[0]) * random(s);
        var trait = {
            lifeSec: life + spread * random(s),
            sizePx: sizes[0] + (sizes[1] - sizes[0]) * random(s) * (fast ? 1.35 : 1),
            lum: lums[0] + (lums[1] - lums[0]) * random(s) * (fast ? 1.3 : 1),
            colour: t.colour || [1, 0.97, 0.92],
            depth: t.depth === undefined ? (random(s) < 0.45 ? 1 : 0) : t.depth,
            depthZ: t.depthZ,
            fast: fast ? 1 : 0,
            drag: number(t.drag, 0.6, 0, 4),
            t0: number(t.t0, 0.02, 0.002, 4),
            // A fast fragment leaves a longer trail than a slow one twice
            // over: it is faster, and its shutter is open longer.
            group: t.group,
            streakPx: t.streakPx,
            exposureSec: t.exposureSec === undefined ? undefined : t.exposureSec * (fast ? 1.6 : 1),
            endColour: t.endColour
        };
        if (spawnAt(s, x, y, 0, 0, Math.cos(angle) * speed, Math.sin(angle) * speed, trait) >= 0) ++made;
    }
    s.counters.debris += made;
    return made;
}
// A body with its own proper motion: the comet's nucleus. drag 0, so it holds
// its speed across the field instead of relaxing into the flow, and with the
// hole on the velocity goes into vx/vy where gravity bends it into a real
// hyperbolic pass.
function spawnBody(s, x, y, vx, vy, traits) {
    var t = traits || {};
    var blend = cameraOn(s);
    var kx = blend * vx, ky = blend * vy;
    var i = spawnAt(s, x, y, (1 - blend) * vx, (1 - blend) * vy, kx, ky,
        {lifeSec: t.lifeSec, sizePx: t.sizePx, lum: t.lum, colour: t.colour,
         depth: t.depth === undefined ? 1 : t.depth, depthZ: t.depthZ,
         archetype: t.archetype === undefined ? 0 : t.archetype,
         group: t.group, drag: 0, t0: 0.02, streakPx: t.streakPx, exposureSec: t.exposureSec});
    return i;
}
// Translate one event's material as a body. The debris of a supernova expands
// about its own site by its own velocity; the site itself travels on the far
// layer's streamline, which is what a distant thing does in the camera regime,
// and this is how the two are composed without giving every ember a second
// integration. `group` is the event's id, stored in p2 because a transient has
// no archetype parameters to keep there.
function driftGroup(s, group, dx, dy) {
    if (!(dx || dy)) return 0;
    var moved = 0;
    for (var k = 0; k < s.liveCount; ++k) {
        var i = s.live[k];
        if (!s.alive[i] || !s.transient[i] || s.p2[i] !== group) continue;
        s.x[i] += dx; s.y[i] += dy;
        ++moved;
    }
    return moved;
}
// A transient luminosity lift on the stars that are already there: the flash
// lighting its neighbourhood. Rendered by Appearance.render(), so it costs one
// distance test per particle per live glow and nothing at all when there are
// none.
function brightenNear(s, x, y, radius, gain, decaySec) {
    var r = number(radius, 0, 0, 8 * Math.max(s.width, s.height));
    var g = number(gain, 0, 0, 8);
    var d = number(decaySec, 1, 0.05, 120);
    if (!(r > 0) || !(g > 0)) return false;
    if (s.glows.length >= BOUNDS.glows) s.glows.shift();
    s.glows.push({x: x, y: y, radius: r, gain: g, start: s.clock, decay: d});
    return true;
}
function glowStep(s) {
    for (var i = s.glows.length - 1; i >= 0; --i)
        if (s.clock - s.glows[i].start >= s.glows[i].decay) s.glows.splice(i, 1);
}
// A cloud the field passes THROUGH: the nebula. One ellipse, a slight drag and
// a colour weight, applied once per outer step over the live list rather than
// inside the substep loop, because it is a per-second effect and not a force.
function setCloud(s, cloud) {
    if (!cloud || !(cloud.radius > 0)) { s.cloud = null; return; }
    s.cloud = {x: cloud.x, y: cloud.y, radius: cloud.radius,
        aspect: number(cloud.aspect, 1, 0.2, 5), angle: number(cloud.angle, 0, -7, 7),
        drag: number(cloud.drag, 0, 0, 1), tint: cloud.tint || [1, 0.86, 0.72],
        weight: number(cloud.weight, 0, 0, 1)};
}
function cloudWeight(s, i) {
    var c = s.cloud;
    if (!c) return 0;
    var dx = s.x[i] - c.x, dy = s.y[i] - c.y;
    var cs = Math.cos(-c.angle), sn = Math.sin(-c.angle);
    var u = (dx * cs - dy * sn) / c.radius, v = (dx * sn + dy * cs) / (c.radius * c.aspect);
    var q = u * u + v * v;
    return q >= 1 ? 0 : (1 - q) * (1 - q);
}
function cloudStep(s, dt) {
    var c = s.cloud;
    if (!c || !(c.drag > 0) || !(dt > 0)) return;
    // The drag is expressed in each regime's OWN terms, because a multiply on
    // the stored velocity only works in one of them: with the camera on that
    // velocity is rewritten by the magnification every substep, so damping it
    // there is erased on the same frame and the cloud would do nothing in the
    // one regime he actually runs. In the camera regime the cloud instead HOLDS
    // THE MATERIAL BACK IN DEPTH -- the approach slows by `drag` while the
    // particle is inside -- which slows it on the screen, keeps it smaller and
    // keeps it dimmer, all three of the depth cues together, and leaves it
    // honestly further away once the cloud has gone past.
    var blend = cameraOn(s);
    var camDir = s.cameraDir < 0 ? -1 : 1;
    var camRate = s.cameraRate > 0 && isFinite(s.cameraRate) ? s.cameraRate : 0;
    var far = cameraFar(s);
    for (var k = 0; k < s.liveCount; ++k) {
        var i = s.live[k];
        if (!s.alive[i]) continue;
        var w = cloudWeight(s, i);
        if (!(w > 0.004)) continue;
        var hold = c.drag * w;
        if (hold > 0.6) hold = 0.6;
        if (blend > 0 && camRate > 0) {
            var z = s.depthZ[i] + camDir * camRate * dt * hold * blend;
            if (z < CAMERA_NEAR) z = CAMERA_NEAR; else if (z > far) z = far;
            s.depthZ[i] = z;
        }
        if (blend < 1) {
            var f = Math.exp(-hold * (1 - blend) * dt);
            s.vx[i] *= f; s.vy[i] *= f;
            if (s.kickX[i] || s.kickY[i]) { s.kickX[i] *= f; s.kickY[i] *= f; }
        }
    }
}
// The star an event is going to happen TO. It must be a real particle that is
// already on the screen and will still be there when its precursor runs out,
// because the whole point is that he can see the star BEFORE it goes.
function pickStar(s, options) {
    var o = options || {};
    var margin = number(o.marginPx, 0.10 * Math.min(s.width, s.height), 0, Math.min(s.width, s.height) / 2);
    var need = number(o.holdSec, 25, 0, 600);
    var keepOut = number(o.keepOutPx, 0, 0, 8 * Math.max(s.width, s.height));
    var minSize = number(o.minSizePx, 0, 0, 12);
    var best = -1, bestScore = -Infinity;
    var cx = s.centreX, cy = s.centreY;
    for (var k = 0; k < s.liveCount; ++k) {
        var i = s.live[k];
        if (!s.alive[i] || s.transient[i]) continue;
        if (s.radiusAtCapture[i] > 0 || doomed(s, i)) continue;
        if (s.age[i] < 1.5) continue;                       // still fading in
        if (s.safetyLife[i] - s.age[i] < need) continue;    // would die mid-precursor
        if (s.size[i] < minSize) continue;
        var x = s.x[i], y = s.y[i];
        if (x < margin || x > s.width - margin || y < margin || y > s.height - margin) continue;
        var dx = x - cx, dy = y - cy, r = Math.sqrt(dx * dx + dy * dy);
        if (r < keepOut) continue;
        // Where it will be when the precursor ends. A star that walks off the
        // screen mid-swell is the same defect as one that dies mid-swell.
        var px = x + (s.vx[i] + s.kickX[i]) * need, py = y + (s.vy[i] + s.kickY[i]) * need;
        if (px < 0.4 * margin || px > s.width - 0.4 * margin || py < 0.4 * margin || py > s.height - 0.4 * margin) continue;
        // ... and not into the hole. With the hole on the field streams inward
        // fast, so a long precursor simply has no candidate; the caller shortens
        // `holdSec` against the measured flow rather than pretending otherwise.
        if (keepOut > 0 && Math.hypot(px - cx, py - cy) < keepOut) continue;
        // Bright, near, and not moving fast: a near star that holds still is the
        // one the eye has already learned before it starts to swell.
        var speed = Math.sqrt(s.vx[i] * s.vx[i] + s.vy[i] * s.vy[i]);
        var score = (s.depth[i] > 0.5 ? 2.4 : 0) + s.size[i] * 0.5 + s.luminosity[i] * 0.25
            - speed / Math.max(1, s.config.vref) - (o.jitter ? 0 : 0) + random(s) * 0.8;
        if (score > bestScore) { bestScore = score; best = i; }
    }
    return best;
}
// The precursor descriptor, shaped like `s.tde`: the renderer marks the star
// here and Appearance.render() reads it, so the swelling is a property of THAT
// particle and travels with it.
function markNova(s, i, options) {
    if (!(i >= 0) || !s.alive[i]) return false;
    var o = options || {};
    s.nova = {index: i, generation: s.generation[i], start: s.clock,
        precursor: Math.max(0.5, number(o.precursorSec, 14, 0.5, 240)),
        sizeGain: number(o.sizeGain, 4, 1, 12),
        lumGain: number(o.lumGain, 5.5, 1, 20),
        warm: o.warm || [1, 0.60, 0.38],
        hot: o.hot || [0.84, 0.92, 1]};
    return true;
}
function novaStar(s) {
    var n = s.nova;
    if (!n) return -1;
    if (!s.alive[n.index] || s.generation[n.index] !== n.generation) { s.nova = null; return -1; }
    return n.index;
}
function clearNova(s) { s.nova = null; }
// Mean screen speed of the live field, which is what "three to eight times
// faster than everything around it" is measured against. Sampled rather than
// summed: 96 particles is inside 4 % of the mean at these populations and the
// call is once per comet, not once per frame.
function flowSpeed(s) {
    var n = s.liveCount;
    if (!n) return 0;
    var stride = Math.max(1, Math.floor(n / 96));
    var sum = 0, count = 0;
    for (var k = 0; k < n; k += stride) {
        var i = s.live[k];
        if (!s.alive[i] || s.transient[i]) continue;
        var vx = s.vx[i] + s.kickX[i], vy = s.vy[i] + s.kickY[i];
        sum += Math.sqrt(vx * vx + vy * vy); ++count;
    }
    return count ? sum / count : 0;
}

// Stream table for clustered births. Each stream is a birth-frozen edge position
// with its own drift and width, re-rolled on its own lifetime, so the preferred
// directions wander over minutes instead of being fixed forever.
function streamTable(s, perimeter) {
    var c = s.config.clustering, n = c.streams;
    var table = s.streamState;
    if (!table || table.count !== n) {
        table = s.streamState = {count: n, at: new Float64Array(n), w: new Float64Array(n),
            width: new Float64Array(n), drift: new Float64Array(n), until: new Float64Array(n),
            weight: 0};
        for (var j = 0; j < n; ++j) table.until[j] = -1;
    }
    var total = 0;
    for (var i = 0; i < n; ++i) {
        if (s.clock >= table.until[i]) {
            table.at[i] = random(s)*perimeter;
            table.w[i] = 0.35+random(s)*random(s)*2.2;
            table.width[i] = perimeter*(0.012+0.05*random(s));
            table.drift[i] = (random(s)-0.5)*perimeter/600;
            table.until[i] = s.clock+c.streamLifeSec*(0.6+0.8*random(s));
        } else table.at[i] += table.drift[i]*(s.clock-table.stamp);
        total += table.w[i];
    }
    table.stamp = s.clock;
    table.weight = total;
    return table;
}
function damp(s, i, dt, gamma, nu) {
    var x=s.x[i]-s.centreX,y=s.y[i]-s.centreY,r=Math.sqrt(x*x+y*y);
    if (r === 0) return;
    var ex=x/r,ey=y/r,vr=s.vx[i]*ex+s.vy[i]*ey,vt=-s.vx[i]*ey+s.vy[i]*ex;
    vr*=Math.exp(-gamma*dt); vt*=Math.exp(-nu*dt);
    s.vx[i]=vr*ex-vt*ey; s.vy[i]=vr*ey+vt*ex;
}
function kill(s, i, cause) {
    s.alive[i]=0; --s.aliveCount; ++s.counters.deaths; ++s.counters[cause];
    if (s.kickX[i] || s.kickY[i]) { s.kickX[i]=0; s.kickY[i]=0; if (s.kickAlive>0) --s.kickAlive; }
    // Event debris is NOT a star: it must not be counted toward the population
    // target (which would suppress ordinary births for the debris' whole life)
    // and it must not feed the lifetime estimator (400 forty-second lives
    // against a 97 s orbital mean would quadruple the birth rate for minutes).
    if (s.transient[i]) {
        s.transient[i]=0; if (s.transientCount>0) --s.transientCount;
        return;
    }
    ++s.lifetimeSamples; s.lifetimeSum+=s.age[i];
    // A 30-second prior avoids the first short plunges dominating birth rate.
    s.meanLifetime=(3000+s.lifetimeSum)/(100+s.lifetimeSamples);
    s.birthRate=s.targetPopulation/s.meanLifetime;
}
// Public death, for an event that consumes a particle: the supernova's
// precursor star is removed on the frame it detonates, and the cause is its
// own counter so a swallow rate is not polluted by it.
function remove(s, i, cause) {
    if (!(i >= 0 && i < s.capacity) || !s.alive[i]) return false;
    var name = cause || 'consumed';
    if (s.counters[name] === undefined) s.counters[name] = 0;
    kill(s, i, name);
    return true;
}
function swept(x, y, nx, ny, radius) {
    var dx=nx-x,dy=ny-y,den=dx*dx+dy*dy;
    var t=den > 0 ? Math.max(0,Math.min(1,-(x*dx+y*dy)/den)) : 0;
    x+=t*dx;y+=t*dy;return x*x+y*y<=radius*radius;
}
// First nucleus intersection with the viewport; return -1 for no intersection.
function viewportEntry(x, y, nx, ny, width, height) {
    var dx=nx-x,dy=ny-y,enter=0,leave=1,a,b;
    if (dx===0) { if (x<0 || x>width) return -1; }
    else {
        a=-x/dx;b=(width-x)/dx;
        enter=Math.max(enter,Math.min(a,b));leave=Math.min(leave,Math.max(a,b));
    }
    if (dy===0) { if (y<0 || y>height) return -1; }
    else {
        a=-y/dy;b=(height-y)/dy;
        enter=Math.max(enter,Math.min(a,b));leave=Math.min(leave,Math.max(a,b));
    }
    return enter<=leave ? enter : -1;
}
// Hot loop. Everything it touches is hoisted into locals (a property lookup on
// the state object costs more than the arithmetic in QML's JS engine), it walks
// the dense live list instead of the capacity, and every square root past the
// force evaluation is computed only on the branch that needs it: outside the
// capture radius there is no drag, no torque and no circularisation test, and
// inside the padded rectangle there is no escape test.
function step(s, dt, options) {
    if (!(dt > 0) || !isFinite(dt)) return;
    var o=options || {}, c=s.config.capture, eps2=s.epsilon*s.epsilon;
    var X=s.x, Y=s.y, VX=s.vx, VY=s.vy, AGE=s.age, ENTRY=s.entryTime;
    var SINCE=s.circularSince, EXPOSURE=s.captureExposure, RATE=s.spiralRate;
    var RCAP=s.radiusAtCapture, CTIME=s.captureTime, LIFE=s.safetyLife, SPIRAL=s.spiralSec;
    var alive=s.alive, live=s.live, n=s.liveCount;
    var cx=s.centreX, cy=s.centreY, mu=s.mu, rh=s.rh, clock=s.clock;
    var width=s.width, height=s.height, pad=s.padding;
    // The swallow radius is the SHADOW, the black core: that is where a star
    // falling in disappears, and nothing is drawn inside it. Crossing the disk
    // band on the way there is not a swallow, it is an occlusion, and the
    // compositing in starfield.frag owns it. Still gated by the visibility
    // envelope, so at 0 there is no hole and particles pass through the centre.
    var shadow=s.shadow, deathR=shadow*(s.absorb === undefined ? 1 : s.absorb);
    var inner=s.captureInner, outer=s.captureOuter, outer2=outer*outer, drag=c.gamma;
    var floor=s.captureFloor;
    // The camera regime crossfades against the orbital one over the hole's own
    // enable envelope: gravity and the capture drag fade out as the camera's
    // magnification fades in, so the toggle is a thirty-second change of regime
    // and never a cut. At blend 1 the stored velocity IS the camera velocity,
    // so streaks, the tidal direction term and the tests all read the truth.
    // Gravity leaves AHEAD of the picture, as the square of the envelope. The
    // swallow radius follows `absorb` linearly, so a linear mass fade leaves a
    // late crossfade holding 6 % of the pull with a 14 px event horizon, and a
    // star diving into that gap whips round it: measured worst one-frame streak
    // change 8.0 px against a 2.8 px orbital baseline. Squaring it takes the
    // peak speed at a given radius down by four at that point and the artefact
    // with it, and it is the right way round anyway -- he asked for the hole AND
    // its physics off, not for an invisible mass to go on pulling.
    var blend=cameraOn(s), gravity=(1-blend)*(1-blend), DZ=s.depthZ;
    var KX=s.kickX, KY=s.kickY, KA=s.kickAge, KD=s.kickDrag, anyKick=s.kickAlive>0;
    // EVENT MATERIAL IS EXEMPT FROM THE CAMERA REGIME. The camera crosses the
    // whole depth range in sixty active seconds at the shipped speed, so
    // anything anchored in 3-D leaves the screen before its own shell has
    // finished -- the v9 note on supernovaSite established that for the site
    // and it is just as true for the material. Worse, a cloud whose particles
    // each drew their own depth magnifies by a different factor per particle,
    // which pulls the debris away from the rim that is supposed to be running
    // through it: measured 650 px of debris against a 279 px rim. Debris
    // therefore expands by its OWN velocity only and the whole cloud is
    // translated together (driftGroup) along the far layer's streamline, which
    // is where a supernova is. It is also why a transient never dies by
    // reaching the camera's near plane.
    var TRANSIENT=s.transient;
    var camRate=0, camDir=1, camFar=cameraFar(s), camRoll=0;
    if (blend>0) {
        mu*=gravity; drag*=gravity;
        camRate=s.cameraRate>0 && isFinite(s.cameraRate) ? s.cameraRate : 0;
        camDir=s.cameraDir<0 ? -1 : 1;
        camRoll=isFinite(s.cameraRoll) ? s.cameraRoll : 0;
    }
    var doDrag=o.drag !== false, doTorque=o.torque !== false, doDeaths=o.deaths !== false;
    // Per-particle subdivision. The design criterion is dt*sqrt(mu/r^3) < 0.03;
    // it binds only near the hole, so a particle out in the field integrates the
    // whole publish interval in one kick-drift-kick while one skimming the
    // shadow still gets the full 1/120 s. Thresholds are squared radii, computed
    // once per call by advance(); without them the step is uniform, which is
    // what the numerics and behaviour fixtures exercise.
    var limits=o.limits, subs=limits ? o.substeps : 1;
    var t1=limits ? limits[0] : 0, t2=limits ? limits[1] : 0, t3=limits ? limits[2] : 0;
    var travel2=dt*dt;   // (speed*dt)^2 vs (0.08*r)^2: never cross a big fraction of r in one step
    var write=0;
    for (var q=0;q<n;++q) {
        var i=live[q];
        if (!alive[i]) continue;
        var x=X[i]-cx, y=Y[i]-cy, vx=VX[i], vy=VY[i];
        var count=1;
        if (limits) {
            var s2=x*x+y*y;
            if (s2<t1) count = s2<t3 ? 4 : (s2<t2 ? 3 : 2);
            if (count<subs && (vx*vx+vy*vy)*travel2>0.0064*s2) count=subs;
            if (count>subs) count=subs;
        }
        var h=dt/count, half=h/2, invH=count/dt, t=clock, dead=false, zn=0;
        for (var m=0;m<count;++m) {
            var r2=x*x+y*y, g=0, r=0;
            // smooth() inlined: a call into it and the clamp() inside it cost
            // 125 ns in QML's JS engine against 25 ns for the arithmetic, and
            // this runs per substep per particle. Same expression, same result.
            if (r2<outer2) {
                r=Math.sqrt(r2);
                var ga=(r-floor)/(inner-floor); ga=ga>1?1:(ga>0?ga:0);
                var gb=(r-inner)/(outer-inner); gb=gb>1?1:(gb>0?gb:0);
                g=ga*ga*(3-2*ga)*(1-gb*gb*(3-2*gb));
            }
            var gamma=doDrag ? drag*g : 0;
            var nu=0;
            if (doTorque) {
                var rt=RATE[i];
                if (rt!==0) { var ts=(t-CTIME[i])/3; ts=ts>1?1:(ts>0?ts:0); nu=rt*ts*ts*(3-2*ts); }
            }
            if (gamma !== 0 || nu !== 0) {
                if (r === 0) r=Math.sqrt(r2);
                if (r > 0) {
                    var ex=x/r, ey=y/r, vr=vx*ex+vy*ey, vt=-vx*ey+vy*ex;
                    vr*=Math.exp(-gamma*half); vt*=Math.exp(-nu*half);
                    vx=vr*ex-vt*ey; vy=vr*ey+vt*ex;
                }
            }
            var softened=r2+eps2;
            // mu is exactly 0 in the camera regime (gravity = (1-blend)^2 with
            // blend 1), and the kick it produces is then exactly 0 -- but the
            // cube root of the softened radius is computed and thrown away all
            // the same, twice per substep per particle. The mass IS off; skip
            // its force. With mu non-zero this is the same arithmetic.
            if (mu!==0) {
                var f=-mu/(softened*Math.sqrt(softened));
                vx+=half*f*x; vy+=half*f*y;
            }
            var nx=x+h*vx, ny=y+h*vy;
            var cam=blend>0 && !TRANSIENT[i];
            if (cam) {
                // The camera advances rate*h in depth and every screen position
                // scales about the centre by z/z'. Exact, exactly invertible --
                // which is what makes reverse playback an exact reverse -- and
                // one multiply. A slow roll rides along in the same 2x2.
                // cameraDepthOf's fast path is one array read; reaching it
                // through two function calls (it calls cameraFar too) costs
                // more than everything else in this branch. camFar is already
                // hoisted, so read the slot and only call out to draw a depth.
                var z=DZ[i];
                if (!(z>=CAMERA_NEAR && z<=camFar)) z=cameraDepthOf(s,i);
                zn=z-camDir*camRate*h;
                if (zn<CAMERA_NEAR) zn=CAMERA_NEAR; else if (zn>camFar) zn=camFar;
                DZ[i]=zn;
                var mag=zn>0 ? z/zn : 1, mx=mag*x, my=mag*y;
                if (camRoll!==0) {
                    var ra=camRoll*h, rc=1-0.5*ra*ra;
                    var rx=mx*rc-my*ra; my=mx*ra+my*rc; mx=rx;
                }
                nx+=blend*(mx-nx); ny+=blend*(my-ny);
                vx+=blend*((nx-x)*invH-vx); vy+=blend*((ny-y)*invH-vy);
            }
            // The peculiar-velocity channel. It moves the POSITION and never
            // the velocity, which is the only way a shove survives a regime
            // where the magnification rewrites the velocity every substep. Its
            // decay is v = v0*(t0/t)^p: at p = 0.6 the displacement is exactly
            // r ~ t^0.4, the Sedov law the shell sprite is drawn with, so the
            // rim and the debris it is made of cannot drift apart. p = 0 is a
            // body under its own proper motion and never slows.
            if (anyKick) {
                var kx=KX[i], ky=KY[i];
                if (kx!==0 || ky!==0) {
                    nx+=kx*h; ny+=ky*h;
                    var ka=KA[i], kp=KD[i];
                    KA[i]=ka+h;
                    if (kp>0) {
                        var decay=Math.pow(ka/(ka+h),kp);
                        kx*=decay; ky*=decay;
                        // 2 px/s is 0.07 px in a 30 Hz frame: the shove is
                        // over. Without a floor the power law's tail runs for
                        // half a minute at speeds nothing can see.
                        if (kx*kx+ky*ky<4) { kx=0; ky=0; --s.kickAlive; }
                        KX[i]=kx; KY[i]=ky;
                    }
                }
            }
            if (ENTRY[i]<0) {
                var entry=viewportEntry(cx+x,cy+y,cx+nx,cy+ny,width,height);
                if (entry>=0) ENTRY[i]=t+h*entry;
            }
            X[i]=cx+nx; Y[i]=cy+ny; AGE[i]+=h;
            if (doDeaths && deathR>0 && swept(x,y,nx,ny,deathR)) { VX[i]=vx; VY[i]=vy; kill(s,i,'absorbed'); dead=true; break; }
            var nr2=nx*nx+ny*ny;
            softened=nr2+eps2;
            if (mu!==0) {
                var f2=-mu/(softened*Math.sqrt(softened));
                vx+=half*f2*nx; vy+=half*f2*ny;
            }
            g=0; r=0;
            if (nr2<outer2) {
                r=Math.sqrt(nr2);
                var ha=(r-floor)/(inner-floor); ha=ha>1?1:(ha>0?ha:0);
                var hb=(r-inner)/(outer-inner); hb=hb>1?1:(hb>0?hb:0);
                g=ha*ha*(3-2*ha)*(1-hb*hb*(3-2*hb));
            }
            gamma=doDrag ? drag*g : 0;
            if (gamma !== 0 || nu !== 0) {
                if (r === 0) r=Math.sqrt(nr2);
                if (r > 0) {
                    var ex2=nx/r, ey2=ny/r, vr2=vx*ex2+vy*ey2, vt2=-vx*ey2+vy*ex2;
                    vr2*=Math.exp(-gamma*half); vt2*=Math.exp(-nu*half);
                    vx=vr2*ex2-vt2*ey2; vy=vr2*ey2+vt2*ex2;
                }
            }
            if (doDrag && g !== 0) EXPOSURE[i]+=h*g;
            // Circularisation can only happen inside the capture region, so the
            // eccentricity and circular-speed roots stay off the common path.
            if (g>0 && RCAP[i] === 0 && doTorque) {
                var e=0.5*(vx*vx+vy*vy)-mu/Math.sqrt(softened);
                var hh=nx*vy-ny*vx;
                var ecc=Math.sqrt(Math.max(0,1+2*e*hh*hh/(mu*mu)));
                var vc=Math.sqrt(mu*nr2/(softened*Math.sqrt(softened)));
                if (e<0 && ecc<0.2 && Math.abs((nx*vx+ny*vy)/r)<0.18*vc) {
                    if (SINCE[i]<0) SINCE[i]=t;
                    if (t+h-SINCE[i]>=3) {
                        RCAP[i]=r; CTIME[i]=t+h;
                        // The spiral runs from the ring at the disk's rim all
                        // the way down through the material to the shadow,
                        // where the star is finally eaten.
                        RATE[i]=Math.max(0,Math.log(r/shadow)/(2*SPIRAL[i]));
                        ++s.counters.captures;
                    }
                } else SINCE[i]=-1;
            } else if (RCAP[i] === 0 && doTorque) SINCE[i]=-1;
            x=nx; y=ny; t+=h;
            if (doDeaths) {
                // The camera's own boundary: forward a star passes the near
                // plane, in reverse it dissolves back through the far one. Both
                // happen at the far end of the depth fade, so nothing pops.
                if (cam && blend>0.5 && (camDir>0 ? zn<=CAMERA_NEAR : zn>=camFar)) {
                    VX[i]=vx; VY[i]=vy; kill(s,i,'passed'); dead=true; break;
                }
                if (AGE[i]>=LIFE[i]) { VX[i]=vx; VY[i]=vy; kill(s,i,'safety'); dead=true; break; }
                // The cheap rectangle test gates the energy root, not the reverse.
                var px=cx+nx, py=cy+ny;
                if ((px<-pad || px>width+pad || py<-pad || py>height+pad)
                    && (nx*vx+ny*vy)>0
                    && 0.5*(vx*vx+vy*vy)-(mu!==0 ? mu/Math.sqrt(softened) : 0)>=0) {
                    VX[i]=vx; VY[i]=vy; kill(s,i,'escapes'); dead=true; break;
                }
            }
        }
        if (dead) continue;
        VX[i]=vx; VY[i]=vy;
        live[write++]=i;
    }
    s.liveCount=write;
    s.clock+=dt;++s.counters.steps;
}
function replenish(s, dt, callback) {
    // Event debris is not part of the population: counting it here would stop
    // ordinary births for the whole life of a burst and leave a thinned field
    // behind the explosion.
    var stars = s.aliveCount - s.transientCount;
    if (stars>=s.targetPopulation) { s.birthAccumulator=0;return; }
    // Burst modulation: two incommensurate 4096-safe cycles with mean 1, so the
    // population target is unchanged but arrivals come in waves. It is an INFALL
    // idea - the stream arriving in gusts - and the camera has no infall; with a
    // mean life of 21 s against the orbital 97 s a gust also lands inside one
    // generation instead of averaging out, and the field measured a 467-600
    // swing against 577-600. It fades out with the rest of the regime.
    var depth = s.config.clustering.burstDepth * (1 - cameraOn(s));
    var burst = depth > 0
        ? 1+depth*0.5*(Math.sin(s.clock*(2*Math.PI/23)+s.burstPhase)+Math.sin(s.clock*(2*Math.PI/71)+s.burstPhase*1.7))
        : 1;
    // The rate is a feed-forward guess (population over the measured mean life)
    // and nothing corrects it, which is fine for a regime that never changes:
    // the orbital field sits at its target because the guess is right. A change
    // of regime breaks the guess twice over - the old population is not a camera
    // population and a chunk of it leaves at once, and the lives recorded across
    // the change began under gravity - and the field measured 600 -> 314 stars
    // with a recovery over minutes. While the camera is on, a proportional term
    // closes the gap on its own: zero at the target, and a 300-star deficit adds
    // fifteen births a second, so the field refills in about twenty seconds.
    // Off, this is exactly the v7 expression.
    var camera = cameraOn(s);
    if (s.refillFor > 0) s.refillFor -= dt;
    var push = s.refillFor > 0 ? Math.min(1, s.refillFor/30) : 0;
    if (camera > push) push = camera;
    var rate = push > 0
        ? s.birthRate + push*(s.targetPopulation-stars)/10
        : s.birthRate;
    s.birthAccumulator+=dt*rate*(burst>0 ? burst : 0);
    while (s.birthAccumulator>=1-1e-12 && s.aliveCount-s.transientCount<s.targetPopulation) {
        var searched=0;
        while (s.alive[s.nextSlot] && searched<s.capacity) { s.nextSlot=(s.nextSlot+1)%s.capacity;++searched; }
        if (searched===s.capacity) { s.birthAccumulator=0;return; }
        var i=s.nextSlot;s.nextSlot=(s.nextSlot+1)%s.capacity;
        if (launch(s,i) && callback) callback(s,i);
        s.birthAccumulator=Math.max(0,s.birthAccumulator-1);
    }
}
function advance(s, dt, radialSpeed, filteredFlow, centreX, centreY, rotationSign, birthCallback) {
    if (!(radialSpeed>0) || !isFinite(radialSpeed) || !(dt>=0) || !isFinite(dt)) return 0;
    // Match the existing v3 public speed domain before squaring the reactive gain.
    var k=Math.min(radialSpeed,BOUNDS.radialSpeed[1])/6*(0.8+0.4*number(filteredFlow,0.5,0,1));
    var subs=s.config.substeps;
    var muTarget=s.muBase*k*k, nominal=1/30;
    if (!isFinite(muTarget) || muTarget<0 || !isFinite(s.mu) || s.mu<0) return 0;
    // The outer step is the publish interval; the inner subdivision is chosen
    // per particle. 0.029 provides strict headroom under the specified 0.03
    // stability limit, and the outer step is still capped so that even the
    // finest subdivision satisfies it at the innermost surviving radius.
    // The stability limits are gravity's, and the camera has none: a blend of 1
    // relaxes every particle back to a single kick-drift-kick, so the regime
    // that has no hole does not pay for the hole's innermost orbit.
    var camera=cameraOn(s), gravity=(1-camera)*(1-camera);
    // The lifetime estimator is regime-specific and it has unbounded memory: an
    // orbital life averages 97 s and a camera life 21, so carrying the old
    // number across the toggle sets the birth rate four times too low and the
    // field drains. Measured in the QML harness: 289 of 600 stars a minute after
    // the hole went off. Clearing it on the crossing puts it back on its own
    // 30 s prior, which re-converges in a hundred deaths - four seconds of
    // camera. A run that never changes regime never touches this.
    var regime = camera > 0.5 ? 1 : 0;
    if (s.cameraRegime !== regime) {
        s.cameraRegime = regime;
        s.lifetimeSamples = 0; s.lifetimeSum = 0;
        s.meanLifetime = 30; s.birthRate = s.targetPopulation / 30;
        // Ninety seconds of active refill, which outlives the thirty-second
        // envelope: the change back to the hole ends at camera 0, where a term
        // scaled by the blend would already be gone.
        s.refillFor = 90;
    }
    // The estimator's memory is unbounded, which is right for a regime that
    // never changes and wrong for one that does: the change itself records
    // lives that began under gravity and ended under the camera, and those
    // inflated samples then hold the birth rate down long after. While the
    // camera is on, halve the accumulators every 800 samples so the estimate
    // follows the regime it is actually in.
    if (camera > 0 && s.lifetimeSamples > 800) {
        s.lifetimeSamples *= 0.5; s.lifetimeSum *= 0.5;
        s.meanLifetime = (3000+s.lifetimeSum)/(100+s.lifetimeSamples);
        s.birthRate = s.targetPopulation/s.meanLifetime;
    }
    var finest=0.029/Math.sqrt(Math.max(s.mu,muTarget)*gravity/Math.pow(s.rh,3));
    var fixed=Math.min(nominal,finest*subs);
    var accumulator=s.accumulator+dt;
    if (!(fixed>0) || !isFinite(fixed) || !isFinite(accumulator)) return 0;
    s.k=k;s.muTarget=muTarget;
    s.centreX=number(centreX,s.centreX,-s.width,s.width*2);
    s.centreY=number(centreY,s.centreY,-s.height,s.height*2);
    s.rotationSign=rotationSign<0 ? -1 : 1;
    s.accumulator=accumulator;
    var count=0;
    // Squared radii where one, two, three or four inner steps satisfy
    // fixed/j * sqrt(mu/r^3) < 0.0145 (half the stability limit). Recomputed
    // per call because mu tracks the reactive target.
    var options=s.stepOptions || (s.stepOptions={limits:[0,0,0],substeps:subs});
    var base=Math.pow(Math.max(s.mu,muTarget)*gravity*fixed*fixed/(0.0145*0.0145),1/3);
    options.substeps=subs;
    options.limits[0]=base*base;
    options.limits[1]=Math.pow(base/Math.pow(2,2/3),2);
    options.limits[2]=Math.pow(base/Math.pow(3,2/3),2);
    while (s.accumulator>=fixed*(1-1e-10)) {
        s.mu+=(s.muTarget-s.mu)*(1-Math.exp(-fixed/60));
        step(s,fixed,options);replenish(s,fixed,birthCallback || s.birthCallback);
        // Outside the hot loop and outside step(): one descriptor test per
        // outer step, nothing per particle.
        tdeStep(s,birthCallback || s.birthCallback);
        // The nebula's drag and the flash glows are per-second effects, not
        // forces: once per outer step over the live list, and both are inert
        // (one null test) when no event is running.
        cloudStep(s,fixed);
        if (s.glows.length) glowStep(s);
        s.accumulator=Math.max(0,s.accumulator-fixed);++count;
    }
    return count;
}

if (typeof module !== 'undefined' && module.exports) module.exports = {
    BOUNDS: BOUNDS, defaults: defaults, validate: validate, create: create, configure: configure,
    advance: advance, step: step, launch: launch, energy: energy, angularMomentum: angularMomentum,
    damp: damp, random: random, swept: swept, viewportEntry: viewportEntry, rescale: rescale,
    doom: doom, doomed: doomed, tdeStep: tdeStep, inject: inject,
    visibleRadius: visibleRadius, screenRadius: screenRadius,
    cameraLaunch: cameraLaunch, cameraDepthOf: cameraDepthOf, CAMERA_NEAR: CAMERA_NEAR,
    // v10, the event -> particle interface
    applyImpulse: applyImpulse, spawnBurst: spawnBurst, spawnBody: spawnBody,
    brightenNear: brightenNear, pickStar: pickStar, markNova: markNova,
    novaStar: novaStar, clearNova: clearNova, flowSpeed: flowSpeed,
    remove: remove, debrisRoom: debrisRoom, setCloud: setCloud, cloudWeight: cloudWeight,
    driftGroup: driftGroup
};
