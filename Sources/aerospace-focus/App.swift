import Cocoa

/// Application delegate for the daemon
class AppDelegate: NSObject, NSApplicationDelegate {
    let focusBar = FocusBar()
    let server = FocusServer()
    
    // Track last known window frame to detect geometry changes
    private var lastKnownFrame: CGRect?
    private var lastKnownApp: String?
    private var geometryCheckTimer: Timer?
    
    // Mission Control state - pause updates during Exposé
    private var isMissionControlActive = false
    private var missionControlActivationCount = 0
    
    // Timing constants
    private let initialUpdateDelay: TimeInterval = 0.5
    private let geometryCheckInterval: TimeInterval = 0.2
    private let windowSettlingDelay: TimeInterval = 0.3
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Daemon starting...")
        
        // Handle POSIX signals for clean shutdown
        signal(SIGTERM) { _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
        signal(SIGINT) { _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
        signal(SIGHUP) { _ in
            DispatchQueue.main.async { NSApplication.shared.terminate(nil) }
        }
        
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
        DispatchQueue.main.asyncAfter(deadline: .now() + initialUpdateDelay) { [weak self] in
            self?.focusBar.update()
            self?.updateLastKnownGeometry()
        }
        
        // Start periodic geometry check to catch window resizes/retiling
        // This handles cases like closing a window where on-focus-changed doesn't fire
        startGeometryCheck()
        
        // Listen for Mission Control activation/deactivation
        setupMissionControlObservers()
        
        log("Daemon ready")
    }
    
    /// Start periodic check for window geometry changes
    private func startGeometryCheck() {
        geometryCheckTimer = Timer.scheduledTimer(withTimeInterval: geometryCheckInterval, repeats: true) { [weak self] _ in
            self?.checkGeometryChange()
        }
    }
    
    /// Set up observers for Mission Control (Exposé) activation
    private func setupMissionControlObservers() {
        let dnc = DistributedNotificationCenter.default()
        
        // Mission Control activating - hide bar and pause updates
        dnc.addObserver(
            self,
            selector: #selector(missionControlActivated),
            name: NSNotification.Name("com.apple.exposé.willActivate"),
            object: nil
        )
        
        // Mission Control deactivating - restore bar after windows settle
        dnc.addObserver(
            self,
            selector: #selector(missionControlDeactivated),
            name: NSNotification.Name("com.apple.exposé.didDeactivate"),
            object: nil
        )
        
        log("Mission Control observers registered")
    }
    
    @objc private func missionControlActivated(_ notification: Notification) {
        log("Mission Control activated - hiding bar")
        isMissionControlActive = true
        missionControlActivationCount += 1
        lastKnownFrame = nil  // Force refresh after Mission Control
        lastKnownApp = nil
        focusBar.hide()
    }
    
    @objc private func missionControlDeactivated(_ notification: Notification) {
        log("Mission Control deactivated - restoring bar")
        isMissionControlActive = false
        let currentCount = missionControlActivationCount
        
        // Delay update to let windows settle to their final positions
        DispatchQueue.main.asyncAfter(deadline: .now() + windowSettlingDelay) { [weak self] in
            guard let self = self,
                  currentCount == self.missionControlActivationCount else { return }
            self.focusBar.update()
            self.updateLastKnownGeometry()
        }
    }
    
    /// Check if focused window geometry changed and update if needed
    private func checkGeometryChange() {
        // Skip updates during Mission Control
        guard !isMissionControlActive else { return }
        
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
        DistributedNotificationCenter.default().removeObserver(self)
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
