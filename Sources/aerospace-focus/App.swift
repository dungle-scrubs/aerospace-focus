import Cocoa

/// Application delegate for the daemon
class AppDelegate: NSObject, NSApplicationDelegate {
    let focusBar = FocusBar()
    let server = FocusServer()
    
    // Track last known window frame to detect geometry changes
    private var lastKnownFrame: CGRect?
    private var lastKnownApp: String?
    private var geometryCheckTimer: Timer?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Daemon starting...")
        
        // Create the focus bar
        focusBar.createBar()
        
        // Set up server callbacks
        server.onUpdate = { [weak self] in
            self?.focusBar.update()
            self?.updateLastKnownGeometry()
        }
        
        server.onHide = { [weak self] in
            self?.focusBar.hide()
        }
        
        server.onShow = { [weak self] in
            self?.focusBar.show()
        }
        
        server.onReload = { [weak self] in
            self?.focusBar.reloadConfig()
        }
        
        server.onSetColor = { [weak self] color in
            self?.focusBar.setColor(color)
        }
        
        server.onQuit = {
            log("Quit command received")
            NSApplication.shared.terminate(nil)
        }
        
        // Start the server
        server.start()
        
        // Initial update
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.focusBar.update()
            self?.updateLastKnownGeometry()
        }
        
        // Start periodic geometry check to catch window resizes/retiling
        // This handles cases like closing a window where on-focus-changed doesn't fire
        startGeometryCheck()
        
        log("Daemon ready")
    }
    
    /// Start periodic check for window geometry changes
    private func startGeometryCheck() {
        geometryCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.checkGeometryChange()
        }
    }
    
    /// Check if focused window geometry changed and update if needed
    private func checkGeometryChange() {
        guard let info = WindowQuery.getFocusedWindowInfo() else {
            // No focused window - if we had one before, update (will hide bar)
            if lastKnownFrame != nil {
                lastKnownFrame = nil
                lastKnownApp = nil
                focusBar.update()
            }
            return
        }
        
        let frameChanged = lastKnownFrame != info.frame
        let appChanged = lastKnownApp != info.appName
        
        if frameChanged || appChanged {
            log("Geometry change detected: \(info.appName) \(info.frame)")
            focusBar.update()
            updateLastKnownGeometry()
        }
    }
    
    /// Update cached geometry
    private func updateLastKnownGeometry() {
        if let info = WindowQuery.getFocusedWindowInfo() {
            lastKnownFrame = info.frame
            lastKnownApp = info.appName
        } else {
            lastKnownFrame = nil
            lastKnownApp = nil
        }
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        log("Daemon shutting down...")
        geometryCheckTimer?.invalidate()
        geometryCheckTimer = nil
        server.stop()
        focusBar.hide()
    }
}

/// Start the daemon
func runDaemon() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    
    // Run as accessory (no dock icon, no menu bar)
    app.setActivationPolicy(.accessory)
    
    log("Starting run loop...")
    app.run()
}
