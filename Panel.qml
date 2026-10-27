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
  property bool helpOpen: false
  property bool popupOpen: false

  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color subtleFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.07)
  readonly property color hotFill: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.16)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color barIconColor: tailnet.active ? barForeground : Qt.darker(barForeground, 1.55)
  // This machine is row 0 so the keyboard cursor walks one flat list.
  readonly property var rows: tailnet.active && tailnet.selfDevice ? [tailnet.selfDevice].concat(tailnet.visibleDevices) : []
  readonly property var shortcuts: [
    { key: "↵", text: "SSH" },
    { key: "f", text: "Upload / download" },
    { key: "u", text: "Upload files" },
    { key: "b", text: "Download files" },
    { key: "y", text: "Copy…" },
    { key: "c", text: "Copy IP" },
    { key: "d", text: "Copy alias" },
    { key: "o", text: "Open web service" },
    { key: "r", text: "Refresh and scan" },
    { key: "t", text: "Tailscale on/off" },
    { key: "?", text: "Help" },
    { key: "right click", text: "Icon: on/off" },
    { key: "middle click", text: "Icon: scan" }
  ]

  function selectedRow() {
    if (rows.length === 0) return null
    return rows[Math.max(0, Math.min(rowIndex, rows.length - 1))]
  }

  function selectedRowItem() {
    if (!deviceColumn || rowIndex < 0 || rowIndex >= deviceColumn.children.length) return null
    return deviceColumn.children[rowIndex]
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
    var item = selectedRowItem()
    if (!panelFlick || !item) return
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

  function rescan() {
    tailnet.refresh()
    tailnet.scan()
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

  function copyValue(device, kind) {
    if (!device) return
    if (kind === "ip") tailnet.copyToClipboard(device.ip, device.name + " IP")
    else tailnet.copyToClipboard(device.dnsName, device.name + " alias")
  }

  function popupClosed() {
    popupOpen = false
    if (opened) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    helpOpen = false
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
    function refresh(): string { root.rescan(); return "ok" }
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
      else if (buttonCode === Qt.MiddleButton) root.rescan()
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
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.popupOpen
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.sshTo(root.selectedRow())
      onCloseRequested: {
        if (root.helpOpen) root.helpOpen = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var device = root.selectedRow()
        var item = root.selectedRowItem()
        var key = String(t).toLowerCase()
        if (t === "?") root.helpOpen = !root.helpOpen
        else if (key === "t") tailnet.toggleTailscale()
        else if (key === "r") root.rescan()
        else if (key === "c") root.copyValue(device, "ip")
        else if (key === "d") root.copyValue(device, "alias")
        else if (key === "y") { if (item && item.openCopy) item.openCopy() }
        else if (key === "f") { if (item && item.openTransfer) item.openTransfer() }
        else if (key === "o") tailnet.openFirstWebService(device)
        else if (key === "u") root.transferTo(device, "upload")
        else if (key === "b") root.transferTo(device, "download")
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

          Item {
            id: header
            width: parent.width
            implicitHeight: hero.implicitHeight
            // The hero's trailingControl resolves `root` to PanelHero, so the
            // controls reach panel state through `header`.
            readonly property bool helpOpen: root.helpOpen
            function toggleHelp() { root.helpOpen = !root.helpOpen }
            function rescan() { root.rescan() }

            PanelHero {
              id: hero
              width: parent.width
              title: tailnet.tailnetName !== "" ? tailnet.tailnetName : "Tailnet"
              meta: tailnet.active ? "" : (tailnet.installed ? tailnet.statusText : "Tailscale is not installed")
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconOpacity: tailnet.active ? 1.0 : 0.5
              iconComponent: Component {
                TailscaleIcon {
                  iconSize: Style.font.display
                  color: tailnet.active ? hero.foreground : Qt.darker(hero.foreground, 1.55)
                  badgeColor: Commons.Color.urgent
                  crossed: !tailnet.active && !tailnet.needsLogin
                  warning: tailnet.needsLogin
                }
              }
              trailingControl: Component {
                Row {
                  spacing: Style.space(6)

                  PanelActionButton {
                    id: rescanButton
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tailnet.active
                    // The glyph is drawn below so only it spins; rotating the
                    // button would spin its hover box too.
                    iconText: ""
                    tooltipText: "Refresh and scan"
                    foreground: hero.foreground
                    fontFamily: hero.fontFamily
                    enabled: !tailnet.scanning
                    onClicked: header.rescan()

                    Text {
                      anchors.centerIn: parent
                      text: "󰑐"
                      color: rescanButton.foreground
                      opacity: rescanButton.enabled ? 1.0 : 0.6
                      font.family: rescanButton.fontFamily
                      font.pixelSize: rescanButton.fontSize

                      NumberAnimation on rotation {
                        running: tailnet.scanning
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                      }

                      onRotationChanged: if (!tailnet.scanning && rotation !== 0) rotation = 0
                    }
                  }

                  PanelActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    iconText: header.helpOpen ? "󰅖" : "󰋖"
                    tooltipText: header.helpOpen ? "Close help" : "Shortcuts (?)"
                    foreground: hero.foreground
                    fontFamily: hero.fontFamily
                    onClicked: header.toggleHelp()
                  }

                  ToggleSwitch {
                    id: powerSwitch
                    anchors.verticalCenter: parent.verticalCenter
                    visible: tailnet.installed
                    checked: tailnet.active
                    busy: tailnet.busy
                    foreground: hero.foreground
                    onToggled: tailnet.toggleTailscale()

                    PanelToolTip {
                      visible: powerSwitch.containsMouse
                      text: tailnet.active ? "Turn Tailscale off" : (tailnet.needsLogin ? "Authorize this device" : "Turn Tailscale on")
                      fontFamily: hero.fontFamily
                    }
                  }
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

          GridLayout {
            visible: root.helpOpen
            width: parent.width
            columns: 2
            columnSpacing: Style.space(10)
            rowSpacing: Style.space(6)

            Repeater {
              model: root.helpOpen ? root.shortcuts : []
              delegate: Item {
                required property var modelData
                Layout.fillWidth: true
                implicitHeight: shortcutRow.implicitHeight

                Row {
                  id: shortcutRow
                  spacing: Style.space(8)

                  Rectangle {
                    width: Math.max(Style.space(22), keyText.implicitWidth + Style.space(10))
                    height: keyText.implicitHeight + Style.space(4)
                    radius: Style.cornerRadius
                    color: root.subtleFill
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                      id: keyText
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: modelData.key
                      color: root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    textFormat: Text.PlainText
                    text: modelData.text
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Column {
            id: deviceColumn
            visible: !root.helpOpen && root.rows.length > 0
            width: parent.width
            spacing: Style.space(4)

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

          Text {
            visible: !root.helpOpen && tailnet.active && tailnet.devices.length === 0
            width: parent.width
            text: "No other devices"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
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
    readonly property bool isSelf: device && device.self === true
    readonly property bool remoteOnline: online && !isSelf
    readonly property var services: tailnet.servicesFor(device)
    readonly property string hoverText: {
      if (!device || online) return ""
      var seen = tailnet.relativeTime(device.lastSeen)
      return seen !== "" ? "Offline · seen " + seen : "Offline"
    }

    function openCopy() { copyPopup.open() }
    function closePopups() {
      copyPopup.close()
      transferPopup.close()
    }

    Connections {
      target: root
      function onOpenedChanged() { if (!root.opened) deviceRow.closePopups() }
    }

    function openTransfer() { if (remoteOnline) transferPopup.open() }

    hasCursor: root.cursorActive && root.rowIndex === rowIndex
    foreground: root.foreground
    opacity: online ? 1.0 : 0.5
    implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.setRowCursor(deviceRow.rowIndex)
      onDoubleClicked: root.sshTo(deviceRow.device)
    }

    PanelToolTip {
      visible: deviceRow.hoverText !== "" && rowMouse.containsMouse
      text: deviceRow.hoverText
      fontFamily: root.fontFamily
    }

    RowLayout {
      id: content
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Item {
        Layout.alignment: Qt.AlignTop
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
          color: deviceRow.online ? "#4ade80" : root.dim
          border.color: Commons.Color.background
          border.width: 1
        }
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(4)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: deviceRow.device ? deviceRow.device.name : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: deviceRow.isSelf
          elide: Text.ElideRight
        }

        Flow {
          Layout.fillWidth: true
          visible: deviceRow.services.length > 0
          spacing: Style.space(4)

          Repeater {
            model: deviceRow.services
            ServiceChip {
              required property var modelData
              service: modelData
              device: deviceRow.device
            }
          }
        }
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        visible: deviceRow.remoteOnline
        iconText: "󰣀"
        tooltipText: tailnet.sshLabel(deviceRow.device)
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: root.sshTo(deviceRow.device)
      }

      PanelActionButton {
        id: transferButton
        Layout.alignment: Qt.AlignTop
        visible: deviceRow.remoteOnline
        iconText: "󰓢"
        tooltipText: "Upload / download"
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: transferPopup.open()
      }

      PanelActionButton {
        id: copyButton
        Layout.alignment: Qt.AlignTop
        iconText: "󰆏"
        tooltipText: "Copy"
        enabled: deviceRow.device && (deviceRow.device.ip !== "" || deviceRow.device.dnsName !== "")
        foreground: root.foreground
        fontFamily: root.fontFamily
        onClicked: copyPopup.open()
      }
    }

    MiniPopup {
      id: transferPopup
      anchorButton: transferButton
      // 0 = upload (left), 1 = download (right)
      property int choice: 0
      onOpened: choice = 0
      onKey: function(event) {
        if (event.key === Qt.Key_Left || event.text === "h" || event.text === "u") choice = 0
        else if (event.key === Qt.Key_Right || event.text === "l" || event.text === "b") choice = 1
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          close()
          root.transferTo(deviceRow.device, choice === 0 ? "upload" : "download")
        } else return
        event.accepted = true
      }

      Row {
        spacing: Style.space(6)
        padding: Style.space(6)

        TransferTile {
          iconText: "󰕒"
          label: "Upload"
          selected: transferPopup.choice === 0
          onHovered: transferPopup.choice = 0
          onChosen: { transferPopup.close(); root.transferTo(deviceRow.device, "upload") }
        }

        TransferTile {
          iconText: "󰇚"
          label: "Download"
          selected: transferPopup.choice === 1
          onHovered: transferPopup.choice = 1
          onChosen: { transferPopup.close(); root.transferTo(deviceRow.device, "download") }
        }
      }
    }

    MiniPopup {
      id: copyPopup
      anchorButton: copyButton
      property int choice: 0
      readonly property var options: {
        var result = []
        if (deviceRow.device && deviceRow.device.ip !== "") result.push({ kind: "ip", label: "IP", value: deviceRow.device.ip })
        if (deviceRow.device && deviceRow.device.dnsName !== "") result.push({ kind: "alias", label: "Alias", value: deviceRow.device.dnsName })
        return result
      }
      onOpened: choice = 0
      onKey: function(event) {
        if (event.key === Qt.Key_Down || event.text === "j") choice = Math.min(options.length - 1, choice + 1)
        else if (event.key === Qt.Key_Up || event.text === "k") choice = Math.max(0, choice - 1)
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
          if (options.length > 0) root.copyValue(deviceRow.device, options[choice].kind)
          close()
        } else return
        event.accepted = true
      }

      Column {
        width: Style.space(260)

        Repeater {
          model: copyPopup.options
          CopyChoice {
            required property var modelData
            required property int index
            width: Style.space(260)
            label: modelData.label
            value: modelData.value
            selected: copyPopup.choice === index
            onHovered: copyPopup.choice = index
            onChosen: { root.copyValue(deviceRow.device, modelData.kind); copyPopup.close() }
          }
        }
      }
    }
  }

  // Small floating card under a row button. Owns its key handling so the
  // panel's key catcher stays out of the way while it is open.
  component MiniPopup: Popup {
    id: miniPopup
    property Item anchorButton: null
    default property alias body: miniBody.data
    signal key(var event)

    parent: anchorButton
    x: anchorButton ? anchorButton.width - width : 0
    y: anchorButton ? anchorButton.height + Style.space(4) : 0
    padding: 0
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    onOpenedChanged: {
      if (opened) {
        root.popupOpen = true
        Qt.callLater(function() { miniBody.forceActiveFocus() })
      } else {
        root.popupClosed()
      }
    }

    background: BorderSurface {
      color: Commons.Color.background
      borderSpec: Border.flat(root.dim, 1)
      radius: Style.cornerRadius
    }

    contentItem: Item {
      id: miniBody
      implicitWidth: childrenRect.width
      implicitHeight: childrenRect.height
      focus: true
      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { miniPopup.close(); event.accepted = true; return }
        miniPopup.key(event)
      }
    }
  }

  component TransferTile: Rectangle {
    id: tile
    signal chosen()
    signal hovered()
    property string iconText: ""
    property string label: ""
    property bool selected: false

    width: Style.space(96)
    height: Style.space(72)
    radius: Style.cornerRadius
    color: selected || tileMouse.containsMouse ? root.hotFill : root.subtleFill

    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: tile.iconText
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.heading
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: tile.label
        color: tile.selected ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: tileMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: tile.hovered()
      onClicked: tile.chosen()
    }
  }

  component CopyChoice: CursorSurface {
    id: copyChoice
    signal chosen()
    signal hovered()
    property string label: ""
    property string value: ""
    property bool selected: false

    foreground: root.foreground
    hasCursor: selected
    radius: 0
    implicitHeight: choiceColumn.implicitHeight + Style.space(14)

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: copyChoice.hovered()
      onClicked: copyChoice.chosen()
    }

    Column {
      id: choiceColumn
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(12)
      anchors.rightMargin: Style.space(12)
      spacing: Style.space(1)

      Text {
        textFormat: Text.PlainText
        text: copyChoice.label
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: copyChoice.value
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideMiddle
      }
    }
  }

  component ServiceChip: Rectangle {
    id: chip
    property var service: null
    property var device: null
    readonly property bool funnel: service && service.kind === "funnel"
    readonly property bool clickable: service && (service.url !== "" || service.ssh)

    implicitWidth: chipText.implicitWidth + Style.space(10)
    implicitHeight: chipText.implicitHeight + Style.space(2)
    radius: Style.cornerRadius
    color: chipMouse.containsMouse ? root.hotFill : root.subtleFill
    border.width: funnel ? 1 : 0
    border.color: root.urgent

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.service ? chip.service.label : ""
      color: chipMouse.containsMouse ? root.foreground : root.dim
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
      text: chip.service ? chip.service.detail : ""
      fontFamily: root.fontFamily
    }
  }
}
