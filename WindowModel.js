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

function desktopToplevels(toplevels, wantedWorkspaceId, wantedMonitorId) {
  var source = valuesOf(toplevels)
  var workspace = numberOr(wantedWorkspaceId, -1)
  var monitor = numberOr(wantedMonitorId, -1)
  var result = []

  for (var i = 0; i < source.length; i++) {
    var toplevel = source[i]
    if (!isVisibleToplevel(toplevel) || monitorId(toplevel) !== monitor) continue
    if (workspaceId(toplevel) !== workspace && metadata(toplevel).pinned !== true) continue
    result.push(toplevel)
  }

  result.sort(function(left, right) {
    var byHistory = historyRank(right) - historyRank(left)
    if (byHistory !== 0) return byHistory
    var leftAddress = stableAddress(left)
    var rightAddress = stableAddress(right)
    return leftAddress < rightAddress ? -1 : (leftAddress > rightAddress ? 1 : 0)
  })
  return result
}

function workspaceThumbnailRect(toplevel, monitor, frameWidth, frameHeight) {
  var data = metadata(toplevel)
  var at = valuesOf(data.at)
  var size = valuesOf(data.size)
  var monitorWidth = numberOr(monitor && monitor.width, 0)
  var monitorHeight = numberOr(monitor && monitor.height, 0)
  var width = numberOr(frameWidth, 0)
  var height = numberOr(frameHeight, 0)
  if (at.length < 2 || size.length < 2 || monitorWidth <= 0 || monitorHeight <= 0
      || width <= 0 || height <= 0) return null

  var scaleX = width / monitorWidth
  var scaleY = height / monitorHeight
  return {
    x: (numberOr(at[0], 0) - numberOr(monitor && monitor.x, 0)) * scaleX,
    y: (numberOr(at[1], 0) - numberOr(monitor && monitor.y, 0)) * scaleY,
    width: Math.max(1, numberOr(size[0], 1) * scaleX),
    height: Math.max(1, numberOr(size[1], 1) * scaleY)
  }
}




function workspaceIds(workspaces, wantedMonitorId, selectedWorkspaceId, managedIds) {
  var source = valuesOf(workspaces)
  var monitor = numberOr(wantedMonitorId, -1)
  var selected = numberOr(selectedWorkspaceId, -1)
  var ids = []

  function include(id) {
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  include(selected)
  var managed = valuesOf(managedIds)
  for (var i = 0; i < managed.length; i++) include(numberOr(managed[i], -1))

  for (var j = 0; j < source.length; j++) {
    var workspace = source[j]
    if (!workspace) continue

    var workspaceMonitor = workspace.monitor
      ? numberOr(workspace.monitor.id, -1)
      : numberOr(workspace.lastIpcObject && workspace.lastIpcObject.monitor, -1)
    if (monitor >= 0 && workspaceMonitor !== monitor) continue
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

function nextFreeWorkspaceId(existingIds, cap) {
  var ceiling = Math.floor(numberOr(cap, 10))
  if (ceiling < 1) return -1

  var taken = []
  var source = valuesOf(existingIds)
  for (var i = 0; i < source.length; i++) {
    var id = Math.floor(numberOr(source[i], -1))
    if (id > 0) taken.push(id)
  }

  for (var candidate = 1; candidate <= ceiling; candidate++) {
    if (taken.indexOf(candidate) === -1) return candidate
  }
  return -1
}

function moveArrayValue(values, from, to) {
  var size = valuesOf(values).length
  var source = Math.floor(numberOr(from, -1))
  var target = Math.floor(numberOr(to, -1))
  if (size === 0 || source < 0 || source >= size || target < 0 || target >= size
    || source === target) return null

  var next = []
  for (var i = 0; i < size; i++) next.push(values[i])
  var moved = next.splice(source, 1)[0]
  next.splice(target, 0, moved)
  return next
}

function reassignPlan(currentIds, desiredIds, tempBase, existingIds) {
  var current = valuesOf(currentIds)
  var desired = valuesOf(desiredIds)
  if (current.length === 0 || current.length !== desired.length) return []

  var base = Math.floor(numberOr(tempBase, 0))
  if (base <= 0) return []

  var existing = existingIds === undefined ? desired : valuesOf(existingIds)
  var phase = []
  var seen = []
  for (var i = 0; i < existing.length; i++) {
    var workspace = numberOr(existing[i], -1)
    if (workspace <= 0 || seen.indexOf(workspace) !== -1) continue
    seen.push(workspace)

    var position = desired.indexOf(workspace)
    if (position < 0) continue
    var targetId = numberOr(current[position], -1)
    if (targetId <= 0 || targetId === workspace) continue
    phase.push({ workspace: workspace, temporaryId: base + phase.length, targetId: targetId })
  }

  var moves = []
  for (var j = 0; j < phase.length; j++)
    moves.push({ workspace: phase[j].workspace, id: phase[j].temporaryId })
  for (var k = 0; k < phase.length; k++)
    moves.push({ workspace: phase[k].temporaryId, id: phase[k].targetId })
  return moves
}

function removalNeighbor(ids, removedId) {
  var source = valuesOf(ids)
  if (source.length < 2) return -1

  var index = source.indexOf(Math.floor(numberOr(removedId, -1)))
  if (index === -1) return -1
  return index > 0 ? numberOr(source[index - 1], -1) : numberOr(source[1], -1)
}

function remapWorkspaceIds(ids, currentIds, desiredIds) {
  var source = valuesOf(ids)
  var current = valuesOf(currentIds)
  var desired = valuesOf(desiredIds)
  if (current.length === 0 || current.length !== desired.length) return []

  var remapped = []
  for (var i = 0; i < source.length; i++) {
    var oldId = numberOr(source[i], -1)
    var position = desired.indexOf(oldId)
    if (position < 0) continue
    var newId = numberOr(current[position], -1)
    if (newId > 0 && remapped.indexOf(newId) === -1) remapped.push(newId)
  }
  remapped.sort(function(left, right) { return left - right })
  return remapped
}

function normalizedSpaceName(value, limit) {
  var text = String(value || "").replace(/\s+/g, " ").trim()
  var maximum = Math.max(1, numberOr(limit, 32))
  return text.slice(0, maximum)
}

function remapSpaceNames(names, currentIds, desiredIds) {
  var source = names && typeof names === "object" ? names : ({})
  var current = valuesOf(currentIds)
  var desired = valuesOf(desiredIds)
  var canRemap = current.length > 0 && current.length === desired.length
  var result = ({})

  for (var key in source) {
    var oldId = Math.floor(numberOr(key, -1))
    var name = normalizedSpaceName(source[key], 32)
    if (oldId <= 0 || !name) continue

    var newId = oldId
    if (canRemap) {
      var position = desired.indexOf(oldId)
      if (position >= 0) newId = Math.floor(numberOr(current[position], oldId))
    }
    if (newId > 0) result[String(newId)] = name
  }
  return result
}

function spaceCardIndexAt(x, y, count, cardWidth, cardHeight, cardSpacing) {
  var numericCount = Math.floor(numberOr(count, 0))
  var size = numericCount > 0 ? numericCount : valuesOf(count).length
  var width = numberOr(cardWidth, 0)
  var height = numberOr(cardHeight, 0)
  var spacing = Math.max(0, numberOr(cardSpacing, 0))
  if (size === 0 || width <= 0 || height <= 0) return -1

  var px = Number(x)
  var py = Number(y)
  if (!isFinite(px) || !isFinite(py)) return -1
  if (px < 0 || py < 0 || py >= height) return -1

  var step = width + spacing
  var slot = Math.floor(px / step)
  if (slot >= size) return -1
  return px - slot * step < width ? slot : -1
}


function shortenedTitle(value, limit) {
  var text = String(value || "").replace(/\s+/g, " ").trim()
  var maximum = Math.max(1, numberOr(limit, 80))
  return text.length <= maximum ? text : text.slice(0, maximum - 1) + "…"
}
