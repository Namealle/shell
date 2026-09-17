// Apparent-plane bins. Supports, not just centres, own every touched cell.
// Reuse counters, offsets and reference storage across publications.
function growRows(old, size) {
    var next = new Int32Array(size);
    next.set(old);
    return next;
}
// `probe` is the optional diagnostics accumulator (Starfield.qml's `perf`): an
// object carrying an ElapsedTimer as `clock` and one nanosecond total per
// phase. Absent -- which is every ordinary frame and every test -- it costs one
// undefined test per phase and makes no clock call.
function build(previous, items, width, height, probe) {
    var clk = probe ? probe.clock : null;
    var pt0 = clk ? clk.elapsedNs() : 0, pt1 = 0;
    var nx = Math.max(1, Math.ceil(width / 32));
    var ny = Math.max(1, Math.ceil(height / 32));
    var n = nx * ny;
    var b = previous;
    if (!b || b.nx !== nx || b.ny !== ny) {
        b = { nx: nx, ny: ny, width: width, height: height,
            counts: new Uint16Array(n), offsets: new Uint32Array(n + 1),
            cursor: new Uint32Array(n), indices: new Uint16Array(0),
            ranges: new Int32Array(0), rows: new Int32Array(0),
            // Which bins this publication actually put something in. A 4K
            // portrait output has 14400 bins and six hundred particles reach
            // perhaps a sixth of them; the prefix sum, and the packer's header
            // pass, used to walk all of them every frame.
            touched: new Int32Array(n), touchedCount: 0 };
    }
    // Flat render instances (particles/Appearance.js): stride 21, x/y/support at
    // offsets 0/1/5. The same field order the packer reads.
    var data = items.data, stride = items.stride, count = items.count;
    if (count > 6400)
        throw new Error("Particle render-instance limit exceeded");
    if (b.ranges.length < count * 4)
        b.ranges = new Int32Array(Math.max(count * 4, b.ranges.length * 2));
    // Only the bins this buffer filled last time need clearing; a full fill() of
    // a 14400-entry grid is a memset, but the prefix sum over it is not.
    var touched = b.touched, tc = b.touchedCount, counts = b.counts, i, x, y, k;
    if (tc > n * 0.4) counts.fill(0);
    else for (i = 0; i < tc; ++i) counts[touched[i]] = 0;
    tc = 0;
    b.rowCount = 0;
    if (clk) { pt1 = clk.elapsedNs(); probe.binClear += pt1 - pt0; pt0 = pt1; }
    for (i = 0; i < count; ++i) {
        var base = i * stride, px = data[base], py = data[base + 1], radius = data[base + 5];
        // Offsets 18/19 are the half-extents along and across the streak. The
        // footprint is that capsule, walked row by row: a long diagonal trail
        // crosses a handful of bins where its bounding box covers five times as
        // many, and every bin the kernel touches is still inserted.
        var major = data[base + 18], minor = data[base + 19];
        if (!(radius >= 0 && radius <= 127.5) || !Number.isFinite(px + py + radius + major + minor)
            || !(minor >= 0 && minor <= radius + 1e-9) || !(major >= 0 && major <= radius + 1e-9))
            throw new Error("Invalid or unbounded particle support");
        var vx = data[base + 2], vy = data[base + 3];
        var speed = Math.sqrt(vx * vx + vy * vy);
        var ux = 1, uy = 0;
        if (speed > 0.01) { ux = vx / speed; uy = vy / speed; }
        var reach = major - minor;                     // segment half-length
        var ax = px - ux * reach, ay = py - uy * reach;
        var bx2 = px + ux * reach, by2 = py + uy * reach;
        var y0 = Math.max(0, Math.floor((Math.min(ay, by2) - minor) / 32));
        var y1 = Math.min(ny - 1, Math.floor((Math.max(ay, by2) + minor) / 32));
        var spanBase = 2 * i;
        if (b.rows.length < (y1 - y0 + 1) * 2 + b.rowCount)
            b.rows = growRows(b.rows, ((y1 - y0 + 1) * 2 + b.rowCount) * 2);
        b.ranges[4 * i] = y0; b.ranges[4 * i + 1] = y1; b.ranges[4 * i + 2] = b.rowCount;
        for (y = y0; y <= y1; ++y) {
            // x-range of the capsule inside this bin row, then the bin span.
            var lo = Math.max(y * 32, Math.min(ay, by2) - minor);
            var hi = Math.min(y * 32 + 32, Math.max(ay, by2) + minor);
            var sx0, sx1;
            if (Math.abs(uy) < 1e-6) { sx0 = Math.min(ax, bx2); sx1 = Math.max(ax, bx2); }
            else {
                var t0 = (lo - ay) / (by2 - ay || 1e-12), t1 = (hi - ay) / (by2 - ay || 1e-12);
                var c0 = ax + (bx2 - ax) * Math.max(0, Math.min(1, t0));
                var c1 = ax + (bx2 - ax) * Math.max(0, Math.min(1, t1));
                sx0 = Math.min(c0, c1); sx1 = Math.max(c0, c1);
            }
            var bx0 = Math.max(0, Math.floor((sx0 - minor) / 32));
            var bx1 = Math.min(nx - 1, Math.floor((sx1 + minor) / 32));
            b.rows[b.rowCount++] = bx0;
            b.rows[b.rowCount++] = bx1;
            var rowBase = y * nx;
            for (x = bx0; x <= bx1; ++x) {
                k = rowBase + x;
                if (counts[k]++ === 0) touched[tc++] = k;
            }
        }
    }
    b.touchedCount = tc;
    if (clk) { pt1 = clk.elapsedNs(); probe.binWalk += pt1 - pt0; pt0 = pt1; }
    // The prefix sum runs over the OCCUPIED bins only, in the order they were
    // first touched. Nothing downstream needs ascending bin order: the packer
    // walks the same list and reads offsets[bin] for the bins in it, and an
    // empty bin's offset is never read. `references` and the overflow counts
    // are unchanged, because an empty bin contributes nothing to either.
    var refs = 0, maxOcc = 0, overBins = 0, overPages = 0;
    var offsets = b.offsets, cursor = b.cursor;
    for (i = 0; i < tc; ++i) {
        k = touched[i];
        var occupants = counts[k];
        offsets[k] = refs;
        cursor[k] = refs;
        refs += occupants;
        if (occupants > maxOcc) maxOcc = occupants;
        if (occupants > 16) {
            ++overBins;
            overPages += Math.ceil(occupants / 16) - 1;
        }
    }
    b.references = refs; b.maxOccupants = maxOcc;
    b.overflowBins = overBins; b.overflowPages = overPages;
    b.offsets[n] = refs;
    if (b.indices.length < b.references)
        b.indices = new Uint16Array(Math.max(b.references, b.indices.length * 2));
    if (clk) { pt1 = clk.elapsedNs(); probe.binGrid += pt1 - pt0; pt0 = pt1; }
    var indices = b.indices, ranges = b.ranges, rows = b.rows;
    for (i = 0; i < count; ++i) {
        var at = ranges[4 * i + 2];
        for (y = ranges[4 * i]; y <= ranges[4 * i + 1]; ++y) {
            var from = rows[at++], to = rows[at++];
            var insertBase = y * nx;
            for (x = from; x <= to; ++x) {
                k = insertBase + x;
                indices[cursor[k]++] = i;
            }
        }
    }
    if (clk) probe.binInsert += clk.elapsedNs() - pt0;
    return b;
}

if (typeof module !== "undefined") module.exports = { build: build };
