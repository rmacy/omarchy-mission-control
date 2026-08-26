import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property int foreignToplevelCount: ToplevelManager.toplevels.values.length
  property bool dragActive: false
  property int dragFromIndex: -1
  property int dragTargetIndex: -1
  property bool windowDragActive: false
  property int windowDragIndex: -1
  property int windowDropWorkspaceId: -1
  property bool windowDropAnimating: false
  property var pendingWindowToplevel: null
  property int pendingWindowWorkspaceId: -1
  property var managedWorkspaceIds: []
  property bool spacesLoaded: false
  readonly property string spacesStatePath: Quickshell.env("HOME")
    + "/.local/state/omarchy/mission-control-spaces.json"
  property bool opened: false
  property real revealProgress: 0
  property int targetMonitorId: -1
  property string targetMonitorName: ""
  property int selectedWorkspaceId: -1
  property int selectedIndex: -1
  property var workspaceIds: []
  property var windows: []
  property var desktopCache: ({})

  readonly property color backgroundColor: Color.menu.background
  readonly property color foregroundColor: Color.menu.text
  readonly property color borderColor: Color.menu.border
  readonly property color scrimColor: Color.menu.scrim
  readonly property color selectedColor: Color.menu.selectedBackground
  readonly property color selectedTextColor: Color.menu.selectedText
  readonly property color selectedBorderColor: Color.menu.selectedBorder
  readonly property int gridSpacing: Math.max(Style.spacing.lg, 18)
  readonly property string currentBackgroundLink: Quickshell.env("HOME")
    + "/.local/state/omarchy/current/background"
  readonly property var overviewMonitor: root.monitorById(root.targetMonitorId)
  readonly property int gridColumns: WindowModel.gridColumns(
    root.windows.length, windowGrid.width, windowGrid.height)
  readonly property int gridRows: root.windows.length === 0 || root.gridColumns === 0
    ? 0 : Math.ceil(root.windows.length / root.gridColumns)
  readonly property real cellWidth: root.gridColumns === 0 ? 0
    : (windowGrid.width - (root.gridColumns - 1) * root.gridSpacing) / root.gridColumns
  readonly property real cellHeight: root.gridRows === 0 ? 0
    : (windowGrid.height - (root.gridRows - 1) * root.gridSpacing) / root.gridRows

  function monitorScreen(name) {
    var screens = Quickshell.screens || []
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name || "") === String(name || "")) return screens[i]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function monitorById(monitorId) {
    var monitors = Hyprland.monitors.values
    for (var i = 0; i < monitors.length; i++) {
      if (Number(monitors[i].id) === Number(monitorId)) return monitors[i]
    }
    return null
  }

  function desktopWindows(workspaceId) {
    return WindowModel.desktopToplevels(
      Hyprland.toplevels.values, Number(workspaceId), root.targetMonitorId)
  }

  function thumbnailRect(toplevel, width, height) {
    return WindowModel.workspaceThumbnailRect(
      toplevel, root.overviewMonitor, width, height)
  }

  function desktopEntry(metadata) {
    if (!root.appLibrary) return null

    var initialClass = String(metadata.initialClass || "")
    var windowClass = String(metadata.class || "")
    var cacheKey = (initialClass + "\n" + windowClass).toLowerCase()
    if (root.desktopCache[cacheKey] !== undefined) return root.desktopCache[cacheKey]

    var entries = root.appLibrary.sortedEntries("") || []
    var keys = [initialClass, windowClass]
    var best = null
    var bestScore = 100

    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      var entryId = String(entry.id || "").replace(/\.desktop$/i, "").toLowerCase()
      var entryName = String(root.appLibrary.entryName(entry) || "").toLowerCase()
      for (var j = 0; j < keys.length; j++) {
        var key = String(keys[j] || "").replace(/\.desktop$/i, "").toLowerCase()
        if (!key) continue

        var score = 100
        if (entryId === key) score = 0
        else if (entryId.slice(-(key.length + 1)) === "." + key
                 || key.slice(-(entryId.length + 1)) === "." + entryId) score = 1
        else if (entryName === key) score = 2

        if (score < bestScore) {
          best = entry
          bestScore = score
        }
      }
    }

    root.desktopCache[cacheKey] = best
    return best
  }

  function decorate(toplevel) {
    var metadata = toplevel.lastIpcObject || ({})
    var entry = root.desktopEntry(metadata)
    var fallbackName = String(metadata.class || metadata.initialClass || "Application")
    var appName = entry ? String(root.appLibrary.entryName(entry) || fallbackName) : fallbackName
    var iconName = entry ? String(entry.icon || "")
      : String(metadata.initialClass || metadata.class || "application-x-executable")
    var sourceSize = metadata.size || []
    var sourceAspect = Number(sourceSize[0]) / Number(sourceSize[1])
    if (!isFinite(sourceAspect) || sourceAspect <= 0) sourceAspect = 16 / 10

    return {
      toplevel: toplevel,
      captureSource: toplevel.wayland,
      address: String(toplevel.address || metadata.address || ""),
      aspect: sourceAspect,
      appName: appName,
      title: WindowModel.shortenedTitle(toplevel.title || metadata.title || appName, 120),
      iconSource: root.appLibrary
        ? root.appLibrary.iconSource(iconName)
        : Quickshell.iconPath(iconName, true)
    }
  }

  function currentSelectedAddress() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.windows.length) return ""
    return String(root.windows[root.selectedIndex].address || "")
  }

  function refreshWindows(preferredAddress) {
    var handles = WindowModel.visibleToplevels(
      Hyprland.toplevels.values, root.selectedWorkspaceId, root.targetMonitorId)
    var nextWindows = []
    for (var i = 0; i < handles.length; i++) nextWindows.push(root.decorate(handles[i]))

    root.windows = nextWindows
    var wantedAddress = String(preferredAddress || "")
    var nextIndex = -1

    for (var j = 0; j < nextWindows.length; j++) {
      if (wantedAddress && nextWindows[j].address === wantedAddress) {
        nextIndex = j
        break
      }
      if (nextIndex < 0 && nextWindows[j].toplevel.activated) nextIndex = j
    }

    root.selectedIndex = nextIndex >= 0 ? nextIndex : (nextWindows.length > 0 ? 0 : -1)
  }

  function refreshOverview() {
    var preferredAddress = root.currentSelectedAddress()
    if (!root.dragActive) {
      root.workspaceIds = WindowModel.workspaceIds(
        Hyprland.workspaces.values, root.targetMonitorId, root.selectedWorkspaceId,
        root.managedWorkspaceIds)

      if (root.workspaceIds.indexOf(root.selectedWorkspaceId) === -1)
        root.selectedWorkspaceId = root.workspaceIds.length > 0 ? root.workspaceIds[0] : -1
    }

    root.refreshWindows(preferredAddress)
  }

  function open(payloadJson) {
    var monitor = Hyprland.focusedMonitor
    if (!monitor) return "unavailable"

    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (_error) { payload = ({}) }

    root.targetMonitorId = Number(monitor.id)
    root.targetMonitorName = String(monitor.name || "")
    var activeWorkspace = monitor.activeWorkspace || Hyprland.focusedWorkspace
    var requestedWorkspace = Number(payload.workspace)
    root.selectedWorkspaceId = requestedWorkspace > 0
      ? requestedWorkspace : (activeWorkspace ? Number(activeWorkspace.id) : -1)

    Hyprland.refreshWorkspaces()
    Hyprland.refreshToplevels()
    root.opened = true
    root.revealProgress = 0
    root.refreshOverview()

    Qt.callLater(function() {
      if (!root.opened) return
      root.refreshOverview()
      root.revealProgress = 1
      keyScope.forceActiveFocus()
    })
    return "ok"
  }

  function toggle(payloadJson) {
    if (root.opened) {
      root.close()
      return "closed"
    }
    return root.open(payloadJson || "{}")
  }

  function close() {
    root.revealProgress = 0
    root.opened = false
    root.windows = []
    root.selectedIndex = -1
    root.windowDragActive = false
    root.windowDragIndex = -1
    root.windowDropWorkspaceId = -1
    root.windowDropAnimating = false
    root.pendingWindowToplevel = null
    root.pendingWindowWorkspaceId = -1
    windowDropTimer.stop()
    windowDropCleanupTimer.stop()
  }

  function selectWorkspace(workspaceId) {
    var nextId = Number(workspaceId)
    if (nextId <= 0 || nextId === root.selectedWorkspaceId) return
    root.selectedWorkspaceId = nextId
    root.refreshWindows("")
    keyScope.forceActiveFocus()
  }

  function workspaceSelector(workspaceId) {
    return '"' + Math.floor(Number(workspaceId)) + '"'
  }

  function windowSelector(toplevel) {
    var address = WindowModel.stableAddress(toplevel)
    if (address && address.slice(0, 2).toLowerCase() !== "0x") address = "0x" + address
    return '"address:' + address + '"'
  }

  function loadManagedSpaces(raw) {
    var values = []
    try {
      var parsed = JSON.parse(String(raw || "[]"))
      if (Array.isArray(parsed)) values = parsed
    } catch (_error) { }
    root.saveManagedSpaces(values)
  }

  function saveManagedSpaces(values) {
    var next = []
    var source = Array.isArray(values) ? values : []
    for (var i = 0; i < source.length; i++) {
      var id = Math.floor(Number(source[i]))
      if (id > 0 && id <= 10 && next.indexOf(id) === -1) next.push(id)
    }
    next.sort(function(left, right) { return left - right })
    root.managedWorkspaceIds = next
    root.spacesLoaded = true
    spacesStateFile.setText(JSON.stringify(next) + "\n")
    if (root.opened) root.refreshOverview()
  }

  function runWorkspaceLua(lua, description) {
    if (workspaceProcess.running) {
      console.warn("bitr0t.mission-control: workspace op still running, skipped " + description)
      return false
    }
    workspaceProcess.operation = description
    workspaceProcess.command = ["hyprctl", "eval", lua]
    workspaceProcess.running = true
    return true
  }

  function addWorkspace() {
    var nextId = WindowModel.nextFreeWorkspaceId(root.workspaceIds, 10)
    if (nextId <= 0) return

    var nextManaged = root.managedWorkspaceIds.slice()
    nextManaged.push(nextId)
    root.saveManagedSpaces(nextManaged)
    runWorkspaceLua(
      'hl.dispatch(hl.dsp.focus({ workspace = ' + root.workspaceSelector(nextId) + ' }))',
      "add workspace")
    root.selectWorkspace(nextId)
  }

  function removeWorkspace(workspaceId) {
    var removedId = Math.floor(Number(workspaceId))
    var neighbor = WindowModel.removalNeighbor(root.workspaceIds, removedId)
    if (removedId <= 0 || neighbor <= 0) return

    var nextManaged = []
    for (var i = 0; i < root.managedWorkspaceIds.length; i++) {
      if (root.managedWorkspaceIds[i] !== removedId)
        nextManaged.push(root.managedWorkspaceIds[i])
    }
    root.saveManagedSpaces(nextManaged)

    var lua = [
      'hl.dispatch(hl.dsp.focus({ workspace = ' + root.workspaceSelector(neighbor) + ' }))'
    ]
    var handles = WindowModel.visibleToplevels(
      Hyprland.toplevels.values, removedId, root.targetMonitorId)
    for (var j = 0; j < handles.length; j++) {
      lua.push('hl.dispatch(hl.dsp.window.move({ window = ' + root.windowSelector(handles[j])
        + ', workspace = ' + root.workspaceSelector(neighbor) + ', follow = false }))')
    }

    runWorkspaceLua(lua.join("\n"), "remove workspace " + removedId)
    if (root.selectedWorkspaceId === removedId) root.selectedWorkspaceId = neighbor
  }

  function commitReorder(fromIndex, toIndex) {
    if (fromIndex === toIndex) return
    var currentIds = root.workspaceIds
    var desiredIds = WindowModel.moveArrayValue(currentIds, fromIndex, toIndex)
    if (!desiredIds) return

    var maxId = 0
    for (var i = 0; i < currentIds.length; i++)
      maxId = Math.max(maxId, Math.floor(Number(currentIds[i]) || 0))

    var actualIds = WindowModel.workspaceIds(
      Hyprland.workspaces.values, root.targetMonitorId, -1, [])
    var moves = WindowModel.reassignPlan(
      currentIds, desiredIds, 1000 + maxId, actualIds)
    if (moves.length > 0) {
      var lua = []
      for (var j = 0; j < moves.length; j++) {
        lua.push('hl.dispatch(hl.dsp.workspace.change_id({ workspace = '
          + root.workspaceSelector(moves[j].workspace) + ', id = '
          + Math.floor(moves[j].id) + ' }))')
      }
      runWorkspaceLua(lua.join("\n"), "reorder workspaces")
    }

    root.saveManagedSpaces(WindowModel.remapWorkspaceIds(
      root.managedWorkspaceIds, currentIds, desiredIds))
    var selectedPosition = desiredIds.indexOf(root.selectedWorkspaceId)
    if (selectedPosition >= 0) {
      root.selectedWorkspaceId = currentIds[selectedPosition]
      root.refreshWindows("")
    }
  }

  function nudgeSelectedWorkspace(direction) {
    var index = root.workspaceIds.indexOf(root.selectedWorkspaceId)
    if (index < 0) return
    var target = index + (Number(direction) < 0 ? -1 : 1)
    if (target < 0 || target >= root.workspaceIds.length) return
    root.commitReorder(index, target)
  }

  function activateWorkspace() {
    if (root.selectedWorkspaceId <= 0) {
      root.close()
      return
    }

    var workspaceId = root.selectedWorkspaceId
    root.close()
    Quickshell.execDetached([
      "hyprctl", "dispatch",
      'hl.dsp.focus({ workspace = "' + workspaceId + '" })'
    ])
  }

  function activateSelected() {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.windows.length) {
      root.activateWorkspace()
      return
    }

    var toplevel = root.windows[root.selectedIndex].captureSource
    root.close()
    Qt.callLater(function() {
      if (toplevel) toplevel.activate()
    })
  }

  function closeWindow(index) {
    if (index < 0 || index >= root.windows.length) return
    var toplevel = root.windows[index].captureSource
    if (toplevel) toplevel.close()
    refreshTimer.restart()
  }

  function moveWindowToWorkspace(toplevel, workspaceId) {
    var destination = Math.floor(Number(workspaceId))
    if (!toplevel || destination <= 0 || destination === root.selectedWorkspaceId
        || root.workspaceIds.indexOf(destination) === -1) return false

    return root.runWorkspaceLua(
      'hl.dispatch(hl.dsp.window.move({ window = ' + root.windowSelector(toplevel)
        + ', workspace = ' + root.workspaceSelector(destination)
        + ', follow = false }))',
      "move window to space " + destination)
  }

  function moveSelectedWindowToWorkspace(workspaceId) {
    if (root.selectedIndex < 0 || root.selectedIndex >= root.windows.length) return false
    var item = windowRepeater.itemAt(root.selectedIndex)
    return item && typeof item.animateToWorkspace === "function"
      ? item.animateToWorkspace(workspaceId) : false
  }

  function moveSelection(horizontal, vertical) {
    root.selectedIndex = WindowModel.nextGridIndex(
      root.selectedIndex, horizontal, vertical, root.gridColumns, root.windows.length)
  }

  function workspaceWindowCount(workspaceId) {
    return WindowModel.visibleToplevels(
      Hyprland.toplevels.values, Number(workspaceId), root.targetMonitorId).length
  }



  function status(_argument) {
    return JSON.stringify({
      open: root.opened,
      monitor: root.targetMonitorName,
      workspace: root.selectedWorkspaceId,
      workspaceCount: root.workspaceIds.length,
      workspaceIds: root.workspaceIds,
      selectedIndex: root.selectedIndex,
      selectedHasToplevel: root.selectedIndex >= 0
        && root.selectedIndex < root.windows.length
        && !!root.windows[root.selectedIndex].toplevel,
      windowCount: root.windows.length,
      hyprlandToplevelCount: Hyprland.toplevels.values.length,
      foreignToplevelCount: root.foreignToplevelCount,
      selectedAddress: root.currentSelectedAddress()
    })
  }

  Connections {
    target: Hyprland
    function onRawEvent(_event) {
      if (root.opened) refreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() {
      if (root.opened) refreshTimer.restart()
    }
  }

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() {
      if (root.opened) refreshTimer.restart()
    }
  }


  FileView {
    id: spacesStateFile
    path: root.spacesStatePath
    watchChanges: false
    printErrors: false
    atomicWrites: true
    onLoaded: if (!root.spacesLoaded) root.loadManagedSpaces(text())
    onLoadFailed: {
      root.spacesLoaded = true
      if (root.opened) root.refreshOverview()
    }
  }

  Timer {
    id: refreshTimer
    interval: 45
    repeat: false
    onTriggered: if (root.opened) root.refreshOverview()
  }

  Timer {
    id: windowDropTimer
    interval: 180
    repeat: false
    onTriggered: {
      root.moveWindowToWorkspace(
        root.pendingWindowToplevel, root.pendingWindowWorkspaceId)
      windowDropCleanupTimer.restart()
    }
  }

  Timer {
    id: windowDropCleanupTimer
    interval: 100
    repeat: false
    onTriggered: {
      root.windowDropAnimating = false
      root.windowDragActive = false
      root.windowDragIndex = -1
      root.windowDropWorkspaceId = -1
      root.pendingWindowToplevel = null
      root.pendingWindowWorkspaceId = -1
    }
  }

  Process {
    id: workspaceProcess
    property string operation: ""
    stdout: StdioCollector { id: workspaceStdout; waitForEnd: true }
    stderr: StdioCollector { id: workspaceStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        var detail = String(workspaceStdout.text || workspaceStderr.text || "").trim()
        console.warn("bitr0t.mission-control: failed to " + operation
          + " (exit " + exitCode + ")" + (detail ? ": " + detail : ""))
      }
      Hyprland.refreshWorkspaces()
      Hyprland.refreshToplevels()
      refreshTimer.restart()
    }
  }

  PanelWindow {
    id: panel

    visible: root.opened
    screen: root.monitorScreen(root.targetMonitorName)
    anchors { top: true; right: true; bottom: true; left: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "bitr0t-mission-control"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    FocusScope {
      id: keyScope
      anchors.fill: parent
      focus: root.opened
      opacity: root.revealProgress
      scale: 0.975 + root.revealProgress * 0.025

      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var vimModifiers = event.modifiers === Qt.NoModifier
          || event.modifiers === Qt.ShiftModifier
        if (event.key === Qt.Key_Escape || (event.key === Qt.Key_Q && vimModifiers)) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          var reverse = event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier)
          root.moveSelection(reverse ? -1 : 1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.ShiftModifier)) {
          root.nudgeSelectedWorkspace(-1)
          event.accepted = true
        } else if (event.key === Qt.Key_Right && (event.modifiers & Qt.ShiftModifier)) {
          root.nudgeSelectedWorkspace(1)
          event.accepted = true
        } else if (event.key === Qt.Key_Left || (event.key === Qt.Key_H && vimModifiers)) {
          root.moveSelection(-1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Right || (event.key === Qt.Key_L && vimModifiers)) {
          root.moveSelection(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Up || (event.key === Qt.Key_K && vimModifiers)) {
          root.moveSelection(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down || (event.key === Qt.Key_J && vimModifiers)) {
          root.moveSelection(0, 1)
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          var workspaceId = event.key - Qt.Key_0
          if (root.workspaceIds.indexOf(workspaceId) !== -1) {
            if (event.modifiers & Qt.ShiftModifier)
              root.moveSelectedWindowToWorkspace(workspaceId)
            else
              root.selectWorkspace(workspaceId)
            event.accepted = true
          }
        }
      }

      Rectangle {
        anchors.fill: parent
        color: root.scrimColor
        opacity: 0.94

        MouseArea {
          anchors.fill: parent
          onClicked: root.close()
        }
      }

      Item {
        id: overview
        anchors.fill: parent
        anchors.margins: Math.max(Style.space(28), 28)

        Column {
          id: heading
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Math.max(Style.spacing.xs, 4)

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Mission Control"
            color: root.foregroundColor
            font.family: Style.font.menuFamily
            font.pixelSize: Math.max(Style.font.display, 28)
            font.weight: Font.DemiBold
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Control + Up  ·  three-finger swipe up  ·  arrows or HJKL to navigate  ·  Enter to open"
            color: root.foregroundColor
            opacity: 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: workspaceRail
          readonly property real monitorAspect: root.overviewMonitor
            && root.overviewMonitor.height > 0
            ? root.overviewMonitor.width / root.overviewMonitor.height : 16 / 9
          anchors.horizontalCenter: parent.horizontalCenter
          readonly property real chipSpacing: Math.max(Style.spacing.sm, 10)
          readonly property real chipWidth: Math.max(120, Math.min(240,
            (overview.width - 180 - root.workspaceIds.length * chipSpacing)
              / Math.max(1, root.workspaceIds.length)))
          readonly property real chipHeight: Math.max(58, Math.min(140,
            chipWidth / monitorAspect))

          anchors.top: heading.bottom
          anchors.topMargin: Math.max(Style.space(18), 18)
          width: Math.min(parent.width, workspaceRow.implicitWidth + Math.max(Style.space(20), 20) * 2)
          height: chipHeight + Math.max(Style.space(18), 18)
          radius: Math.max(Style.cornerRadius, 18)
          color: Util.alpha(root.backgroundColor, 0.88)
          border.color: root.borderColor
          border.width: 1

          MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

          Row {
            id: workspaceRow
            anchors.centerIn: parent
            spacing: workspaceRail.chipSpacing

            Repeater {
              model: root.workspaceIds

              Rectangle {
                id: workspaceChip
                required property int modelData
                required property int index
                readonly property bool selected: modelData === root.selectedWorkspaceId
                readonly property int windowCount: root.workspaceWindowCount(modelData)
                readonly property bool windowDropTarget: (root.windowDragActive
                  || root.windowDropAnimating) && root.windowDropWorkspaceId === modelData
                property bool hovered: false
                property real dragOffset: 0

                width: workspaceRail.chipWidth
                height: workspaceRail.chipHeight
                radius: Math.max(Style.cornerRadius - 4, 12)
                color: windowDropTarget || selected
                  ? root.selectedColor : Util.alpha(root.backgroundColor, 0.55)
                border.color: windowDropTarget || selected
                  ? root.selectedBorderColor : Util.alpha(root.borderColor, 0.7)
                border.width: windowDropTarget ? 3 : (selected ? 2 : 1)
                z: root.dragActive && root.dragFromIndex === index ? 20 : 1
                scale: windowDropTarget ? 1.06
                  : (root.dragActive && root.dragFromIndex === index ? 1.04 : 1)
                transform: Translate { x: workspaceChip.dragOffset }

                Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

                Item {
                  id: desktopSurface
                  anchors.fill: parent
                  clip: true

                  Image {
                    anchors.fill: parent
                    source: Util.fileUrl(root.currentBackgroundLink)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    smooth: true
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: Util.alpha(root.scrimColor, 0.12)
                  }

                  Repeater {
                    model: root.desktopWindows(workspaceChip.modelData)

                    Item {
                      id: thumbnailWindow
                      required property var modelData
                      readonly property var geometry: root.thumbnailRect(
                        modelData, desktopSurface.width, desktopSurface.height)

                      visible: geometry !== null && !!modelData.wayland
                      x: geometry ? geometry.x : 0
                      y: geometry ? geometry.y : 0
                      width: geometry ? geometry.width : 0
                      height: geometry ? geometry.height : 0

                      ScreencopyView {
                        anchors.fill: parent
                        captureSource: thumbnailWindow.modelData.wayland
                        live: root.opened && workspaceChip.selected
                        paintCursor: false
                      }

                      Rectangle {
                        anchors.fill: parent
                        color: "transparent"
                        border.color: Util.alpha(root.borderColor, 0.7)
                        border.width: 1
                      }
                    }
                  }

                  Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: Math.min(24, parent.height * 0.34)
                    color: Util.alpha(root.backgroundColor, 0.82)
                    z: 5

                    Row {
                      anchors.centerIn: parent
                      spacing: 6

                      Text {
                        text: "Space " + workspaceChip.modelData
                        color: workspaceChip.selected
                          ? root.selectedTextColor : root.foregroundColor
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                        font.weight: Font.DemiBold
                      }

                      Text {
                        text: workspaceChip.windowCount
                        color: root.foregroundColor
                        opacity: 0.55
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: workspaceChip.radius
                    border.color: workspaceChip.windowDropTarget || workspaceChip.selected
                      ? root.selectedBorderColor : Util.alpha(root.borderColor, 0.7)
                    border.width: workspaceChip.windowDropTarget
                      ? 3 : (workspaceChip.selected ? 2 : 1)
                    z: 6
                  }
                }

                MouseArea {
                  id: workspaceDrag
                  anchors.fill: parent
                  enabled: !root.windowDragActive && !root.windowDropAnimating
                  hoverEnabled: true
                  cursorShape: root.dragActive ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  preventStealing: true
                  property real pressRowX: 0
                  property bool moved: false

                  onEntered: workspaceChip.hovered = true
                  onExited: workspaceChip.hovered = false
                  onPressed: function(mouse) {
                    var point = mapToItem(workspaceRow, mouse.x, mouse.y)
                    pressRowX = point.x
                    moved = false
                    root.dragActive = true
                    root.dragFromIndex = workspaceChip.index
                    root.dragTargetIndex = workspaceChip.index
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var point = mapToItem(workspaceRow, mouse.x, mouse.y)
                    workspaceChip.dragOffset = point.x - pressRowX
                    if (Math.abs(workspaceChip.dragOffset) > 6) moved = true

                    var step = workspaceRail.chipWidth + workspaceRail.chipSpacing
                    var target = Math.round((workspaceChip.x + workspaceChip.dragOffset) / step)
                    root.dragTargetIndex = Math.max(0, Math.min(root.workspaceIds.length - 1, target))
                  }
                  onReleased: {
                    var from = root.dragFromIndex
                    var to = root.dragTargetIndex
                    workspaceChip.dragOffset = 0
                    root.dragActive = false
                    root.dragFromIndex = -1
                    root.dragTargetIndex = -1
                    if (moved) root.commitReorder(from, to)
                  }
                  onCanceled: {
                    workspaceChip.dragOffset = 0
                    root.dragActive = false
                    root.dragFromIndex = -1
                    root.dragTargetIndex = -1
                  }
                  onClicked: if (!moved) root.selectWorkspace(workspaceChip.modelData)
                  onDoubleClicked: if (!moved) {
                    root.selectWorkspace(workspaceChip.modelData)
                    root.activateWorkspace()
                  }
                }

                Rectangle {
                  visible: workspaceChip.hovered && !root.dragActive
                    && !root.windowDragActive && root.workspaceIds.length > 1
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: 4
                  width: 22
                  height: 22
                  radius: width / 2
                  color: Util.alpha(root.scrimColor, 0.92)
                  border.color: Util.alpha(root.borderColor, 0.8)
                  border.width: 1
                  z: 30

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.foregroundColor
                    font.pixelSize: Style.font.body
                    font.weight: Font.DemiBold
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(mouse) {
                      mouse.accepted = true
                      root.removeWorkspace(workspaceChip.modelData)
                    }
                  }
                }
              }
            }

            Rectangle {
              id: addWorkspaceButton
              visible: root.workspaceIds.length < 10
              width: workspaceRail.chipHeight
              height: workspaceRail.chipHeight
              radius: Math.max(Style.cornerRadius - 4, 12)
              color: "transparent"
              border.color: Util.alpha(root.borderColor, 0.8)
              border.width: 1

              Text {
                anchors.centerIn: parent
                text: "+"
                color: root.foregroundColor
                opacity: 0.72
                font.family: Style.font.menuFamily
                font.pixelSize: Math.max(Style.font.display, 26)
                font.weight: Font.Light
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.addWorkspace()
              }
            }
          }

          Rectangle {
            visible: root.dragActive && root.dragTargetIndex >= 0
              && root.dragTargetIndex !== root.dragFromIndex
            x: workspaceRow.x + root.dragTargetIndex
              * (workspaceRail.chipWidth + workspaceRail.chipSpacing)
              + (root.dragTargetIndex > root.dragFromIndex
                ? workspaceRail.chipWidth + workspaceRail.chipSpacing / 2
                : -workspaceRail.chipSpacing / 2)
            anchors.verticalCenter: workspaceRow.verticalCenter
            width: 3
            height: workspaceRail.chipHeight - 8
            radius: width / 2
            color: root.selectedBorderColor
            z: 40
          }
        }

        Item {
          id: windowGrid
          anchors.top: workspaceRail.bottom
          anchors.topMargin: Math.max(Style.space(24), 24)
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom

          Repeater {
            id: windowRepeater
            model: root.windows

            Item {
              id: windowCell
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              property bool hovered: false
              property real dragOffsetX: 0
              property real dragOffsetY: 0
              property real dragScale: 1
              readonly property bool beingDragged: root.windowDragIndex === index
                && (root.windowDragActive || root.windowDropAnimating)
              z: beingDragged ? 100 : 1

              function animateToWorkspace(workspaceId) {
                var destination = Math.floor(Number(workspaceId))
                if (!modelData.toplevel || destination <= 0
                    || destination === root.selectedWorkspaceId
                    || root.workspaceIds.indexOf(destination) === -1
                    || workspaceProcess.running) return false

                var targetIndex = root.workspaceIds.indexOf(destination)
                var step = workspaceRail.chipWidth + workspaceRail.chipSpacing
                var targetCenter = workspaceRow.mapToItem(
                  overview, targetIndex * step + workspaceRail.chipWidth / 2,
                  workspaceRail.chipHeight / 2)
                var currentCenter = windowCard.mapToItem(
                  overview, windowCard.width / 2, windowCard.height / 2)

                root.pendingWindowToplevel = modelData.toplevel
                root.pendingWindowWorkspaceId = destination
                root.windowDragIndex = index
                root.windowDropWorkspaceId = destination
                root.windowDropAnimating = true
                root.windowDragActive = false
                dragOffsetX += targetCenter.x - currentCenter.x
                dragOffsetY += targetCenter.y - currentCenter.y
                dragScale = Math.max(0.08, Math.min(
                  workspaceRail.chipWidth * 0.72 / Math.max(1, windowCard.width),
                  workspaceRail.chipHeight * 0.72 / Math.max(1, windowCard.height)))
                windowDropTimer.restart()
                return true
              }
              Behavior on dragOffsetX {
                enabled: root.windowDropAnimating
                NumberAnimation { duration: 170; easing.type: Easing.InOutCubic }
              }
              Behavior on dragOffsetY {
                enabled: root.windowDropAnimating
                NumberAnimation { duration: 170; easing.type: Easing.InOutCubic }
              }
              onBeingDraggedChanged: if (!beingDragged) {
                dragOffsetX = 0
                dragOffsetY = 0
                dragScale = 1
              }
              readonly property int column: root.gridColumns > 0 ? index % root.gridColumns : 0
              readonly property int row: root.gridColumns > 0 ? Math.floor(index / root.gridColumns) : 0

              x: column * (root.cellWidth + root.gridSpacing)
              y: row * (root.cellHeight + root.gridSpacing)
              width: root.cellWidth
              height: root.cellHeight

              Rectangle {
                id: windowCard
                readonly property real previewAspect: Math.max(
                  0.4, Math.min(4, Number(windowCell.modelData.aspect) || 16 / 10))
                readonly property real chromeHeight: Math.max(Style.space(52), 52)
                  + Math.max(Style.space(16), 16)
                anchors.centerIn: parent
                width: Math.max(0, parent.width - Math.max(Style.space(8), 8))
                height: Math.min(
                  Math.max(0, parent.height - Math.max(Style.space(8), 8)),
                  Math.max(chromeHeight + 80, (width - Math.max(Style.space(16), 16))
                    / previewAspect + chromeHeight))
                transform: Translate {
                  x: windowCell.dragOffsetX
                  y: windowCell.dragOffsetY
                }
                radius: Math.max(Style.cornerRadius, 18)
                color: windowCell.selected
                  ? Util.alpha(root.selectedColor, 0.92)
                  : Util.alpha(root.backgroundColor, 0.82)
                border.color: windowCell.selected ? root.selectedBorderColor : root.borderColor
                border.width: windowCell.selected ? 3 : 1
                scale: windowCell.beingDragged ? windowCell.dragScale
                  : (windowCell.selected ? 1 : (windowCell.hovered ? 0.99 : 0.965))
                opacity: root.windowDropAnimating && windowCell.beingDragged
                  ? 0.28
                  : (windowCell.beingDragged || windowCell.selected || windowCell.hovered
                    ? 1 : 0.82)

                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 120 } }
                Behavior on color { ColorAnimation { duration: 120 } }

                Item {
                  id: previewFrame
                  anchors.top: parent.top
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: titleBar.top
                  anchors.margins: Math.max(Style.space(8), 8)
                  clip: true

                  Rectangle {
                    anchors.fill: parent
                    color: Util.alpha(root.scrimColor, 0.72)
                    radius: Math.max(Style.cornerRadius - 4, 12)
                  }

                  ScreencopyView {
                    id: preview
                    captureSource: windowCell.modelData.captureSource
                    live: root.opened
                    paintCursor: false
                    readonly property real sourceAspect: sourceSize.height > 0
                      ? sourceSize.width / sourceSize.height : 16 / 10
                    width: Math.min(previewFrame.width, previewFrame.height * sourceAspect)
                    height: width / sourceAspect
                    anchors.centerIn: parent
                    visible: hasContent
                  }

                  Image {
                    anchors.centerIn: parent
                    visible: !preview.hasContent
                    width: Math.min(parent.width, parent.height) * 0.24
                    height: width
                    source: String(windowCell.modelData.iconSource || "")
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    opacity: 0.8
                  }

                  Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: Math.max(Style.cornerRadius - 4, 12)
                    border.color: Util.alpha(root.borderColor, 0.75)
                    border.width: 1
                  }
                }

                Item {
                  id: titleBar
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  height: Math.max(Style.space(52), 52)

                  Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Math.max(Style.space(12), 12)
                    anchors.rightMargin: Math.max(Style.space(12), 12)
                    spacing: Math.max(Style.spacing.sm, 8)

                    Image {
                      width: Math.max(Style.space(24), 24)
                      height: width
                      source: String(windowCell.modelData.iconSource || "")
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                      smooth: true
                    }

                    Column {
                      width: Math.max(0, parent.width - parent.spacing - Math.max(Style.space(24), 24))
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: 1

                      Text {
                        width: parent.width
                        text: String(windowCell.modelData.appName || "Application")
                        color: windowCell.selected ? root.selectedTextColor : root.foregroundColor
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.body
                        font.weight: Font.DemiBold
                      }

                      Text {
                        width: parent.width
                        text: String(windowCell.modelData.title || "")
                        color: windowCell.selected ? root.selectedTextColor : root.foregroundColor
                        opacity: 0.62
                        elide: Text.ElideRight
                        maximumLineCount: 1
                        font.family: Style.font.menuFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }

                Rectangle {
                  id: closeButton
                  visible: windowCell.hovered && !windowCell.beingDragged
                  anchors.top: parent.top
                  anchors.right: parent.right
                  anchors.margins: Math.max(Style.space(10), 10)
                  width: Math.max(Style.space(28), 28)
                  height: width
                  radius: width / 2
                  color: Util.alpha(root.backgroundColor, 0.92)
                  border.color: root.borderColor
                  border.width: 1
                  z: 3

                  Text {
                    anchors.centerIn: parent
                    text: "×"
                    color: root.foregroundColor
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.title
                    font.weight: Font.Medium
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.closeWindow(windowCell.index)
                  }
                }

                MouseArea {
                  id: windowDrag
                  anchors.fill: parent
                  enabled: !workspaceProcess.running && !root.windowDropAnimating
                  hoverEnabled: true
                  preventStealing: true
                  cursorShape: windowCell.beingDragged ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                  z: 2
                  property real pressOverviewX: 0
                  property real pressOverviewY: 0
                  property bool moved: false

                  onEntered: {
                    windowCell.hovered = true
                    root.selectedIndex = windowCell.index
                  }
                  onExited: if (!windowCell.beingDragged) windowCell.hovered = false
                  onPressed: function(mouse) {
                    var point = mapToItem(overview, mouse.x, mouse.y)
                    pressOverviewX = point.x
                    pressOverviewY = point.y
                    moved = false
                    root.selectedIndex = windowCell.index
                  }
                  onPositionChanged: function(mouse) {
                    if (!pressed) return
                    var point = mapToItem(overview, mouse.x, mouse.y)
                    var offsetX = point.x - pressOverviewX
                    var offsetY = point.y - pressOverviewY
                    if (!moved && Math.sqrt(offsetX * offsetX + offsetY * offsetY) <= 8) return

                    moved = true
                    root.windowDragActive = true
                    root.windowDragIndex = windowCell.index
                    windowCell.dragOffsetX = offsetX
                    windowCell.dragOffsetY = offsetY

                    var rowPoint = mapToItem(workspaceRow, mouse.x, mouse.y)
                    var targetIndex = WindowModel.spaceCardIndexAt(
                      rowPoint.x, rowPoint.y, root.workspaceIds.length,
                      workspaceRail.chipWidth, workspaceRail.chipHeight,
                      workspaceRail.chipSpacing)
                    var destination = targetIndex >= 0 ? root.workspaceIds[targetIndex] : -1
                    root.windowDropWorkspaceId = destination === root.selectedWorkspaceId
                      ? -1 : destination
                    var dropScale = root.windowDropWorkspaceId > 0
                      ? Math.min(0.32,
                        workspaceRail.chipWidth * 0.82 / Math.max(1, windowCard.width),
                        workspaceRail.chipHeight * 0.82 / Math.max(1, windowCard.height))
                      : 0.72
                    windowCell.dragScale = Math.max(0.1, dropScale)
                  }
                  onReleased: {
                    var destination = root.windowDropWorkspaceId
                    if (moved && destination > 0
                        && windowCell.animateToWorkspace(destination)) return

                    windowCell.dragOffsetX = 0
                    windowCell.dragOffsetY = 0
                    windowCell.dragScale = 1
                    root.windowDragActive = false
                    root.windowDragIndex = -1
                    root.windowDropWorkspaceId = -1
                  }
                  onCanceled: {
                    windowCell.dragOffsetX = 0
                    windowCell.dragOffsetY = 0
                    root.windowDragActive = false
                    root.windowDragIndex = -1
                    root.windowDropWorkspaceId = -1
                    windowCell.dragScale = 1
                    root.windowDropAnimating = false
                    root.pendingWindowToplevel = null
                    root.pendingWindowWorkspaceId = -1
                  }
                  onClicked: if (!moved) root.activateSelected()
                }
              }
            }
          }

          Column {
            visible: root.windows.length === 0
            anchors.centerIn: parent
            spacing: Math.max(Style.spacing.md, 12)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "No windows in Space " + root.selectedWorkspaceId
              color: root.foregroundColor
              font.family: Style.font.menuFamily
              font.pixelSize: Math.max(Style.font.title, 20)
              font.weight: Font.DemiBold
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: "Press Enter to switch to this workspace"
              color: root.foregroundColor
              opacity: 0.55
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.body
            }
          }
        }
      }
    }
  }
}
