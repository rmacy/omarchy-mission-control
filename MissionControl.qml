import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "WindowModel.js" as WindowModel

Item {
  id: root

  property var shell: null
  property var manifest: null
  readonly property var appLibrary: root.shell ? root.shell.appLibrary : null
  readonly property int foreignToplevelCount: ToplevelManager.toplevels.values.length

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
    root.workspaceIds = WindowModel.workspaceIds(
      Hyprland.workspaces.values, root.targetMonitorId, root.selectedWorkspaceId)

    if (root.workspaceIds.indexOf(root.selectedWorkspaceId) === -1)
      root.selectedWorkspaceId = root.workspaceIds.length > 0 ? root.workspaceIds[0] : -1

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
  }

  function selectWorkspace(workspaceId) {
    var nextId = Number(workspaceId)
    if (nextId <= 0 || nextId === root.selectedWorkspaceId) return
    root.selectedWorkspaceId = nextId
    root.refreshWindows("")
    keyScope.forceActiveFocus()
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


  Timer {
    id: refreshTimer
    interval: 45
    repeat: false
    onTriggered: if (root.opened) root.refreshOverview()
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
        if (event.key === Qt.Key_Escape) {
          root.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.activateSelected()
          event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          var reverse = event.key === Qt.Key_Backtab || !!(event.modifiers & Qt.ShiftModifier)
          root.moveSelection(reverse ? -1 : 1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Left) {
          root.moveSelection(-1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Right) {
          root.moveSelection(1, 0)
          event.accepted = true
        } else if (event.key === Qt.Key_Up) {
          root.moveSelection(0, -1)
          event.accepted = true
        } else if (event.key === Qt.Key_Down) {
          root.moveSelection(0, 1)
          event.accepted = true
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
          var workspaceId = event.key - Qt.Key_0
          if (root.workspaceIds.indexOf(workspaceId) !== -1) {
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
            text: "Control + Up  ·  three-finger swipe up  ·  arrows to navigate  ·  Enter to open"
            color: root.foregroundColor
            opacity: 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        Rectangle {
          id: workspaceRail
          anchors.top: heading.bottom
          anchors.topMargin: Math.max(Style.space(18), 18)
          anchors.horizontalCenter: parent.horizontalCenter
          width: Math.min(parent.width, workspaceRow.implicitWidth + Math.max(Style.space(20), 20) * 2)
          height: Math.max(Style.space(58), 58)
          radius: Math.max(Style.cornerRadius, 18)
          color: Util.alpha(root.backgroundColor, 0.88)
          border.color: root.borderColor
          border.width: 1

          MouseArea { anchors.fill: parent; onClicked: function(mouse) { mouse.accepted = true } }

          Row {
            id: workspaceRow
            anchors.centerIn: parent
            spacing: Math.max(Style.spacing.sm, 8)

            Repeater {
              model: root.workspaceIds

              Rectangle {
                id: workspaceChip
                required property int modelData
                readonly property bool selected: modelData === root.selectedWorkspaceId
                readonly property int windowCount: root.workspaceWindowCount(modelData)

                width: Math.max(Style.space(92), 116)
                height: Math.max(Style.space(38), 38)
                radius: height / 2
                color: selected ? root.selectedColor : "transparent"
                border.color: selected ? root.selectedBorderColor : Util.alpha(root.borderColor, 0.7)
                border.width: selected ? 2 : 1

                Text {
                  anchors.centerIn: parent
                  text: "Space " + workspaceChip.modelData + "  ·  " + workspaceChip.windowCount
                  color: workspaceChip.selected ? root.selectedTextColor : root.foregroundColor
                  opacity: workspaceChip.selected ? 1 : 0.72
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  font.weight: workspaceChip.selected ? Font.DemiBold : Font.Medium
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectWorkspace(workspaceChip.modelData)
                  onDoubleClicked: root.activateWorkspace()
                }
              }
            }
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
            model: root.windows

            Item {
              id: windowCell
              required property var modelData
              required property int index
              readonly property bool selected: index === root.selectedIndex
              property bool hovered: false
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
                radius: Math.max(Style.cornerRadius, 18)
                color: windowCell.selected
                  ? Util.alpha(root.selectedColor, 0.92)
                  : Util.alpha(root.backgroundColor, 0.82)
                border.color: windowCell.selected ? root.selectedBorderColor : root.borderColor
                border.width: windowCell.selected ? 3 : 1
                scale: windowCell.selected ? 1 : (windowCell.hovered ? 0.99 : 0.965)
                opacity: windowCell.selected || windowCell.hovered ? 1 : 0.82

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
                  visible: windowCell.hovered
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
                  anchors.fill: parent
                  hoverEnabled: true
                  z: 2
                  onEntered: {
                    windowCell.hovered = true
                    root.selectedIndex = windowCell.index
                  }
                  onExited: windowCell.hovered = false
                  onClicked: root.activateSelected()
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
