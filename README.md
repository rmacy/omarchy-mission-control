# Omarchy Mission Control

A macOS-style workspace and window overview for Omarchy. It runs inside the existing `omarchy-shell` process as a third-party plugin; there is no separate daemon, privileged installer, or Hyprland plugin to compile.

## Features

- Live, aspect-correct previews of every window in the selected workspace
- Adaptive layout for laptop, desktop, and ultrawide displays
- Space cards with drag-to-reorder, correct renumbering, creation, and removal
- Drag a window onto a space card to move it to another space
- Focuses the monitor that was active when the overview opened
- Uses Omarchy's active colors, typography, and application icons
- Restores the user's normal Hyprland configuration when disabled or removed

## Requirements

- Omarchy 4.0 or newer
- Hyprland 0.56 or newer with Lua configuration
- Quickshell 0.3 or newer
- Hyprland support for `hyprland-toplevel-export-v1` and foreign-toplevel management; both are present in stock Omarchy

## Install

```bash
omarchy plugin add https://github.com/rmacy/omarchy-mission-control.git --enable
```

Omarchy clones the repository into `~/.config/omarchy/plugins/bitr0t.mission-control/`, validates `manifest.json`, and enables it. The plugin installer does not run hooks or use `sudo`.

## Use

Open or close Mission Control with either trigger:

- `Control + Up`
- Three-finger swipe up

Inside the overview:

| Input | Action |
|---|---|
| Mouse hover or arrow keys | Select a window |
| Click or `Enter` | Open the selected window |
| Click a workspace | Preview that workspace |
| Double-click a workspace | Switch to that workspace |
| Drag a workspace | Reorder spaces; Hyprland IDs are renumbered to match |
| Workspace `+` button | Create and switch to a persistent space |
| Workspace `×` button | Remove a space and move its windows to its neighbor |
| `Shift + Left` / `Shift + Right` | Reorder the selected workspace |
| Drag a window onto a space card | Move only that window to the space; the view and focus stay put |
| `Shift + 1` through `Shift + 9` | Move the selected window to that space |
| `1` through `9` | Preview that numbered workspace when present |
| `Tab` / `Shift + Tab` | Select next / previous window |
| `Escape` | Close Mission Control |
| Window close button | Ask the application to close that window |

The plugin registers its shortcut and gesture at runtime. If either trigger replaced a user mapping, disabling or removing the plugin reloads Hyprland so the user's configured mapping returns.

Mission Control remembers managed spaces in `~/.local/state/omarchy/mission-control-spaces.json` and recreates empty ones on demand. It supports spaces 1 through 10, matching Omarchy's workspace conventions. Removing the final remaining space is disabled.

## Update or remove

```bash
omarchy plugin update bitr0t.mission-control
omarchy plugin remove bitr0t.mission-control
```

## Development

The repository uses `mise` for a reproducible Node test runtime:

```bash
mise run test
mise run lint
```

Install a local checkout through the same plugin path used in production:

```bash
omarchy plugin add "file://$PWD" --enable --yes
```

Live window pixels are provided directly by Hyprland's capture protocol to Quickshell. The plugin does not save previews to disk or send them over the network.
