import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"

const qml = readFileSync(new URL("../WindowSwitcher.qml", import.meta.url), "utf8")

test("client-derived labels are always rendered as plain text", () => {
  const plainTextBindings = qml.match(/textFormat:\s*Text\.PlainText/g) || []
  assert.ok(plainTextBindings.length >= 5, "expected every dynamic label and error label to be PlainText")
  assert.match(qml,
    /text:\s*root\.clients\.length === 1[\s\S]{0,120}?appName[\s\S]{0,120}?textFormat:\s*Text\.PlainText/)
  assert.match(qml,
    /text:\s*root\.clients\.length === 1[\s\S]{0,120}?displayTitle[\s\S]{0,120}?textFormat:\s*Text\.PlainText/)
  assert.match(qml,
    /text:\s*String\(windowCard\.modelData\.appName[\s\S]{0,120}?textFormat:\s*Text\.PlainText/)
  assert.match(qml,
    /text:\s*String\(windowCard\.modelData\.displayTitle[\s\S]{0,120}?textFormat:\s*Text\.PlainText/)
  assert.doesNotMatch(qml, /textFormat:\s*Text\.(?:AutoText|RichText|StyledText|MarkdownText)/)
})

test("window discovery uses the bounded native Hyprland model", () => {
  assert.match(qml, /SwitcherModel\.switchableClients\(Hyprland\.toplevels/)
  assert.match(qml, /SwitcherModel\.MAX_CLIENTS/)
  assert.doesNotMatch(qml, /hyprctl["']?\s*,\s*["']-j["']\s*,\s*["']clients/)
  assert.doesNotMatch(qml, /StdioCollector/)
})

test("commit revalidates and focuses stable identity", () => {
  assert.match(qml, /findSwitchableByStableId\(Hyprland\.toplevels/)
  assert.match(qml, /window = "stableid:/)
  assert.doesNotMatch(qml, /window = "address:/)
})

test("class fallback icons pass through the strict model sanitizer", () => {
  assert.match(qml, /SwitcherModel\.safeIconName\(fallbackClass\)/)
})

test("single and multi cards expose accessible button actions", () => {
  assert.equal((qml.match(/Accessible\.role:\s*Accessible\.Button/g) || []).length, 2)
  assert.equal((qml.match(/Accessible\.onPressAction/g) || []).length, 2)
})
