import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import vm from "node:vm"

const source = readFileSync(new URL("../WindowModel.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const model = {}
vm.createContext(model)
vm.runInContext(source, model, { filename: "WindowModel.js" })

function toplevel(address, workspace, monitor, focusHistoryID, overrides = {}) {
  return {
    address,
    wayland: {},
    workspace: { id: workspace },
    monitor: { id: monitor },
    lastIpcObject: {
      mapped: true,
      hidden: false,
      acceptsInput: true,
      focusHistoryID,
      ...overrides
    }
  }
}

test("filters live toplevels by workspace and monitor and orders them by MRU", () => {
  const windows = [
    toplevel("0x3", 1, 7, 3),
    toplevel("0x1", 1, 7, 0),
    toplevel("0x2", 2, 7, 1),
    toplevel("0x4", 1, 8, 2),
    toplevel("0x5", 1, 7, 1, { hidden: true }),
    { ...toplevel("0x6", 1, 7, 2), wayland: null },
    toplevel("0x7", 1, 7, -1)
  ]

  const result = model.visibleToplevels(windows, 1, 7)
  assert.deepEqual(Array.from(result, window => window.address), ["0x1", "0x3", "0x7"])
})

test("accepts Quickshell's array-like object models", () => {
  const first = toplevel("0x1", 1, 7, 0)
  const second = toplevel("0x2", 1, 7, 1)
  const qmlList = { 0: first, 1: second, length: 2 }

  assert.deepEqual(
    Array.from(model.visibleToplevels(qmlList, 1, 7), window => window.address),
    ["0x1", "0x2"]
  )
})

test("lists only positive workspaces on the target monitor and retains selection", () => {
  const workspaces = [
    { id: 4, monitor: { id: 7 } },
    { id: 2, monitor: { id: 7 } },
    { id: 3, monitor: { id: 8 } },
    { id: -99, monitor: { id: 7 } },
    { id: 11, monitor: { id: 7 } }
  ]

  assert.deepEqual(Array.from(model.workspaceIds(workspaces, 7, 1)), [1, 2, 4])
  assert.deepEqual(Array.from(model.workspaceIds(workspaces, 7, 4)), [2, 4])
  assert.deepEqual(Array.from(model.workspaceIds(workspaces, 7, 1, [3, 5])), [1, 2, 3, 4, 5])
})

test("chooses an adaptive grid for normal and ultrawide monitors", () => {
  assert.equal(model.gridColumns(0, 1920, 1080), 0)
  assert.equal(model.gridColumns(1, 1920, 1080), 1)
  assert.equal(model.gridColumns(5, 1920, 1080), 3)
  assert.equal(model.gridColumns(5, 7680, 1600), 5)
  assert.equal(model.gridColumns(4, 800, 1200), 2)
})

test("keyboard navigation wraps and preserves columns across short rows", () => {
  assert.equal(model.nextGridIndex(4, 1, 0, 3, 5), 0)
  assert.equal(model.nextGridIndex(0, -1, 0, 3, 5), 4)
  assert.equal(model.nextGridIndex(1, 0, 1, 3, 5), 4)
  assert.equal(model.nextGridIndex(2, 0, 1, 3, 5), 4)
  assert.equal(model.nextGridIndex(4, 0, 1, 3, 5), 1)
  assert.equal(model.nextGridIndex(-1, 0, 0, 3, 5), 0)
  assert.equal(model.nextGridIndex(0, 1, 0, 0, 0), -1)
})

test("finds the lowest free workspace id within the cap", () => {
  assert.equal(model.nextFreeWorkspaceId([1, 2, 4], 10), 3)
  assert.equal(model.nextFreeWorkspaceId([2, 3], 10), 1)
  assert.equal(model.nextFreeWorkspaceId([1, 2, 3], 3), -1)
  assert.equal(model.nextFreeWorkspaceId([], 10), 1)
  assert.equal(model.nextFreeWorkspaceId([-5, 0, "x"], 10), 1)
})

test("moves a value between positions without mutating the source", () => {
  const ids = [1, 2, 3, 4]
  assert.deepEqual(Array.from(model.moveArrayValue(ids, 0, 2)), [2, 3, 1, 4])
  assert.deepEqual(Array.from(model.moveArrayValue(ids, 3, 0)), [4, 1, 2, 3])
  assert.deepEqual(Array.from(ids), [1, 2, 3, 4])
  assert.equal(model.moveArrayValue(ids, 1, 1), null)
  assert.equal(model.moveArrayValue(ids, 0, 9), null)
  assert.equal(model.moveArrayValue([], 0, 0), null)
})

test("plans a collision-free two-phase workspace renumber", () => {
  const plan = JSON.parse(JSON.stringify(model.reassignPlan([1, 2, 3, 4], [3, 1, 2, 4], 100)))
  assert.deepEqual(plan, [
    { workspace: 3, id: 100 },
    { workspace: 1, id: 101 },
    { workspace: 2, id: 102 },
    { workspace: 100, id: 1 },
    { workspace: 101, id: 2 },
    { workspace: 102, id: 3 }
  ])
  const sparsePlan = JSON.parse(JSON.stringify(
    model.reassignPlan([1, 2, 3], [1, 3, 2], 200, [1, 3])
  ))
  assert.deepEqual(sparsePlan, [
    { workspace: 3, id: 200 },
    { workspace: 200, id: 2 }
  ])
  assert.deepEqual(Array.from(model.reassignPlan([1, 2], [1, 2], 100)), [])
  assert.deepEqual(Array.from(model.reassignPlan([1], [1, 2], 100)), [])
  assert.deepEqual(Array.from(model.reassignPlan([1, 2], [2, 1], 0)), [])
})

test("remaps managed space ids after content reordering", () => {
  assert.deepEqual(
    Array.from(model.remapWorkspaceIds([2, 4], [1, 2, 3, 4], [3, 1, 4, 2])),
    [3, 4]
  )
  assert.deepEqual(Array.from(model.remapWorkspaceIds([], [1, 2], [2, 1])), [])
  assert.deepEqual(Array.from(model.remapWorkspaceIds([1], [1], [1, 2])), [])
})

test("picks an adjacent neighbor for workspace removal", () => {
  assert.equal(model.removalNeighbor([1, 2, 3], 2), 1)
  assert.equal(model.removalNeighbor([1, 2, 3], 1), 2)
  assert.equal(model.removalNeighbor([1, 2, 3], 3), 2)
  assert.equal(model.removalNeighbor([1], 1), -1)
  assert.equal(model.removalNeighbor([1, 2], 9), -1)
})

test("maps space row pointer hits to card indexes and rejects gaps and out-of-bounds", () => {
  const width = 144
  const height = 58
  const spacing = 10

  // Cards cover [0,144), [154,298), [308,452).
  assert.equal(model.spaceCardIndexAt(0, 29, 3, width, height, spacing), 0)
  assert.equal(model.spaceCardIndexAt(72, 0, 3, width, height, spacing), 0)
  assert.equal(model.spaceCardIndexAt(226, 57.5, 3, width, height, spacing), 1)
  assert.equal(model.spaceCardIndexAt(308, 29, 3, width, height, spacing), 2)
  assert.equal(model.spaceCardIndexAt(451.9, 29, 3, width, height, spacing), 2)

  // Gaps between cards and both edges of the row reject.
  assert.equal(model.spaceCardIndexAt(150, 29, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(300, 29, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(460, 29, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(-0.5, 29, 3, width, height, spacing), -1)

  // Half-open card edges: right edge of any card rejects.
  assert.equal(model.spaceCardIndexAt(144, 29, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(452, 29, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(462, 29, 3, width, height, spacing), -1)

  // Vertical bounds follow the same half-open rule.
  assert.equal(model.spaceCardIndexAt(72, -1, 3, width, height, spacing), -1)
  assert.equal(model.spaceCardIndexAt(72, 58, 3, width, height, spacing), -1)
})

test("rejects empty space rows, degenerate geometry, and invalid coordinates", () => {
  assert.equal(model.spaceCardIndexAt(72, 29, 0, 144, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(72, 29, [], 144, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(72, 29, { length: 0 }, 144, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(72, 29, -3, 144, 58, 10), -1)

  assert.equal(model.spaceCardIndexAt(72, 29, 3, 0, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(72, 29, 3, 144, -1, 10), -1)

  assert.equal(model.spaceCardIndexAt(NaN, 29, 3, 144, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(72, undefined, 3, 144, 58, 10), -1)
})

test("resolves single cards and Quickshell array-like counts", () => {
  assert.equal(model.spaceCardIndexAt(143, 29, 1, 144, 58, 10), 0)
  assert.equal(model.spaceCardIndexAt(144, 29, 1, 144, 58, 10), -1)
  assert.equal(model.spaceCardIndexAt(200, 29, 1, 144, 58, 10), -1)

  const qmlIds = { 0: 1, 1: 2, length: 2 }
  assert.equal(model.spaceCardIndexAt(0, 29, qmlIds, 144, 58, 10), 0)
  assert.equal(model.spaceCardIndexAt(160, 29, qmlIds, 144, 58, 10), 1)
  assert.equal(model.spaceCardIndexAt(150, 29, qmlIds, 144, 58, 10), -1)
})

test("normalizes titles without breaking short labels", () => {
  assert.equal(model.shortenedTitle("  A   useful title  ", 20), "A useful title")
  assert.equal(model.shortenedTitle("A very long window title", 10), "A very lo…")
})
