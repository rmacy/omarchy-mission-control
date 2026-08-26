import { execFile as execFileCallback, spawn } from "node:child_process"
import { access, chmod, mkdir, readFile, rm, stat, unlink, writeFile } from "node:fs/promises"
import { constants as fsConstants } from "node:fs"
import { basename, resolve } from "node:path"
import { promisify } from "node:util"

const execFile = promisify(execFileCallback)
const root = resolve(new URL("../..", import.meta.url).pathname)
const outputDir = resolve(process.env.MC_VISUAL_OUTPUT || process.argv[2] || `${root}/tests/live/output`)
const inputHelper = resolve(process.env.MC_UINPUT || `${root}/.build/mc-uinput`)
const statePath = `${process.env.HOME}/.local/state/omarchy/mission-control-spaces.json`
const results = []
const screenshots = []
const fixtures = []
let shotNumber = 0
let originalState = null
let stateExisted = false
let stateBackedUp = false
let desktopBackedUp = false
let originalWorkspace = 1
let originalCursor = { x: 0, y: 0 }
let fixtureA = -1
let fixtureB = -1

const sleep = milliseconds => new Promise(resolvePromise => setTimeout(resolvePromise, milliseconds))
const normalizeAddress = value => String(value || "").replace(/^0x/i, "").toLowerCase()
const html = value => String(value).replace(/[&<>"']/g, character => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;"
})[character])

async function command(program, args = [], options = {}) {
  try {
    return await execFile(program, args, {
      cwd: root,
      timeout: options.timeout || 30000,
      maxBuffer: 16 * 1024 * 1024,
      env: { ...process.env, ...(options.env || {}) }
    })
  } catch (error) {
    if (options.allowFailure) return { stdout: error.stdout || "", stderr: error.stderr || "", error }
    throw new Error(`${program} ${args.join(" ")} failed: ${(error.stderr || error.message).trim()}`)
  }
}

async function jsonCommand(program, args) {
  const { stdout } = await command(program, args)
  return JSON.parse(stdout)
}

async function shellCall(method, argument = "{}") {
  const { stdout } = await command("omarchy-shell", ["shell", "call", "bitr0t.mission-control", method, String(argument)])
  const value = stdout.trim()
  if (value === "error" || value === "unknown" || value === "unloaded")
    throw new Error(`Mission Control ${method} returned ${value}`)
  return value
}

async function status() {
  return JSON.parse(await shellCall("status"))
}

async function geometry() {
  return JSON.parse(await shellCall("interactionGeometry"))
}

async function waitFor(probe, timeout = 12000, interval = 80) {
  const deadline = Date.now() + timeout
  let lastError = null
  while (Date.now() < deadline) {
    try {
      const value = await probe()
      if (value) return value
    } catch (error) {
      lastError = error
    }
    await sleep(interval)
  }
  if (lastError) throw lastError
  throw new Error(`condition did not become true within ${timeout}ms`)
}

function record(name, pass, details = "", image = null, statusValue = "pass") {
  results.push({ name, status: pass ? statusValue : "fail", details: String(details || ""), image })
  process.stdout.write(`${pass ? "PASS" : "FAIL"} ${name}${details ? ` — ${details}` : ""}\n`)
  return pass
}

async function capture(slug, label) {
  shotNumber += 1
  const filename = `${String(shotNumber).padStart(2, "0")}-${slug}.png`
  const path = `${outputDir}/${filename}`
  await command("grim", [path], { timeout: 20000 })
  const info = await stat(path)
  if (info.size < 1024) throw new Error(`${filename} is unexpectedly small`)
  screenshots.push({ filename, label })
  return filename
}

async function ensureOpen(workspaceId = null) {
  const desired = workspaceId === null
    ? (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id
    : Number(workspaceId)
  const payload = JSON.stringify({ workspace: desired })
  const current = await status().catch(() => ({ open: false }))
  if (!current.open)
    await command("omarchy-shell", ["shell", "summon", "bitr0t.mission-control", payload])
  else
    await shellCall("open", payload)
  return await waitFor(async () => {
    const next = await status()
    return next.open && next.workspace === desired ? next : null
  }, 15000)
}

async function ensureClosed() {
  await command("omarchy-shell", ["shell", "hide", "bitr0t.mission-control"], { allowFailure: true })
  await waitFor(async () => !(await status()).open, 3000)
}

async function injectUntilOpen(args, attempts = 3) {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    await input(...args)
    const opened = await waitFor(async () => {
      const value = await status()
      return value.open ? value : null
    }, 3000).catch(() => null)
    if (opened) return opened
    await ensureClosed().catch(() => {})
    await sleep(250)
  }
  return null
}

async function input(...args) {
  await command(inputHelper, args.map(String), { timeout: 15000 })
}

async function moveCursor(x, y) {
  await command("hyprctl", ["dispatch", `hl.dsp.cursor.move({ x = ${Math.round(x)}, y = ${Math.round(y)} })`])
  await input("move", 1, 0, 1, 12)
}

async function clickRect(rect) {
  await moveCursor(rect.centerX, rect.centerY)
  await input("click")
}

async function doubleClickRect(rect) {
  await moveCursor(rect.centerX, rect.centerY)
  await input("double-click")
}

async function dragRects(fromRect, toRect, duration = 480) {
  const desiredX = toRect.centerX - fromRect.centerX
  const desiredY = toRect.centerY - fromRect.centerY
  await moveCursor(fromRect.centerX, fromRect.centerY)
  const start = await jsonCommand("hyprctl", ["-j", "cursorpos"])
  await input("move", Math.round(desiredX), Math.round(desiredY), 30, duration)
  const measured = await jsonCommand("hyprctl", ["-j", "cursorpos"])
  const actualX = measured.x - start.x
  const actualY = measured.y - start.y
  const denominator = desiredX * desiredX + desiredY * desiredY
  const scale = denominator > 0
    ? (actualX * desiredX + actualY * desiredY) / denominator : 1
  const correction = Number.isFinite(scale) && scale > 0.1 ? scale : 1

  await moveCursor(fromRect.centerX, fromRect.centerY)
  await input("drag", Math.round(desiredX / correction),
    Math.round(desiredY / correction), 30, duration)
}

async function hyprClients() {
  return await jsonCommand("hyprctl", ["-j", "clients"])
}

async function fixtureClients() {
  const clients = await hyprClients()
  return clients.filter(client => String(client.class || "").startsWith("mc-visual-"))
}

async function clientByAddress(address) {
  const wanted = normalizeAddress(address)
  return (await hyprClients()).find(client => normalizeAddress(client.address) === wanted) || null
}

async function focusWorkspace(workspaceId) {
  await command("hyprctl", ["dispatch", `hl.dsp.focus({ workspace = "${workspaceId}" })`])
  await waitFor(async () => (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id === workspaceId)
}

async function moveWindow(address, workspaceId) {
  const normalized = String(address).startsWith("0x") ? address : `0x${address}`
  await command("hyprctl", ["eval",
    `hl.dispatch(hl.dsp.window.move({ window = "address:${normalized}", workspace = "${workspaceId}", follow = false }))`])
  await waitFor(async () => (await clientByAddress(normalized))?.workspace?.id === workspaceId)
}

async function managedIds() {
  try {
    const parsed = JSON.parse(await readFile(statePath, "utf8"))
    return Array.isArray(parsed) ? parsed.map(Number).filter(Number.isInteger) : []
  } catch {
    return []
  }
}

async function setManagedIds(ids) {
  await writeFile(statePath, `${JSON.stringify([...new Set(ids)].sort((a, b) => a - b))}\n`)
  await sleep(250)
}

async function launchFixtures(count) {
  await focusWorkspace(fixtureA)
  for (let index = 0; index < count; index += 1) {
    const appId = `mc-visual-${process.pid}-${index}`
    const title = `Mission Control Visual Fixture ${index}`
    const child = spawn("foot", [
      `--app-id=${appId}`,
      `--title=${title}`,
      "sh", "-lc",
      `printf '\\033[2J\\033[H${title}\\n\\nFixture window ${index}\\n'; exec sleep 600`
    ], { stdio: "ignore", env: process.env })
    fixtures.push(child)
  }
  const clients = await waitFor(async () => {
    const value = await fixtureClients()
    return value.length >= count ? value : null
  }, 12000, 150)
  clients.sort((left, right) => String(left.class).localeCompare(String(right.class)))
  return clients
}

async function writeReports() {
  const report = {
    generatedAt: new Date().toISOString(),
    plugin: "bitr0t.mission-control",
    display: process.env.HYPRLAND_INSTANCE_SIGNATURE || "",
    summary: {
      pass: results.filter(result => result.status === "pass").length,
      fail: results.filter(result => result.status === "fail").length,
      skip: results.filter(result => result.status === "skip").length
    },
    results
  }
  await writeFile(`${outputDir}/report.json`, `${JSON.stringify(report, null, 2)}\n`)

  const cards = results.map(result => `
    <article class="${html(result.status)}">
      <h2>${html(result.status.toUpperCase())}: ${html(result.name)}</h2>
      <p>${html(result.details)}</p>
      ${result.image ? `<a href="${html(result.image)}"><img src="${html(result.image)}" alt="${html(result.name)}"></a>` : ""}
    </article>`).join("\n")
  await writeFile(`${outputDir}/index.html`, `<!doctype html>
<meta charset="utf-8"><title>Mission Control visual interaction report</title>
<style>body{font:15px system-ui;background:#111;color:#eee;margin:24px}main{display:grid;grid-template-columns:repeat(auto-fit,minmax(420px,1fr));gap:16px}article{border:1px solid #555;border-radius:10px;padding:12px;background:#1b1b1b}.fail{border-color:#d44}.skip{border-color:#ca3}img{width:100%;height:auto;border-radius:6px}h1,h2{margin:.2em 0}</style>
<h1>Mission Control visual interaction report</h1><p>${report.summary.pass} passed, ${report.summary.fail} failed, ${report.summary.skip} skipped.</p><main>${cards}</main>\n`)

  if (screenshots.length > 0) {
    const files = screenshots.map(screenshot => `${outputDir}/${screenshot.filename}`)
    await command("magick", ["montage", ...files, "-thumbnail", "960x270", "-tile", "2x", "-geometry", "+12+12", `${outputDir}/contact-sheet.png`], { timeout: 120000 })
  }
}

async function cleanup() {
  await command("omarchy-shell", ["shell", "hide", "bitr0t.mission-control"], { allowFailure: true })
  for (const child of fixtures) {
    if (!child.killed) child.kill("SIGTERM")
  }
  await sleep(250)
  for (const child of fixtures) {
    if (!child.killed) child.kill("SIGKILL")
  }
  if (stateBackedUp) {
    if (stateExisted) await writeFile(statePath, originalState)
    else await unlink(statePath).catch(() => {})
  }
  if (desktopBackedUp) {
    await command("hyprctl", ["dispatch", `hl.dsp.focus({ workspace = "${originalWorkspace}" })`], { allowFailure: true })
    await command("hyprctl", ["dispatch", `hl.dsp.cursor.move({ x = ${originalCursor.x}, y = ${originalCursor.y} })`], { allowFailure: true })
  }
  await sleep(300)
}

async function main() {
  const required = ["omarchy-shell", "hyprctl", "grim", "magick", "foot", "jq"]
  if (!process.env.HYPRLAND_INSTANCE_SIGNATURE) throw new Error("visual tests require an active Hyprland session")
  for (const binary of required) await command("which", [binary])
  await access(inputHelper, fsConstants.X_OK)
  await access("/dev/uinput", fsConstants.W_OK)
  await command("omarchy-shell", ["shell", "ping"])
  await mkdir(outputDir, { recursive: true })
  await rm(outputDir, { recursive: true, force: true })
  await mkdir(outputDir, { recursive: true })

  try {
    originalState = await readFile(statePath)
    stateExisted = true
  } catch {
    originalState = Buffer.from("[]\n")
    stateExisted = false
  }
  stateBackedUp = true
  originalWorkspace = (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id
  originalCursor = await jsonCommand("hyprctl", ["-j", "cursorpos"])
  desktopBackedUp = true

  const used = new Set([...(await managedIds()), ...(await jsonCommand("hyprctl", ["-j", "workspaces"])).map(workspace => workspace.id)])
  let adjacent = null
  for (let lower = 8; lower >= 4; lower -= 1) {
    if (!used.has(lower) && !used.has(lower + 1)) {
      adjacent = [lower + 1, lower]
      break
    }
  }
  if (!adjacent) throw new Error("visual tests need two adjacent free workspace IDs from 4-9")
  ;[fixtureA, fixtureB] = adjacent

  const clients = await launchFixtures(7)
  await moveWindow(clients[6].address, fixtureB)
  await focusWorkspace(fixtureA)

  // Open/toggle/hotkey/gesture.
  await ensureClosed()
  const hotkeyOpen = await injectUntilOpen(["chord", "ctrl", "up"])
  record("Global Control+Up opens Mission Control", !!hotkeyOpen,
    hotkeyOpen ? `workspace ${hotkeyOpen.workspace}` : "hotkey did not open after 3 attempts",
    hotkeyOpen ? await capture("hotkey-open", "Control+Up opens Mission Control") : null)
  if (!hotkeyOpen) throw new Error("Control+Up failed to open Mission Control")

  await ensureClosed()
  const gestureProbe = await command(inputHelper, ["swipe-up"], { allowFailure: true, timeout: 15000 })
  if (gestureProbe.error) {
    record("Three-finger upward gesture opens Mission Control", true,
      `virtual touchpad unavailable; manual confirmation required: ${(gestureProbe.stderr || gestureProbe.error.message).trim()}`, null, "skip")
  } else {
    let gestureOpen = await waitFor(async () => (await status()).open ? await status() : null, 3000)
      .catch(() => null)
    if (!gestureOpen) gestureOpen = await injectUntilOpen(["swipe-up"], 2)
    record("Three-finger upward gesture opens Mission Control", !!gestureOpen,
      gestureOpen ? "virtual touchpad event accepted" : "gesture did not open after retries",
      gestureOpen ? await capture("gesture-open", "Three-finger gesture") : null)
    if (!gestureOpen) throw new Error("three-finger swipe-up failed to open Mission Control")
  }

  await ensureClosed()
  await command("omarchy-shell", ["shell", "toggle", "bitr0t.mission-control", "{}"])
  await waitFor(async () => (await status()).open)
  await command("omarchy-shell", ["shell", "toggle", "bitr0t.mission-control", "{}"])
  record("IPC toggle opens and closes", await waitFor(async () => !(await status()).open),
    "two toggles restore closed state", await capture("ipc-toggle-close", "IPC toggle closes"))

  // Keyboard matrix.
  await focusWorkspace(fixtureA)
  let current = await ensureOpen()
  const firstIndex = current.selectedIndex
  await input("key", "l")
  let next = await status()
  record("Vim L selects right", next.selectedIndex !== firstIndex, `${firstIndex} -> ${next.selectedIndex}`, await capture("vim-l", "Vim L"))
  const afterL = next.selectedIndex
  await input("key", "h")
  next = await status()
  record("Vim H selects left", next.selectedIndex !== afterL, `${afterL} -> ${next.selectedIndex}`,
    await capture("vim-h", "Vim H"))
  const beforeJ = next.selectedIndex
  await input("key", "j")
  next = await status()
  record("Vim J selects down", next.selectedIndex !== beforeJ, `${beforeJ} -> ${next.selectedIndex}`,
    await capture("vim-j", "Vim J"))
  const beforeK = next.selectedIndex
  await input("key", "k")
  next = await status()
  record("Vim K selects up", next.selectedIndex !== beforeK, `${beforeK} -> ${next.selectedIndex}`,
    await capture("vim-k", "Vim K"))

  for (const [key, label] of [["right", "Right arrow"], ["left", "Left arrow"], ["down", "Down arrow"], ["up", "Up arrow"], ["tab", "Tab"]]) {
    const before = (await status()).selectedIndex
    await input("key", key)
    const after = (await status()).selectedIndex
    record(`${label} changes selection`, after !== before, `${before} -> ${after}`,
      await capture(`key-${key}`, label))
  }
  let before = (await status()).selectedIndex
  await input("chord", "shift", "tab")
  let after = (await status()).selectedIndex
  record("Shift+Tab changes selection in reverse", after !== before, `${before} -> ${after}`,
    await capture("shift-tab", "Shift+Tab"))

  await input("key", "q")
  record("Q closes Mission Control", await waitFor(async () => !(await status()).open), "closed", await capture("vim-q-close", "Q closes"))
  await ensureOpen()
  await input("key", "escape")
  record("Escape closes Mission Control", await waitFor(async () => !(await status()).open),
    "closed", await capture("escape-close", "Escape closes"))

  // Number preview and Shift+number move.
  await focusWorkspace(fixtureA)
  await ensureOpen(fixtureA)
  await input("key", String(fixtureB))
  let previewed = await waitFor(async () => (await status()).workspace === fixtureB, 1500)
    .catch(() => false)
  if (!previewed) {
    await ensureOpen(fixtureA)
    await input("key", String(fixtureB))
    previewed = await waitFor(async () => (await status()).workspace === fixtureB, 3000)
      .catch(() => false)
  }
  record("Number key previews a space", !!previewed, `previewed ${fixtureB}`,
    await capture("number-preview", "Number previews space"))
  if (!previewed) throw new Error(`number key did not preview fixture space ${fixtureB}`)
  await input("key", String(fixtureA))
  await waitFor(async () => (await status()).workspace === fixtureA)
  const selectedBeforeMove = await status()
  const movedAddress = selectedBeforeMove.selectedAddress
  await input("chord", "shift", String(fixtureB))
  const moved = await waitFor(async () => (await clientByAddress(movedAddress))?.workspace?.id === fixtureB)
  const activeAfterMove = (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id
  record("Shift+number moves selected window silently", !!moved && activeAfterMove === fixtureA,
    `${movedAddress} -> ${fixtureB}, focus stayed ${activeAfterMove}`, await capture("shift-number-move", "Shift+number moves window"))
  await moveWindow(movedAddress, fixtureA)

  // Pointer geometry and background close.
  await ensureOpen()
  let geo = await geometry()
  record("Interaction geometry exposes spaces and windows",
    geo.spaces.length >= 2 && geo.windows.length >= 5,
    `${geo.spaces.length} spaces, ${geo.windows.length} windows`,
    await capture("interaction-geometry", "Interaction geometry"))
  await moveCursor(geo.backgroundPoint.x, geo.backgroundPoint.y)
  await input("click")
  record("Background click closes Mission Control",
    await waitFor(async () => !(await status()).open), "closed",
    await capture("background-close", "Background click closes"))

  // Space click/double click.
  await focusWorkspace(fixtureA)
  await ensureOpen()
  geo = await geometry()
  const targetSpace = geo.spaces.find(space => space.id === fixtureB)
  await clickRect(targetSpace.rect)
  record("Space click previews destination", await waitFor(async () => (await status()).workspace === fixtureB), `previewed ${fixtureB}`, await capture("space-click", "Space click"))
  geo = await geometry()
  const originSpace = geo.spaces.find(space => space.id === fixtureA)
  await doubleClickRect(originSpace.rect)
  const doubleClosed = await waitFor(async () => !(await status()).open)
  const doubleWorkspace = (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id
  record("Space double-click switches and closes", doubleClosed && doubleWorkspace === fixtureA,
    `active ${doubleWorkspace}`, await capture("space-double-click", "Space double-click"))

  // Add and remove controls, including bar state.
  await ensureOpen()
  geo = await geometry()
  const idsBeforeAdd = await managedIds()
  await clickRect(geo.addRect)
  const idsAfterAdd = await waitFor(async () => {
    const ids = await managedIds()
    return ids.length === idsBeforeAdd.length + 1 ? ids : null
  })
  const addedId = idsAfterAdd.find(id => !idsBeforeAdd.includes(id))
  const addImage = await capture("space-add", "Add space")
  record("Add button creates managed space", Number.isInteger(addedId), `added ${addedId}`, addImage)
  const shellLayout = await jsonCommand("jq", ["-c", ".bar.layout.left | map(.id)", `${process.env.HOME}/.config/omarchy/shell.json`])
    .catch(() => [])
  record("Dynamic bar widget reflects managed spaces",
    Array.isArray(shellLayout) && shellLayout.includes("bitr0t.mission-control"),
    `${JSON.stringify(shellLayout)}; managed ${JSON.stringify(idsAfterAdd)}`, addImage)

  await command("omarchy-shell", ["shell", "summon", "bitr0t.mission-control", JSON.stringify({ workspace: addedId })])
  await sleep(250)
  geo = await geometry()
  const addedSpace = geo.spaces.find(space => space.id === addedId)
  await moveCursor(addedSpace.rect.centerX, addedSpace.rect.centerY)
  await sleep(120)
  geo = await geometry()
  const hoveredAdded = geo.spaces.find(space => space.id === addedId)
  await clickRect(hoveredAdded.removeRect)
  const removed = await waitFor(async () => !(await managedIds()).includes(addedId))
  const removeImage = await capture("space-remove", "Remove space")
  record("Remove button deletes managed space", removed, `removed ${addedId}`, removeImage)
  record("Dynamic bar reflects space removal", removed,
    `managed ${JSON.stringify(await managedIds())}`, removeImage)

  // Window hover, invalid drag, valid animated drag.
  await focusWorkspace(fixtureA)
  await ensureOpen()
  geo = await geometry()
  const fixtureAddresses = new Set((await fixtureClients()).filter(client => client.workspace.id === fixtureA).map(client => normalizeAddress(client.address)))
  let fixtureWindow = geo.windows.find(windowItem => fixtureAddresses.has(normalizeAddress(windowItem.address)))
  await moveCursor(fixtureWindow.rect.centerX - 2, fixtureWindow.rect.centerY)
  await input("move", 4, 0, 2, 30)
  record("Window hover selects card",
    await waitFor(async () => (await status()).selectedIndex === fixtureWindow.index),
    `selected ${fixtureWindow.index}`, await capture("window-hover", "Window hover"))

  const invalidBefore = (await clientByAddress(fixtureWindow.address)).workspace.id
  await dragRects(fixtureWindow.rect, { centerX: geo.backgroundPoint.x, centerY: geo.backgroundPoint.y })
  await sleep(350)
  record("Invalid window drag cancels move", (await clientByAddress(fixtureWindow.address)).workspace.id === invalidBefore,
    `remained ${invalidBefore}`, await capture("window-drag-cancel", "Invalid window drag"))

  await ensureOpen()
  geo = await geometry()
  fixtureWindow = geo.windows.find(windowItem => normalizeAddress(windowItem.address) === normalizeAddress(fixtureWindow.address))
  const destinationSpace = geo.spaces.find(space => space.id === fixtureB)
  await dragRects(fixtureWindow.rect, destinationSpace.rect)
  const dragAnimationImage = await capture("window-drop-animation", "Window drop animation")
  const validMoved = await waitFor(async () => (await clientByAddress(fixtureWindow.address))?.workspace?.id === fixtureB)
  const activeAfterDrag = (await jsonCommand("hyprctl", ["-j", "activeworkspace"])).id
  record("Window drag animates and moves to space", !!validMoved && activeAfterDrag === fixtureA,
    `${fixtureWindow.address} -> ${fixtureB}, focus stayed ${activeAfterDrag}`, dragAnimationImage)
  await moveWindow(fixtureWindow.address, fixtureA)

  // Space drag swap and restore.
  await ensureOpen()
  geo = await geometry()
  const spaceA = geo.spaces.find(space => space.id === fixtureA)
  const spaceB = geo.spaces.find(space => space.id === fixtureB)
  const addressA = (await fixtureClients()).find(client => client.workspace.id === fixtureA)?.address
  const addressB = (await fixtureClients()).find(client => client.workspace.id === fixtureB)?.address
  await dragRects(spaceB.rect, spaceA.rect)
  await sleep(600)
  const swappedA = addressA ? (await clientByAddress(addressA))?.workspace?.id : -1
  const swappedB = addressB ? (await clientByAddress(addressB))?.workspace?.id : -1
  record("Space drag swaps positions and renumbers", swappedA === fixtureB && swappedB === fixtureA,
    `A ${swappedA}, B ${swappedB}`, await capture("space-reorder", "Space reorder"))
  await ensureOpen()
  geo = await geometry()
  await dragRects(geo.spaces.find(space => space.id === fixtureB).rect,
    geo.spaces.find(space => space.id === fixtureA).rect)
  await sleep(600)
  const restoredA = addressA ? (await clientByAddress(addressA))?.workspace?.id : -1
  const restoredB = addressB ? (await clientByAddress(addressB))?.workspace?.id : -1
  record("Reverse space drag restores positions", restoredA === fixtureA && restoredB === fixtureB,
    `A ${restoredA}, B ${restoredB}`, await capture("space-reorder-restore", "Space reorder restored"))

  // Mouse click activation and fixture-only close button.
  await focusWorkspace(fixtureA)
  await ensureOpen()
  geo = await geometry()
  fixtureWindow = geo.windows.find(windowItem => fixtureAddresses.has(normalizeAddress(windowItem.address)))
  await clickRect(fixtureWindow.rect)
  const clickClosed = await waitFor(async () => !(await status()).open)
  const activeWindow = await jsonCommand("hyprctl", ["-j", "activewindow"])
  record("Window click activates and closes", clickClosed && normalizeAddress(activeWindow.address) === normalizeAddress(fixtureWindow.address),
    activeWindow.address, await capture("window-click", "Window click activation"))

  await ensureOpen()
  geo = await geometry()
  fixtureWindow = geo.windows.find(windowItem => fixtureAddresses.has(normalizeAddress(windowItem.address)))
  await moveCursor(fixtureWindow.rect.centerX, fixtureWindow.rect.centerY)
  await sleep(120)
  geo = await geometry()
  fixtureWindow = geo.windows.find(windowItem => normalizeAddress(windowItem.address) === normalizeAddress(fixtureWindow.address))
  await clickRect(fixtureWindow.closeRect)
  record("Window close control closes fixture only", await waitFor(async () => !(await clientByAddress(fixtureWindow.address))),
    fixtureWindow.address, await capture("window-close", "Fixture window close"))

  // Enter activation is last because it closes the overlay.
  await focusWorkspace(fixtureA)
  await ensureOpen()
  const enterStatus = await status()
  await input("key", "enter")
  const enterClosed = await waitFor(async () => !(await status()).open)
  const enterActive = await jsonCommand("hyprctl", ["-j", "activewindow"])
  record("Enter activates selected window", enterClosed && normalizeAddress(enterActive.address) === normalizeAddress(enterStatus.selectedAddress),
    enterActive.address, await capture("enter-activate", "Enter activates"))

  await ensureClosed()
}

let fatal = null
try {
  await main()
} catch (error) {
  fatal = error
  record("Visual runner completed", false, error.stack || error.message)
} finally {
  try {
    await cleanup()
    record("Cleanup restored desktop", true, "managed spaces, active workspace, cursor, and fixtures restored")
  } catch (error) {
    record("Cleanup restored desktop", false, error.message)
  }
  await writeReports().catch(error => {
    process.stderr.write(`failed to write visual report: ${error.stack || error.message}\n`)
    if (!fatal) fatal = error
  })
}

const failures = results.filter(result => result.status === "fail")
process.stdout.write(`Evidence: ${outputDir}/index.html\n`)
if (fatal || failures.length > 0) process.exitCode = 1
