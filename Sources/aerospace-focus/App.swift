import Cocoa

/// Application delegate for the daemon
class AppDelegate: NSObject, NSApplicationDelegate {
    let focusBar = FocusBar()
    let server = FocusServer()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        log("Daemon starting...")
        
        // Create the focus bar
        focusBar.createBar()
        
        // Set up server callbacks
        server.onUpdate = { [weak self] in
            self?.focusBar.update()
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
        }
        
        log("Daemon ready")
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        log("Daemon shutting down...")
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
