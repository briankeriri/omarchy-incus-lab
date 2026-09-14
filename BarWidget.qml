import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "keri.incus-lab"

  readonly property string instanceName: String(setting("instance", "omarchy-lab"))
  readonly property string snapshotName: String(setting("snapshot", "golden"))
  readonly property int refreshMs: Math.max(5, Number(setting("refreshIntervalSec", 15))) * 1000
  readonly property string statusScript: localPath("scripts/status.sh")
  readonly property string agentScript: localPath("scripts/lab-agent.sh")
  readonly property string pkgScript: localPath("scripts/lab-pkg.sh")
  readonly property string saveScript: localPath("scripts/lab-save-golden.sh")

  property var report: ({ state: "unknown" })
  readonly property string labState: report && report.state ? String(report.state) : "unknown"
  readonly property bool isolated: !!(report && report.isolated)
  readonly property bool snapshotReady: !!(report && report.hasSnapshot)
  readonly property string barIcon: "󰆧"
  readonly property color statusColor: {
    // This theme sets Color.accent == Color.foreground, so accent cannot
    // mark isolated. Isolated uses accent when it is distinct; otherwise
    // full foreground vs muted idle.
    if (labState === "running" && isolated) {
      if (!Qt.colorEqual(Color.accent, Color.foreground)) return Color.accent
      return Color.foreground
    }
    if (labState === "running" || labState === "no-permission") return Color.urgent
    return Color.muted
  }
  readonly property string tooltipDetail: {
    var iso = isolated ? "isolated" : "not isolated"
    var snap = snapshotReady ? "snapshot ready" : "snapshot missing"
    return "Incus lab · " + labState + " · " + iso + " · " + snap
  }

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function localPath(rel) {
    var u = Qt.resolvedUrl(rel).toString()
    if (u.indexOf("file://") === 0) return decodeURIComponent(u.substring(7))
    return u
  }

  function parseReport(raw) {
    var text = String(raw || "").trim()
    if (text === "") return null
    var lines = text.split("\n")
    var last = String(lines[lines.length - 1] || "").trim()
    var payload = last.indexOf("{") === 0 ? last : text
    try {
      return JSON.parse(payload)
    } catch (e) {
      console.warn("keri.incus-lab", "bad status json", e)
      return null
    }
  }

  function applyReport(next) {
    if (!next) return
    root.report = next
    if (panelLoader.item && panelLoader.item.syncReport)
      panelLoader.item.syncReport(root.report)
  }

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    if ("bar" in target) target.bar = root.bar
    if ("settings" in target) target.settings = root.settings
    if ("anchorItem" in target) target.anchorItem = button
    if ("hostWidget" in target) target.hostWidget = root
    if ("host" in target) target.host = root
    if (target.syncReport) target.syncReport(root.report)
  }

  function refresh() {
    if (statusScript === "" || statusProc.running) return
    statusProc.running = true
  }

  function launchLab() {
    if (agentScript === "") return
    Quickshell.execDetached([agentScript, instanceName, snapshotName])
  }

  function launchPkg() {
    if (pkgScript === "") return
    Quickshell.execDetached([
      "/usr/bin/omarchy-launch-tui",
      "--app-id=org.omarchy.lab-pkg",
      pkgScript,
      instanceName
    ])
  }

  function launchSave() {
    if (saveScript === "") return
    Quickshell.execDetached([
      "/usr/bin/omarchy-launch-tui",
      "--app-id=org.omarchy.lab-save",
      saveScript,
      instanceName,
      snapshotName
    ])
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  // IpcHandler is one-per-target. open/toggle must use Bar.findPanelWidget
  // (focused monitor), same path as `omarchy-shell shell summon <id>`.
  function summonOnFocused() {
    if (root.bar && typeof root.bar.summonBarWidget === "function") {
      root.bar.summonBarWidget(root.moduleName)
      return
    }
    root.open()
  }

  function hideOnFocused() {
    if (root.bar && typeof root.bar.hideBarWidget === "function") {
      root.bar.hideBarWidget(root.moduleName)
      return
    }
    root.close()
  }

  function toggleOnFocused() {
    if (root.bar && typeof root.bar.isBarWidgetOpen === "function") {
      if (root.bar.isBarWidgetOpen(root.moduleName))
        root.hideOnFocused()
      else
        root.summonOnFocused()
      return
    }
    root.togglePanel()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    refresh()
  }
  Component.onCompleted: refresh()

  Timer {
    interval: root.refreshMs
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    running: false
    command: [root.statusScript, root.instanceName, root.snapshotName]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyReport(root.parseReport(text))
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var err = String(text || "").trim()
        if (err !== "") console.warn("keri.incus-lab", err)
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) console.warn("keri.incus-lab", "status exit", exitCode)
    }
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    // Literal target: IpcHandler registers at construction. One handler per
    // target; the peer on the other monitor warns and is unused. refresh
    // broadcasts so both screens pick up the same status.
    target: "keri.incus-lab"
    function refresh(): void { root.broadcast("refresh") }
    function launch(): void { root.launchLab() }
    function installPkgs(): void { root.launchPkg() }
    function saveGolden(): void { root.launchSave() }
    function open(): void { root.summonOnFocused() }
    function close(): void { root.hideOnFocused() }
    function show(): void { root.summonOnFocused() }
    function hide(): void { root.hideOnFocused() }
    function toggle(): void { root.toggleOnFocused() }
    function status(): string { return JSON.stringify(root.report || {}) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.barIcon
    slotSize: Style.bar.statusSlot
    fontSize: Style.font.caption
    foreground: root.statusColor
    tooltipText: root.tooltipDetail

    onPressed: function(b) {
      if (b === Qt.RightButton) root.launchLab()
      else if (b === Qt.MiddleButton) root.refresh()
      else root.togglePanel()
    }
  }
}
