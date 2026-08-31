import assert from "node:assert/strict"
import { readFileSync } from "node:fs"
import { test } from "node:test"
import vm from "node:vm"

const qml = readFileSync(new URL("../WindowSwitcher.qml", import.meta.url), "utf8")
const missionQml = readFileSync(new URL("../MissionControl.qml", import.meta.url), "utf8")
const switcherSource = readFileSync(new URL("../SwitcherModel.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/m, "")
const switcherModel = {}
vm.createContext(switcherModel)
vm.runInContext(switcherSource, switcherModel, { filename: "SwitcherModel.js" })

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

test("Mission Control renders workspace and client labels as plain text", () => {
  assert.match(missionQml,
    /text:\s*workspaceChip\.displayName\s*\n\s*textFormat:\s*Text\.PlainText/)
  assert.match(missionQml,
    /text:\s*String\(windowCell\.modelData\.appName[\s\S]{0,100}?textFormat:\s*Text\.PlainText/)
  assert.match(missionQml,
    /text:\s*String\(windowCell\.modelData\.title[\s\S]{0,100}?textFormat:\s*Text\.PlainText/)
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

test("Mission Control client-metadata fallback icons are sanitized before resolution", () => {
  assert.match(missionQml,
    /var iconName = entry \? String\(entry\.icon \|\| ""\)\s*\n\s*: SwitcherModel\.safeIconName\(metadata\.initialClass \|\| metadata\.class\)/)
  assert.match(missionQml, /root\.appLibrary\.iconSource\(iconName\)/)
  assert.match(missionQml, /Quickshell\.iconPath\(iconName, true\)/)
  assert.doesNotMatch(missionQml,
    /(?:iconSource|iconPath)\(String\(metadata\.(?:initialClass|class)/)
  assert.doesNotMatch(missionQml, /safeIconName\(entry\.icon/)

  const fallbackFor = metadata =>
    switcherModel.safeIconName(metadata.initialClass || metadata.class)
  assert.equal(fallbackFor({ initialClass: "file:///tmp/bomb.svg" }),
    "application-x-executable")
  assert.equal(fallbackFor({ initialClass: "/tmp/bomb.svg" }),
    "application-x-executable")
  assert.equal(fallbackFor({ initialClass: "https://example.test/icon" }),
    "application-x-executable")
  assert.equal(fallbackFor({ initialClass: "image://provider/payload" }),
    "application-x-executable")
  assert.equal(fallbackFor({ initialClass: "", class: "org.example.Chromium" }),
    "org.example.Chromium")
  assert.equal(fallbackFor({}), "application-x-executable")
})
