import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const qml = readFileSync(new URL("../MissionControl.qml", import.meta.url), "utf8")

test("overview and workspace thumbnail models have explicit bounds", () => {
  assert.match(qml, /maxOverviewWindows:\s*WindowModel\.MAX_SELECTED_GRID_CAPTURES/)
  assert.match(qml, /maxSpaceThumbnailWindows:\s*WindowModel\.MAX_WORKSPACE_THUMBNAIL_CAPTURES/)
  assert.match(qml, /WindowModel\.selectedGridCaptureModel\(/)
  assert.match(qml, /WindowModel\.workspaceThumbnailCaptureModel\(/)
})

test("space rail bounds duplicate live captures and discloses omitted windows", () => {
  assert.match(qml, /id:\s*thumbnailWindowRepeater[\s\S]{0,700}?ScreencopyView\s*\{[\s\S]{0,180}?live:\s*root\.opened && workspaceChip\.selected/)
  assert.match(qml, /renderedWindowCount < workspaceChip\.windowCount/)
  assert.match(qml, /previewModel\.omittedCount/)
})

test("animated close destroys retained workspace preview delegates after exit", () => {
  assert.match(qml, /function close\(\)\s*\{[\s\S]{0,500}?closeAnimationTimer\.restart\(\)/)
  assert.match(qml, /id:\s*closeAnimationTimer[\s\S]{0,120}?onTriggered:\s*root\.finishClose\(\)/)
  assert.match(qml, /function finishClose\(\)\s*\{[\s\S]{0,600}?root\.workspaceIds = \[\]/)
  assert.match(qml, /function finishClose\(\)\s*\{[\s\S]{0,600}?root\.desktopCache = \(\{\}\)/)
})

test("status exposes rendered and omitted window counts", () => {
  assert.match(qml, /totalWindowCount:\s*root\.totalWindowCount/)
  assert.match(qml, /windowCountCapped:\s*root\.totalWindowCount > root\.windows\.length/)
  assert.match(qml, /omittedWindowCount:\s*Math\.max\(0, root\.totalWindowCount - root\.windows\.length\)/)
})
