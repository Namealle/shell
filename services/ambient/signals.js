// Plain ES5; values and category strengths only, never window/title history.
var TAU = {
    cpuLoad: 15,
    cpuHeat: 60,
    gpuLoad: 20,
    gpuHeat: 60,
    vram: 30,
    ram: 30,
    network: 20,
    rain: 180,
    wind: 180,
    humidity: 180,
    temperature: 180,
    weatherNight: 180,
    media: 30,
    idle: 60,
    agentProcess: 60,
    night: 300,
    notifications: 20
};
var MAX_AGE = {
    cpuLoad: 10,
    cpuHeat: 20,
    gpuLoad: 20,
    gpuHeat: 20,
    vram: 20,
    ram: 20,
    network: 20,
    rain: 10800,
    wind: 10800,
    humidity: 10800,
    temperature: 10800,
    weatherNight: 10800,
    media: 5,
    idle: 5,
    agentProcess: 30,
    night: 120,
    notifications: 5
};

function finite(x) {
    return typeof x === "number" && isFinite(x);
}
function clamp(x, a, b) {
    return Math.max(a, Math.min(b, x));
}
function smoothstep(a, b, x) {
    var t = clamp((x - a) / (b - a), 0, 1);
    return t * t * (3 - 2 * t);
}
function ratio(x) {
    return finite(x) && x >= 0 && x <= 1 ? x : null;
}
function workspaceActivity(value, dt, switched) {
    var activity = finite(value) ? clamp(value, 0, 1) : 0;
    if (finite(dt) && dt > 0)
        activity *= Math.exp(-dt / 120);
    return Math.min(1, activity + (switched ? 0.15 : 0));
}
function heat(x, high) {
    return finite(x) && x > 0 && x <= 150 ? smoothstep(45, high, x) : null;
}
function network(rx, tx) {
    return finite(rx) && finite(tx) && rx >= 0 && tx >= 0 ? clamp(Math.log(1 + (rx + tx) / 65536) / Math.LN2 / 8, 0, 1) : null;
}
function night(hours, minutes) {
    if (!finite(hours) || !finite(minutes))
        return null;
    var h = hours + minutes / 60;
    return h >= 12 ? smoothstep(21, 24, h) : 1 - smoothstep(5, 8, h);
}
function weather(cc) {
    var result = {}, codes = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82, 85, 86, 95, 96, 99];
    if (!cc || codes.indexOf(cc.weatherCode) === -1)
        return result;
    var code = cc.weatherCode, rain = 0;
    if ([51, 53, 55, 56, 57].indexOf(code) !== -1)
        rain = 0.25;
    else if ([61, 66, 80].indexOf(code) !== -1)
        rain = 0.40;
    else if ([63, 81].indexOf(code) !== -1)
        rain = 0.65;
    else if ([65, 67, 82].indexOf(code) !== -1)
        rain = 0.90;
    else if ([95, 96, 99].indexOf(code) !== -1)
        rain = 0.80;
    result.rain = rain;
    if (finite(cc.windSpeed) && cc.windSpeed >= 0)
        result.wind = clamp(cc.windSpeed / 40, 0, 1);
    if (finite(cc.humidity) && cc.humidity >= 0 && cc.humidity <= 100)
        result.humidity = cc.humidity / 100;
    if (finite(cc.tempC))
        result.temperature = clamp((cc.tempC + 10) / 45, 0, 1);
    if (cc.isDay === 0 || cc.isDay === 1)
        result.weatherNight = 1 - cc.isDay;
    return result;
}
function parseGpu(line) {
    var fields = line.trim().split(",");
    if (fields.length !== 4)
        return null;
    var values = [];
    for (var i = 0; i < 4; i++) {
        if (!/^\s*\d+(?:\.\d+)?\s*$/.test(fields[i]))
            return null;
        values.push(Number(fields[i]));
        if (!finite(values[i]))
            return null;
    }
    if (values[0] <= 0 || values[0] > 150 || values[1] > 100 || values[3] <= 0 || values[2] > values[3])
        return null;
    return {
        gpuHeat: heat(values[0], 80),
        gpuLoad: values[1] / 100,
        vram: values[2] / values[3]
    };
}
function parseCpu(text) {
    var line = /^cpu\s+([^\n]+)/m.exec(text);
    if (!line)
        return null;
    var fields = line[1].trim().split(/\s+/), total = 0;
    if (fields.length < 8)
        return null;
    for (var i = 0; i < 8; i++) {
        if (!/^\d+$/.test(fields[i]) || !finite(Number(fields[i])))
            return null;
        total += Number(fields[i]);
    }
    return {
        total: total,
        idle: Number(fields[3]) + Number(fields[4])
    };
}
function cpuDelta(previous, current) {
    if (!previous || !current)
        return null;
    var total = current.total - previous.total, idle = current.idle - previous.idle;
    if (total <= 0 || idle < 0 || idle > total)
        return null;
    return 1 - idle / total;
}
function parseMemory(text) {
    var total = /^MemTotal:\s+(\d+)\s+kB\s*$/m.exec(text), available = /^MemAvailable:\s+(\d+)\s+kB\s*$/m.exec(text);
    if (!total || !available || Number(total[1]) <= 0 || Number(available[1]) > Number(total[1]))
        return null;
    return 1 - Number(available[1]) / Number(total[1]);
}
function parseTemperature(text) {
    var value = /^\s*\d+(?:\.\d+)?\s*$/.test(text) ? Number(text) / 1000 : null;
    return heat(value, 85);
}

function elapsedStep(previousMono, mono, previousWall, wall) {
    var dt = mono - previousMono, wallGap = wall - previousWall - dt;
    var reset = dt < 0 || dt > 2 || Math.abs(wallGap) > 2;
    return {
        dt: reset ? 0 : dt,
        reset: reset,
        ageAdvance: wallGap > 2 ? wallGap : 0
    };
}

function createBank() {
    return Object.create(null);
}
function record(bank, name, raw, now, tau, maxAge) {
    if (!finite(raw) || !finite(now))
        return false;
    var state = bank[name];
    if (!state) {
        state = {
            value: 0,
            velocity: 0,
            raw: 0,
            lastSeen: now,
            tau: tau || TAU[name] || 45,
            maxAge: maxAge || MAX_AGE[name] || 5
        };
        bank[name] = state;
    }
    state.raw = clamp(raw, 0, 1);
    state.lastSeen = now;
    return true;
}
function availability(lastSeen, now, maxAge) {
    return clamp(1 - Math.max(0, now - lastSeen - maxAge) / 120, 0, 1);
}
function step(state, dt) {
    if (!finite(dt) || dt <= 0)
        return;
    var old = state.value;
    state.value += (state.raw - old) * (1 - Math.exp(-dt / state.tau));
    state.velocity += ((state.value - old) / dt - state.velocity) * (1 - Math.exp(-dt / 20));
}
function rate01(velocity) {
    return 0.5 + 0.5 * clamp(velocity / 0.03, -1, 1);
}
function advance(bank, now, dt) {
    var values = {}, rates = {}, valid = {}, weights = {};
    var keys = Object.keys(bank);
    for (var i = 0; i < keys.length; i++) {
        var name = keys[i], state = bank[name];
        step(state, dt);
        var weight = availability(state.lastSeen, now, state.maxAge);
        valid[name] = now - state.lastSeen <= state.maxAge;
        weights[name] = weight;
        values[name] = state.value * weight;
        rates[name] = rate01(state.velocity);
        values[name + "Rising"] = Math.max(0, 2 * rates[name] - 1) * weight;
    }
    return {
        values: values,
        rates: rates,
        valid: valid,
        weights: weights
    };
}
function reset(bank) {
    var keys = Object.keys(bank);
    for (var i = 0; i < keys.length; i++)
        bank[keys[i]].velocity = 0;
}
function derive(values, processWeight, bank, weights) {
    function value(name) {
        return finite(values[name]) ? values[name] : 0;
    }
    values.load = Math.max(value("cpuLoad"), value("gpuLoad"));
    values.heat = Math.max(value("cpuHeat"), value("gpuHeat"));
    values.loadRising = Math.max(value("cpuLoadRising"), value("gpuLoadRising"));
    // Fade AFTER the nonlinear pressure transform, so a stale sensor loses weight linearly.
    var ram = bank.ram ? smoothstep(0.70, 0.95, bank.ram.value) * weights.ram : 0;
    var vram = bank.vram ? smoothstep(0.75, 0.95, bank.vram.value) * weights.vram : 0;
    values.memoryPressure = Math.max(ram, vram);
    values.agent = Math.max(value("agentWindow"), processWeight * value("agentProcess"));
    return values;
}
