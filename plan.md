# Aerospace Focus Bar

A lightweight Swift app that draws a colored bar at the bottom edge of the focused window, using the gap space created by Aerospace.

## Overview

When a window gains focus in Aerospace, a thin colored bar appears in the gap below it—providing a subtle, non-intrusive focus indicator that lives in the dead space between tiled windows.

```
┌─────────────────────────────┐
│                             │
│      Focused Window         │
│                             │
└─────────────────────────────┘
████████████████████████████████  ← 4px green bar in the gap
              ↕ 15px gap (Aerospace inner.vertical)
┌─────────────────────────────┐
│      Other Window           │
└─────────────────────────────┘
```

## Architecture

### Option 1: Aerospace-Driven (Chosen)

Aerospace's `on-focus-changed` hook invokes our app, which then:

1. Queries the focused window's frame via `aerospace list-windows --focused`
2. Positions a borderless overlay window in the gap below
3. The overlay persists until the next focus change

```
┌──────────────┐     on-focus-changed      ┌─────────────────────┐
│   Aerospace  │ ─────────────────────────▶│  aerospace-focus    │
└──────────────┘                           │  (Swift CLI/daemon) │
                                           └──────────┬──────────┘
                                                      │
                                           ┌──────────▼──────────┐
                                           │  Query window frame │
                                           │  via aerospace CLI  │
                                           └──────────┬──────────┘
                                                      │
                                           ┌──────────▼──────────┐
                                           │  Position/show bar  │
                                           │  NSWindow overlay   │
                                           └─────────────────────┘
```

### Components

1. **Daemon Process** (`aerospace-focus`)
   - Runs as a background process (started by Aerospace)
   - Listens for commands via Unix socket or simple CLI invocation
   - Manages the overlay bar window

2. **Overlay Bar** (NSWindow)
   - Borderless, click-through window
   - Positioned at bottom edge of focused window
   - Floats above other windows but below the focused window's level

## Implementation Details

### Getting Window Frame

Two options for getting the focused window's position:

#### A. Via Aerospace CLI (Simple, Recommended)

```bash
aerospace list-windows --focused --format '%{window-id} %{app-name} %{window-title}'
```

However, Aerospace doesn't expose window frame directly. We need to bridge to the window ID and query CoreGraphics:

```swift
// Get window ID from aerospace
let windowId = getAerospaceWindowId()

// Query frame via CGWindowListCopyWindowInfo
let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowId)) as? [[String: Any]]
let bounds = windowList?.first?[kCGWindowBounds as String] as? [String: CGFloat]
```

#### B. Via Accessibility API (Fallback)

```swift
let app = NSWorkspace.shared.frontmostApplication
let axApp = AXUIElementCreateApplication(app!.processIdentifier)
var focusedWindow: CFTypeRef?
AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)

var position: CFTypeRef?
var size: CFTypeRef?
AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXPositionAttribute as CFString, &position)
AXUIElementCopyAttributeValue(focusedWindow as! AXUIElement, kAXSizeAttribute as CFString, &size)
```

### Overlay Window Setup

```swift
class FocusBar {
    private var barWindow: NSWindow?
    
    func createBar() {
        let bar = NSWindow(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Appearance
        bar.backgroundColor = NSColor(red: 0, green: 1, blue: 0, alpha: 1) // Green
        bar.isOpaque = true
        bar.hasShadow = false
        
        // Behavior
        bar.level = .floating
        bar.ignoresMouseEvents = true
        bar.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        
        // Don't show in mission control, dock, etc.
        bar.isExcludedFromWindowsMenu = true
        
        barWindow = bar
    }
    
    func positionBar(below windowFrame: CGRect, barHeight: CGFloat = 4) {
        guard let bar = barWindow else { return }
        
        // Position in the gap below the window
        // Note: macOS screen coordinates have origin at bottom-left
        let barFrame = NSRect(
            x: windowFrame.origin.x,
            y: windowFrame.origin.y - barHeight - 1, // 1px gap from window edge
            width: windowFrame.width,
            height: barHeight
        )
        
        bar.setFrame(barFrame, display: true)
        bar.orderFront(nil)
    }
    
    func hide() {
        barWindow?.orderOut(nil)
    }
}
```

### Process Architecture Options

#### Option A: Persistent Daemon (Recommended)

A long-running process that Aerospace signals on focus change:

```swift
// Main.swift
import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    let focusBar = FocusBar()
    let server = FocusServer() // Unix socket or XPC
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        focusBar.createBar()
        server.onFocusChanged = { [weak self] in
            self?.updateBar()
        }
        server.start()
    }
    
    func updateBar() {
        if let frame = getFocusedWindowFrame() {
            focusBar.positionBar(below: frame)
        }
    }
}

// Run as agent (no dock icon)
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
```

Aerospace config:
```toml
on-focus-changed = ['exec-and-forget aerospace-focus notify']
```

The `notify` command sends a signal to the running daemon via:
- Unix domain socket
- Distributed notification (`DistributedNotificationCenter`)
- Simple file touch + FSEvents
- Or just re-query on timer (simplest but less responsive)

#### Option B: CLI Invocation (Simpler)

Each focus change spawns the process, updates the bar, keeps running:

```swift
// If already running, send signal to update
// If not running, start and show bar

// Use NSDistributedNotificationCenter for IPC
DistributedNotificationCenter.default().post(
    name: Notification.Name("com.aerospace-focus.update"),
    object: nil
)
```

### Communication Protocol

Using Unix domain socket for low-latency IPC:

```swift
// Server (daemon)
class FocusServer {
    let socketPath = "/tmp/aerospace-focus.sock"
    var onFocusChanged: (() -> Void)?
    
    func start() {
        // Remove existing socket
        unlink(socketPath)
        
        // Create socket
        let socket = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        socketPath.withCString { ptr in
            withUnsafeMutablePointer(to: &addr.sun_path.0) { dest in
                strcpy(dest, ptr)
            }
        }
        
        bind(socket, ...)
        listen(socket, 5)
        
        // Accept loop in background
        DispatchQueue.global().async {
            while true {
                let client = accept(socket, nil, nil)
                // Read command, trigger update
                DispatchQueue.main.async {
                    self.onFocusChanged?()
                }
                close(client)
            }
        }
    }
}

// Client (CLI invocation)
func notifyDaemon() {
    let socket = socket(AF_UNIX, SOCK_STREAM, 0)
    var addr = sockaddr_un()
    // ... connect and send "update" ...
    close(socket)
}
```

## Configuration

### Config File: `~/.config/aerospace-focus/config.toml`

```toml
# Bar appearance
bar_height = 4
bar_color = "#00ff00"  # Green
bar_opacity = 1.0

# Position: "bottom", "top", "left", "right"
position = "bottom"

# Offset from window edge (uses Aerospace gap space)
offset = 1

# Only show for specific apps (empty = all apps)
include_apps = []

# Never show for these apps
exclude_apps = ["Finder", "Spotlight"]

# Animation
animate = false
animation_duration = 0.1
```

### Runtime Commands

```bash
# Update bar (called by Aerospace)
aerospace-focus update

# Change color temporarily
aerospace-focus set color "#ff0000"

# Hide bar
aerospace-focus hide

# Show bar
aerospace-focus show

# Reload config
aerospace-focus reload

# Stop daemon
aerospace-focus quit
```

## Project Structure

```
aerospace-focus/
├── Package.swift
├── Sources/
│   └── aerospace-focus/
│       ├── main.swift           # Entry point, argument parsing
│       ├── App.swift            # NSApplication setup
│       ├── FocusBar.swift       # Overlay window management
│       ├── WindowQuery.swift    # Get focused window frame
│       ├── Server.swift         # Unix socket IPC
│       ├── Config.swift         # Configuration loading
│       └── CLI.swift            # Command handling
├── config.example.toml
├── install.sh
└── README.md
```

## Build & Installation

### Package.swift

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "aerospace-focus",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.2.0"),
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "aerospace-focus",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "TOMLKit", package: "TOMLKit"),
            ]
        ),
    ]
)
```

### Build

```bash
swift build -c release
cp .build/release/aerospace-focus ~/.local/bin/
```

### Install Script

```bash
#!/bin/bash
set -e

# Build
swift build -c release

# Install binary
mkdir -p ~/.local/bin
cp .build/release/aerospace-focus ~/.local/bin/

# Install default config
mkdir -p ~/.config/aerospace-focus
if [ ! -f ~/.config/aerospace-focus/config.toml ]; then
    cp config.example.toml ~/.config/aerospace-focus/config.toml
fi

echo "Installed! Add to your aerospace.toml:"
echo ""
echo "after-startup-command = ["
echo "    'exec-and-forget aerospace-focus daemon'"
echo "]"
echo ""
echo "on-focus-changed = ['exec-and-forget aerospace-focus update']"
```

## Aerospace Integration

Update `~/.config/aerospace/aerospace.toml`:

```toml
after-startup-command = [
    # Start the focus bar daemon
    'exec-and-forget aerospace-focus daemon',
    # Existing borders config...
    'exec-and-forget borders active_color=0xff00ff00 inactive_color=0xff494d64 width=5.0',
]

on-focus-changed = [
    # Notify focus bar
    'exec-and-forget aerospace-focus update',
    # Existing borders-toggle...
    'exec-and-forget ~/.local/bin/borders-toggle'
]
```

## Edge Cases & Considerations

### 1. Coordinate System
- macOS uses bottom-left origin for screen coordinates
- CGWindowListCopyWindowInfo returns top-left origin bounds
- Must convert between coordinate systems

### 2. Multiple Monitors
- Each monitor has its own coordinate space
- Need to find which screen the focused window is on
- Position bar relative to that screen's coordinate system

### 3. Full-Screen Windows
- Aerospace gaps don't apply in full-screen
- Hide bar when window is full-screen

### 4. Floating Windows
- May not have consistent gap space
- Could skip or use different positioning

### 5. Window at Screen Edge
- If window is at bottom of screen, bar would be off-screen
- Clamp position or hide bar in this case

### 6. Performance
- Unix socket IPC is fast (~1ms)
- CGWindowListCopyWindowInfo is relatively fast
- Avoid Accessibility API if possible (slower, requires permissions)

### 7. Permissions
- May need Accessibility permissions for some window queries
- Screen Recording permission for CGWindowListCopyWindowInfo with some options

## Future Enhancements

1. **Multiple bar styles** - Gradient, glow effect (like JankyBorders)
2. **Per-app colors** - Different colors for different applications
3. **Workspace indicators** - Show workspace number/letter in the bar
4. **Animation** - Smooth transitions when focus changes
5. **Integration with borders** - Could potentially merge with or extend JankyBorders

## Development Phases

### Phase 1: MVP
- [ ] Basic daemon that shows/hides bar
- [ ] Get focused window frame via CGWindowListCopyWindowInfo
- [ ] Position bar below focused window
- [ ] Aerospace hook integration

### Phase 2: Polish
- [ ] Configuration file support
- [ ] Multiple monitor support
- [ ] Coordinate system handling
- [ ] Edge case handling (full-screen, floating)

### Phase 3: Features
- [ ] Per-app configuration
- [ ] Animation support
- [ ] Additional bar positions (top, left, right)
- [ ] Color themes

## References

- [JankyBorders source](https://github.com/FelixKratz/JankyBorders) - C implementation of window borders
- [Aerospace docs](https://nikitabobko.github.io/AeroSpace/commands) - Hook configuration
- [CGWindowListCopyWindowInfo](https://developer.apple.com/documentation/coregraphics/1455137-cgwindowlistcopywindowinfo) - Window enumeration API
- [NSWindow documentation](https://developer.apple.com/documentation/appkit/nswindow) - Overlay window setup
