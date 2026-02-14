# Aerospace Focus Bar

[![CI](https://github.com/dungle-scrubs/aerospace-focus/actions/workflows/ci.yml/badge.svg)](https://github.com/dungle-scrubs/aerospace-focus/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

A lightweight focus indicator for [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager. Draws a colored bar below the focused window, using the gap space between tiled windows.

```
┌─────────────────────────────┐
│                             │
│      Focused Window         │
│                             │
└─────────────────────────────┘
████████████████████████████████  ← 4px green bar in the gap
              ↕ gap space
┌─────────────────────────────┐
│      Other Window           │
└─────────────────────────────┘
```

## Requirements

- macOS 13+ (Ventura or later)
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager installed in a standard location:
  - Apple Silicon: `/opt/homebrew/bin/aerospace`
  - Intel: `/usr/local/bin/aerospace`
  - Nix: `/run/current-system/sw/bin/aerospace`
- **Accessibility permissions** (required for window detection fallback)

## Installation

### Homebrew (recommended)

```bash
brew install dungle-scrubs/aerospace-focus/aerospace-focus
brew services start aerospace-focus  # Starts via launchd with auto-restart
```

Logs: `$(brew --prefix)/var/log/aerospace-focus.log`

### From source

```bash
git clone https://github.com/dungle-scrubs/aerospace-focus
cd aerospace-focus
./install.sh
```

> **Note:** The binary installs to `~/.local/bin/`. Ensure this is in your PATH:
> ```bash
> export PATH="$HOME/.local/bin:$PATH"  # Add to ~/.zshrc
> ```

## First Run

On first launch, macOS may prompt for **Accessibility** permissions. If the bar doesn't appear:

1. Open **System Settings → Privacy & Security → Accessibility**
2. Enable `aerospace-focus` (or the terminal running it)
3. Restart the daemon: `aerospace-focus quit && aerospace-focus daemon`

Some systems may also require **Screen Recording** permission for window frame detection.

## Aerospace Integration

Add to your `~/.config/aerospace/aerospace.toml`:

```toml
# Gaps — bar auto-sizes to fit these
[gaps]
inner.horizontal = 8
inner.vertical = 8     # Bar height between windows
outer.top = 8
outer.left = 8
outer.bottom = 12      # Bar height at screen bottom (can differ)
outer.right = 8

# Start daemon and notify on focus change
after-startup-command = [
    'exec-and-forget aerospace-focus daemon'
]

on-focus-changed = ['exec-and-forget aerospace-focus update']
```

Then reload: `aerospace reload-config`

## Configuration

Config file: `~/.config/aerospace-focus/config.toml`

```toml
# Bar appearance
# bar_height = 4             # Uncomment to override auto-sizing (pixels)
bar_color = "#00ff00"        # Hex color
bar_opacity = 1.0            # 0.0–1.0

# Auto-size from aerospace gaps (default: true)
# When enabled, bar height matches your aerospace gap config:
#   - Between windows: uses inner.vertical (or inner.horizontal for left/right)
#   - At screen edge: uses outer.bottom (or outer.top/left/right)
auto_size_from_aerospace = true

# Position: "bottom", "top", "left", "right"
position = "bottom"

# Offset from window edge in pixels (0 = flush)
offset = 0

# Only show for specific apps (empty = all apps)
include_apps = []

# Never show for these apps
exclude_apps = ["Spotlight"]

# Auto-exclude apps with 'layout floating' in aerospace config (default: true)
# Reads [[on-window-detected]] rules from your aerospace.toml
auto_exclude_floating = true

# Animation (disabled by default)
animate = false
animation_duration = 0.1
```

Respects `XDG_CONFIG_HOME` if set.

## Commands

```bash
aerospace-focus              # Same as 'update' (default subcommand)
aerospace-focus daemon       # Start the daemon process
aerospace-focus update       # Update bar for focused window (auto-starts daemon if not running)
aerospace-focus hide         # Hide the bar
aerospace-focus show         # Show the bar
aerospace-focus reload       # Reload config from file
aerospace-focus set color "#ff0000"  # Change color temporarily
aerospace-focus status       # Show daemon status and socket path
aerospace-focus quit         # Stop the daemon
```

> **Note:** `aerospace-focus quit` stops the daemon, but if you have `after-startup-command` in aerospace.toml, AeroSpace will restart it on next launch.

## How It Works

1. AeroSpace's `on-focus-changed` hook triggers `aerospace-focus update`
2. The daemon queries focused window position via AeroSpace CLI + CoreGraphics
3. A borderless, click-through overlay bar is positioned in the gap space
4. Bar auto-sizes based on your gap config (inner vs outer depending on position)

**The bar automatically hides when:**
- Window is fullscreen
- Only one window is on the workspace
- The app is excluded (via `exclude_apps` or auto-detected floating layout)
- Mission Control / Exposé is active (restores after dismissal)

**Smart features:**
- Reads your `aerospace.toml` to auto-exclude apps with `layout floating` rules
- Detects screen edges and switches between inner/outer gap sizing
- Polls for window geometry changes (resize, retiling) every 200ms

## Troubleshooting

### Bar doesn't appear
1. Check daemon is running: `aerospace-focus status`
2. Check Accessibility permissions: System Settings → Privacy & Security → Accessibility
3. Check logs: `tail -f $(brew --prefix)/var/log/aerospace-focus.log` (Homebrew) or run daemon in foreground
4. Ensure AeroSpace is running and has gaps configured

### "Daemon not running" errors
- Run `aerospace-focus daemon` to start manually
- Or use `aerospace-focus update` which auto-starts the daemon

### Orphaned socket file
If the daemon was killed ungracefully:
```bash
rm /tmp/aerospace-focus.sock
aerospace-focus daemon
```

### Bar appears in wrong position
- Multi-monitor setups with mixed resolutions may have positioning issues
- Try restarting the daemon after changing display arrangement

## Uninstall

### Homebrew
```bash
brew services stop aerospace-focus
brew uninstall aerospace-focus
rm -rf ~/.config/aerospace-focus
```

### Manual
```bash
aerospace-focus quit
rm ~/.local/bin/aerospace-focus
rm -rf ~/.config/aerospace-focus
rm -f /tmp/aerospace-focus.sock
```

Remove from `~/.config/aerospace/aerospace.toml`:
- Delete the `exec-and-forget aerospace-focus daemon` line from `after-startup-command`
- Delete the `exec-and-forget aerospace-focus update` line from `on-focus-changed`

## License

[MIT](LICENSE)
