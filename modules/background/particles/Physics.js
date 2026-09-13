// Physical-pixel, pause-safe particle dynamics. QML importable; no wall clock.
var BOUNDS = {
    capacity: 3200, population: [0, 3200], radialSpeed: [0, 26], vref: [10, 600], epsilonRh: [0.01, 0.2],
    substeps: [4, 32], betaBound: [0.1, 0.99], betaUnbound: [1.001, 2],
    captureRadius: [1.05, 8], gamma: [0, 2], spiralSec: [5, 240],
    safetyLifeSec: [30, 600], sizePx: [0.25, 12], exposureSec: [0, 0.1], maxPx: [0, 32]
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
        capture: {radius: [3.3, 4.0], gamma: 0.25, spiralSec: [20, 60]},
        epsilonRh: 0.05, substeps: 4, streak: {exposureSec: 0.02, maxPx: 12},
        sizes: {nearPx: [2, 4], middlePx: [1, 2], capturedPx: [0.8, 1.4]},
        safetyLifeSec: [180, 240]};
}
function validate(raw) {
    var d = defaults(), r = raw || {}, p = r.population || {}, l = r.launch || {};
    var c = r.capture || {}, z = r.sizes || {}, t = r.streak || {};
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
    d.streak.exposureSec = number(t.exposureSec, 0.02, 0, 0.1);
    d.streak.maxPx = number(t.maxPx, 12, 0, 32);
    d.sizes.nearPx = range(z.nearPx, d.sizes.nearPx, BOUNDS.sizePx);
    d.sizes.middlePx = range(z.middlePx, d.sizes.middlePx, BOUNDS.sizePx);
    d.sizes.capturedPx = range(z.capturedPx, d.sizes.capturedPx, BOUNDS.sizePx);
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
function configure(s, width, height, rh, raw) {
    s.config = validate(raw); s.width = Math.max(1, width); s.height = Math.max(1, height);
    s.rh = Math.max(0.1, rh); s.padding = Math.max(32, 0.25 * s.rh);
    s.epsilon = s.config.epsilonRh * s.rh;
    var v = s.config.vref * s.rh / 162;
    s.muBase = v * v * (20 / 3) * s.rh;
    s.muTarget = s.muBase * s.k * s.k;
    s.targetPopulation = s.config.population.near + s.config.population.middle;
    s.birthRate = s.targetPopulation / s.meanLifetime;
}
function create(width, height, rh, seed, raw, birthCallback) {
    var s = {capacity: BOUNDS.capacity, aliveCount: 0, randomState: (seed >>> 0) || 1,
        clock: 0, accumulator: 0, birthAccumulator: 0, nextSlot: 0, k: 1,
        centreX: width / 2, centreY: height / 2, rotationSign: 1,
        meanLifetime: 30, lifetimeSamples: 0, lifetimeSum: 0,
        birthCallback: birthCallback, counters: {births: 0, deaths: 0, absorbed: 0,
            escapes: 0, safety: 0, captures: 0, steps: 0}};
    s.alive = new Uint8Array(s.capacity); s.generation = new Uint32Array(s.capacity);
    var fields = ['x','y','vx','vy','age','entryTime','circularSince','captureExposure','spiralRate',
        'radiusAtCapture','captureTime','launchClass','pericentre','safetyLife','spiralSec','depth',
        'r','g','b','size','capturedSize','luminosity','archetype','p0','p1','p2','p3','phase','seed'];
    for (var j = 0; j < fields.length; ++j) s[fields[j]] = new Float64Array(s.capacity);
    configure(s, width, height, rh, raw); s.mu = s.muBase;
    return s;
}
// Unit conversion only (DPR change). A speed/config edit must never call this.
function rescale(s, factor) {
    if (!(factor > 0) || !isFinite(factor)) return;
    var scalar = ['width','height','rh','epsilon','padding','centreX','centreY'];
    var arrays = ['x','y','vx','vy','radiusAtCapture','pericentre','size','capturedSize'];
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
function launch(s, i, options) {
    var o = options || {}, l = s.config.launch, draw = random(s);
    var cls = o.launchClass === undefined ? (draw < l.plunge ? 0 : draw < l.plunge+l.miss ? 1 : 2) : o.launchClass;
    var q = o.q === undefined ? between(s, cls === 0 ? [0.05,0.60] : cls === 1 ? [1.15,1.80] : [2.5,4.5])*s.rh : o.q;
    var beta = o.beta === undefined ? between(s, cls === 1 && random(s) < l.unboundShare ? l.betaUnbound : l.betaBound) : o.beta;
    var w = s.width+2*s.padding, h = s.height+2*s.padding;
    var edge = random(s)*2*(w+h), x, y;
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
    if (!s.alive[i]) ++s.aliveCount;
    s.alive[i]=1; ++s.generation[i]; ++s.counters.births;
    s.age[i]=0; s.circularSince[i]=-1; s.captureExposure[i]=0;
    s.entryTime[i]=x>=0 && x<=s.width && y>=0 && y<=s.height ? s.clock : -1;
    s.spiralRate[i]=0; s.radiusAtCapture[i]=0; s.captureTime[i]=-1;
    s.launchClass[i]=cls; s.pericentre[i]=q;
    s.safetyLife[i]=between(s,s.config.safetyLifeSec); s.spiralSec[i]=between(s,s.config.capture.spiralSec);
    s.depth[i]=o.depth === undefined ? (random(s)*s.targetPopulation < s.config.population.near ? 1 : 0) : o.depth;
    s.seed[i]=random(s); s.phase[i]=random(s)*Math.PI*2;
    s.size[i]=between(s,s.depth[i] ? s.config.sizes.nearPx : s.config.sizes.middlePx);
    s.capturedSize[i]=between(s,s.config.sizes.capturedPx);
    s.r[i]=1; s.g[i]=1; s.b[i]=1; s.luminosity[i]=1;
    s.archetype[i]=0; s.p0[i]=0; s.p1[i]=0; s.p2[i]=0; s.p3[i]=0;
    return true;
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
    ++s.lifetimeSamples; s.lifetimeSum+=s.age[i];
    // A 30-second prior avoids the first short plunges dominating birth rate.
    s.meanLifetime=(3000+s.lifetimeSum)/(100+s.lifetimeSamples);
    s.birthRate=s.targetPopulation/s.meanLifetime;
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
function step(s, dt, options) {
    if (!(dt > 0) || !isFinite(dt)) return;
    var o=options || {}, c=s.config.capture, half=dt/2, eps2=s.epsilon*s.epsilon;
    for (var i=0;i<s.capacity;++i) {
        if (!s.alive[i]) continue;
        var x=s.x[i]-s.centreX,y=s.y[i]-s.centreY,r=Math.sqrt(x*x+y*y);
        var g=1-smooth(c.radius[0]*s.rh,c.radius[1]*s.rh,r);
        var gamma=o.drag === false ? 0 : c.gamma*g;
        var nu=o.torque === false ? 0 : s.spiralRate[i]*smooth(0,3,s.clock-s.captureTime[i]);
        if (gamma !== 0 || nu !== 0) damp(s,i,half,gamma,nu);
        var softened=x*x+y*y+eps2;
        var f=-s.mu/(softened*Math.sqrt(softened));
        s.vx[i]+=half*f*x;s.vy[i]+=half*f*y;
        var nx=x+dt*s.vx[i],ny=y+dt*s.vy[i];
        if (s.entryTime[i]<0) {
            var entry=viewportEntry(s.x[i],s.y[i],s.centreX+nx,s.centreY+ny,s.width,s.height);
            if (entry>=0) s.entryTime[i]=s.clock+dt*entry;
        }
        s.x[i]=s.centreX+nx;s.y[i]=s.centreY+ny;s.age[i]+=dt;
        if (o.deaths !== false && swept(x,y,nx,ny,s.rh)) { kill(s,i,'absorbed');continue; }
        softened=nx*nx+ny*ny+eps2;
        f=-s.mu/(softened*Math.sqrt(softened));
        s.vx[i]+=half*f*nx;s.vy[i]+=half*f*ny;
        r=Math.sqrt(nx*nx+ny*ny);g=1-smooth(c.radius[0]*s.rh,c.radius[1]*s.rh,r);
        gamma=o.drag === false ? 0 : c.gamma*g;
        if (gamma !== 0 || nu !== 0) damp(s,i,half,gamma,nu);
        if (o.drag !== false) s.captureExposure[i]+=dt*g;
        var e=energy(s,i), radial=(nx*s.vx[i]+ny*s.vy[i])/r;
        if (s.radiusAtCapture[i] === 0 && o.torque !== false) {
            var h=nx*s.vy[i]-ny*s.vx[i];
            var ecc=Math.sqrt(Math.max(0,1+2*e*h*h/(s.mu*s.mu)));
            var vc=Math.sqrt(s.mu*r*r/(softened*Math.sqrt(softened)));
            if (g>0 && e<0 && ecc<0.2 && Math.abs(radial)<0.18*vc) {
                if (s.circularSince[i]<0) s.circularSince[i]=s.clock;
                if (s.clock+dt-s.circularSince[i]>=3) {
                    s.radiusAtCapture[i]=r;s.captureTime[i]=s.clock+dt;
                    s.spiralRate[i]=Math.max(0,Math.log(r/s.rh)/(2*s.spiralSec[i]));
                    ++s.counters.captures;
                }
            } else s.circularSince[i]=-1;
        }
        if (o.deaths !== false) {
            if (s.age[i]>=s.safetyLife[i]) kill(s,i,'safety');
            else if (e>=0 && radial>0 && (s.x[i]<-s.padding || s.x[i]>s.width+s.padding || s.y[i]<-s.padding || s.y[i]>s.height+s.padding)) kill(s,i,'escapes');
        }
    }
    s.clock+=dt;++s.counters.steps;
}
function replenish(s, dt, callback) {
    if (s.aliveCount>=s.targetPopulation) { s.birthAccumulator=0;return; }
    s.birthAccumulator+=dt*s.birthRate;
    while (s.birthAccumulator>=1-1e-12 && s.aliveCount<s.targetPopulation) {
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
    var muTarget=s.muBase*k*k, nominal=1/(30*s.config.substeps);
    if (!isFinite(muTarget) || muTarget<0 || !isFinite(s.mu) || s.mu<0) return 0;
    // 0.029 provides strict headroom under the specified 0.03 stability limit.
    var fixed=Math.min(nominal,0.029/Math.sqrt(Math.max(s.mu,muTarget)/Math.pow(s.rh,3)));
    var accumulator=s.accumulator+dt;
    if (!(fixed>0) || !isFinite(fixed) || !isFinite(accumulator)) return 0;
    s.k=k;s.muTarget=muTarget;
    s.centreX=number(centreX,s.centreX,-s.width,s.width*2);
    s.centreY=number(centreY,s.centreY,-s.height,s.height*2);
    s.rotationSign=rotationSign<0 ? -1 : 1;
    s.accumulator=accumulator;
    var count=0;
    while (s.accumulator>=fixed*(1-1e-10)) {
        s.mu+=(s.muTarget-s.mu)*(1-Math.exp(-fixed/60));
        step(s,fixed);replenish(s,fixed,birthCallback || s.birthCallback);
        s.accumulator=Math.max(0,s.accumulator-fixed);++count;
    }
    return count;
}

if (typeof module !== 'undefined' && module.exports) module.exports = {
    BOUNDS: BOUNDS, defaults: defaults, validate: validate, create: create, configure: configure,
    advance: advance, step: step, launch: launch, energy: energy, angularMomentum: angularMomentum,
    damp: damp, random: random, swept: swept, viewportEntry: viewportEntry, rescale: rescale
};
