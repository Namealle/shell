import QtQuick
import QtQuick.Shapes
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

Shape {
    id: root

    property bool expanded: false
    property bool pressed: false
    property color iconColor: Colours.palette.m3onSurface
    property color activeColor: Colours.palette.m3primary
    property real size: Tokens.font.size.large * 0.8
    property real strokeThickness: size * 0.18

    width: size
    height: width
    implicitWidth: size
    implicitHeight: width
    Layout.preferredWidth: size
    Layout.preferredHeight: width
    Layout.minimumWidth: size
    Layout.maximumWidth: size
    Layout.minimumHeight: width
    Layout.maximumHeight: width
    preferredRendererType: Shape.CurveRenderer
    asynchronous: true

    property real midY: {
        if (pressed) return height * 0.5;
        if (expanded) return height * 0.30;
        return height * 0.70;
    }
    property real sideY: {
        if (pressed) return height * 0.5;
        if (expanded) return height * 0.70;
        return height * 0.30;
    }

    ShapePath {
        strokeWidth: root.strokeThickness
        strokeColor: root.expanded ? root.activeColor : root.iconColor
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin

        startX: root.width * 0.15
        startY: root.sideY

        PathLine {
            x: root.width * 0.5
            y: root.midY
        }
        PathLine {
            x: root.width * 0.85
            y: root.sideY
        }

        Behavior on strokeColor {
            CAnim {}
        }
    }

    Behavior on midY {
        Anim {
            easing: Tokens.anim.standard
            duration: Tokens.anim.durations.normal
        }
    }
    Behavior on sideY {
        Anim {
            easing: Tokens.anim.standard
            duration: Tokens.anim.durations.normal
        }
    }
}
