pragma ComponentBehavior: Bound

import QtQuick
import qs.services as Services
import "." as BackgroundComponents

// One copy of the renderer's property wiring, mounted by whichever process is
// drawing the sky: Background.qml when `starfield.json`'s `process` is "shell",
// StarfieldWindows.qml (the starfield.qml entry point) when it is "separate".
// The renderer itself knows nothing about either; everything here is a
// pass-through from the two singletons, which any Quickshell instance can load.
//
// Still a Loader, so Visualiser.qml keeps taking the same kind of source item.
Loader {
    id: root

    required property string screenName

    // The diagnostics probe reaches the renderer through the service's registry;
    // `starfield-shell perf dump` then answers for every output at once.
    onLoaded: Services.Starfield.registerRenderer(root.screenName, item)
    Component.onDestruction: Services.Starfield.unregisterRenderer(root.screenName)

    sourceComponent: BackgroundComponents.Starfield {
        running: Services.Ambient.forScreen(root.screenName).running

        Connections {
            target: Services.Starfield

            function onFire(name: string, screen: string, overrides: var): void {
                if (!screen || screen === root.screenName)
                    root.item.pushEvent(name, 0, overrides);
            }
        }
        screenSeed: Services.Ambient.seedFor(root.screenName)
        ambientBirth: Services.Ambient.forScreen(root.screenName).birth
        ambientLive: Services.Ambient.forScreen(root.screenName).live
        paletteColors: Services.Starfield.paletteColors
        paletteWeightsTarget: Services.Ambient.forScreen(root.screenName).paletteWeights
        paletteMixTarget: Services.Ambient.forScreen(root.screenName).mix
        archetypeWeightsTarget: Services.Ambient.forScreen(root.screenName).archetypeWeights
        archetypeParams: Services.Starfield.archetypeParams
        calmTarget: Services.Ambient.forScreen(root.screenName).calm
        ambientHole: Services.Ambient.forScreen(root.screenName).hole
        blackHole: Services.Starfield.blackHole
        particles: Services.Starfield.particles
        particlesEnabled: Services.Starfield.particlesEnabled
        eventFamilies: Services.Starfield.eventFamilies
        eventHeadCap: Services.Starfield.eventHeadCap
        devicePixelRatio: root.Screen.devicePixelRatio
        density: Services.Starfield.density
        driftSpeed: Services.Starfield.driftSpeed
        driftDirection: Services.Starfield.driftDirection
        twinkle: Services.Starfield.twinkle
        flareFraction: Services.Starfield.flareFraction
        brightness: Services.Starfield.brightness
        backgroundColor: Services.Starfield.backgroundColor
        edgeLift: Services.Starfield.edgeLift
        fps: Services.Starfield.fps
        motionMode: Services.Starfield.motion.mode
        radialSpeed: Services.Starfield.motion.radialSpeed
        centreWander: Services.Starfield.motion.centreWander
        zoomBreath: Services.Starfield.motion.zoom
        reversals: Services.Starfield.motion.reversals
        cameraEnabled: Services.Starfield.motion.camera.enabled
        cameraDirection: Services.Starfield.motion.camera.direction
        cameraSpeed: Services.Starfield.motion.camera.speed
        cameraDepth: Services.Starfield.motion.camera.depth
        cameraDustFlow: Services.Starfield.motion.camera.dustFlow
        cameraRoll: Services.Starfield.motion.camera.roll
        cameraWander: Services.Starfield.motion.camera.wander
        cameraSizeGain: Services.Starfield.motion.camera.sizeGain
        motionWander: Services.Starfield.motion.wander
        motionZoom: Services.Starfield.motion.zoom
        motionRotation: Services.Starfield.motion.rotation
        varietyEnabled: Services.Starfield.variety.enabled
        varietySeed: Services.Starfield.variety.seed
        variableFraction: Services.Starfield.variables.fraction
        companionChance: Services.Starfield.meteors.companionChance
        fireballChance: Services.Starfield.meteors.fireballChance
        meteorsEnabled: Services.Starfield.meteors.enabled
        meteorsInterval: Services.Starfield.meteors.interval
        cometEnabled: Services.Starfield.comet.enabled
        cometInterval: Services.Starfield.comet.interval
        satellitesEnabled: Services.Starfield.satellites.enabled
        satellitesInterval: Services.Starfield.satellites.interval
    }
}
