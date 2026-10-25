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

  function toggleVpn() {
    if (vpn.installed && !vpn.busy) vpn.toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    vpn.refresh()
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
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { vpn.refresh(); return "ok" }
    function start(): string { vpn.connect(); return "ok" }
    function stop(): string { vpn.disconnect(); return "ok" }
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(400))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {}
      onActivateRequested: root.toggleVpn()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") vpn.refresh()
        else if (t === "t" || t === "T") root.toggleVpn()
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

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "AdGuard VPN"
            meta: !vpn.installed ? "CLI not found" : vpn.active ? (vpn.location !== "" ? vpn.location : "Connected") : "Disconnected"
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
                visible: vpn.installed
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
            visible: vpn.installed && root.socksMode
            foreground: root.foreground
          }

          Column {
            visible: vpn.installed && root.socksMode
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "SOCKS USAGE"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              text: "Only apps pointed at the proxy go through the VPN. Everything else stays direct."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }

            CopyRow {
              width: parent.width
              label: "Proxy address"
              value: vpn.proxyUri()
              glyph: "󰆏"
            }

            CopyRow {
              width: parent.width
              label: "Test in terminal"
              value: "curl --proxy socks5h://" + vpn.proxyAddress + " https://api.ipify.org"
              glyph: "󰛢"
            }
          }
        }
      }
    }
  }

  component CopyRow: CursorSurface {
    id: copyRow
    property string label: ""
    property string value: ""
    property string glyph: "󰆏"

    foreground: root.foreground

    implicitHeight: copyRowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: copyRow.value !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
      enabled: copyRow.value !== ""
      onClicked: vpn.copyToClipboard(copyRow.value)
    }

    RowLayout {
      id: copyRowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        text: copyRow.glyph
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: copyRow.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: copyRow.value
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }

      PanelActionButton {
        iconText: "󰆏"
        foreground: root.foreground
        fontFamily: root.fontFamily
        enabled: copyRow.value !== ""
        Layout.alignment: Qt.AlignVCenter
        onClicked: vpn.copyToClipboard(copyRow.value)
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
