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
function capacity(bins, maxItems, maxSupport) {
    var perAxis = Math.floor(2 * maxSupport / 32) + 2;
    var references = maxItems * perAxis * perAxis;
    var needed = 4 + bins.nx * bins.ny + references + Math.ceil(references / 16) + 8 * maxItems + 1;
    return Math.max(16, Math.ceil(needed / (256 * 16)) * 16);
}
function pack(previous, bins, items, meta, allocate) {
    var out = layout(previous, bins, items.length, meta.minHeight);
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
    rgb(0, 83, 70, 4); // SF version 4; independently checked after upload.
    number24(1, out.revision);
    number24(2, Math.floor(((meta.clock % 86400) + 86400) % 86400 * 128));
    rgb(3, 17, 129, 253); // detects channel swaps / color conversion.
    var used = 0;
    for (var bin = 0; bin < bins.counts.length; ++bin) {
        var remaining = bins.counts[bin], cursor = bins.offsets[bin];
        var target = out.headersBase + bin;
        if (!remaining) { rgb(target, 0, 0, 0); continue; }
        while (remaining) {
            var take = Math.min(16, remaining);
            header(target, used, take, remaining > take);
            for (var j = 0; j < take; ++j) {
                var index = bins.indices[cursor++];
                rgb(out.listBase + used++, index % 256, Math.floor(index / 256), 0);
            }
            remaining -= take;
            if (remaining) target = out.listBase + used++;
        }
    }
    var domain = out.domain;
    for (var i = 0; i < items.length; ++i) {
        var p = items[i], base = out.dataBase + 8 * i;
        var x = word((p.x - domain[0]) * 65535 / domain[2]);
        var y = word((p.y - domain[1]) * 65535 / domain[3]);
        var vx = word((p.vx + 32768) * (65535 / 65536));
        var vy = word((p.vy + 32768) * (65535 / 65536));
        var lum = word(p.lum * (65535 / 4));
        var phase = word((((p.phase % (2 * Math.PI)) + 2 * Math.PI) % (2 * Math.PI)) * (65535 / (2 * Math.PI)));
        var param = word(p.p0 || 0), age = word(p.age * 128);
        rgb(base, x % 256, Math.floor(x / 256), y % 256);
        rgb(base + 1, Math.floor(y / 256), Math.ceil(clamp(p.support, 0, 40) * 4), Math.round(clamp(p.core, 0.25, 12) * 16));
        rgb(base + 2, vx % 256, Math.floor(vx / 256), vy % 256);
        rgb(base + 3, Math.floor(vy / 256), Math.round(clamp(p.r, 0, 1) * 255), Math.round(clamp(p.g, 0, 1) * 255));
        rgb(base + 4, Math.round(clamp(p.b, 0, 1) * 255), lum % 256, Math.floor(lum / 256));
        rgb(base + 5, p.kind, phase % 256, Math.floor(phase / 256));
        rgb(base + 6, param % 256, Math.floor(param / 256), Math.round(clamp(p.streak, 0, 32) * (255 / 32)));
        rgb(base + 7, age % 256, Math.floor(age / 256), Math.round(clamp(p.captured, 0, 1) * 255));
    }
    rgb(out.texelsUsed - 1, 251, 127, 19);
    return out;
}
function verify(packet) {
    var d = packet.bytes, end = (packet.texelsUsed - 1) * 4;
    return d[0] === 83 && d[1] === 70 && d[2] === 4 && d[3] === 255
        && d[4] + d[5] * 256 + d[6] * 65536 === packet.revision
        && d[12] === 17 && d[13] === 129 && d[14] === 253 && d[15] === 255
        && d[end] === 251 && d[end + 1] === 127 && d[end + 2] === 19 && d[end + 3] === 255;
}

if (typeof module !== "undefined") module.exports = { layout: layout, pack: pack, verify: verify, capacity: capacity };
