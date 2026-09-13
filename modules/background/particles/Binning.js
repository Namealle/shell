// Apparent-plane bins. Supports, not just centres, own every touched cell.
// Reuse counters, offsets and reference storage across publications.
function growRows(old, size) {
    var next = new Int32Array(size);
    next.set(old);
    return next;
}
function build(previous, items, width, height) {
    var nx = Math.max(1, Math.ceil(width / 32));
    var ny = Math.max(1, Math.ceil(height / 32));
    var n = nx * ny;
    var b = previous;
    if (!b || b.nx !== nx || b.ny !== ny) {
        b = { nx: nx, ny: ny, width: width, height: height,
            counts: new Uint16Array(n), offsets: new Uint32Array(n + 1),
            cursor: new Uint32Array(n), indices: new Uint16Array(0),
            ranges: new Int32Array(0), rows: new Int32Array(0) };
    }
    // Flat render instances (particles/Appearance.js): stride 21, x/y/support at
    // offsets 0/1/5. The same field order the packer reads.
    var data = items.data, stride = items.stride, count = items.count;
    if (count > 6400)
        throw new Error("Particle render-instance limit exceeded");
    if (b.ranges.length < count * 4)
        b.ranges = new Int32Array(Math.max(count * 4, b.ranges.length * 2));
    b.counts.fill(0);
    b.rowCount = 0;
    var counts = b.counts, i, x, y, k;
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
            for (x = bx0; x <= bx1; ++x) ++counts[y * nx + x];
        }
    }
    b.references = 0; b.maxOccupants = 0; b.overflowBins = 0; b.overflowPages = 0;
    for (k = 0; k < n; ++k) {
        var occupants = counts[k];
        b.offsets[k] = b.references;
        b.cursor[k] = b.references;
        b.references += occupants;
        if (occupants > b.maxOccupants) b.maxOccupants = occupants;
        if (occupants > 16) {
            ++b.overflowBins;
            b.overflowPages += Math.ceil(occupants / 16) - 1;
        }
    }
    b.offsets[n] = b.references;
    if (b.indices.length < b.references)
        b.indices = new Uint16Array(Math.max(b.references, b.indices.length * 2));
    var cursor = b.cursor, indices = b.indices, ranges = b.ranges, rows = b.rows;
    for (i = 0; i < count; ++i) {
        var at = ranges[4 * i + 2];
        for (y = ranges[4 * i]; y <= ranges[4 * i + 1]; ++y) {
            var from = rows[at++], to = rows[at++];
            for (x = from; x <= to; ++x) {
                k = y * nx + x;
                indices[cursor[k]++] = i;
            }
        }
    }
    return b;
}

if (typeof module !== "undefined") module.exports = { build: build };
