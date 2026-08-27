# Omarchy Mission Control

A macOS-style workspace and window overview for Omarchy. It runs inside the existing `omarchy-shell` process as a third-party plugin; there is no separate daemon, privileged installer, or Hyprland plugin to compile.

## Features

- Live, aspect-correct previews of every window in the selected workspace
- Desktop thumbnails reconstruct each space's tiled and floating window layout over the current wallpaper
- Bar workspace widget that takes over the stock Workspaces slot and shows exactly the spaces that exist
- Adaptive layout for laptop, desktop, and ultrawide displays
- Space cards with drag-to-reorder, correct renumbering, creation, and removal
- Persistent custom space names shared by Mission Control and the Omarchy bar
- Drag a window onto a space card to move it to another space
- Focuses the monitor that was active when the overview opened
- Uses Omarchy's active colors, typography, and application icons
- Restores the user's normal Hyprland configuration when disabled or removed

## Requirements

- Omarchy 4.0 or newer
- Hyprland 0.56 or newer with Lua configuration
- Quickshell 0.3 or newer
- Hyprland support for `hyprland-toplevel-export-v1` and foreign-toplevel management; both are present in stock Omarchy

## Desktop thumbnails

Each space card composes Hyprland's real window geometry with captured client surfaces, so tiled and floating windows appear where they actually live. The selected space stays live; inactive spaces take a snapshot to avoid multiplying compositor capture work every frame.

Wayland's toplevel export omits compositor-only decorations and layer-shell surfaces. The cards therefore include wallpaper, window placement, sizes, and content, but not the Omarchy bar, compositor shadows, or notification layers.

## Install

```bash
omarchy plugin add https://github.com/rmacy/omarchy-mission-control.git --enable
```

Omarchy clones the repository into `~/.config/omarchy/plugins/bitr0t.mission-control/`, validates `manifest.json`, and enables it. The plugin installer does not run hooks or use `sudo`.

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

## Use

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

## Update or remove

```bash
omarchy plugin update bitr0t.mission-control
omarchy plugin remove bitr0t.mission-control
```

If the plugin is still installed when you restore the stock widget, the next shell restart replaces it with the Mission Control widget again (that is the migration above doing its job); restore after removing, or keep the Mission Control widget and skip this step.

## Development

The repository uses `mise` for a reproducible Node runtime and enforces at least 90% line, branch, and function coverage for the executable `WindowModel.js` logic:

```bash
mise run test      # fast model tests
mise run coverage  # tests plus all three 90% coverage gates
mise run lint      # QML validation
mise run check     # coverage gates plus QML validation
```

The coverage workflow runs on every GitHub push and pull request. Declarative QML is validated with `qmllint` and the live Omarchy smoke scenario rather than being included in Node's V8 coverage denominator.

### Live interaction and visual evidence

The compositor-level suite deliberately drives keyboard, pointer, workspace, and window state. Run it only in a disposable or otherwise idle Hyprland session:

```bash
MC_VISUAL_ALLOW_ACTIVE_SESSION=1 mise run visual-test
```

Without that explicit opt-in, the runner refuses to start. The suite builds a temporary `/dev/uinput` helper, launches isolated `foot` fixture windows, drives the real Mission Control surface, checks Hyprland/workspace/bar state, and restores the original workspace and managed-space file in cleanup.

The battery covers the global hotkey and real three-finger gesture injection, every keyboard path, bar and space clicks, add/remove, keyboard and pointer reordering, window activation/close, invalid and valid drag flows, animation, synchronization, and cleanup restoration.

Evidence is written under `tests/live/output/`:

- `report.json` — machine-readable pass/fail/skip assertions
- `index.html` — labeled visual gallery
- `contact-sheet.png` — all scenario screenshots on one review surface
- individual PNGs for keyboard, pointer, space, window, drag, animation, and bar scenarios

The runner requires write access to `/dev/uinput` plus `foot`, `grim`, ImageMagick, `hyprctl`, and `omarchy-shell`. It refuses to run outside Hyprland, when a prerequisite is missing, or without the active-session acknowledgement above.

Install a local checkout through the same plugin path used in production:

```bash
omarchy plugin add "file://$PWD" --enable --yes
```

Live window pixels are provided directly by Hyprland's capture protocol to Quickshell. The plugin does not save previews to disk or send them over the network.
