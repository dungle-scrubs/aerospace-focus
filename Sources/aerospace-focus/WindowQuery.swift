import Cocoa
import CoreGraphics

/// Result of focused window query
struct FocusedWindowInfo {
    let frame: CGRect
    let appName: String
    let bundleId: String?
}

/// Query window information using CoreGraphics
class WindowQuery {
    private static var cachedAerospacePath: String?
    
    /// Get full focused window info including bundle ID
    static func getFocusedWindowInfo() -> FocusedWindowInfo? {
        // First try Aerospace CLI
        if let info = getAerospaceWindow() {
            // Get bundle ID from frontmost app (aerospace doesn't provide it)
            let bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            return FocusedWindowInfo(frame: info.frame, appName: info.appName, bundleId: bundleId)
        }
        
        // Fallback to frontmost application's focused window
        return getFrontmostWindowInfo()
    }
    
    /// Find aerospace binary
    private static func findAerospaceBinary() -> String? {
        if let cached = cachedAerospacePath { return cached }
        let paths = [
            "/opt/homebrew/bin/aerospace",  // Apple Silicon Homebrew
            "/usr/local/bin/aerospace",      // Intel Homebrew
            "/run/current-system/sw/bin/aerospace"  // Nix
        ]
        for path in paths {
            if FileManager.default.fileExists(atPath: path) {
                cachedAerospacePath = path
                return path
            }
        }
        return nil
    }
    
    /// Run an aerospace CLI command with timeout
    /// - Parameters:
    ///   - args: Command arguments to pass to aerospace binary
    ///   - timeout: Maximum seconds to wait (default 2.0)
    /// - Returns: Trimmed stdout string, or nil on failure
    private static func runAerospaceCommand(_ args: [String], timeout: TimeInterval = 2.0) -> String? {
        guard let aerospacePath = findAerospaceBinary() else {
            log("Aerospace binary not found")
            return nil
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospacePath)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        
        do {
            try process.run()
        } catch {
            log("Aerospace CLI failed: \(error)")
            return nil
        }
        
        // Wait with timeout to prevent hanging
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }
        
        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            log("Aerospace CLI timed out after \(timeout)s")
            return nil
        }
        
        guard process.terminationStatus == 0 else { return nil }
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !output.isEmpty else {
            return nil
        }
        return output
    }
    
    /// Get window info via Aerospace CLI
    private static func getAerospaceWindow() -> (frame: CGRect, appName: String)? {
        guard let output = runAerospaceCommand(["list-windows", "--focused", "--format", "%{window-id}|%{app-name}"]) else {
            return nil
        }
        
        let parts = output.split(separator: "|", maxSplits: 1)
        guard parts.count >= 2,
              let windowId = UInt32(parts[0]) else {
            return nil
        }
        
        let appName = String(parts[1])
        
        if let frame = getWindowFrame(windowId: windowId) {
            return (frame, appName)
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
    
    /// Convert from CG coordinates (top-left origin, global) to NS coordinates (bottom-left origin, global)
    /// CG coordinate system: origin at top-left of primary display
    /// NS coordinate system: origin at bottom-left of primary display
    private static func convertToScreenCoordinates(_ cgRect: CGRect) -> CGRect {
        // The primary screen's height is the reference for global coordinate conversion
        // NSScreen.screens[0] is always the primary display
        guard let primaryScreen = NSScreen.screens.first else {
            return cgRect
        }
        
        let primaryHeight = primaryScreen.frame.height
        
        // Convert Y: NS_Y = primaryHeight - CG_Y - height
        let nsY = primaryHeight - cgRect.origin.y - cgRect.height
        
        return CGRect(
            x: cgRect.origin.x,
            y: nsY,
            width: cgRect.width,
            height: cgRect.height
        )
    }
    
    /// Fallback: Get frontmost application's window info using Accessibility API
    private static func getFrontmostWindowInfo() -> FocusedWindowInfo? {
        guard AXIsProcessTrusted() else {
            log("Accessibility permissions not granted — grant in System Settings → Privacy & Security → Accessibility")
            return nil
        }
        
        guard let frontApp = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        
        let appName = frontApp.localizedName ?? "Unknown"
        let bundleId = frontApp.bundleIdentifier
        let pid = frontApp.processIdentifier
        
        let axApp = AXUIElementCreateApplication(pid)
        
        var focusedWindow: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString, &focusedWindow)
        
        guard result == .success, let window = focusedWindow else {
            return nil
        }
        
        // CFTypeRef from Accessibility API is already AXUIElement
        let axWindow = unsafeBitCast(window, to: AXUIElement.self)
        
        // Get position
        var positionRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXPositionAttribute as CFString, &positionRef)
        
        var position = CGPoint.zero
        if let posRef = positionRef {
            let value = unsafeBitCast(posRef, to: AXValue.self)
            AXValueGetValue(value, .cgPoint, &position)
        }
        
        // Get size
        var sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axWindow, kAXSizeAttribute as CFString, &sizeRef)
        
        var size = CGSize.zero
        if let sRef = sizeRef {
            let value = unsafeBitCast(sRef, to: AXValue.self)
            AXValueGetValue(value, .cgSize, &size)
        }
        
        // Convert coordinates (Accessibility uses top-left origin)
        let cgRect = CGRect(origin: position, size: size)
        let frame = convertToScreenCoordinates(cgRect)
        
        return FocusedWindowInfo(frame: frame, appName: appName, bundleId: bundleId)
    }
    
    /// Count windows on the focused workspace
    static func getWorkspaceWindowCount() -> Int {
        guard let output = runAerospaceCommand(["list-windows", "--workspace", "focused", "--format", "%{window-id}"]) else {
            return 0
        }
        return output.components(separatedBy: .newlines).filter { !$0.isEmpty }.count
    }
    
    /// Check if a window is in fullscreen mode
    static func isWindowFullscreen(_ frame: CGRect) -> Bool {
        for screen in NSScreen.screens {
            let menuBarAllowance = screen.frame.height - screen.visibleFrame.height + screen.visibleFrame.origin.y - screen.frame.origin.y
            if abs(frame.width - screen.frame.width) < 10 &&
               abs(frame.height - screen.frame.height) < menuBarAllowance + 10 {
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
