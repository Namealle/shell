// Apparent-plane bins. Supports, not just centres, own every touched cell.
// Reuse counters, offsets and reference storage across publications.
function build(previous, items, width, height) {
    var nx = Math.max(1, Math.ceil(width / 32));
    var ny = Math.max(1, Math.ceil(height / 32));
    var n = nx * ny;
    var b = previous;
    if (!b || b.nx !== nx || b.ny !== ny) {
        b = { nx: nx, ny: ny, width: width, height: height,
            counts: new Uint16Array(n), offsets: new Uint32Array(n + 1),
            cursor: new Uint32Array(n), indices: new Uint16Array(0),
            ranges: new Int32Array(0) };
    }
    // Flat render instances (particles/Appearance.js): stride 18, x/y/support at
    // offsets 0/1/5. The same field order the packer reads.
    var data = items.data, stride = items.stride, count = items.count;
    if (count > 6400)
        throw new Error("Particle render-instance limit exceeded");
    if (b.ranges.length < count * 4)
        b.ranges = new Int32Array(Math.max(count * 4, b.ranges.length * 2));
    b.counts.fill(0);
    var counts = b.counts, i, x, y, k;
    for (i = 0; i < count; ++i) {
        var base = i * stride, px = data[base], py = data[base + 1], radius = data[base + 5];
        if (!(radius >= 0 && radius <= 127.5) || !Number.isFinite(px + py + radius))
            throw new Error("Invalid or unbounded particle support");
        var x0 = Math.max(0, Math.floor((px - radius) / 32));
        var x1 = Math.min(nx - 1, Math.floor((px + radius) / 32));
        var y0 = Math.max(0, Math.floor((py - radius) / 32));
        var y1 = Math.min(ny - 1, Math.floor((py + radius) / 32));
        b.ranges[4 * i] = x0; b.ranges[4 * i + 1] = x1;
        b.ranges[4 * i + 2] = y0; b.ranges[4 * i + 3] = y1;
        for (y = y0; y <= y1; ++y)
            for (x = x0; x <= x1; ++x)
                ++counts[y * nx + x];
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
    var cursor = b.cursor, indices = b.indices, ranges = b.ranges;
    for (i = 0; i < count; ++i) {
        for (y = ranges[4 * i + 2]; y <= ranges[4 * i + 3]; ++y) {
            for (x = ranges[4 * i]; x <= ranges[4 * i + 1]; ++x) {
                k = y * nx + x;
                indices[cursor[k]++] = i;
            }
        }
    }
    return b;
}

if (typeof module !== "undefined") module.exports = { build: build };
