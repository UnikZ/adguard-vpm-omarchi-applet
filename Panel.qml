import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "unikz.adguardvpn"
  ipcTarget: "unikz.adguardvpn"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: vpn.active ? foreground : dim
  readonly property string toggleHint: vpn.active ? "Disconnect VPN" : "Connect VPN"
  readonly property color barIconColor: vpn.active ? barForeground : Qt.darker(barForeground, 1.55)
  readonly property bool socksMode: vpn.mode === "socks"

  // Locations render in chunks as you scroll; ping-sorted means anything
  // worth clicking is near the top anyway. Reset on every panel open.
  property int locationLimit: 20

  function toggleVpn() {
    if (vpn.installed && !vpn.busy) vpn.toggle()
  }

  function isActiveLocation(loc) {
    if (!loc || !vpn.running || vpn.location === "") return false
    return Model.sameCity(loc.city, vpn.location)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    vpn.refresh()
    vpn.refreshLocations()
    locationLimit = 20
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: vpn
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
    function start(): string { vpn.connect(); return "ok" }
    function stop(): string { vpn.disconnect(); return "ok" }
    function connectTo(city: string): string { vpn.connectTo(city); return "ok" }
    function fastest(): string { vpn.connectFastest(); return "ok" }
    function status(): string { return vpn.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        AdguardIcon {
          anchors.centerIn: parent
          iconSize: Style.space(12)
          outlineColor: root.barIconColor
          contentColor: root.barIconColor
          opacity: vpn.active ? 1.0 : 0.6
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.toggleVpn()
      else if (buttonCode === Qt.MiddleButton) vpn.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {}
      onActivateRequested: root.toggleVpn()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") { vpn.refresh(); vpn.refreshLocations() }
        else if (t === "t" || t === "T") root.toggleVpn()
        else if (t === "f" || t === "F") vpn.connectFastest()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        // Reaching the bottom grows the catalog by one chunk; unseen rows
        // never instantiate, so 80 locations cost 20 delegates until asked.
        onAtYEndChanged: if (atYEnd) {
          var total = vpn.catalogLocations.length
          if (locationLimit < total) locationLimit = Math.min(locationLimit + 20, total)
        }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "AdGuard VPN"
            meta: !vpn.installed ? "CLI not found" : vpn.loginRequired ? "Not logged in" : vpn.active ? (vpn.location !== "" ? vpn.location : "Connected") : "Disconnected"
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: vpn.active ? 1.0 : 0.5
            iconComponent: Component {
              AdguardIcon {
                iconSize: Style.font.display
                outlineColor: root.iconColor
                contentColor: vpn.active ? Commons.Color.accent : root.iconColor
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: vpn.installed && !vpn.loginRequired
                checked: vpn.active
                busy: vpn.busy
                foreground: hero.foreground
                onToggled: root.toggleVpn()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: root.toggleHint
                  fontFamily: hero.fontFamily
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.actionStatus !== "" || vpn.lastError !== ""
            width: parent.width
            text: vpn.actionStatus !== "" ? vpn.actionStatus : vpn.lastError
            color: vpn.lastError !== "" && vpn.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: vpn.warnings.length > 0
            width: parent.width
            text: vpn.warnings.join("\n")
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          Column {
            visible: vpn.installed
            width: parent.width
            spacing: Style.spacing.labelGap

            InfoPair { label: "Status"; value: vpn.statusText }
            InfoPair { label: "Location"; value: vpn.location !== "" ? vpn.location : "—" }
            InfoPair { label: "Mode"; value: Model.modeLabel(vpn.mode) }
            InfoPair { label: "Proxy"; value: root.socksMode && vpn.proxyAddress !== "" ? vpn.proxyUri() : "—" }
          }

          PanelSeparator {
            visible: vpn.installed && !vpn.loginRequired
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && !vpn.loginRequired
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "LOCATIONS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              visible: vpn.locationsRefreshing && vpn.locations.length === 0
              width: parent.width
              text: "Measuring pings…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            LocationRow {
              width: parent.width
              city: "Fastest"
              country: "Lowest ping estimate"
              ping: -1
              isActive: false
              showStar: false
              enabled: !vpn.busy
              onChoose: vpn.connectFastest()
            }

            Column {
              visible: vpn.favoriteLocations.length > 0
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.favoriteLocations

                LocationRow {
                  required property var modelData
                  width: parent.width
                  city: modelData.city
                  country: modelData.country
                  ping: modelData.ping
                  isActive: root.isActiveLocation(modelData)
                  starred: true
                  enabled: !vpn.busy
                  onChoose: vpn.connectTo(modelData.city)
                  onToggleStar: vpn.toggleFavorite(modelData.city)
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: vpn.catalogLocations.slice(0, locationLimit)

                LocationRow {
                  required property var modelData
                  width: parent.width
                  city: modelData.city
                  country: modelData.country
                  ping: modelData.ping
                  isActive: root.isActiveLocation(modelData)
                  starred: false
                  enabled: !vpn.busy
                  onChoose: vpn.connectTo(modelData.city)
                  onToggleStar: vpn.toggleFavorite(modelData.city)
                }
              }
            }
          }
        }
      }
    }
  }

  component LocationRow: CursorSurface {
    id: locationRow

    property string city: ""
    property string country: ""
    property int ping: -1
    property bool isActive: false
    property bool starred: false
    property bool showStar: true
    signal choose()
    signal toggleStar()

    foreground: root.foreground

    implicitHeight: locationContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: parent.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: if (parent.enabled) locationRow.choose()
    }

    RowLayout {
      id: locationContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      // Star button inside the layout: beside the name, vertically
      // centered, with its own click target so favoriting never connects.
      Item {
        visible: locationRow.showStar
        implicitWidth: Style.font.icon + Style.space(4)
        implicitHeight: Style.font.icon
        Layout.alignment: Qt.AlignVCenter

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: locationRow.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: if (locationRow.enabled) locationRow.toggleStar()
        }

        Text {
          anchors.centerIn: parent
          text: locationRow.starred ? "★" : "☆"
          color: locationRow.starred ? Commons.Color.accent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: locationRow.city
          color: locationRow.isActive ? Commons.Color.accent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: locationRow.isActive
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: locationRow.country
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Text {
        textFormat: Text.PlainText
        visible: locationRow.ping >= 0
        text: locationRow.ping + " ms"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }

      Text {
        textFormat: Text.PlainText
        visible: locationRow.isActive
        text: "●"
        color: Commons.Color.accent
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        Layout.alignment: Qt.AlignVCenter
      }
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    InfoLabel { text: label }
    Item { width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2); height: 1 }
    InfoValue { text: value }
  }

  component InfoLabel: Text {
    textFormat: Text.PlainText
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component InfoValue: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }
}
