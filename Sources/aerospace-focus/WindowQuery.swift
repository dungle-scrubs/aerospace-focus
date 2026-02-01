import Cocoa
import CoreGraphics

/// Information about a window
struct WindowInfo {
    let windowId: CGWindowID
    let ownerName: String
    let frame: CGRect
    let isOnScreen: Bool
    let layer: Int
}

/// Query window information using CoreGraphics
class WindowQuery {
    
    /// Get the focused window's frame
    /// Uses Aerospace CLI to get the window ID, then CGWindowListCopyWindowInfo for the frame
    static func getFocusedWindowFrame() -> (frame: CGRect, appName: String)? {
        // First try Aerospace CLI
        if let info = getAerospaceWindow() {
            return info
        }
        
        // Fallback to frontmost application's focused window
        return getFrontmostWindowFrame()
    }
    
    /// Find aerospace binary
    private static func findAerospaceBinary() -> String? {
        let paths = [
            "/opt/homebrew/bin/aerospace",  // Apple Silicon Homebrew
            "/usr/local/bin/aerospace",      // Intel Homebrew
            "/run/current-system/sw/bin/aerospace"  // Nix
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        return nil
    }
    
    /// Get window info via Aerospace CLI
    private static func getAerospaceWindow() -> (frame: CGRect, appName: String)? {
        guard let aerospacePath = findAerospaceBinary() else {
            log("Aerospace binary not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = ["list-windows", "--focused", "--format", "%{window-id}|%{app-name}"]
        
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
            process.waitUntilExit()
            
            guard process.terminationStatus == 0 else { return nil }
            
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !output.isEmpty else {
                return nil
            }
            
            let parts = output.split(separator: "|", maxSplits: 1)
            guard parts.count >= 2,
                  let windowId = UInt32(parts[0]) else {
                return nil
            }
            
            let appName = String(parts[1])
            
            // Get frame from CGWindowListCopyWindowInfo
            if let frame = getWindowFrame(windowId: windowId) {
                return (frame, appName)
            }
        } catch {
            log("Aerospace CLI failed: \(error)")
        }
        
        return nil
    }
    
    /// Get window frame by window ID using CoreGraphics
    private static func getWindowFrame(windowId: CGWindowID) -> CGRect? {
        let windowList = CGWindowListCopyWindowInfo([.optionIncludingWindow], windowId) as? [[String: Any]]
        
        guard let window = windowList?.first,
              let bounds = window[kCGWindowBounds as String] as? [String: CGFloat] else {
            return nil
        }
        
        // CGWindowListCopyWindowInfo returns bounds with top-left origin
        let x = bounds["X"] ?? 0
        let y = bounds["Y"] ?? 0
        let width = bounds["Width"] ?? 0
        let height = bounds["Height"] ?? 0
        
        // Convert from top-left origin to bottom-left origin (macOS screen coords)
        // We need to find which screen this window is on
        let topLeftFrame = CGRect(x: x, y: y, width: width, height: height)
        return convertToScreenCoordinates(topLeftFrame)
    }
    
    /// Convert from CG coordinates (top-left origin) to NS coordinates (bottom-left origin)
    private static func convertToScreenCoordinates(_ cgRect: CGRect) -> CGRect {
        // Find the screen that contains most of this window
        guard let screen = NSScreen.screens.first(where: { screen in
            screen.frame.intersects(CGRect(
                x: cgRect.origin.x,
                y: screen.frame.height - cgRect.origin.y - cgRect.height,
                width: cgRect.width,
                height: cgRect.height
            ))
        }) ?? NSScreen.main else {
            return cgRect
        }
        
        // Get the main screen's height for coordinate conversion
        let mainScreenHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        
        // Convert Y coordinate: nsY = mainScreenHeight - cgY - height
        let nsY = mainScreenHeight - cgRect.origin.y - cgRect.height
        
        return CGRect(
            x: cgRect.origin.x,
            y: nsY,
            width: cgRect.width,
            height: cgRect.height
        )
    }
    
    /// Fallback: Get frontmost application's window frame using Accessibility API
    private static func getFrontmostWindowFrame() -> (frame: CGRect, appName: String)? {
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appName = frontApp.localizedName ?? "Unknown"
        let pid = frontApp.processIdentifier
        
        let axApp = AXUIElementCreateApplication(pid)
        
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let window = focusedWindow else {
            return nil
        }
        
        let axWindow = window as! AXUIElement
        
        // Get position
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        
        var position = CGPoint.zero
        if let posRef = positionRef {
            AXValueGetValue(posRef as! AXValue, .cgPoint, &position)
        }
        
        // Get size
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        
        var size = CGSize.zero
        if let sRef = sizeRef {
            AXValueGetValue(sRef as! AXValue, .cgSize, &size)
        }
        
        // Convert coordinates (Accessibility uses top-left origin)
        let cgRect = CGRect(origin: position, size: size)
        let frame = convertToScreenCoordinates(cgRect)
        
        return (frame, appName)
    }
    
    /// Check if a window is in fullscreen mode
    static func isWindowFullscreen(_ frame: CGRect) -> Bool {
        for screen in NSScreen.screens {
            // Check if window frame matches screen frame (approximately)
            if abs(frame.width - screen.frame.width) < 10 &&
               abs(frame.height - screen.frame.height) < 50 { // Menu bar allowance
                return true
            }
        }
        return false
    }
    
    /// Get the screen containing the given frame
    static func screenContaining(_ frame: CGRect) -> NSScreen? {
        let center = CGPoint(x: frame.midX, y: frame.midY)
        return NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
    }
}
