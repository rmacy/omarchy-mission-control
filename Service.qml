import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "WindowModel.js" as WindowModel

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  readonly property string ownerToken: "bitr0t.omarchy-mission-control-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false

  readonly property string spacesStatePath: Quickshell.env("HOME")
    + "/.local/state/omarchy/mission-control-spaces.json"
  property var managedWorkspaceIds: []
  property bool spacesLoaded: false
  readonly property string spaceNamesPath: Quickshell.env("HOME")
    + "/.local/state/omarchy/mission-control-space-names.json"
  property var spaceNames: ({})
  property bool namesLoaded: false

  function normalizedManagedSpaces(values) {
    return WindowModel.workspaceIds([], -1, -1, values)
  }

  function loadManagedSpaces(raw) {
    var values = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) values = parsed
    } catch (_error) { }
    var next = root.normalizedManagedSpaces(values)
    if (JSON.stringify(next) !== JSON.stringify(root.managedWorkspaceIds))
      root.managedWorkspaceIds = next
    root.spacesLoaded = true
  }

  function setManagedSpaces(values) {
    var next = root.normalizedManagedSpaces(values)
    if (JSON.stringify(next) !== JSON.stringify(root.managedWorkspaceIds))
      root.managedWorkspaceIds = next
    root.spacesLoaded = true
    spacesStateFile.setText(JSON.stringify(next) + "\n")
    return next
  }

  function normalizedSpaceNames(values) {
    var source = values && typeof values === "object" ? values : ({})
    var next = ({})
    for (var key in source) {
      var id = Math.floor(Number(key))
      var name = WindowModel.normalizedSpaceName(source[key], 32)
      if (id > 0 && id <= 10 && name) next[String(id)] = name
    }
    return next
  }

  function loadSpaceNames(raw) {
    var values = ({})
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed))
        values = parsed
    } catch (_error) { }
    var next = root.normalizedSpaceNames(values)
    if (JSON.stringify(next) !== JSON.stringify(root.spaceNames))
      root.spaceNames = next
    root.namesLoaded = true
  }

  function setSpaceNames(values) {
    var next = root.normalizedSpaceNames(values)
    if (JSON.stringify(next) !== JSON.stringify(root.spaceNames))
      root.spaceNames = next
    root.namesLoaded = true
    spaceNamesFile.setText(JSON.stringify(next) + "\n")
    return next
  }

  function spaceName(workspaceId) {
    return String(root.spaceNames[String(Math.floor(Number(workspaceId)))] || "")
  }

  function setSpaceName(workspaceId, value) {
    var id = Math.floor(Number(workspaceId))
    if (id <= 0 || id > 10) return ""
    var next = JSON.parse(JSON.stringify(root.spaceNames || ({})))
    var name = WindowModel.normalizedSpaceName(value, 32)
    if (name) next[String(id)] = name
    else delete next[String(id)]
    root.setSpaceNames(next)
    return name
  }

  function remapNames(currentIds, desiredIds) {
    return root.setSpaceNames(
      WindowModel.remapSpaceNames(root.spaceNames, currentIds, desiredIds))
  }

  function removeGestureLua() {
    return 'hl.gesture({ fingers = 3, direction = "up", mods = "", scale = 1.0, action = "unset" })'
  }

  function applyLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      '_G.bitr0t_omarchy_mission_control_owner = owner',
      'hl.unbind("CTRL + UP")',
      'hl.unbind("CTRL + DOWN")',
      'hl.bind("CTRL + UP",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell summon bitr0t.omarchy-mission-control {}"),',
      '  { description = "Open Mission Control" })',
      'hl.bind("CTRL + DOWN",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell hide bitr0t.omarchy-mission-control"),',
      '  { description = "Close Mission Control" })',
      'hl.gesture({',
      '  fingers = 3,',
      '  direction = "up",',
      '  mods = "",',
      '  scale = 1.0,',
      '  action = function()',
      '    hl.exec_cmd("omarchy-shell -q shell summon bitr0t.omarchy-mission-control {}")',
      '  end',
      '})'
    ].join("\n")
  }

  function cleanupLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      'if _G.bitr0t_omarchy_mission_control_owner == owner then',
      '  _G.bitr0t_omarchy_mission_control_owner = nil',
      '  hl.unbind("CTRL + UP")',
      '  hl.unbind("CTRL + DOWN")',
      '  hl.gesture({ fingers = 3, direction = "up", mods = "", scale = 1.0, action = "unset" })',
      'end'
    ].join("\n")
  }

  function queueApply() {
    if (!root.shuttingDown) applyTimer.restart()
  }

  function applyBindings() {
    if (root.shuttingDown) return
    if (removeGestureProcess.running || applyProcess.running) {
      root.applyQueued = true
      return
    }

    root.applyQueued = false
    removeGestureProcess.command = ["hyprctl", "eval", root.removeGestureLua()]
    removeGestureProcess.running = true
  }

  function startApply() {
    if (root.shuttingDown) return
    applyProcess.command = ["hyprctl", "eval", root.applyLua()]
    applyProcess.running = true
  }

  Timer {
    id: applyTimer
    interval: 100
    repeat: false
    onTriggered: root.applyBindings()
  }

  Process {
    id: removeGestureProcess
    onExited: root.startApply()
  }

  Process {
    id: applyProcess
    stdout: StdioCollector { id: applyStdout; waitForEnd: true }
    stderr: StdioCollector { id: applyStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.shuttingDown) return
      if (exitCode !== 0) {
        var detail = String(applyStdout.text || applyStderr.text || "").trim()
        console.warn("bitr0t.omarchy-mission-control: failed to register shortcut and gesture (exit "
          + exitCode + ")" + (detail ? ": " + detail : ""))
      }
      if (root.applyQueued) root.queueApply()
    }
  }

  // Alt-Tab registration is delegated to a dedicated binding component.
  // On integrated teardown it launches nothing itself; the destruction
  // handler below sequences its cleanupScript with this service's own
  // cleanup and the single restoring reload in one detached command.
  AltTabService {
    id: altTabService
    shell: root.shell
    integrationMode: true
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.queueApply()
    }
  }

  Component.onCompleted: {
    root.queueApply()
  }

  FileView {
    id: spacesStateFile
    path: root.spacesStatePath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadManagedSpaces(text())
    onLoadFailed: if (!root.spacesLoaded) {
      root.managedWorkspaceIds = []
      root.spacesLoaded = true
    }
    onFileChanged: reload()
  }

  FileView {
    id: spaceNamesFile
    path: root.spaceNamesPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadSpaceNames(text())
    onLoadFailed: if (!root.namesLoaded) {
      root.spaceNames = ({})
      root.namesLoaded = true
    }
    onFileChanged: reload()
  }

  IpcHandler {
    target: "bitr0t-omarchy-mission-control-state"

    function get(): string {
      return JSON.stringify(root.managedWorkspaceIds)
    }

    function set(ids: string): string {
      var raw = String(ids || "").trim()
      var values = raw ? raw.split(":") : []
      for (var i = 0; i < values.length; i++) {
        if (!/^\d+$/.test(values[i])) return "invalid"
        values[i] = Number(values[i])
      }
      return JSON.stringify(root.setManagedSpaces(values))
    }

    function names(): string {
      return JSON.stringify(root.spaceNames)
    }

    function name(id: string): string {
      return root.spaceName(id)
    }

    function rename(id: string, value: string): string {
      return root.setSpaceName(id, value)
    }

    function clearName(id: string): string {
      return root.setSpaceName(id, "")
    }

    function clearNames(): string {
      return JSON.stringify(root.setSpaceNames(({})))
    }
  }

  Component.onDestruction: {
    root.shuttingDown = true
    applyTimer.stop()
    if (removeGestureProcess.running) removeGestureProcess.running = false
    if (applyProcess.running) applyProcess.running = false
    // One sequential detached command: Alt-Tab cleanup, then this
    // service's cleanup, then the single restoring reload. Sequencing —
    // never a timed delay — guarantees no Alt-Tab unbind lands after the
    // reload has restored configured bindings.
    Quickshell.execDetached([
      "sh", "-c",
      'hyprctl eval "$1" >/dev/null 2>&1; hyprctl eval "$2" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1',
      "mission-control-cleanup",
      altTabService.cleanupScript,
      root.cleanupLua()
    ])
  }
}
