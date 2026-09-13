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
    if (items.length > 6400)
        throw new Error("Particle render-instance limit exceeded");
    if (b.ranges.length < items.length * 4)
        b.ranges = new Int32Array(Math.max(items.length * 4, b.ranges.length * 2));
    b.counts.fill(0);
    var i, x, y, k;
    for (i = 0; i < items.length; ++i) {
        var p = items[i], radius = p.support;
        if (!(radius >= 0 && radius <= 40) || !Number.isFinite(p.x + p.y + radius))
            throw new Error("Invalid or unbounded particle support");
        var x0 = Math.max(0, Math.floor((p.x - radius) / 32));
        var x1 = Math.min(nx - 1, Math.floor((p.x + radius) / 32));
        var y0 = Math.max(0, Math.floor((p.y - radius) / 32));
        var y1 = Math.min(ny - 1, Math.floor((p.y + radius) / 32));
        b.ranges[4 * i] = x0; b.ranges[4 * i + 1] = x1;
        b.ranges[4 * i + 2] = y0; b.ranges[4 * i + 3] = y1;
        for (y = y0; y <= y1; ++y)
            for (x = x0; x <= x1; ++x)
                ++b.counts[y * nx + x];
    }
    b.references = 0; b.maxOccupants = 0; b.overflowBins = 0; b.overflowPages = 0;
    for (k = 0; k < n; ++k) {
        var count = b.counts[k];
        b.offsets[k] = b.references;
        b.cursor[k] = b.references;
        b.references += count;
        b.maxOccupants = Math.max(b.maxOccupants, count);
        if (count > 16) {
            ++b.overflowBins;
            b.overflowPages += Math.ceil(count / 16) - 1;
        }
    }
    b.offsets[n] = b.references;
    if (b.indices.length < b.references)
        b.indices = new Uint16Array(Math.max(b.references, b.indices.length * 2));
    for (i = 0; i < items.length; ++i) {
        for (y = b.ranges[4 * i + 2]; y <= b.ranges[4 * i + 3]; ++y) {
            for (x = b.ranges[4 * i]; x <= b.ranges[4 * i + 1]; ++x) {
                k = y * nx + x;
                b.indices[b.cursor[k]++] = i;
            }
        }
    }
    return b;
}

if (typeof module !== "undefined") module.exports = { build: build };
