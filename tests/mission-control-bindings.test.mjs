import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const service = readFileSync(new URL("../Service.qml", import.meta.url), "utf8")
const apply = service.match(/function applyLua\(\)\s*\{([\s\S]*?)\n  \}\n\n  function cleanupLua/)?.[1] || ""
const cleanup = service.match(/function cleanupLua\(\)\s*\{([\s\S]*?)\n  \}\n\n  function queueApply/)?.[1] || ""

test("Control-Up only opens and Control-Down only closes Mission Control", () => {
  assert.match(apply, /hl\.bind\("CTRL \+ UP"/)
  assert.match(apply, /shell summon bitr0t\.mission-control/)
  assert.match(apply, /description = "Open Mission Control"/)
  assert.match(apply, /hl\.bind\("CTRL \+ DOWN"/)
  assert.match(apply, /shell hide bitr0t\.mission-control/)
  assert.match(apply, /description = "Close Mission Control"/)
  assert.doesNotMatch(apply, /CTRL \+ UP[\s\S]{0,220}?shell toggle bitr0t\.mission-control/)
})

test("three-finger up shares the open-only path", () => {
  assert.match(apply, /direction = "up"/)
  assert.match(apply, /action = function\(\)[\s\S]*?shell summon bitr0t\.mission-control/)
})

test("cleanup retires both global shortcuts", () => {
  assert.match(cleanup, /hl\.unbind\("CTRL \+ UP"\)/)
  assert.match(cleanup, /hl\.unbind\("CTRL \+ DOWN"\)/)
})
