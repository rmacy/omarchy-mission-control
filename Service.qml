import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property string omarchyPath: ""
  readonly property string ownerToken: "bitr0t.mission-control-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false

  function applyLua() {
    return [
      'local owner = "' + root.ownerToken + '"',
      '_G.bitr0t_mission_control_owner = owner',
      'hl.unbind("CTRL + UP")',
      'hl.bind("CTRL + UP",',
      '  hl.dsp.exec_cmd("omarchy-shell -q shell toggle bitr0t.mission-control"),',
      '  { description = "Mission Control" })',
      'hl.gesture({ fingers = 3, direction = "up", action = "unset" })',
      'hl.gesture({',
      '  fingers = 3,',
      '  direction = "up",',
      '  action = function()',
      '    hl.exec_cmd("omarchy-shell -q shell toggle bitr0t.mission-control")',
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
      '  hl.gesture({ fingers = 3, direction = "up", action = "unset" })',
      'end'
    ].join("\n")
  }

  function queueApply() {
    if (!root.shuttingDown) applyTimer.restart()
  }

  function applyBindings() {
    if (root.shuttingDown) return
    if (applyProcess.running) {
      root.applyQueued = true
      return
    }

    root.applyQueued = false
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
    id: applyProcess
    onExited: function(exitCode) {
      if (root.shuttingDown) return
      if (exitCode !== 0)
        console.warn("bitr0t.mission-control: failed to register shortcut and gesture (exit " + exitCode + ")")
      if (root.applyQueued) root.queueApply()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event && String(event.name) === "configreloaded") root.queueApply()
    }
  }

  Component.onCompleted: root.queueApply()

  Component.onDestruction: {
    root.shuttingDown = true
    applyTimer.stop()
    if (applyProcess.running) applyProcess.running = false
    Quickshell.execDetached([
      "sh", "-c",
      'hyprctl eval "$1" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1',
      "mission-control-cleanup", root.cleanupLua()
    ])
  }
}
