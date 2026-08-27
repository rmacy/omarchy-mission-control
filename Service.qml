import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  readonly property string ownerToken: "bitr0t.mission-control-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false
  property bool barMigrationDone: false

  readonly property string stockWorkspacesId: "omarchy.workspaces"
  readonly property string widgetId: "bitr0t.mission-control"
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
      '_G.bitr0t_mission_control_owner = owner',
      'hl.unbind("CTRL + UP")',
      'hl.unbind("CTRL + DOWN")',
      'hl.bind("CTRL + UP",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell summon bitr0t.mission-control {}"),',
      '  { description = "Open Mission Control" })',
      'hl.bind("CTRL + DOWN",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell hide bitr0t.mission-control"),',
      '  { description = "Close Mission Control" })',
      'hl.gesture({',
      '  fingers = 3,',
      '  direction = "up",',
      '  mods = "",',
      '  scale = 1.0,',
      '  action = function()',
      '    hl.exec_cmd("omarchy-shell -q shell summon bitr0t.mission-control {}")',
      '  end',
      '})'
    ].join("\n")
  }

  function cleanupLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      'if _G.bitr0t_mission_control_owner == owner then',
      '  _G.bitr0t_mission_control_owner = nil',
      '  hl.unbind("CTRL + UP")',
      '  hl.unbind("CTRL + DOWN")',
      '  hl.exec_cmd("hyprctl reload")',
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
        console.warn("bitr0t.mission-control: failed to register shortcut and gesture (exit "
          + exitCode + ")" + (detail ? ": " + detail : ""))
      }
      if (root.applyQueued) root.queueApply()
    }
  }

  // Alt-Tab registration is delegated to a dedicated binding component.
  // It runs its own generated cleanup on teardown; in integration mode it
  // never reloads Hyprland itself — the reload below stays the only one.
  AltTabService {
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
    root.queueBarMigration()
  }

  // ------------------------------------------------------------------
  // Bar widget migration
  //
  // The plugin ships a bar widget that supersedes the stock Workspaces
  // widget, so a fresh install takes over that slot instead of leaving two
  // workspace indicators on the bar. Once the shell's config has settled,
  // every `omarchy.workspaces` entry in bar.layout becomes a
  // `bitr0t.mission-control` entry in place — same section, same index,
  // duplicate plugin or stock entries are dropped. A config that already
  // points here and has no stock entry is left untouched, so repeated shell
  // reloads write nothing.

  function barLayout(config) {
    if (!Util.isPlainObject(config)) return null
    if (!Util.isPlainObject(config.bar)) return null
    if (!Util.isPlainObject(config.bar.layout)) return null
    return config.bar.layout
  }

  function entryId(entry) {
    return Util.canonicalWidgetId(Util.isPlainObject(entry) ? entry.id : entry)
  }


  function stockWorkspacesCount(layout) {
    if (!layout) return 0
    var sections = ["left", "center", "right"]
    var count = 0
    for (var s = 0; s < sections.length; s++) {
      var entries = layout[sections[s]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        if (root.entryId(entries[i]) === root.stockWorkspacesId) count++
      }
    }
    return count
  }

  function replaceWorkspacesEntries(config) {
    var layout = root.barLayout(config)
    if (!layout) return

    var sections = ["left", "center", "right"]

    // Enabling a multi-kind plugin can place its widget before this migration
    // runs. Remove those provisional entries so the stock slot remains the
    // authoritative section, index, and settings source.
    for (var s = 0; s < sections.length; s++) {
      var provisional = layout[sections[s]]
      if (!Array.isArray(provisional)) continue
      for (var p = provisional.length - 1; p >= 0; p--) {
        if (root.entryId(provisional[p]) === root.widgetId)
          provisional.splice(p, 1)
      }
    }

    var claimed = false
    for (var section = 0; section < sections.length; section++) {
      var entries = layout[sections[section]]
      if (!Array.isArray(entries)) continue
      for (var i = 0; i < entries.length; i++) {
        var entry = entries[i]
        if (root.entryId(entry) !== root.stockWorkspacesId) continue
        if (claimed) {
          entries.splice(i, 1)
          i--
          continue
        }
        if (Util.isPlainObject(entry)) entry.id = root.widgetId
        else entries[i] = { id: root.widgetId }
        claimed = true
      }
    }
  }

  function queueBarMigration() {
    if (root.shuttingDown || root.barMigrationDone) return
    barMigrationTimer.restart()
  }

  function runBarMigration() {
    if (root.shuttingDown || root.barMigrationDone) return
    var shell = root.shell
    if (!shell || typeof shell.mutateShellConfig !== "function"
        || !Util.isPlainObject(shell.shellConfig)) {
      root.queueBarMigration()
      return
    }

    root.barMigrationDone = true
    if (root.stockWorkspacesCount(root.barLayout(shell.shellConfig)) === 0) return

    shell.mutateShellConfig(function(config) {
      root.replaceWorkspacesEntries(config)
    })
  }

  Timer {
    id: barMigrationTimer
    interval: 2000
    repeat: false
    onTriggered: root.runBarMigration()
  }

  // Startup rewrites shellConfig as defaults and the user file finish
  // loading; restarting the delay each time keeps the migration from
  // racing (and clobbering) a configuration that is still settling.
  Connections {
    target: root.shell
    function onShellConfigChanged() { root.queueBarMigration() }
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
    target: "bitr0t-mission-control-state"

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
    barMigrationTimer.stop()
    if (removeGestureProcess.running) removeGestureProcess.running = false
    if (applyProcess.running) applyProcess.running = false
    Quickshell.execDetached([
      "sh", "-c",
      'sleep 0.4; hyprctl eval "$1" >/dev/null 2>&1',
      "mission-control-cleanup", root.cleanupLua()
    ])
  }
}
