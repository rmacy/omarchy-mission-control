import assert from "node:assert/strict"
import { execFile } from "node:child_process"
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { test } from "node:test"
import { fileURLToPath } from "node:url"
import { promisify } from "node:util"

const exec = promisify(execFile)
const script = fileURLToPath(new URL("../bin/background-source", import.meta.url))

// Every test drives the real bin/background-source against a throwaway
// sandbox: a fake /proc tree with synthetic NUL-delimited cmdlines plus a
// fake state symlink, injected through MC_PROC_ROOT/MC_BACKGROUND_LINK so no
// real system state is ever read.

function makeSandbox() {
  const root = mkdtempSync(join(tmpdir(), "mc-background-source-"))
  const proc = join(root, "proc")
  const home = join(root, "home")
  const stateLink = join(root, "state", "background")
  mkdirSync(proc)
  mkdirSync(home)
  mkdirSync(dirname(stateLink))
  const env = {
    PATH: "/usr/bin:/bin",
    HOME: home,
    MC_PROC_ROOT: proc,
    MC_BACKGROUND_LINK: stateLink,
  }
  return {
    root,
    env,
    addProcess(pid, argv) {
      const dir = join(proc, String(pid))
      mkdirSync(dir)
      writeFileSync(join(dir, "cmdline"), Buffer.from(argv.map((arg) => `${arg}\0`).join("")))
    },
    addRawProcess(pid, bytes) {
      const dir = join(proc, String(pid))
      mkdirSync(dir)
      writeFileSync(join(dir, "cmdline"), bytes)
    },
    addFile(relative) {
      const path = join(root, relative)
      mkdirSync(dirname(path), { recursive: true })
      writeFileSync(path, "fixture\n")
      return path
    },
    linkState(target) {
      symlinkSync(target, stateLink)
    },
    source(monitor, overrides = {}) {
      return exec(script, [monitor], { env: { ...env, ...overrides } })
    },
  }
}

async function withSandbox(body) {
  const sandbox = makeSandbox()
  try {
    await body(sandbox)
  } finally {
    rmSync(sandbox.root, { recursive: true, force: true })
  }
}

// The contract is exactly one line of compact JSON with a fixed key order.
const assertSingleLine = (stdout) => assert.match(stdout, /^\{[^\r\n]*\}\n$/)

test("resolves the mpvpaper video playing on the requested monitor", async () => {
  await withSandbox(async (fx) => {
    const video = fx.addFile("wallpapers/tokyo-car-lights.mp4")
    fx.addProcess(1734, [
      "/usr/bin/mpvpaper",
      "-l",
      "bottom",
      "-o",
      "--loop-file=inf --no-audio --panscan=1.0",
      "DP-1",
      video,
    ])
    fx.linkState(fx.addFile("state/bauhaus.png"))
    const { stdout } = await fx.source("DP-1")
    assertSingleLine(stdout)
    assert.deepEqual(JSON.parse(stdout), { path: video, kind: "video", source: "mpvpaper" })
    assert.equal(stdout, `${JSON.stringify({ path: video, kind: "video", source: "mpvpaper" })}\n`)
  })
})

test("prefers an exact monitor match over a wildcard and the state link", async () => {
  await withSandbox(async (fx) => {
    const wildcardVideo = fx.addFile("wallpapers/all-outputs.webm")
    const exactVideo = fx.addFile("wallpapers/dp-1-only.mkv")
    fx.addProcess(100, ["mpvpaper", "-vo", "--panscan=1.0", "--layer=bottom", "*", wildcardVideo])
    fx.addProcess(200, ["mpvpaper", "DP-1", exactVideo])
    fx.linkState(fx.addFile("state/fallback.png"))
    assert.equal(JSON.parse((await fx.source("DP-1")).stdout).path, exactVideo)
    assert.equal(JSON.parse((await fx.source("HDMI-A-1")).stdout).path, wildcardVideo)
  })
})

test("falls back to the canonical state image when mpvpaper targets another monitor", async () => {
  await withSandbox(async (fx) => {
    const background = fx.addFile("theme/backgrounds/bauhaus.png")
    const intermediate = join(fx.root, "state", "alias")
    symlinkSync(background, intermediate)
    fx.linkState(intermediate) // state/background -> alias -> real file
    fx.addProcess(300, ["mpvpaper", "HDMI-A-1", fx.addFile("wallpapers/elsewhere.mp4")])
    const { stdout } = await fx.source("DP-1")
    assert.deepEqual(JSON.parse(stdout), { path: background, kind: "image", source: "state" })
  })
})

test("classifies only whitelisted video extensions as video", async () => {
  await withSandbox(async (fx) => {
    fx.linkState(fx.addFile("state/background.png"))
    const cases = [
      ["clip.mp4", "video"],
      ["clip.mkv", "video"],
      ["clip.webm", "video"],
      ["clip.MOV", "video"],
      ["photo.png", "image"],
      ["photo.jpeg", "image"],
      ["wallpaper", "image"],
      ["notes.mp4.txt", "image"],
    ]
    cases.forEach(([name], index) => {
      fx.addProcess(400 + index, ["mpvpaper", `DP-${index}`, fx.addFile(`wallpapers/${name}`)])
    })
    for (let index = 0; index < cases.length; index++) {
      const [name, kind] = cases[index]
      const { stdout } = await fx.source(`DP-${index}`)
      assert.deepEqual(
        JSON.parse(stdout),
        { path: join(fx.root, "wallpapers", name), kind, source: "mpvpaper" },
        name,
      )
    }
  })
})

test("skips malformed mpvpaper cmdlines and falls back to state", async () => {
  await withSandbox(async (fx) => {
    const background = fx.addFile("state/background.jpg")
    fx.linkState(background)
    fx.addRawProcess(500, Buffer.alloc(0)) // empty cmdline
    fx.addRawProcess(501, Buffer.from("bash -lc sleep 1000")) // no NUL delimiters at all
    fx.addProcess(502, ["/usr/bin/sleep", "1000"]) // well-formed but not mpvpaper
    fx.addProcess(503, ["mpvpaper", "DP-1"]) // missing <path> operand
    fx.addProcess(504, ["mpvpaper", "DP-1", "/a.mp4", "extra"]) // surplus operand
    fx.addProcess(505, ["mpvpaper", "DP-1", "/a.mp4", "-o"]) // option missing its value
    fx.addProcess(506, ["mpvpaper", "-l"]) // option missing value, no operands
    const { stdout } = await fx.source("DP-1")
    assert.deepEqual(JSON.parse(stdout), { path: background, kind: "image", source: "state" })
  })
})

test("skips nonexistent, remote, relative, and non-regular candidates", async () => {
  await withSandbox(async (fx) => {
    const background = fx.addFile("theme/desk.png")
    fx.linkState(background)
    fx.addProcess(600, ["mpvpaper", "DP-1", join(fx.root, "missing.mp4")])
    fx.addProcess(601, ["mpvpaper", "DP-2", "https://media.example.com/loop.mp4"])
    fx.addProcess(602, ["mpvpaper", "DP-3", "relative/clip.mp4"])
    fx.addProcess(603, ["mpvpaper", "DP-4", "/tmp"]) // exists but is a directory
    for (const monitor of ["DP-1", "DP-2", "DP-3", "DP-4"]) {
      const { stdout } = await fx.source(monitor)
      assert.deepEqual(JSON.parse(stdout), { path: background, kind: "image", source: "state" }, monitor)
    }
  })
})

test("round-trips paths with spaces, quotes, and backslashes", async () => {
  await withSandbox(async (fx) => {
    const video = fx.addFile("wallpapers/my wall 'paper' \"quoted\" \\slash\\ clip.mp4")
    fx.addProcess(700, ["mpvpaper", "DP-1", video])
    const { stdout } = await fx.source("DP-1")
    assertSingleLine(stdout)
    assert.equal(JSON.parse(stdout).path, video)
  })
})

test("escapes control characters so the result stays one JSON line", async () => {
  await withSandbox(async (fx) => {
    const background = fx.addFile("state/line\nbreak.png")
    fx.linkState(background)
    const { stdout } = await fx.source("DP-1")
    assertSingleLine(stdout) // a raw newline would break the one-line shape
    assert.deepEqual(JSON.parse(stdout), { path: background, kind: "image", source: "state" })
  })
})

test("reports none when no mpvpaper runs and the state link is broken", async () => {
  await withSandbox(async (fx) => {
    symlinkSync(join(fx.root, "state", "gone.png"), fx.env.MC_BACKGROUND_LINK)
    const { stdout } = await fx.source("DP-1")
    assert.equal(stdout, '{"path":"","kind":"none","source":"none"}\n')
  })
})

test("uses the default state link under HOME when MC_BACKGROUND_LINK is unset", async () => {
  await withSandbox(async (fx) => {
    const background = fx.addFile("home-background.png")
    const defaultLink = join(fx.env.HOME, ".local/state/omarchy/current/background")
    mkdirSync(dirname(defaultLink), { recursive: true })
    symlinkSync(background, defaultLink)
    const { stdout } = await exec(script, ["DP-1"], {
      env: { PATH: fx.env.PATH, HOME: fx.env.HOME, MC_PROC_ROOT: fx.env.MC_PROC_ROOT },
    })
    assert.deepEqual(JSON.parse(stdout), { path: background, kind: "image", source: "state" })
  })
})

test("ends option parsing at -- so dashed operands still resolve", async () => {
  await withSandbox(async (fx) => {
    const video = fx.addFile("wallpapers/--leading-dash.mp4")
    fx.addProcess(800, ["mpvpaper", "-p", "--", "DP-1", video])
    const { stdout } = await fx.source("DP-1")
    assert.deepEqual(JSON.parse(stdout), { path: video, kind: "video", source: "mpvpaper" })
  })
})

test("rejects invocations without exactly one monitor argument", async () => {
  await withSandbox(async (fx) => {
    await assert.rejects(
      exec(script, [], { env: fx.env }),
      (error) => error.code === 2 && error.stdout === "" && /usage/.test(error.stderr),
    )
    await assert.rejects(
      exec(script, ["DP-1", "extra"], { env: fx.env }),
      (error) => error.code === 2 && error.stdout === "",
    )
  })
})
