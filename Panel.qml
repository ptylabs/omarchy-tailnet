import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

Panel {
  id: root
  moduleName: "ptylabs.tailnet"
  ipcTarget: "ptylabs.tailnet"
  manageIpc: false

  property int rowIndex: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: tailnet.active ? barForeground : Qt.darker(barForeground, 1.55)
  // This machine is row 0 so the keyboard cursor walks one flat list.
  readonly property var rows: tailnet.active && tailnet.selfDevice ? [tailnet.selfDevice].concat(tailnet.visibleDevices) : []
  readonly property string heroMeta: {
    if (!tailnet.installed) return "Tailscale no está instalado"
    if (!tailnet.active) return tailnet.statusText
    var parts = []
    if (tailnet.magicDnsSuffix !== "") parts.push(tailnet.magicDnsSuffix)
    parts.push(tailnet.onlineCount + "/" + tailnet.devices.length + " en línea")
    return parts.join(" · ")
  }

  function selectedRow() {
    if (rows.length === 0) return null
    return rows[Math.max(0, Math.min(rowIndex, rows.length - 1))]
  }

  function ensureCursor() {
    if (rowIndex >= rows.length) rowIndex = Math.max(0, rows.length - 1)
  }

  function moveCursor(dy) {
    cursorActive = true
    rowIndex = Math.max(0, Math.min(rows.length - 1, rowIndex + dy))
    scrollCursorIntoView()
  }

  function setRowCursor(index) {
    cursorActive = true
    rowIndex = index
  }

  function scrollCursorIntoView() {
    if (!panelFlick || !deviceColumn || rowIndex < 0 || rowIndex >= deviceColumn.children.length) return
    var item = deviceColumn.children[rowIndex]
    Qt.callLater(function() {
      if (!item) return
      var margin = Style.space(6)
      var top = item.mapToItem(panelFlick.contentItem, 0, 0).y
      var bottom = top + item.height
      var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
      if (top < panelFlick.contentY + margin) panelFlick.contentY = Math.max(0, top - margin)
      else if (bottom > panelFlick.contentY + panelFlick.height - margin) panelFlick.contentY = Math.min(maxY, bottom + margin - panelFlick.height)
    })
  }

  function sshTo(device) {
    if (!tailnet.canSsh(device)) return
    tailnet.openSsh(device)
    close()
  }

  function transferTo(device, mode) {
    if (!tailnet.canSsh(device)) return
    tailnet.transfer(device, mode)
    close()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    if (panelFlick) panelFlick.contentY = 0
    tailnet.refresh()
    tailnet.scanIfStale()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }
  onRowsChanged: ensureCursor()

  Service {
    id: tailnet
    settings: root.settings
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { tailnet.refresh(); tailnet.scan(); return "ok" }
    function status(): string { return tailnet.statusText }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        TailscaleIcon {
          anchors.centerIn: parent
          iconSize: Style.space(11)
          color: root.barIconColor
          badgeColor: root.urgent
          crossed: !tailnet.active && !tailnet.needsLogin
          warning: tailnet.needsLogin
        }
      }
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) tailnet.toggleTailscale()
      else if (buttonCode === Qt.MiddleButton) { tailnet.refresh(); tailnet.scan() }
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
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.sshTo(root.selectedRow())
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var device = root.selectedRow()
        if (t === "t" || t === "T") tailnet.toggleTailscale()
        else if (t === "r" || t === "R") { tailnet.refresh(); tailnet.scan() }
        else if (t === "c" || t === "C") { if (device) tailnet.copyToClipboard(device.ip, device.name + " IP") }
        else if (t === "d" || t === "D") { if (device) tailnet.copyToClipboard(device.dnsName, device.name + " DNS") }
        else if (t === "o" || t === "O") tailnet.openFirstWebService(device)
        else if (t === "u" || t === "U") root.transferTo(device, "upload")
        else if (t === "b" || t === "B") root.transferTo(device, "download")
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
            title: tailnet.tailnetName !== "" ? tailnet.tailnetName : "Tailnet"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: tailnet.active ? 1.0 : 0.5
            iconComponent: Component {
              TailscaleIcon {
                iconSize: Style.font.display
                color: tailnet.active ? root.foreground : root.dim
                badgeColor: root.urgent
                crossed: !tailnet.active && !tailnet.needsLogin
                warning: tailnet.needsLogin
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: powerSwitch
                visible: tailnet.installed
                checked: tailnet.active
                busy: tailnet.busy
                foreground: root.foreground
                onToggled: tailnet.toggleTailscale()

                PanelToolTip {
                  visible: powerSwitch.containsMouse
                  text: tailnet.active ? "Desactivar Tailscale" : (tailnet.needsLogin ? "Autorizar este equipo" : "Activar Tailscale")
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: tailnet.actionStatus !== "" ? tailnet.actionStatus : tailnet.lastError
            color: tailnet.actionStatus === "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          PanelSeparator {
            visible: root.rows.length > 0
            foreground: root.foreground
          }

          Column {
            visible: root.rows.length > 0
            width: parent.width
            spacing: Style.space(10)

            RowLayout {
              width: parent.width

              PanelSectionHeader {
                Layout.fillWidth: true
                text: "DISPOSITIVOS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                textFormat: Text.PlainText
                text: tailnet.scanning ? "escaneando servicios…" : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              PanelActionButton {
                iconText: "󰑐"
                tooltipText: "Actualizar y escanear (r)"
                foreground: root.foreground
                fontFamily: root.fontFamily
                enabled: !tailnet.scanning
                onClicked: { tailnet.refresh(); tailnet.scan() }
              }
            }

            Column {
              id: deviceColumn
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: root.rows
                DeviceRow {
                  required property var modelData
                  required property int index
                  width: deviceColumn.width
                  device: modelData
                  rowIndex: index
                }
              }
            }
          }

          Text {
            visible: tailnet.active && tailnet.devices.length === 0
            width: parent.width
            text: "No hay otros dispositivos en este tailnet."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Text {
            visible: tailnet.active
            width: parent.width
            text: "↵ ssh · u subir · b bajar · c copiar IP · d copiar DNS · o abrir web · r escanear · t on/off"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  component DeviceRow: CursorSurface {
    id: deviceRow
    property var device: null
    property int rowIndex: 0
    readonly property bool online: device && device.online === true
    readonly property var services: tailnet.servicesFor(device)
    readonly property string subtitle: {
      if (!device) return ""
      var parts = []
      if (device.self) parts.push("este equipo")
      if (device.ip !== "") parts.push(device.ip)
      if (device.dnsName !== "") parts.push(device.dnsName)
      if (!online) {
        var seen = tailnet.relativeTime(device.lastSeen)
        parts.push(seen !== "" ? "visto " + seen : "offline")
      }
      return parts.join(" · ")
    }
    readonly property string servicesHint: {
      if (!online) return ""
      if (!tailnet.hasScanned(device)) return tailnet.scanning ? "escaneando…" : "sin escanear"
      return services.length === 0 ? "sin servicios detectados" : ""
    }

    hasCursor: root.cursorActive && root.rowIndex === rowIndex
    current: device && device.self === true
    foreground: root.foreground
    opacity: online ? 1.0 : 0.55
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setRowCursor(deviceRow.rowIndex)
      onDoubleClicked: root.sshTo(deviceRow.device)
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(8)
      spacing: Style.space(8)

      Item {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Style.space(2)
        implicitWidth: Style.space(22)
        implicitHeight: osGlyph.implicitHeight

        Text {
          id: osGlyph
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          textFormat: Text.PlainText
          text: tailnet.osIcon(deviceRow.device ? deviceRow.device.os : "")
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.icon
        }

        Rectangle {
          width: Style.space(7)
          height: width
          radius: width / 2
          anchors.right: osGlyph.right
          anchors.bottom: osGlyph.bottom
          anchors.rightMargin: -Style.space(2)
          color: deviceRow.online ? "#4ade80" : root.dim
          border.color: Commons.Color.background
          border.width: 1
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: deviceRow.device ? deviceRow.device.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: deviceRow.device && deviceRow.device.self === true
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: deviceRow.subtitle
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }

        Flow {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: deviceRow.services.length > 0 || deviceRow.servicesHint !== ""
          spacing: Style.space(4)

          Repeater {
            model: deviceRow.services
            ServiceChip {
              required property var modelData
              service: modelData
              device: deviceRow.device
            }
          }

          Text {
            visible: deviceRow.servicesHint !== ""
            textFormat: Text.PlainText
            text: deviceRow.servicesHint
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.italic: true
          }
        }
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        visible: deviceRow.device && deviceRow.device.self !== true
        iconText: "󰣀"
        tooltipText: tailnet.canSsh(deviceRow.device) ? tailnet.sshLabel(deviceRow.device) : "Sin conexión"
        enabled: tailnet.canSsh(deviceRow.device)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.sshTo(deviceRow.device)
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        visible: deviceRow.device && deviceRow.device.self !== true
        iconText: "󰕒"
        tooltipText: "Subir archivos (u)"
        enabled: tailnet.canSsh(deviceRow.device)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.transferTo(deviceRow.device, "upload")
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        visible: deviceRow.device && deviceRow.device.self !== true
        iconText: "󰇚"
        tooltipText: "Descargar archivos (b)"
        enabled: tailnet.canSsh(deviceRow.device)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.transferTo(deviceRow.device, "download")
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        iconText: "󰆏"
        tooltipText: "Copiar IP"
        enabled: deviceRow.device && deviceRow.device.ip !== ""
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: tailnet.copyToClipboard(deviceRow.device.ip, deviceRow.device.name + " IP")
      }
    }
  }

  component ServiceChip: Rectangle {
    id: chip
    property var service: null
    property var device: null
    readonly property bool funnel: service && service.kind === "funnel"
    readonly property bool clickable: service && (service.url !== "" || service.ssh)

    implicitWidth: chipText.implicitWidth + Style.space(12)
    implicitHeight: chipText.implicitHeight + Style.space(4)
    radius: Style.cornerRadius
    color: chipMouse.containsMouse ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.16)
                                   : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.07)
    border.width: 1
    border.color: funnel ? root.urgent : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.18)

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.service ? chip.service.label : ""
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        tailnet.openService(chip.device, chip.service)
        if (chip.clickable) root.close()
      }
    }

    PanelToolTip {
      visible: chipMouse.containsMouse
      text: chip.service ? (chip.service.detail + (chip.service.ssh ? " · abrir SSH" : (chip.service.url !== "" ? " · abrir" : " · copiar"))) : ""
      fontFamily: root.fontFamily
    }
  }
}
