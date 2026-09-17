// RGB24 data in opaque RGBA8 texels. Binding 3 is reserved for this texture.
// Header B: low 6 bits = count (0..16), bit 6 = 64K index bank,
// bit 7 = another page. An overflow header follows each full 16-index page.
function clamp(x, lo, hi) { return Math.max(lo, Math.min(hi, Number.isFinite(x) ? x : lo)); }
function word(x) { return Math.round(clamp(x, 0, 65535)); }
// minHeight is the caller's height for BOTH publication buffers; it REPLACES
// the per-buffer floor, so a smaller configuration can shrink the allocation.
// Without one buffer's history leaking into the other, a population sitting on
// a 4096-texel boundary would give the two buffers different heights and the
// sampled texture would change size on every publication.
function layout(previous, bins, count, minHeight) {
    var headersBase = 4;
    var listBase = headersBase + bins.nx * bins.ny;
    var listLength = bins.references + bins.overflowPages;
    if (listLength >= 131072) throw new Error("Particle index bank limit exceeded");
    var dataBase = listBase + listLength;
    var needed = dataBase + 8 * count + 1;
    var floor = minHeight > 0 ? minHeight : (previous ? previous.height : 0);
    var height = Math.max(floor, Math.ceil(needed / (256 * 16)) * 16);
    return { width: 256, height: Math.max(16, height), headersBase: headersBase,
        listBase: listBase, dataBase: dataBase, count: count, texelsUsed: needed,
        overflowBins: bins.overflowBins, overflowPages: bins.overflowPages,
        maxOccupants: bins.maxOccupants, references: bins.references };
}
// Height that covers EVERY population this configuration can produce, so the
// sampled texture is allocated once and never resized. A single resize of the
// sampled texture cost 13 ms -> 6700 ms per frame of scene-graph submission on
// llvmpipe, and it did not recover; a pre-sized texture never pays it.
function capacity(bins, maxItems, maxSupport, maxFlares, flareSupport, maxBends, bendSupport, maxTde, tdeSupport, maxWide, wideSupport) {
    var perAxis = Math.floor(2 * maxSupport / 32) + 2;
    var references = maxItems * perAxis * perAxis;
    if (maxBends > 0) {
        var bendAxis = Math.floor(2 * bendSupport / 32) + 2;
        references += maxBends * (bendAxis * bendAxis - perAxis * perAxis);
    }
    if (maxWide > 0 && wideSupport > 0) {
        // v10: the supernova's swollen precursor and the comet's nucleus are
        // wider than any configured star. A handful of instances, bounded like
        // the flare and tidal-disruption sets rather than a ceiling on all.
        var wideAxis = Math.floor(2 * wideSupport / 32) + 2;
        var bendBase = maxBends > 0 ? Math.floor(2 * bendSupport / 32) + 2 : perAxis;
        references += maxWide * Math.max(0, wideAxis * wideAxis - bendBase * bendBase);
    }
    if (maxTde > 0 && tdeSupport > 0) {
        // A tidal-disruption victim is one instance with a far wider footprint
        // than any other, so it is a bounded addition like the flare set.
        var tdeAxis = Math.floor(2 * tdeSupport / 32) + 2;
        var wideAxis = maxBends > 0 ? Math.floor(2 * bendSupport / 32) + 2 : perAxis;
        references += maxTde * Math.max(0, tdeAxis * tdeAxis - wideAxis * wideAxis);
    }
    if (maxFlares > 0) {
        // render() caps the flared instances, so their much larger footprint is
        // a bounded addition rather than a ceiling on every instance.
        var flareAxis = Math.floor(2 * flareSupport / 32) + 2;
        references += maxFlares * (flareAxis * flareAxis - perAxis * perAxis);
    }
    var needed = 4 + bins.nx * bins.ny + references + Math.ceil(references / 16) + 8 * maxItems + 1;
    return Math.max(16, Math.ceil(needed / (256 * 16)) * 16);
}
// `probe`: see Binning.build. Absent on every ordinary frame and every test.
function pack(previous, bins, items, meta, allocate, probe) {
    var clk = probe ? probe.clock : null;
    var pt0 = clk ? clk.elapsedNs() : 0, pt1 = 0;
    var out = layout(previous, bins, items.count, meta.minHeight);
    var length = out.width * out.height * 4;
    var fresh = !previous || !previous.bytes || previous.bytes.length !== length;
    var bytes = fresh ? (allocate ? allocate(out.width, out.height) : new Uint8ClampedArray(length)) : previous.bytes;
    if (fresh) for (var a = 3; a < length; a += 4) bytes[a] = 255;
    out.bytes = bytes;
    out.domain = meta.domain.slice();
    out.clock = meta.clock;
    out.revision = meta.revision % 16777216;
    function rgb(texel, r, g, b) {
        var j = texel * 4; bytes[j] = r; bytes[j + 1] = g; bytes[j + 2] = b;
    }
    function number24(texel, n) { rgb(texel, n % 256, Math.floor(n / 256) % 256, Math.floor(n / 65536) % 256); }
    function header(texel, offset, count, more) {
        rgb(texel, offset % 256, Math.floor(offset / 256) % 256,
            count + (offset >= 65536 ? 64 : 0) + (more ? 128 : 0));
    }
    rgb(0, 83, 70, 5); // SF version 5; independently checked after upload.
    number24(1, out.revision);
    number24(2, Math.floor(((meta.clock % 86400) + 86400) % 86400 * 128));
    rgb(3, 17, 129, 253); // detects channel swaps / color conversion.
    // Clear only the headers this buffer wrote last time. Sweeping all of them
    // costs three byte writes per bin per frame on a grid that is mostly empty.
    var occupied = previous && previous.occupied && !fresh ? previous.occupied : null;
    var counts = bins.counts, binCount = counts.length, headersBase = out.headersBase;
    if (occupied) {
        for (var q = 0; q < occupied.length; ++q) {
            var j0 = (headersBase + occupied[q]) * 4;
            bytes[j0] = 0; bytes[j0 + 1] = 0; bytes[j0 + 2] = 0;
        }
    } else {
        for (var b0 = 0; b0 < binCount; ++b0) {
            var j1 = (headersBase + b0) * 4;
            bytes[j1] = 0; bytes[j1 + 1] = 0; bytes[j1 + 2] = 0;
        }
    }
    if (clk) { pt1 = clk.elapsedNs(); probe.packClear += pt1 - pt0; pt0 = pt1; }
    var written = previous && previous.occupied ? previous.occupied : [];
    var writtenCount = 0;
    var used = 0;
    // Only the bins the binner actually filled. Walking the whole grid meant
    // 14400 iterations a frame on the portrait output to find about two
    // thousand that had anything in them. header() and rgb() are inlined for
    // the same reason smooth() is in Appearance: a call costs more here than
    // the three byte writes inside it.
    var touched = bins.touched, tc = bins.touchedCount, offsets = bins.offsets, indices = bins.indices;
    // A bins object that did not come from Binning.build (a fixture, a future
    // caller) has no list; derive it once rather than keeping a second hot path.
    if (touched === undefined) {
        touched = []; tc = 0;
        for (var b2 = 0; b2 < binCount; ++b2)
            if (counts[b2]) touched[tc++] = b2;
    }
    var listBase = out.listBase;
    for (var t = 0; t < tc; ++t) {
        var bin = touched[t];
        var remaining = counts[bin], cursor = offsets[bin];
        var target = headersBase + bin;
        if (!remaining) continue;
        written[writtenCount++] = bin;
        while (remaining) {
            var take = remaining < 16 ? remaining : 16;
            var jh = target * 4;
            bytes[jh] = used % 256;
            bytes[jh + 1] = Math.floor(used / 256) % 256;
            bytes[jh + 2] = take + (used >= 65536 ? 64 : 0) + (remaining > take ? 128 : 0);
            for (var j = 0; j < take; ++j) {
                var index = indices[cursor++];
                var jl = (listBase + used++) * 4;
                bytes[jl] = index % 256;
                bytes[jl + 1] = Math.floor(index / 256);
                bytes[jl + 2] = 0;
            }
            remaining -= take;
            if (remaining) target = listBase + used++;
        }
    }
    out.occupied = written;
    written.length = writtenCount;
    if (clk) { pt1 = clk.elapsedNs(); probe.packGrid += pt1 - pt0; pt0 = pt1; }
    // The instance loop is the hot one: byte offsets are computed once per texel
    // and written directly instead of through a closure.
    // Flat render instances (particles/Appearance.js): stride 21, field order
    // x y vx vy core support streak r g b lum flags phase p0 age captured id gen
    // halfMajor halfMinor stretch.
    var domain = out.domain, dx = domain[0], dy = domain[1];
    var sx = 65535 / domain[2], sy = 65535 / domain[3];
    var src = items.data, stride = items.stride;
    var count = items.count, j = out.dataBase * 4;
    for (var i = 0, f = 0; i < count; ++i, j += 32, f += stride) {
        // word()/clamp() inlined: seven calls per instance per frame is real cost.
        var x = (src[f] - dx) * sx; x = x > 65535 ? 65535 : (x > 0 ? (x + 0.5) | 0 : 0);
        var y = (src[f + 1] - dy) * sy; y = y > 65535 ? 65535 : (y > 0 ? (y + 0.5) | 0 : 0);
        var vx = (src[f + 2] + 32768) * (65535 / 65536); vx = vx > 65535 ? 65535 : (vx > 0 ? (vx + 0.5) | 0 : 0);
        var vy = (src[f + 3] + 32768) * (65535 / 65536); vy = vy > 65535 ? 65535 : (vy > 0 ? (vy + 0.5) | 0 : 0);
        var lum = src[f + 10] * (65535 / 4); lum = lum > 65535 ? 65535 : (lum > 0 ? (lum + 0.5) | 0 : 0);
        var raw = src[f + 12] % 6.283185307179586;
        var phase = (raw < 0 ? raw + 6.283185307179586 : raw) * (65535 / 6.283185307179586);
        phase = phase > 65535 ? 65535 : (phase > 0 ? (phase + 0.5) | 0 : 0);
        var param = src[f + 13]; param = param > 65535 ? 65535 : (param > 0 ? (param + 0.5) | 0 : 0);
        // Texel +7 carries the oriented half-extents the binner used, so the
        // shader can reject on the streak's box instead of a disc of its
        // half-length: a long thin trail fills a tenth of that disc.
        var major = src[f + 18], minor = src[f + 19];
        // 21/22: the unit velocity render() already resolved, with the same
        // 0.01 px/s guard this used to reproduce here.
        var ex = src[f + 21], ey = src[f + 22];
        var m2 = major * major, n2 = minor * minor;
        var bx = Math.sqrt(m2 * ex * ex + n2 * ey * ey) * 2;
        var by = Math.sqrt(m2 * ey * ey + n2 * ex * ex) * 2;
        // A curved trail is displaced transversely by up to the sagitta the bin
        // radius reserved; at a diagonal the ellipse box would clip that, and the
        // capsule the binner used already covers it. The shader clamps that
        // displacement to +-6 px times the stretch, so the padding follows the
        // same scalar instead of switching on with the old bend bit.
        var stretch = src[f + 20];
        if (stretch > 0) {
            var pad = Math.ceil(12 * (stretch > 1 ? 1 : stretch));
            bx += pad; by += pad;
        }
        bx = bx > 255 ? 255 : (bx > 0 ? Math.ceil(bx) : 0);
        by = by > 255 ? 255 : (by > 0 ? Math.ceil(by) : 0);
        var core = src[f + 4], streak = src[f + 6], captured = src[f + 15];
        var xh = (x / 256) | 0, yh = (y / 256) | 0, vxh = (vx / 256) | 0, vyh = (vy / 256) | 0;
        bytes[j] = x - xh * 256; bytes[j + 1] = xh; bytes[j + 2] = y - yh * 256;
        bytes[j + 4] = yh;
        // Texel +1 green carried the bin support, which the reject box replaced
        // and no shader has read since v4. It now carries the continuous tidal
        // stretch 0..255, and costs no extra fetch: the shader already samples
        // this texel for the high bits of the position.
        bytes[j + 5] = ((stretch > 1 ? 1 : (stretch > 0 ? stretch : 0)) * 255 + 0.5) | 0;
        bytes[j + 6] = ((core > 12 ? 12 : (core > 0.25 ? core : 0.25)) * 16 + 0.5) | 0;
        bytes[j + 8] = vx - vxh * 256; bytes[j + 9] = vxh; bytes[j + 10] = vy - vyh * 256;
        bytes[j + 12] = vyh;
        var cr = src[f + 7], cg = src[f + 8];
        bytes[j + 13] = ((cr > 1 ? 1 : (cr > 0 ? cr : 0)) * 255 + 0.5) | 0;
        bytes[j + 14] = ((cg > 1 ? 1 : (cg > 0 ? cg : 0)) * 255 + 0.5) | 0;
        var cb = src[f + 9];
        bytes[j + 16] = ((cb > 1 ? 1 : (cb > 0 ? cb : 0)) * 255 + 0.5) | 0;
        var lumh = (lum / 256) | 0;
        bytes[j + 17] = lum - lumh * 256; bytes[j + 18] = lumh;
        // kind 0..6 in the low three bits, bit 3 = four-point flare, bit 4 = near
        var phaseh = (phase / 256) | 0, paramh = (param / 256) | 0;
        bytes[j + 20] = src[f + 11];
        bytes[j + 21] = phase - phaseh * 256; bytes[j + 22] = phaseh;
        bytes[j + 24] = param - paramh * 256; bytes[j + 25] = paramh;
        bytes[j + 26] = ((streak > 120 ? 120 : (streak > 0 ? streak : 0)) * (255 / 120) + 0.5) | 0;
        bytes[j + 28] = bx; bytes[j + 29] = by;
        bytes[j + 30] = ((captured > 1 ? 1 : (captured > 0 ? captured : 0)) * 255 + 0.5) | 0;
    }
    rgb(out.texelsUsed - 1, 251, 127, 19);
    if (clk) probe.packInst += clk.elapsedNs() - pt0;
    return out;
}
function verify(packet) {
    var d = packet.bytes, end = (packet.texelsUsed - 1) * 4;
    return d[0] === 83 && d[1] === 70 && d[2] === 5 && d[3] === 255
        && d[4] + d[5] * 256 + d[6] * 65536 === packet.revision
        && d[12] === 17 && d[13] === 129 && d[14] === 253 && d[15] === 255
        && d[end] === 251 && d[end + 1] === 127 && d[end + 2] === 19 && d[end + 3] === 255;
}

if (typeof module !== "undefined") module.exports = { layout: layout, pack: pack, verify: verify, capacity: capacity };
