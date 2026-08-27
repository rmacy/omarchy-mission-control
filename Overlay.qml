import QtQuick
import Quickshell

// Composite overlay entry for bitr0t.mission-control. The shell host loads
// exactly one overlay per plugin and injects `shell` and `manifest`, so both
// surfaces live here as children of a single loader item. Mission Control
// keeps its long-standing IPC surface (`open`, `toggle`, `close`, `status`,
// `interactionGeometry`); the Alt-Tab switcher answers through `advance`,
// `commit`, `cancel`, and `switcherStatus`. Only one surface is ever open:
// every opening path closes the other first, and `close` (also used by the
// host's hide) dismisses both.
Item {
  id: root

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var shell: null
  property var manifest: null
  readonly property bool opened: missionControlSurface.opened || switcherSurface.opened

  // Child references for diagnostics and for the runtime smoke, which drives
  // surface state directly instead of through the host loader.
  readonly property var missionControl: missionControlSurface
  readonly property var switcher: switcherSurface

  MissionControl {
    id: missionControlSurface
    shell: root.shell
    manifest: root.manifest
  }

  WindowSwitcher {
    id: switcherSurface
    omarchyPath: root.omarchyPath
    shell: root.shell
    manifest: root.manifest
  }

  function open(argument) {
    if (switcherSurface.opened) switcherSurface.cancel()
    return missionControlSurface.open(argument)
  }

  function toggle(argument) {
    if (switcherSurface.opened) switcherSurface.cancel()
    return missionControlSurface.toggle(argument)
  }

  function close() {
    missionControlSurface.close()
    switcherSurface.cancel()
  }

  function status(argument) {
    return missionControlSurface.status(argument)
  }

  function interactionGeometry(argument) {
    return missionControlSurface.interactionGeometry(argument)
  }

  function advance(delta) {
    if (missionControlSurface.opened) missionControlSurface.close()
    return switcherSurface.advance(delta)
  }

  function commit(argument) {
    switcherSurface.commit(argument)
  }

  function cancel(argument) {
    switcherSurface.cancel()
  }

  function switcherStatus(argument) {
    return switcherSurface.status(argument)
  }
}
