// Physical-pixel, pause-safe particle dynamics. QML importable; no wall clock.
var BOUNDS = {
    capacity: 3200, population: [0, 3200], radialSpeed: [0, 26], vref: [10, 600], epsilonRh: [0.01, 0.2],
    substeps: [4, 32], betaBound: [0.1, 0.99], betaUnbound: [1.001, 2],
    captureRadius: [1.05, 8], gamma: [0, 2], spiralSec: [5, 240],
    safetyLifeSec: [30, 600], sizePx: [0.25, 12], exposureSec: [0, 0.1], maxPx: [0, 32], publishHz: [10, 30],
    flareShare: [0, 0.5], flareMaxAlive: [0, 64], capturedLight: [0, 1]
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
        sizes: {nearPx: [2.4, 4.4], middlePx: [1, 2], capturedPx: [1.0, 1.8]},
        flare: {share: 0.085, maxAlive: 10, capturedLight: 0.5}, publishHz: 30,
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
    d.streak.exposureSec = number(t.exposureSec, 0.02, 0, 0.1);
    d.streak.maxPx = number(t.maxPx, 12, 0, 32);
    d.sizes.nearPx = range(z.nearPx, d.sizes.nearPx, BOUNDS.sizePx);
    d.sizes.middlePx = range(z.middlePx, d.sizes.middlePx, BOUNDS.sizePx);
    d.sizes.capturedPx = range(z.capturedPx, d.sizes.capturedPx, BOUNDS.sizePx);
    d.flare.share = number(fl.share, 0.085, 0, 0.5);
    d.flare.maxAlive = Math.round(number(fl.maxAlive, 10, 0, 64));
    d.flare.capturedLight = number(fl.capturedLight, 0.5, 0, 1);
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
    // Dense list of occupied slots. step() compacts it, launch() appends to it,
    // so no consumer ever walks the 3200 capacity slots to find 600 particles.
    s.live = new Int32Array(s.capacity); s.liveCount = 0;
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
    if (!s.alive[i]) { ++s.aliveCount; s.live[s.liveCount++]=i; }
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
    var inner=c.radius[0]*rh, outer=c.radius[1]*rh, outer2=outer*outer, drag=c.gamma;
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
        var h=dt/count, half=h/2, t=clock, dead=false;
        for (var m=0;m<count;++m) {
            var r2=x*x+y*y, g=0, r=0;
            if (r2<outer2) { r=Math.sqrt(r2); g=1-smooth(inner,outer,r); }
            var gamma=doDrag ? drag*g : 0;
            var nu=doTorque ? RATE[i]*smooth(0,3,t-CTIME[i]) : 0;
            if (gamma !== 0 || nu !== 0) {
                if (r === 0) r=Math.sqrt(r2);
                if (r > 0) {
                    var ex=x/r, ey=y/r, vr=vx*ex+vy*ey, vt=-vx*ey+vy*ex;
                    vr*=Math.exp(-gamma*half); vt*=Math.exp(-nu*half);
                    vx=vr*ex-vt*ey; vy=vr*ey+vt*ex;
                }
            }
            var softened=r2+eps2;
            var f=-mu/(softened*Math.sqrt(softened));
            vx+=half*f*x; vy+=half*f*y;
            var nx=x+h*vx, ny=y+h*vy;
            if (ENTRY[i]<0) {
                var entry=viewportEntry(cx+x,cy+y,cx+nx,cy+ny,width,height);
                if (entry>=0) ENTRY[i]=t+h*entry;
            }
            X[i]=cx+nx; Y[i]=cy+ny; AGE[i]+=h;
            if (doDeaths && swept(x,y,nx,ny,rh)) { VX[i]=vx; VY[i]=vy; kill(s,i,'absorbed'); dead=true; break; }
            var nr2=nx*nx+ny*ny;
            softened=nr2+eps2;
            f=-mu/(softened*Math.sqrt(softened));
            vx+=half*f*nx; vy+=half*f*ny;
            g=0; r=0;
            if (nr2<outer2) { r=Math.sqrt(nr2); g=1-smooth(inner,outer,r); }
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
                        RATE[i]=Math.max(0,Math.log(r/rh)/(2*SPIRAL[i]));
                        ++s.counters.captures;
                    }
                } else SINCE[i]=-1;
            } else if (RCAP[i] === 0 && doTorque) SINCE[i]=-1;
            x=nx; y=ny; t+=h;
            if (doDeaths) {
                if (AGE[i]>=LIFE[i]) { VX[i]=vx; VY[i]=vy; kill(s,i,'safety'); dead=true; break; }
                // The cheap rectangle test gates the energy root, not the reverse.
                var px=cx+nx, py=cy+ny;
                if ((px<-pad || px>width+pad || py<-pad || py>height+pad)
                    && (nx*vx+ny*vy)>0
                    && 0.5*(vx*vx+vy*vy)-mu/Math.sqrt(softened)>=0) {
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
    var subs=s.config.substeps;
    var muTarget=s.muBase*k*k, nominal=1/30;
    if (!isFinite(muTarget) || muTarget<0 || !isFinite(s.mu) || s.mu<0) return 0;
    // The outer step is the publish interval; the inner subdivision is chosen
    // per particle. 0.029 provides strict headroom under the specified 0.03
    // stability limit, and the outer step is still capped so that even the
    // finest subdivision satisfies it at the innermost surviving radius.
    var finest=0.029/Math.sqrt(Math.max(s.mu,muTarget)/Math.pow(s.rh,3));
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
    var base=Math.pow(Math.max(s.mu,muTarget)*fixed*fixed/(0.0145*0.0145),1/3);
    options.substeps=subs;
    options.limits[0]=base*base;
    options.limits[1]=Math.pow(base/Math.pow(2,2/3),2);
    options.limits[2]=Math.pow(base/Math.pow(3,2/3),2);
    while (s.accumulator>=fixed*(1-1e-10)) {
        s.mu+=(s.muTarget-s.mu)*(1-Math.exp(-fixed/60));
        step(s,fixed,options);replenish(s,fixed,birthCallback || s.birthCallback);
        s.accumulator=Math.max(0,s.accumulator-fixed);++count;
    }
    return count;
}

if (typeof module !== 'undefined' && module.exports) module.exports = {
    BOUNDS: BOUNDS, defaults: defaults, validate: validate, create: create, configure: configure,
    advance: advance, step: step, launch: launch, energy: energy, angularMomentum: angularMomentum,
    damp: damp, random: random, swept: swept, viewportEntry: viewportEntry, rescale: rescale
};
