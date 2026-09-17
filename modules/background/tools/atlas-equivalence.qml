// Proves the split/cached descriptor atlas produces the SAME data URL, byte for
// byte, as the single-pass builder it replaced.
//
//   cd modules/background && QT_ASSUME_STDERR_HAS_CONSOLE=1 QT_QPA_PLATFORM=offscreen \
//     /usr/lib/qt6/bin/qml tools/atlas-equivalence.qml
//
// QT_ASSUME_STDERR_HAS_CONSOLE is not optional: without it every console.log
// here is silently dropped and the run looks like it printed nothing.
//
// The builder now encodes the BMP header and the 1280-row entry ledger once and
// caches that base64, then appends the encoding of the 256 descriptor rows.
// That is only valid because base64 works in three-byte groups and both parts
// are multiples of three; this checks the claim on the real state, with the
// ledger empty (particles on) and populated (particles off), across seals.
import QtQuick
import ".."

Item {
    id: root

    width: 1440
    height: 900

    property int failures: 0

    // The builder as it was: one array, every row, one Qt.btoa.
    function oldUrl(state) {
        const bytes = [];
        function le(n, count) {
            for (let i = 0; i < count; ++i)
                bytes.push(Math.floor(n / Math.pow(256, i)) % 256);
        }
        le(0x4d42, 2);
        le(54 + 64 * 1536 * 3, 4);
        le(0, 4);
        le(54, 4);
        le(40, 4);
        le(64, 4);
        le(1536, 4);
        le(1, 2);
        le(24, 2);
        le(0, 4);
        le(64 * 1536 * 3, 4);
        le(0, 4);
        le(0, 4);
        le(0, 4);
        le(0, 4);
        for (let row = 1535; row >= 0; --row) {
            const p = row < 256 ? state.history[row].pixels : state.entryPixels;
            const offset = row < 256 ? 0 : (row - 256) * 64 * 3;
            for (let x = 0; x < 64; ++x)
                bytes.push(p[offset + x * 3 + 2], p[offset + x * 3 + 1], p[offset + x * 3]);
        }
        return "data:image/bmp;base64," + Qt.btoa(bytes);
    }

    function check(label, sky) {
        const now = sky.atlasUrl();
        const then = oldUrl(sky._state);
        if (now === then) {
            console.log("ok    " + label + "   " + now.length + " chars identical");
        } else {
            ++failures;
            let at = 0;
            while (at < now.length && at < then.length && now[at] === then[at])
                ++at;
            console.log("FAIL  " + label + "   first difference at " + at
                        + " of " + now.length + "/" + then.length);
        }
    }

    Starfield {
        id: withParticles

        anchors.fill: parent
        running: false
        screenSeed: 4242
        particlesEnabled: true
        paletteColors: [[0.66, 0.90, 0.74], [1, 0.94, 0.68], [0.95, 0.69, 0.69]]
        paletteWeightsTarget: [1, 1, 1]
    }

    Starfield {
        id: withEntries

        anchors.fill: parent
        running: false
        screenSeed: 4242
        // particles off is the only regime that writes the entry ledger, which
        // is the half the prefix cache holds.
        particlesEnabled: false
        paletteColors: [[0.66, 0.90, 0.74], [1, 0.94, 0.68], [0.95, 0.69, 0.69]]
        paletteWeightsTarget: [1, 1, 1]
    }

    // Not Component.onCompleted: the renderer builds its state in its own
    // onCompleted, and this root's runs first. Same reason the other harnesses
    // drive themselves from a Timer.
    Timer {
        running: true
        interval: 50
        onTriggered: root.run()
    }

    function run() {
        check("fresh state, empty ledger", withParticles);
        withParticles.seek(95);
        check("after three seals", withParticles);
        withParticles.seek(400);
        check("after thirteen seals", withParticles);

        check("fresh state, entries on", withEntries);
        withEntries.seek(65);
        check("entries published, two seals", withEntries);
        withEntries.seek(200);
        check("entries republished", withEntries);

        console.log("");
        console.log(failures === 0 ? "QML ATLAS EQUIVALENCE PASS" : "QML ATLAS EQUIVALENCE FAIL " + failures);
        Qt.exit(failures === 0 ? 0 : 1);
    }
}
