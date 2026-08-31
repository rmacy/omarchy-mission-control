import assert from "node:assert/strict"
import { readFileSync, readdirSync } from "node:fs"
import { fileURLToPath } from "node:url"
import { test } from "node:test"

const root = new URL("../", import.meta.url)
const rootPath = fileURLToPath(root)
const manifest = JSON.parse(readFileSync(new URL("manifest.json", root), "utf8"))
const shippedFiles = readdirSync(rootPath, { withFileTypes: true })
  .filter(entry => entry.isFile() && /\.(?:js|json|md|qml)$/.test(entry.name))
  .map(entry => ({
    name: entry.name,
    source: readFileSync(new URL(entry.name, root), "utf8"),
  }))

const legacyId = ["bitr0t", "mission-control"].join(".")
const legacyDashNamespace = ["bitr0t", "mission-control"].join("-")
const legacyLuaNamespace = ["bitr0t", "mission_control"].join("_")

test("marketplace package uses one public plugin identity", () => {
  assert.equal(manifest.id, "bitr0t.omarchy-mission-control")
  assert.equal(manifest.version, "4.0.0")
  for (const file of shippedFiles) {
    if (file.name !== "README.md")
      assert.ok(!file.source.includes(legacyId), `${file.name} contains the legacy plugin id`)
    assert.ok(!file.source.includes(legacyDashNamespace), `${file.name} contains the legacy IPC namespace`)
    assert.ok(!file.source.includes(legacyLuaNamespace), `${file.name} contains the legacy Lua namespace`)
  }
})

test("plugin service never rewrites shell configuration", () => {
  const service = readFileSync(new URL("Service.qml", root), "utf8")
  assert.doesNotMatch(service, /mutateShellConfig|barMigration|shellConfig|bar\.layout/)
})

test("marketplace package documents explicit install and removal", () => {
  const readme = readFileSync(new URL("README.md", root), "utf8")
  assert.match(readme, /omarchy plugin add https:\/\/github\.com\/rmacy\/omarchy-mission-control\.git --enable/)
  assert.match(readme, /omarchy plugin remove bitr0t\.omarchy-mission-control/)
  assert.match(readme, /omarchy plugin disable bitr0t\.mission-control/)
  assert.match(readme, /omarchy plugin remove bitr0t\.mission-control --yes/)
  assert.match(readme, /never edits `~\/\.config\/omarchy\/shell\.json` or `bar\.layout` itself/)
  assert.match(readme, /\[MIT\]\(LICENSE\)/)
})
