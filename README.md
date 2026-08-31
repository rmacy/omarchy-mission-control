# Omarchy Mission Control

A macOS-style workspace and window overview for Omarchy — plus the dynamic bar spaces widget and a themed macOS-style Alt-Tab switcher, all in one plugin. It runs inside the existing `omarchy-shell` process as a third-party plugin; there is no separate daemon, privileged installer, or Hyprland plugin to compile.

As of 3.0.0 the former standalone Alt-Tab plugin (`bitr0t.window-switcher`) is merged into Mission Control. Mission Control now owns Alt-Tab; install this one plugin and remove the standalone switcher (see [Migrating from the standalone Alt-Tab plugin](#migrating-from-the-standalone-alt-tab-plugin)).

## Features

- Live, aspect-correct previews of every window in the selected workspace
- Desktop thumbnails reconstruct each space over the monitor's actual static or mpvpaper video wallpaper
- Optional bar spaces widget you place yourself; it shows exactly the spaces that exist instead of always painting workspaces 1-5
- Adaptive layout for laptop, desktop, and ultrawide displays
- Space cards with drag-to-reorder, correct renumbering, creation, and removal
- Persistent custom space names shared by Mission Control and the Omarchy bar
- Drag a window onto a space card to move it to another space
- Themed, translucent macOS-style Alt-Tab switcher cycling the active workspace of the focused monitor, ordered by Hyprland focus history
- macOS-style opening, closing, window-flight, space-rail, and selection animations
- Focuses the monitor that was active when the overview opened
- Uses Omarchy's active colors, typography, and application icons
- Restores the user's normal Hyprland configuration when disabled or removed

## Requirements

- Omarchy 4.0 or newer
- Hyprland 0.56 or newer with Lua configuration (tested with Hyprland 0.56.2), including the `hyprctl` client that ships with Hyprland
- Quickshell 0.3 or newer (Omarchy's `omarchy-shell` host process)
- Hyprland support for `hyprland-toplevel-export-v1` and foreign-toplevel management; both are present in stock Omarchy
- Qt Multimedia (`qt6-multimedia`, included by Omarchy) for shared video wallpaper frames
- Bash and coreutils `realpath`, used by the bundled `bin/background-source` wallpaper helper that the overview launches through its `#!/usr/bin/env bash` shebang (`/usr/bin/env` resolves `bash` from `PATH`)
- A POSIX `sh`, used only by the serialized teardown command chain
- `notify-send`, used only on the binding-registration failure path

No build step, downloaded artifact, native binary, Node package, Python package, or runtime setup is required — the bundled helper is a plain shell script, not a compiled executable. Every dependency above ships with a stock Omarchy installation: `bash`, `sh`, and coreutils `realpath` come from Omarchy's Arch base system, `hyprctl` ships with Hyprland, and `omarchy-shell`, Qt Multimedia, and `notify-send` ship with Omarchy itself.

## Install

```bash
omarchy plugin add https://github.com/rmacy/omarchy-mission-control.git --enable
```

Omarchy clones the repository into `~/.config/omarchy/plugins/bitr0t.omarchy-mission-control/`, validates `manifest.json`, and enables it. The plugin ships no install hooks, requires no elevated privileges, and never edits shell configuration itself. When you explicitly enable it, Omarchy records the plugin and optional bar-widget placement in your shell configuration. This single install delivers Mission Control, the bar spaces widget, and the Alt-Tab switcher.

The single overlay entry point, `Overlay.qml`, hosts both surfaces and forwards the shell and manifest handles to Mission Control and the Alt-Tab switcher alike. The two surfaces are mutually exclusive: opening Mission Control dismisses the Alt-Tab switcher, and starting an Alt-Tab switch closes Mission Control.

### Upgrading from the v3 plugin ID

Version 4 changed the package ID from `bitr0t.mission-control` to `bitr0t.omarchy-mission-control`. Omarchy identifies installed plugins by that ID, so the normal update command cannot cross this boundary. Remove the v3 checkout before installing v4:

```bash
omarchy plugin disable bitr0t.mission-control
omarchy plugin remove bitr0t.mission-control --yes
omarchy plugin add https://github.com/rmacy/omarchy-mission-control.git --enable
```

The managed-space and space-name files under `~/.local/state/omarchy/` are preserved, so the renamed plugin resumes the same state. Removing the old checkout first also prevents both IDs from competing for Mission Control and Alt-Tab shortcuts.

### Migrating from the standalone Alt-Tab plugin

If you previously installed `bitr0t.window-switcher` (the standalone Omarchy Alt-Tab plugin), disable or remove it **before** enabling Mission Control. Both plugins intentionally bind `Alt+Tab` and `Alt+Shift+Tab`; leaving the standalone switcher enabled causes a binding conflict in which each plugin's registration fights the other's.

```bash
omarchy plugin disable bitr0t.window-switcher
omarchy plugin remove bitr0t.window-switcher
```

Then install or update Mission Control as above. Disabling or removing the standalone switcher reloads Hyprland, restoring your configured Alt-Tab chords for a moment; enabling Mission Control registers them again, now owned by `bitr0t.omarchy-mission-control`. No state carries over and none is needed — the switcher keeps everything it needs from Hyprland itself.

## Desktop thumbnails

Each space card composes Hyprland's real window geometry with captured client surfaces, so tiled and floating windows appear where they actually live. The selected space stays live; inactive spaces take a snapshot to avoid multiplying compositor capture work every frame.

Wayland's toplevel export omits compositor-only decorations and layer-shell surfaces. The cards therefore include wallpaper, window placement, sizes, and content, but not the Omarchy bar, compositor shadows, or notification layers.

Static wallpaper paths come from Omarchy's current-background state link. When `mpvpaper` is active, the plugin reads its local `/proc` command line, selects the process targeting the overview monitor (or `*`), and uses that existing local video file instead. Remote, relative, missing, and non-regular paths are rejected.

All space cards share one muted, looping Qt Multimedia decoder and one `VideoOutput`; cards clone that frame rather than starting a decoder per space. Closing Mission Control stops playback and source polling. No frame is downloaded, transcoded, or written to disk.

## Bar widget

The plugin also ships a bar widget, `Mission Control Spaces`. Instead of always painting workspaces 1-5, it renders the union of Mission Control's saved spaces and the workspaces Hyprland currently has (up to space 10), so the bar grows and shrinks with the overview. Occupied and focused spaces keep the stock styling, vertical bars are supported, and clicking a space focuses it.

The plugin service is the single owner of `~/.local/state/omarchy/mission-control-spaces.json`. Mission Control and every bar instance bind directly to that service's normalized ID array, so create, remove, or reorder updates are synchronous and cannot diverge across independent file watchers. Spaces that exist only in Mission Control (empty managed spaces) still appear, so clicking one recreates and focuses it.

### Placing the widget

The plugin never edits `~/.config/omarchy/shell.json` or `bar.layout` itself. Bar-widget placement is explicit and user-controlled, and it is performed by Omarchy's own plugin commands:

- When you install with `--enable` (as above), Omarchy asks which bar section the widget belongs in — `left`, `center`, or `right`, defaulting to the section the plugin's manifest requests — and writes that placement itself. If you install without `--enable`, or want to place or move the widget later, run:

```bash
omarchy plugin enable bitr0t.omarchy-mission-control --section left --after omarchy.workspaces
```

`--section` accepts `left`, `center`, or `right`, and the position can be pinned with `--index N`, `--before <widget-id>`, or `--after <widget-id>`. Equivalent shell IPC calls also exist:

```bash
omarchy-shell shell putBarWidget bitr0t.omarchy-mission-control '{"section":"left"}'
omarchy-shell shell moveBarWidget bitr0t.omarchy-mission-control '{"section":"right"}'
```

`putBarWidget` adds the widget if it is not already on the bar and leaves it alone otherwise; `moveBarWidget` moves an existing entry.

The widget and the stock Workspaces indicator can coexist in any sections you like. If you prefer the Mission Control widget to take the stock slot, hide the stock one explicitly:

```bash
omarchy plugin disable omarchy.workspaces
```

To restore the stock Workspaces widget — for example before or after removing the plugin:

```bash
omarchy plugin enable omarchy.workspaces --section left
```

(or use the bar's widget settings, or `omarchy-shell shell putBarWidget omarchy.workspaces '{}'`). Removing the plugin only drops its own widget; the rest of your bar layout, including the stock Workspaces widget, is left exactly as you configured it.

## Use — Mission Control

Open Mission Control with:

- `Control + Up`
- Three-finger swipe up

Close it with `Control + Down`, `Escape`, or `Q`.

Inside the overview:

| Input | Action |
|---|---|
| Mouse hover, arrow keys, **H/J/K/L** | Select a window |
| Click or `Enter` | Open the selected window |
| Click a workspace | Preview that workspace |
| Double-click a workspace | Switch to that workspace |
| Drag a workspace | Reorder spaces; Hyprland IDs are renumbered to match |
| Workspace `+` button | Create and switch to a persistent space |
| Workspace `×` button | Remove a space and move its windows to its neighbor |
| Workspace `Edit` button | Edit the space name inline; `Enter` saves and `Escape` cancels |
| `Control + Left` / `Control + Right` | Preview the adjacent space while Mission Control stays open |
| `Shift + Left` / `Shift + Right` | Reorder the selected workspace |
| Drag a window onto a space card | Move only that window to the space; the view and focus stay put |
| `Shift + 1` through `Shift + 9` | Move the selected window to that space |
| `1` through `9` | Preview that numbered workspace when present |
| `Tab` / `Shift + Tab` | Select next / previous window |
| `Escape` or **Q** | Close Mission Control |
| Window close button | Ask the application to close that window |

The plugin registers its shortcut and gesture at runtime. If either trigger replaced a user mapping, disabling or removing the plugin reloads Hyprland so the user's configured mapping returns.

Mission Control remembers managed spaces in `~/.local/state/omarchy/mission-control-spaces.json` and custom names in `~/.local/state/omarchy/mission-control-space-names.json`. Names follow their space when positions are reordered and appear in the dynamic Omarchy bar. It supports spaces 1 through 10, matching Omarchy's workspace conventions. Removing the final remaining space is disabled.

## Use — Alt-Tab switcher

The switcher is bound to the two chords it intentionally replaces:

- `Alt+Tab` — open the switcher and select the next window
- `Alt+Shift+Tab` — open the switcher and select the previous window

While the switcher is open:

| Input | Action |
| --- | --- |
| `Tab` / `Right` | Advance to the next window |
| `Shift + Tab` / `Left` | Move backward |
| `Enter` | Focus and raise the selection |
| `Escape` | Cancel |
| Release `Alt` | Focus and raise the selection |
| Click a card | Focus and raise that window |

Display states:

- **Many windows** — the full themed, translucent card panel with live window previews.
- **Single window** — a compact horizontal card.
- **Zero windows** — an empty workspace shows a compact zero state until `Alt` is released; releasing `Alt` with nothing selected changes nothing.

Opening the switcher closes Mission Control, and opening Mission Control cancels the switcher; the surfaces never overlap.

## Alt-Tab scope and behavior

- Only the **active workspace on the focused monitor** is included.
- Hidden, unmapped, non-input, other-workspace, and other-monitor clients are excluded.
- At most 256 MRU candidates are presented, ordered by Hyprland focus history.
- The selected client is revalidated by Hyprland stable ID before focus, so a window that dies mid-switch is skipped instead of focusing stale state.
- Application colors, borders, fonts, spacing, and opacity derive from Omarchy `Color` and `Style` theme tokens and update with the active theme.
- Client-controlled titles are rendered as plain text. Class-based fallback icons accept theme-icon identifiers only; paths and URLs are rejected.
- Client shortcut inhibitors are respected. Alt-Tab remains inside a VM, remote desktop, game, or other client while that client owns shortcuts.

## Capability disclosure

Omarchy shell plugins are unsandboxed. This plugin loads a persistent `service`, a single `overlay` (which hosts both Mission Control and the Alt-Tab switcher), and a `bar-widget` inside `omarchy-shell`.

The service:

- Owns `~/.local/state/omarchy/mission-control-spaces.json` and `~/.local/state/omarchy/mission-control-space-names.json`, and renumbers Hyprland workspace IDs to match managed spaces. It never writes to `~/.config/omarchy/shell.json` or `bar.layout`; bar-widget placement happens only through Omarchy's own plugin commands when you run them.
- Registers the `Control+Up` shortcut and the three-finger swipe-up gesture at runtime; the registered Hyprland bindings and the generated Alt-Tab Lua execute fixed `omarchy-shell -q shell …` command lines through Hyprland's `exec_cmd`.
- Intentionally replaces the configured `Alt+Tab` and `Alt+Shift+Tab` chords while enabled.
- Registers owner-guarded Hyprland Lua callbacks and a temporary switcher submap through `hyprctl eval`.
- Uses bounded Alt-state polling while a switch is active and coalesces rapid navigation.
- Invokes fixed `omarchy-shell` IPC methods (`advance`, `commit`, and `cancel`) on `bitr0t.omarchy-mission-control`.
- Tears down through one serialized `sh -c` chain — Alt-Tab cleanup, then host cleanup, then exactly one final `hyprctl reload` that restores configured bindings — with no fixed sleep and no independent second cleanup process.
- Uses `notify-send` only if binding registration fails after bounded retries.

The overlay reads Quickshell's native Hyprland toplevel model and drives workspace renumbering and window focus with `hyprctl eval` and `hyprctl dispatch`. For desktop thumbnails it also executes the bundled `bin/background-source` helper — a read-only Bash script launched directly through its `#!/usr/bin/env bash` shebang, so via `/usr/bin/env` and `bash` from `PATH` — which inspects local process metadata under `/proc` and the Omarchy current-background state link and canonicalizes wallpaper candidates with coreutils `realpath`. Neither the overlay nor the helper performs network requests, privileged commands, package installation, or filesystem writes.

The bar widget renders from the same in-process service and writes nothing. Clicking a space runs a single shell command — `hyprctl dispatch` with a shell-quoted Lua focus call — through the bar's own shell command runner.

Runtime commands, exactly as shipped: `hyprctl` (direct `eval`, `dispatch`, and `reload` calls, plus the calls serialized inside the `sh` teardown chain); `omarchy-shell` (invoked by the registered Hyprland bindings and by the generated Alt-Tab Lua); the bundled `bin/background-source` script (Bash through `/usr/bin/env`, using coreutils `realpath`); `sh -c` (the serialized teardown chain only); and optional failure-path `notify-send`. All of them ship with a stock Omarchy installation, and none requires root privileges, downloads, or network access.

## Recovery

If a compositor or shell crash interrupts a switch or leaves the temporary submap engaged:

```bash
hyprctl dispatch 'hl.dsp.submap("reset")'
hyprctl reload
omarchy restart shell
```

Inspect configuration errors with:

```bash
hyprctl configerrors
```

## Update or remove

```bash
omarchy plugin update bitr0t.omarchy-mission-control
omarchy plugin remove bitr0t.omarchy-mission-control
```

Updating replaces the whole plugin — Mission Control, bar widget, and Alt-Tab switcher together. Disabling or removing reloads Hyprland, so your configured `Control+Up` mapping, the swipe gesture, and the original `Alt+Tab` and `Alt+Shift+Tab` chords all return. Omarchy removes this plugin's bar-widget entry while leaving every other widget and layout entry untouched. The two state files under `~/.local/state/omarchy/` remain so a reinstall preserves spaces and names; remove those files yourself only if you want to discard that state.

If you want Alt-Tab back as a standalone product afterwards, reinstall it explicitly:

```bash
omarchy plugin add https://github.com/rmacy/omarchy-alt-tab --enable
```

## Development and verification

Repository tasks use [mise](https://mise.jdx.dev/):

```bash
mise run check
```

`check` is fully noninteractive: it runs the combined model and generated-Lua tests, the QML security tests, strict QML diagnostics, an isolated invisible Quickshell construction smoke, manifest validation, and the coverage gates (at least 90% line, branch, and function coverage on the executable model logic). It never changes the active desktop.

The two live suites are **destructive to the active interaction session**. The Mission Control visual suite moves focus and the pointer, changes workspaces, injects physical key events, and reloads Hyprland before restoring state; the Alt-Tab live smoke injects real Alt-Tab chords against your running windows. Do not run either while using the desktop. Each requires explicit opt-in:

```bash
MC_VISUAL_ALLOW_ACTIVE_SESSION=1 mise run visual-test
WINDOW_SWITCHER_LIVE_TEST=1 mise run test-live
```

The Mission Control suite builds a temporary `/dev/uinput` helper, launches isolated `foot` fixture process groups, drives the real Mission Control surface, checks Hyprland/workspace/bar state, and restores the original workspace and managed-space file in cleanup. Each run creates a new sentinel-owned directory directly under `tests/live/output/`; it never removes or reuses an existing directory, and rejects output paths outside that root. The directory contains `report.json`, an `index.html` gallery, a `contact-sheet.png`, and scenario PNGs. The suite requires write access to `/dev/uinput` plus `foot`, `grim`, ImageMagick, `hyprctl`, and `omarchy-shell`, and refuses to run outside Hyprland or without the opt-in acknowledgement.

Install a local checkout through the same plugin path used in production:

```bash
omarchy plugin add "file://$PWD" --enable --yes
```

Live window pixels are provided directly by Hyprland's capture protocol to Quickshell. The plugin does not save previews to disk or send them over the network.

## License

[MIT](LICENSE) — Copyright © 2026 Ryan Macy.
