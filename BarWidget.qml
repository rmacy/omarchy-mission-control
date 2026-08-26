import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar counterpart of the Mission Control overview. The stock Workspaces
// widget always paints slots 1-5; this one shows exactly the spaces that
// exist: the managed spaces recorded by the overview (which persist across
// Hyprland restarts even while empty) plus every live workspace, so adding
// or removing a space in Mission Control reshapes the bar immediately.
BarWidget {
  id: root
  moduleName: "bitr0t.mission-control"

  // Shared with MissionControl.qml; the overlay owns writes, the bar only
  // reads. watchChanges keeps every per-monitor widget instance in sync the
  // moment the overview saves.
  readonly property string spacesStatePath: Quickshell.env("HOME")
    + "/.local/state/omarchy/mission-control-spaces.json"
  property var managedIds: []

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // Managed spaces first, then any live workspace the overview has not
  // claimed yet. No fixed set: an empty list renders nothing at all.
  readonly property var spaceIds: {
    var ids = root.managedIds.slice()
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function loadManagedSpaces(raw) {
    var values = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) values = parsed
    } catch (_error) { }

    var next = []
    for (var i = 0; i < values.length; i++) {
      var id = Math.floor(Number(values[i]))
      if (id > 0 && id <= 10 && next.indexOf(id) === -1) next.push(id)
    }
    next.sort(function(left, right) { return left - right })

    if (JSON.stringify(next) !== JSON.stringify(root.managedIds)) root.managedIds = next
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function interactionRect(item) {
    if (!item) return null
    var point = item.mapToGlobal(0, 0)
    return {
      x: point.x,
      y: point.y,
      width: item.width,
      height: item.height,
      centerX: point.x + item.width / 2,
      centerY: point.y + item.height / 2
    }
  }

  function interactionGeometry() {
    var spaces = []
    for (var i = 0; i < workspaceButtons.count; i++) {
      var button = workspaceButtons.itemAt(i)
      if (!button) continue
      spaces.push({
        index: i,
        id: Number(button.modelData),
        rect: root.interactionRect(button)
      })
    }
    return JSON.stringify({ spaces: spaces })
  }

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  visible: spaceIds.length > 0
  implicitWidth: spaceIds.length > 0 ? grid.implicitWidth + trailingGap : 0
  implicitHeight: spaceIds.length > 0 ? grid.implicitHeight : 0

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.spaceIds.length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: workspaceButtons
      model: root.spaceIds

      WidgetButton {
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        bar: root.bar
        text: focused ? "\uDB85\uDCFB" : (modelData === 10 ? "0" : String(modelData))
        opacity: occupied || focused ? 1 : 0.5
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.focusWorkspace(modelData) }
      }
    }
  }

  FileView {
    id: spacesStateFile
    path: root.spacesStatePath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadManagedSpaces(text())
    onLoadFailed: if (root.managedIds.length > 0) root.managedIds = []
    onFileChanged: reload()
  }

  IpcHandler {
    target: "bitr0t-mission-control-spaces"
    function geometry(): string { return root.interactionGeometry() }
  }
}
