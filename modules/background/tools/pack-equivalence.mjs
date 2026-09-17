// Proves that the occupied-bin walk in Binning.build/Packing.pack publishes the
// SAME atlas content as the full-grid walk it replaced, for a real field.
//
//   node tools/pack-equivalence.mjs
//
// The index list is laid out in the order bins are visited, and the new walk
// visits them in first-touch order instead of ascending bin order, so the bytes
// are not expected to match byte for byte. What the shader reads is: the bin's
// header texel -> (offset, count) -> that many index texels -> instance rows.
// This decodes exactly that, for every bin, from both versions, and compares
// the decoded index SETS, plus the atlas geometry the shader is handed as
// uniforms. Equal sets over an identical geometry means every pixel resolves
// the same instances, which is the thing that must not change. The instance
// loop that writes those rows is untouched by the change under test.
//
// The "old" version is reconstructed here rather than checked out, so this file
// is the record of what the previous layout was.
import { createRequire } from "module";
import { dirname, join } from "path";
import { fileURLToPath } from "url";

const require = createRequire(import.meta.url);
const here = dirname(fileURLToPath(import.meta.url));
const particles = join(here, "..", "particles");
const Physics = require(join(particles, "Physics.js"));
const Appearance = require(join(particles, "Appearance.js"));
const Binning = require(join(particles, "Binning.js"));
const Packing = require(join(particles, "Packing.js"));

// --- the layout as it was before the occupied-bin walk ----------------------
function packOld(bins, items, meta) {
    const out = Packing.layout(null, bins, items.count, meta.minHeight);
    const length = out.width * out.height * 4;
    const bytes = new Uint8ClampedArray(length);
    for (let a = 3; a < length; a += 4) bytes[a] = 255;
    out.bytes = bytes;
    const rgb = (texel, r, g, b) => { const j = texel * 4; bytes[j] = r; bytes[j + 1] = g; bytes[j + 2] = b; };
    const header = (texel, offset, count, more) =>
        rgb(texel, offset % 256, Math.floor(offset / 256) % 256,
            count + (offset >= 65536 ? 64 : 0) + (more ? 128 : 0));
    let used = 0;
    for (let bin = 0; bin < bins.counts.length; ++bin) {
        let remaining = bins.counts[bin], cursor = bins.offsets[bin];
        let target = out.headersBase + bin;
        if (!remaining) continue;
        while (remaining) {
            const take = Math.min(16, remaining);
            header(target, used, take, remaining > take);
            for (let j = 0; j < take; ++j) {
                const index = bins.indices[cursor++];
                rgb(out.listBase + used++, index % 256, Math.floor(index / 256), 0);
            }
            remaining -= take;
            if (remaining) target = out.listBase + used++;
        }
    }
    return out;
}

// --- the shader's read path -------------------------------------------------
function decode(packet, bins) {
    const b = packet.bytes, out = [];
    for (let bin = 0; bin < bins.counts.length; ++bin) {
        let texel = packet.headersBase + bin, list = [];
        for (;;) {
            const j = texel * 4;
            const lo = b[j], hi = b[j + 1], flags = b[j + 2];
            const count = flags & 63, bank = (flags & 64) ? 65536 : 0, more = (flags & 128) !== 0;
            if (!count) break;
            let at = packet.listBase + lo + hi * 256 + bank;
            for (let k = 0; k < count; ++k) {
                const jj = (at + k) * 4;
                list.push(b[jj] + b[jj + 1] * 256);
            }
            if (!more) break;
            texel = at + count;
        }
        out.push(list.sort((x, y) => x - y).join(","));
    }
    return out;
}

const W = 2880, H = 1920;
const pool = Physics.create(W, H, 180, 12345, { population: { near: 200, middle: 700 } },
    (s, i) => Appearance.birth(s, i, { colors: [[0.6, 0.8, 1], [1, 0.8, 0.6]], weights: [1, 1], mix: 0.3,
        archetypes: [0.7, 0.1, 0.06, 0.05, 0.05, 0.04], params: {}, legacy: [0, 0, 0, 0.5], seed: 7 }));
pool.transientBirth = (s, i, traits) => Appearance.transient(s, i, traits);

let items = null, bins = null, checked = 0, mismatches = 0, dataMismatch = 0;
for (let frame = 0; frame < 400; ++frame) {
    Physics.advance(pool, 1 / 30, 6, 0.5, W / 2, H / 2, 1);
    if (frame % 17 !== 0) continue;
    items = Appearance.render(items, pool, { twinkle: 0.22 });
    bins = Binning.build(bins, items, W, H);
    const meta = { domain: [-200, -200, W + 400, H + 400], clock: pool.clock, revision: frame + 1, minHeight: 0 };
    const now = Packing.pack(null, bins, items, meta);
    const then = packOld(bins, items, meta);
    if (!Packing.verify(now)) { console.log("FAIL sentinel check on the new packet"); process.exit(1); }
    const a = decode(now, bins), c = decode(then, bins);
    for (let i = 0; i < a.length; ++i) if (a[i] !== c[i]) ++mismatches;
    // packOld reproduces the header/list walk only -- the instance loop is
    // untouched by this change -- so what has to match besides the decoded sets
    // is the geometry the shader is handed as uniforms: where the instance rows
    // start, how many texels are live, and how tall the texture is.
    if (now.dataBase !== then.dataBase || now.listBase !== then.listBase
        || now.texelsUsed !== then.texelsUsed || now.height !== then.height
        || now.references !== then.references || now.overflowPages !== then.overflowPages)
        ++dataMismatch;
    checked += a.length;
}

console.log(`bins decoded ${checked}, alive ${pool.aliveCount}, items ${items.count}, refs ${bins.references}`);
console.log(mismatches === 0 ? "ok    every bin resolves the same instance set as the full-grid walk"
    : `FAIL  ${mismatches} bins decode differently`);
console.log(dataMismatch === 0 ? "ok    the atlas geometry the shader is handed is identical"
    : `FAIL  ${dataMismatch} frames differ in the atlas geometry`);
process.exit(mismatches === 0 && dataMismatch === 0 ? 0 : 1);
