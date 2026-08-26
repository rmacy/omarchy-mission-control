.pragma library

function numberOr(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function valuesOf(value) {
  if (Array.isArray(value)) return value
  if (value && typeof value !== "string" && typeof value.length === "number") return value
  if (value && Array.isArray(value.values)) return value.values
  return []
}

function metadata(toplevel) {
  return toplevel && toplevel.lastIpcObject ? toplevel.lastIpcObject : ({})
}

function workspaceId(toplevel) {
  if (toplevel && toplevel.workspace)
    return numberOr(toplevel.workspace.id, -1)

  var data = metadata(toplevel)
  if (data.workspace) return numberOr(data.workspace.id, -1)
  return -1
}

function monitorId(toplevel) {
  if (toplevel && toplevel.monitor)
    return numberOr(toplevel.monitor.id, -1)

  return numberOr(metadata(toplevel).monitor, -1)
}

function historyRank(toplevel) {
  var data = metadata(toplevel)
  var rank = numberOr(data.focusHistoryID,
    numberOr(toplevel && toplevel.focusHistoryID, 2147483647))
  return rank >= 0 ? rank : 2147483647
}

function stableAddress(toplevel) {
  var data = metadata(toplevel)
  return String((toplevel && toplevel.address) || data.address || data.stableId || "")
}

function isVisibleToplevel(toplevel) {
  if (!toplevel || !toplevel.wayland) return false

  var data = metadata(toplevel)
  if (data.mapped === false || data.hidden === true || data.acceptsInput === false) return false
  return workspaceId(toplevel) > 0 && monitorId(toplevel) >= 0
}

function visibleToplevels(toplevels, wantedWorkspaceId, wantedMonitorId) {
  var source = valuesOf(toplevels)
  var workspace = numberOr(wantedWorkspaceId, -1)
  var monitor = numberOr(wantedMonitorId, -1)
  var result = []

  for (var i = 0; i < source.length; i++) {
    var toplevel = source[i]
    if (!isVisibleToplevel(toplevel)) continue
    if (workspaceId(toplevel) !== workspace) continue
    if (monitorId(toplevel) !== monitor) continue
    result.push(toplevel)
  }

  result.sort(function(left, right) {
    var byHistory = historyRank(left) - historyRank(right)
    if (byHistory !== 0) return byHistory

    var leftAddress = stableAddress(left)
    var rightAddress = stableAddress(right)
    return leftAddress < rightAddress ? -1 : (leftAddress > rightAddress ? 1 : 0)
  })
  return result
}




function workspaceIds(workspaces, wantedMonitorId, selectedWorkspaceId) {
  var source = valuesOf(workspaces)
  var monitor = numberOr(wantedMonitorId, -1)
  var selected = numberOr(selectedWorkspaceId, -1)
  var ids = []

  function include(id) {
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  include(selected)
  for (var i = 0; i < source.length; i++) {
    var workspace = source[i]
    if (!workspace) continue

    var workspaceMonitor = workspace.monitor
      ? numberOr(workspace.monitor.id, -1)
      : numberOr(workspace.lastIpcObject && workspace.lastIpcObject.monitor, -1)
    if (workspaceMonitor !== monitor) continue
    include(numberOr(workspace.id, -1))
  }

  ids.sort(function(left, right) { return left - right })
  return ids
}

function gridColumns(count, width, height) {
  var size = Math.max(0, Math.floor(numberOr(count, 0)))
  if (size <= 1) return size

  var availableWidth = Math.max(1, numberOr(width, 1))
  var availableHeight = Math.max(1, numberOr(height, 1))
  var aspect = Math.max(0.5, Math.min(6, availableWidth / availableHeight))
  var columns = Math.ceil(Math.sqrt(size * aspect * 0.95))
  return Math.max(1, Math.min(size, columns))
}

function nextGridIndex(index, horizontal, vertical, columns, count) {
  var size = Math.max(0, Math.floor(numberOr(count, 0)))
  if (size === 0) return -1

  var current = Math.floor(numberOr(index, 0))
  if (current < 0 || current >= size) current = 0

  var horizontalStep = Math.sign(numberOr(horizontal, 0))
  if (horizontalStep !== 0)
    return ((current + horizontalStep) % size + size) % size

  var verticalStep = Math.sign(numberOr(vertical, 0))
  if (verticalStep === 0) return current

  var columnCount = Math.max(1, Math.min(size, Math.floor(numberOr(columns, 1))))
  var rowCount = Math.ceil(size / columnCount)
  var currentRow = Math.floor(current / columnCount)
  var currentColumn = current % columnCount
  var targetRow = ((currentRow + verticalStep) % rowCount + rowCount) % rowCount
  var rowStart = targetRow * columnCount
  var rowLength = Math.min(columnCount, size - rowStart)
  return rowStart + Math.min(currentColumn, rowLength - 1)
}


function shortenedTitle(value, limit) {
  var text = String(value || "").replace(/\s+/g, " ").trim()
  var maximum = Math.max(1, numberOr(limit, 80))
  return text.length <= maximum ? text : text.slice(0, maximum - 1) + "…"
}
