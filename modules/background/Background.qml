pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.services
import qs.services as Services
import "." as BackgroundComponents

Variants {
    model: Screens.screens.filter(s => GlobalConfig.forScreen(s.name).background.enabled)

    StyledWindow {
        id: win

        required property ShellScreen modelData
        readonly property bool starfieldEnabled: Services.Starfield.enabledFor(modelData.name)

        screen: modelData
        name: "background"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: starfieldEnabled || contentItem.Config.background.wallpaperEnabled ? WlrLayer.Background : WlrLayer.Bottom
        color: starfieldEnabled || contentItem.Config.background.wallpaperEnabled ? "black" : "transparent"
        surfaceFormat.opaque: false

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        ShellState.ComponentRef {
            screen: win.screen
            slot: "background"
            component: win
        }

        Item {
            id: behindClock

            anchors.fill: parent

            Loader {
                id: wallpaper

                asynchronous: true

                anchors.fill: parent
                active: !win.starfieldEnabled && Config.background.wallpaperEnabled

                sourceComponent: Wallpaper {}
            }

            Loader {
                id: starfield

                anchors.fill: parent
                active: win.starfieldEnabled

                sourceComponent: BackgroundComponents.Starfield {
                    running: Services.Ambient.forScreen(win.modelData.name).running

                    Connections {
                        target: Services.Starfield

                        function onFire(name: string, screen: string): void {
                            if (!screen || screen === win.modelData.name)
                                starfield.item.pushEvent(name, 0, null);
                        }
                    }
                    screenSeed: Services.Ambient.seedFor(win.modelData.name)
                    ambientBirth: Services.Ambient.forScreen(win.modelData.name).birth
                    ambientLive: Services.Ambient.forScreen(win.modelData.name).live
                    paletteColors: Services.Starfield.paletteColors
                    paletteWeightsTarget: Services.Ambient.forScreen(win.modelData.name).paletteWeights
                    paletteMixTarget: Services.Ambient.forScreen(win.modelData.name).mix
                    archetypeWeightsTarget: Services.Ambient.forScreen(win.modelData.name).archetypeWeights
                    archetypeParams: Services.Starfield.archetypeParams
                    calmTarget: Services.Ambient.forScreen(win.modelData.name).calm
                    ambientHole: Services.Ambient.forScreen(win.modelData.name).hole
                    blackHole: Services.Starfield.blackHole
                    particles: Services.Starfield.particles
                    particlesEnabled: Services.Starfield.particlesEnabled
                    eventFamilies: Services.Starfield.eventFamilies
                    eventHeadCap: Services.Starfield.eventHeadCap
                    devicePixelRatio: behindClock.Screen.devicePixelRatio
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

            Visualiser {
                anchors.fill: parent
                screen: win.modelData
                wallpaper: win.starfieldEnabled ? starfield : wallpaper
            }
        }

        Loader {
            id: clockLoader

            asynchronous: true
            active: Config.background.desktopClock.enabled

            anchors.margins: Tokens.padding.extraLargeIncreased
            anchors.leftMargin: Tokens.padding.extraLargeIncreased + Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness)

            state: Config.background.desktopClock.position
            states: [
                State {
                    name: "top-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "top-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "top-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.top: parent.top
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "middle-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "middle-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "middle-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                    }
                },
                State {
                    name: "bottom-left"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                    }
                },
                State {
                    name: "bottom-center"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                },
                State {
                    name: "bottom-right"

                    AnchorChanges {
                        target: clockLoader
                        anchors.bottom: parent.bottom
                        anchors.right: parent.right
                    }
                }
            ]

            transitions: Transition {
                AnchorAnim {}
            }

            sourceComponent: DesktopClock {
                wallpaper: behindClock
                absX: clockLoader.x
                absY: clockLoader.y
            }
        }
    }
}
