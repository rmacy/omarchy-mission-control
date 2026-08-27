import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "AltTabBindingScript.js" as BindingScript

// Alt-Tab half of the merged plugin's bindings. The host Service.qml
// injects `shell` and owns the single Hyprland reload on teardown; this
// component only registers, re-arms, and retires the Alt-Tab chords and
// its temporary submap.
Item {
  id: root

  property var shell: null
  // Integration mode: on teardown this component still runs its generated
  // cleanup (disable tracked handles, drop the submap, unbind the chords)
  // but leaves `hyprctl reload` to the host Service, so the merged plugin
  // restores configured bindings with exactly one reload.
  property bool integrationMode: false

  readonly property string ownerToken: "bitr0t.mission-control-alt-tab-" + Date.now()
    + "-" + Math.random().toString(36).slice(2)
  property bool applyQueued: false
  property bool shuttingDown: false
  property int applyAttempts: 0
  property bool registrationFailed: false

  function queueApply() {
    if (root.shuttingDown) return
    root.applyAttempts = 0
    root.registrationFailed = false
    applyTimer.restart()
  }

  function applyBindings() {
    if (root.shuttingDown) return
    if (applyProcess.running) {
      root.applyQueued = true
      return
    }
    root.applyQueued = false
    applyProcess.command = ["hyprctl", "eval",
      BindingScript.generateApply({ ownerToken: root.ownerToken })]
    applyProcess.running = true
  }

  function notifyRegistrationFailure() {
    Quickshell.execDetached([
      "notify-send", "-u", "critical", "-a", "Mission Control",
      "Mission Control Alt-Tab registration failed",
      "Alt-Tab bindings could not be registered after "
        + BindingScript.REGISTRATION_RETRY.maxAttempts
        + " attempts. Run hyprctl reload to retry."
    ])
  }

  Timer {
    id: applyTimer
    interval: 100
    repeat: false
    onTriggered: root.applyBindings()
  }

  Timer {
    id: retryTimer
    repeat: false
    onTriggered: root.applyBindings()
  }

  Process {
    id: applyProcess
    onExited: function(exitCode) {
      if (root.shuttingDown) return
      if (exitCode === 0) {
        root.applyAttempts = 0
        root.registrationFailed = false
      } else {
        root.applyAttempts += 1
        if (root.applyAttempts < BindingScript.REGISTRATION_RETRY.maxAttempts) {
          retryTimer.interval = BindingScript.REGISTRATION_RETRY.baseDelayMs
            * Math.pow(2, root.applyAttempts - 1)
          retryTimer.restart()
          return
        }
        if (!root.registrationFailed) {
          root.registrationFailed = true
          console.warn("bitr0t.mission-control: Alt-Tab registration failed after "
            + root.applyAttempts + " attempts")
          root.notifyRegistrationFailure()
        }
      }
      if (root.applyQueued) root.queueApply()
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "configreloaded") return
      if (root.shell && typeof root.shell.callIfLoaded === "function")
        root.shell.callIfLoaded(BindingScript.SHELL_TARGET, "cancel", "config-reload")
      root.queueApply()
    }
  }

  Component.onCompleted: root.queueApply()

  Component.onDestruction: {
    root.shuttingDown = true
    applyTimer.stop()
    retryTimer.stop()
    if (applyProcess.running) applyProcess.running = false
    Quickshell.execDetached([
      "sh", "-c",
      root.integrationMode
        ? 'hyprctl eval "$1" >/dev/null 2>&1'
        : 'hyprctl eval "$1" >/dev/null 2>&1; hyprctl reload >/dev/null 2>&1',
      "mission-control-alt-tab-cleanup",
      BindingScript.generateCleanup({ ownerToken: root.ownerToken })
    ])
  }
}
