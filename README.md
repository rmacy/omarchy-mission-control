# Omarchy Mission Control

A macOS-style workspace and window overview for Omarchy — plus the dynamic bar spaces widget and a themed macOS-style Alt-Tab switcher, all in one plugin. It runs inside the existing `omarchy-shell` process as a third-party plugin; there is no separate daemon, privileged installer, or Hyprland plugin to compile.

As of 3.0.0 the former standalone Alt-Tab plugin (`bitr0t.window-switcher`) is merged into Mission Control. Mission Control now owns Alt-Tab; install this one plugin and remove the standalone switcher (see [Migrating from the standalone Alt-Tab plugin](#migrating-from-the-standalone-alt-tab-plugin)).

## Features

- Live, aspect-correct previews of every window in the selected workspace
- Desktop thumbnails reconstruct each space over the monitor's actual static or mpvpaper video wallpaper
- Bar workspace widget that takes over the stock Workspaces slot and shows exactly the spaces that exist
- Adaptive layout for laptop, desktop, and ultrawide displays
- Space cards with drag-to-reorder, correct renumbering, creation, and removal
- Persistent custom space names shared by Mission Control and the Omarchy bar
- Drag a window onto a space card to move it to another space
- Themed, translucent macOS-style Alt-Tab switcher cycling the active workspace of the focused monitor, ordered by Hyprland focus history
- Focuses the monitor that was active when the overview opened
- Uses Omarchy's active colors, typography, and application icons
- Restores the user's normal Hyprland configuration when disabled or removed

## Requirements

- Omarchy 4.0 or newer
- Hyprland 0.56 or newer with Lua configuration (tested with Hyprland 0.56.2)
- Quickshell 0.3 or newer
- Hyprland support for `hyprland-toplevel-export-v1` and foreign-toplevel management; both are present in stock Omarchy
- Qt Multimedia (`qt6-multimedia`, included by Omarchy) for shared video wallpaper frames
- `notify-send` for the persistent binding-registration failure notification

No build step, downloaded artifact, native binary, Node package, Python package, or runtime setup is required.

## Install

```bash
omarchy plugin add https://github.com/rmacy/omarchy-mission-control.git --enable
```

Omarchy clones the repository into `~/.config/omarchy/plugins/bitr0t.mission-control/`, validates `manifest.json`, and enables it. The plugin installer does not run hooks or use `sudo`. This single install delivers Mission Control, the bar spaces widget, and the Alt-Tab switcher — there is nothing else to install or enable.

The single overlay entry point, `Overlay.qml`, hosts both surfaces and forwards the shell and manifest handles to Mission Control and the Alt-Tab switcher alike. The two surfaces are mutually exclusive: opening Mission Control dismisses the Alt-Tab switcher, and starting an Alt-Tab switch closes Mission Control.

### Migrating from the standalone Alt-Tab plugin

If you previously installed `bitr0t.window-switcher` (the standalone Omarchy Alt-Tab plugin), disable or remove it **before** enabling Mission Control 3.0.0. Both plugins intentionally bind `Alt+Tab` and `Alt+Shift+Tab`; leaving the standalone switcher enabled causes a binding conflict in which each plugin's registration fights the other's.

```bash
omarchy plugin disable bitr0t.window-switcher
omarchy plugin remove bitr0t.window-switcher
```

Then install or update Mission Control as above. Disabling or removing the standalone switcher reloads Hyprland, restoring your configured Alt-Tab chords for a moment; enabling Mission Control registers them again, now owned by `bitr0t.mission-control`. No state carries over and none is needed — the switcher keeps everything it needs from Hyprland itself.

## Desktop thumbnails

Each space card composes Hyprland's real window geometry with captured client surfaces, so tiled and floating windows appear where they actually live. The selected space stays live; inactive spaces take a snapshot to avoid multiplying compositor capture work every frame.

Wayland's toplevel export omits compositor-only decorations and layer-shell surfaces. The cards therefore include wallpaper, window placement, sizes, and content, but not the Omarchy bar, compositor shadows, or notification layers.

Static wallpaper paths come from Omarchy's current-background state link. When `mpvpaper` is active, the plugin reads its local `/proc` command line, selects the process targeting the overview monitor (or `*`), and uses that existing local video file instead. Remote, relative, missing, and non-regular paths are rejected.

All space cards share one muted, looping Qt Multimedia decoder and one `VideoOutput`; cards clone that frame rather than starting a decoder per space. Closing Mission Control stops playback and source polling. No frame is downloaded, transcoded, or written to disk.

## Bar widget

The plugin also ships a bar widget, `Mission Control Spaces`. It replaces Omarchy's built-in Workspaces indicator: instead of always painting workspaces 1-5, it renders the union of Mission Control's saved spaces and the workspaces Hyprland currently has (up to space 10), so the bar grows and shrinks with the overview. Occupied and focused spaces keep the stock styling, vertical bars are supported, and clicking a space focuses it.

The plugin service is the single owner of `~/.local/state/omarchy/mission-control-spaces.json`. Mission Control and every bar instance bind directly to that service's normalized ID array, so create, remove, or reorder updates are synchronous and cannot diverge across independent file watchers. Spaces that exist only in Mission Control (empty managed spaces) still appear, so clicking one recreates and focuses it.

### Automatic migration

On startup the plugin's service replaces any `omarchy.workspaces` entry in `bar.layout` (any of the `left`, `center`, `right` sections of `~/.config/omarchy/shell.json`) with `bitr0t.mission-control`, keeping the entry's section, position, and inline settings. The replacement runs once and is idempotent: repeated shell restarts detect the already-migrated layout and write nothing, and a layout that never contained the stock widget is left untouched.

To put the stock Workspaces widget back — for example before removing the plugin — run:

```bash
omarchy-shell shell putBarWidget omarchy.workspaces '{}'
```

The command re-adds `omarchy.workspaces` to the bar's left section (or use the bar's widget settings). After that, `omarchy plugin remove bitr0t.mission-control` leaves the stock widget in place. Removing the plugin without restoring first simply drops the widget from the bar; re-add it with the same `putBarWidget` command.

## Use — Mission Control

Open or close Mission Control with either trigger:

- `Control + Up`
- Three-finger swipe up

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

- Owns `~/.local/state/omarchy/mission-control-spaces.json` and `~/.local/state/omarchy/mission-control-space-names.json`, renumbers Hyprland workspace IDs to match managed spaces, and performs the idempotent `omarchy.workspaces` → `bitr0t.mission-control` bar-layout migration.
- Registers the `Control+Up` shortcut and the three-finger swipe-up gesture at runtime.
- Intentionally replaces the configured `Alt+Tab` and `Alt+Shift+Tab` chords while enabled.
- Registers owner-guarded Hyprland Lua callbacks and a temporary switcher submap through `hyprctl eval`.
- Uses bounded Alt-state polling while a switch is active and coalesces rapid navigation.
- Invokes fixed `omarchy-shell` IPC methods (`advance`, `commit`, and `cancel`) on `bitr0t.mission-control`.
- Runs `hyprctl reload` during orderly teardown to restore configured bindings.
- Uses `notify-send` only if binding registration fails after bounded retries.

The overlay reads Quickshell's native Hyprland toplevel model. It performs no network requests, privileged commands, package installation, or filesystem writes.

Runtime commands: `hyprctl`, `omarchy-shell`, `sh` during teardown, and optional failure-path `notify-send`.

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
omarchy plugin update bitr0t.mission-control
omarchy plugin remove bitr0t.mission-control
```

Updating replaces the whole plugin — Mission Control, bar widget, and Alt-Tab switcher together. Disabling or removing reloads Hyprland, so your configured `Control+Up` mapping, the swipe gesture, and the original `Alt+Tab` and `Alt+Shift+Tab` chords all return.

If the plugin is still installed when you restore the stock bar widget, the next shell restart replaces it with the Mission Control widget again (that is the migration above doing its job); restore after removing, or keep the Mission Control widget and skip this step.

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

The Mission Control suite builds a temporary `/dev/uinput` helper, launches isolated `foot` fixture windows, drives the real Mission Control surface, checks Hyprland/workspace/bar state, and restores the original workspace and managed-space file in cleanup. Evidence is written under `tests/live/output/`: `report.json`, an `index.html` gallery, a `contact-sheet.png`, and individual scenario PNGs. It requires write access to `/dev/uinput` plus `foot`, `grim`, ImageMagick, `hyprctl`, and `omarchy-shell`, and refuses to run outside Hyprland or without the opt-in acknowledgement.

Install a local checkout through the same plugin path used in production:

```bash
omarchy plugin add "file://$PWD" --enable --yes
```

Live window pixels are provided directly by Hyprland's capture protocol to Quickshell. The plugin does not save previews to disk or send them over the network.

## License

[MIT](LICENSE) — Copyright © 2026 Ryan Macy.
