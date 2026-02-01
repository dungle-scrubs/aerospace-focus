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

- macOS 14+
- [AeroSpace](https://github.com/nikitabobko/AeroSpace) window manager

## Installation

### Homebrew (recommended)

```bash
brew install dungle-scrubs/aerospace-focus/aerospace-focus
brew services start aerospace-focus
```

### Manual

```bash
# Build from source
git clone https://github.com/dungle-scrubs/aerospace-focus
cd aerospace-focus
swift build -c release
cp .build/release/aerospace-focus ~/.local/bin/
```

## Aerospace Integration

Add to your `~/.config/aerospace/aerospace.toml`:

```toml
# Gaps (bar auto-sizes to fit)
[gaps]
inner.horizontal = 4
inner.vertical = 4
outer.top = 4
outer.left = 4
outer.bottom = 4
outer.right = 4

# Start daemon and update on focus change
after-startup-command = [
    'exec-and-forget aerospace-focus daemon'
]

on-focus-changed = ['exec-and-forget aerospace-focus update']
```

Then reload: `aerospace reload-config`

## Configuration

Create `~/.config/aerospace-focus/config.toml`:

```toml
# Bar appearance
# bar_height = 4           # Uncomment to override auto-sizing
bar_color = "#00ff00"      # Green
bar_opacity = 1.0

# Auto-size from aerospace gaps (default: true)
auto_size_from_aerospace = true

# Position: "bottom", "top", "left", "right"
position = "bottom"

# Apps to exclude
exclude_apps = ["Finder", "Spotlight"]
```

## Commands

```bash
aerospace-focus daemon     # Start daemon (run by Aerospace)
aerospace-focus update     # Update bar position
aerospace-focus hide       # Hide the bar
aerospace-focus show       # Show the bar
aerospace-focus reload     # Reload config
aerospace-focus set color "#ff0000"  # Change color
aerospace-focus status     # Check daemon status
aerospace-focus quit       # Stop daemon
```

## How It Works

1. Aerospace's `on-focus-changed` hook triggers `aerospace-focus update`
2. Daemon queries focused window position via Aerospace CLI + CoreGraphics
3. A borderless, click-through overlay bar is positioned in the gap
4. Bar auto-sizes based on gap config (inner vs outer depending on window position)

## License

[MIT](LICENSE)
