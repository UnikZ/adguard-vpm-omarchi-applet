import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color outlineColor: Commons.Color.foreground // shield outline
  property color contentColor: Commons.Color.foreground // waves and dot

  width: iconSize * 0.92
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  // Geometry: outline shield with the Wi-Fi waves + dot optically centered
  // in the shield body. All coordinates relative so the icon scales from
  // tiny bar slot to the large panel hero.
  readonly property real waveBaseY: height * 0.57
  readonly property real waveSide: 0.707 // sin/cos of 45° — half-span of each arc
  readonly property real arcStroke: Math.max(0.9, width * 0.075)

  // AdGuard-style shield silhouette drawn natively (like the Dropbox
  // diamond) so the tiny bar slot stays crisp without SVG quirks.
  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.outlineColor
      strokeWidth: Math.max(1, root.width * 0.072)
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.5
      startY: root.height * 0.075
      PathLine { x: root.width * 0.93; y: root.height * 0.205 }
      PathLine { x: root.width * 0.93; y: root.height * 0.46 }
      PathQuad { controlX: root.width * 0.91; controlY: root.height * 0.79; x: root.width * 0.5; y: root.height * 0.945 }
      PathQuad { controlX: root.width * 0.09; controlY: root.height * 0.79; x: root.width * 0.07; y: root.height * 0.46 }
      PathLine { x: root.width * 0.07; y: root.height * 0.205 }
      PathLine { x: root.width * 0.5; y: root.height * 0.075 }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.contentColor
      strokeWidth: root.arcStroke
      capStyle: ShapePath.RoundCap
      startX: root.width * 0.5 - root.waveSide * root.width * 0.15
      startY: root.waveBaseY - root.waveSide * root.width * 0.15
      PathArc {
        x: root.width * 0.5 + root.waveSide * root.width * 0.15
        y: root.waveBaseY - root.waveSide * root.width * 0.15
        radiusX: root.width * 0.15
        radiusY: root.width * 0.15
        direction: PathArc.DirectionClockwise
      }
    }

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.contentColor
      strokeWidth: root.arcStroke
      capStyle: ShapePath.RoundCap
      startX: root.width * 0.5 - root.waveSide * root.width * 0.28
      startY: root.waveBaseY - root.waveSide * root.width * 0.28
      PathArc {
        x: root.width * 0.5 + root.waveSide * root.width * 0.28
        y: root.waveBaseY - root.waveSide * root.width * 0.28
        radiusX: root.width * 0.28
        radiusY: root.width * 0.28
        direction: PathArc.DirectionClockwise
      }
    }
  }

  Rectangle {
    width: root.width * 0.11
    height: width
    radius: width / 2
    color: root.contentColor
    anchors.horizontalCenter: parent.horizontalCenter
    y: root.waveBaseY - width / 2
  }
}
