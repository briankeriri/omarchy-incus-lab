import QtQuick
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "keri.incus-lab"
  ipcTarget: "keri.incus-lab"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var host: null
  property var report: ({ state: "unknown" })
  readonly property var barIdentity: hostWidget || root
  readonly property color contentForeground: bar ? bar.foreground : Color.foreground
  readonly property string contentFontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property string labState: report && report.state ? String(report.state) : "unknown"
  readonly property bool isolated: !!(report && report.isolated)
  readonly property bool hasSnapshot: !!(report && report.hasSnapshot)
  readonly property bool hasType: !!(report && report.type)
  readonly property string headline: {
    if (labState === "running" && isolated) return "Isolated VM"
    if (labState === "running") return "VM on NAT"
    if (labState === "stopped") return "VM stopped"
    if (labState === "missing-incus") return "Incus not installed"
    if (labState === "missing-instance") return "No lab instance"
    if (labState === "no-permission") return "No Incus socket"
    return "Lab unknown"
  }
  readonly property string detail: {
    if (labState === "missing-incus")
      return "Install Incus, then build omarchy-lab. This widget will not create a VM."
    if (labState === "missing-instance")
      return "Instance " + String(report.instance || "omarchy-lab") + " does not exist."
    if (labState === "no-permission")
      return "This widget hops the socket via newgrp. Re-login only for a raw incus in a new terminal."
    if (!hasSnapshot)
      return "Golden snapshot " + String(report.snapshot || "golden") + " is missing. This widget will not invent one."
    if (labState === "stopped")
      return "Golden snapshot is ready."
    if (labState === "running" && !isolated)
      return "Still on incusbr0. Isolate before calling this golden."
    return "Restore golden, install packages from this PC, or save a new isolated golden."
  }
  readonly property bool canLaunch: (labState === "running" || labState === "stopped") && hasSnapshot
  readonly property bool canInstall: labState === "running" || labState === "stopped"
  readonly property bool canSave: (labState === "running" || labState === "stopped") && isolated

  function syncReport(next) {
    if (next) report = next
  }

  function open() {
    if (host && host.refresh) host.refresh()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  function launchLab() {
    if (host && host.launchLab) host.launchLab()
    root.close()
  }

  function launchPkg() {
    if (host && host.launchPkg) host.launchPkg()
    root.close()
  }

  function launchSave() {
    if (host && host.launchSave) host.launchSave()
    root.close()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(body.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onReturnRequested: if (root.canLaunch) root.launchLab()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: body
        x: Style.space(16)
        width: parent.width - Style.space(32)
        spacing: Style.space(12)

        Row {
          spacing: Style.space(12)

          OpticalGlyph {
            text: "󰆧"
            fontFamily: root.contentFontFamily
            fontSize: Style.font.display
            color: root.contentForeground
          }

          Column {
            spacing: Style.space(4)

            Text {
              text: root.headline
              color: root.contentForeground
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.title
              font.bold: true
            }

            Text {
              width: Style.space(280)
              text: root.detail
              wrapMode: Text.WordWrap
              color: root.contentForeground
              opacity: 0.8
              font.family: root.contentFontFamily
              font.pixelSize: Style.font.body
            }
          }
        }

        Text {
          visible: root.hasType
          text: [root.report.type, root.report.instance, root.report.snapshot].filter(function(x) { return x && x !== "" }).join(" · ")
          color: root.contentForeground
          opacity: 0.6
          font.family: root.contentFontFamily
          font.pixelSize: Style.font.caption
        }

        LabAction {
          label: root.canLaunch ? "Restore golden + agent" : "Unavailable"
          ready: root.canLaunch
          onActivated: root.launchLab()
        }

        LabAction {
          label: root.canInstall ? "Install packages from this PC" : "Unavailable"
          ready: root.canInstall
          onActivated: root.launchPkg()
        }

        LabAction {
          label: root.canSave ? "Save isolated snapshot as golden" : "Isolate before saving"
          ready: root.canSave
          onActivated: root.launchSave()
        }
      }
    }
  }

  component LabAction: MouseArea {
    id: action
    property string label: ""
    property bool ready: false
    signal activated()

    width: parent.width - Style.space(32)
    height: Style.space(36)
    enabled: action.ready
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: action.activated()

    Rectangle {
      anchors.fill: parent
      radius: 6
      color: parent.enabled ? Color.accent : root.contentForeground
      opacity: parent.enabled ? 1 : 0.2
    }

    Text {
      anchors.centerIn: parent
      text: action.label
      color: parent.enabled ? Color.background : root.contentForeground
      font.family: root.contentFontFamily
      font.pixelSize: Style.font.body
      font.bold: true
    }
  }
}
