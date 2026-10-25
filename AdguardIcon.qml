import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Commons.Color.foreground
  property color checkColor: Commons.Color.popups.background
  property bool checked: false

  width: iconSize * 0.92
  height: iconSize
  implicitWidth: width
  implicitHeight: height

  // AdGuard-style shield drawn natively (like the Dropbox diamond) so the
  // tiny bar slot stays crisp without SVG rendering quirks.
  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: root.color
      strokeColor: "transparent"
      strokeWidth: 0
      startX: root.width * 0.5
      startY: root.height * 0.04
      PathLine { x: root.width * 0.94; y: root.height * 0.18 }
      PathLine { x: root.width * 0.94; y: root.height * 0.46 }
      PathQuad { controlX: root.width * 0.92; controlY: root.height * 0.80; x: root.width * 0.5; y: root.height * 0.97 }
      PathQuad { controlX: root.width * 0.08; controlY: root.height * 0.80; x: root.width * 0.06; y: root.height * 0.46 }
      PathLine { x: root.width * 0.06; y: root.height * 0.18 }
      PathLine { x: root.width * 0.5; y: root.height * 0.04 }
    }

    ShapePath {
      // ShapePath has no visible property — hide the check by unstroking it.
      fillColor: "transparent"
      strokeColor: root.checked ? root.checkColor : "transparent"
      strokeWidth: Math.max(1.2, root.width * 0.11)
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      startX: root.width * 0.30
      startY: root.height * 0.52
      PathLine { x: root.width * 0.45; y: root.height * 0.66 }
      PathLine { x: root.width * 0.72; y: root.height * 0.34 }
    }
  }
}
