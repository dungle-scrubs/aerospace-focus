import Cocoa

/// Manages the focus indicator bar overlay window
class FocusBar {
    private var barWindow: NSWindow?
    private let config: ConfigManager
    
    init(config: ConfigManager = .shared) {
        self.config = config
    }
    
    /// Create the bar window
    func createBar() {
        // Use default height initially; will be resized when positioned
        let initialHeight = config.config.barHeight ?? config.aerospaceGaps.innerVertical
        let bar = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: initialHeight),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        // Appearance
        updateBarAppearance(bar)
        
        // Behavior
        bar.level = NSWindow.Level.floating
        bar.ignoresMouseEvents = true
        bar.collectionBehavior = NSWindow.CollectionBehavior([.canJoinAllSpaces, .stationary, .fullScreenAuxiliary])
        
        // Don't show in mission control, dock, etc.
        bar.isExcludedFromWindowsMenu = true
        bar.hidesOnDeactivate = false
        
        barWindow = bar
    }
    
    /// Update bar appearance from config
    func updateBarAppearance(_ bar: NSWindow? = nil) {
        let targetBar = bar ?? barWindow
        guard let window = targetBar else { return }
        
        let (r, g, b) = config.config.parseColor()
        window.backgroundColor = NSColor(
            red: r,
            green: g,
            blue: b,
            alpha: config.config.barOpacity
        )
        window.isOpaque = config.config.barOpacity >= 1.0
        window.hasShadow = false
    }
    
    /// Check if window is at the screen edge for the given position
    private func isAtScreenEdge(_ windowFrame: CGRect, position: Config.BarPosition) -> Bool {
        guard let screen = WindowQuery.screenContaining(windowFrame) else {
            return false
        }
        
        let visibleFrame = screen.visibleFrame
        let threshold: CGFloat = 10  // Allow small margin for edge detection
        
        switch position {
        case .bottom:
            return windowFrame.minY <= visibleFrame.minY + threshold
        case .top:
            return windowFrame.maxY >= visibleFrame.maxY - threshold
        case .left:
            return windowFrame.minX <= visibleFrame.minX + threshold
        case .right:
            return windowFrame.maxX >= visibleFrame.maxX - threshold
        }
    }
    
    /// Position the bar relative to the focused window
    func positionBar(relativeTo windowFrame: CGRect) {
        guard let bar = barWindow else {
            createBar()
            positionBar(relativeTo: windowFrame)
            return
        }
        
        let cfg = config.config
        let position = cfg.position
        let isAtEdge = isAtScreenEdge(windowFrame, position: position)
        let barHeight = config.effectiveBarHeight(position: position, isAtScreenEdge: isAtEdge)
        let barFrame: NSRect
        
        switch position {
        case .bottom:
            // Position in the gap below the window
            barFrame = NSRect(
                x: windowFrame.origin.x,
                y: windowFrame.origin.y - barHeight - cfg.offset,
                width: windowFrame.width,
                height: barHeight
            )
            
        case .top:
            // Position in the gap above the window
            barFrame = NSRect(
                x: windowFrame.origin.x,
                y: windowFrame.maxY + cfg.offset,
                width: windowFrame.width,
                height: barHeight
            )
            
        case .left:
            // Position in the gap to the left of the window
            barFrame = NSRect(
                x: windowFrame.origin.x - barHeight - cfg.offset,
                y: windowFrame.origin.y,
                width: barHeight,
                height: windowFrame.height
            )
            
        case .right:
            // Position in the gap to the right of the window
            barFrame = NSRect(
                x: windowFrame.maxX + cfg.offset,
                y: windowFrame.origin.y,
                width: barHeight,
                height: windowFrame.height
            )
        }
        
        // Ensure bar is visible on screen
        let clampedFrame = clampToScreen(barFrame, windowFrame: windowFrame)
        
        if cfg.animate && bar.isVisible {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = cfg.animationDuration
                bar.animator().setFrame(clampedFrame, display: true)
            }
        } else {
            bar.setFrame(clampedFrame, display: true)
        }
        
        bar.orderFront(nil)
    }
    
    /// Clamp bar frame to stay visible on screen
    private func clampToScreen(_ barFrame: NSRect, windowFrame: CGRect) -> NSRect {
        guard let screen = WindowQuery.screenContaining(windowFrame) else {
            return barFrame
        }
        
        var clamped = barFrame
        let screenFrame = screen.visibleFrame
        
        // Clamp X
        if clamped.minX < screenFrame.minX {
            clamped.origin.x = screenFrame.minX
        }
        if clamped.maxX > screenFrame.maxX {
            clamped.origin.x = screenFrame.maxX - clamped.width
        }
        
        // Clamp Y
        if clamped.minY < screenFrame.minY {
            clamped.origin.y = screenFrame.minY
        }
        if clamped.maxY > screenFrame.maxY {
            clamped.origin.y = screenFrame.maxY - clamped.height
        }
        
        return clamped
    }
    
    /// Hide the bar
    func hide() {
        barWindow?.orderOut(nil)
    }
    
    /// Show the bar (at last position)
    func show() {
        barWindow?.orderFront(nil)
    }
    
    /// Check if bar is visible
    var isVisible: Bool {
        barWindow?.isVisible ?? false
    }
    
    /// Update the bar for the currently focused window
    func update() {
        guard let windowInfo = WindowQuery.getFocusedWindowInfo() else {
            log("No focused window found")
            hide()
            return
        }
        
        let frame = windowInfo.frame
        let appName = windowInfo.appName
        let bundleId = windowInfo.bundleId
        
        // Check if app should show bar (includes auto-exclude for floating apps)
        if !config.config.shouldShowForApp(appName, bundleId: bundleId, floatingRules: config.floatingRules) {
            log("App '\(appName)' (\(bundleId ?? "no-bundle-id")) is excluded")
            hide()
            return
        }
        
        // Check for fullscreen
        if WindowQuery.isWindowFullscreen(frame) {
            log("Window is fullscreen, hiding bar")
            hide()
            return
        }
        
        // Only show focus bar if there are multiple windows on the workspace
        let windowCount = WindowQuery.getWorkspaceWindowCount()
        if windowCount <= 1 {
            log("Only \(windowCount) window(s) on workspace, hiding bar")
            hide()
            return
        }
        
        log("Showing bar for '\(appName)' at \(frame)")
        positionBar(relativeTo: frame)
    }
    
    /// Reload configuration and update appearance
    func reloadConfig() {
        config.reload()
        updateBarAppearance()
        update()
    }
    
    /// Set bar color temporarily (doesn't persist to config)
    func setColor(_ hexColor: String) {
        guard let bar = barWindow else { return }
        
        var hex = hexColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        
        guard hex.count == 6, let hexInt = UInt64(hex, radix: 16) else {
            log("Invalid color: \(hexColor)")
            return
        }
        
        let red = CGFloat((hexInt >> 16) & 0xFF) / 255.0
        let green = CGFloat((hexInt >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hexInt & 0xFF) / 255.0
        
        bar.backgroundColor = NSColor(red: red, green: green, blue: blue, alpha: config.config.barOpacity)
    }
}
