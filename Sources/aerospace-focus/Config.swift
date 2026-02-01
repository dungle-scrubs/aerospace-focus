import Foundation
import TOMLKit

/// Aerospace gap configuration
struct AerospaceGaps {
    var innerHorizontal: CGFloat = 4
    var innerVertical: CGFloat = 4
    var outerTop: CGFloat = 4
    var outerLeft: CGFloat = 4
    var outerBottom: CGFloat = 4
    var outerRight: CGFloat = 4
}

/// Configuration for the focus bar
struct Config: Codable {
    var barHeight: CGFloat? = nil  // nil = auto from aerospace gaps
    var barColor: String = "#00ff00"
    var barOpacity: Double = 1.0
    var position: BarPosition = .bottom
    var offset: CGFloat = 0
    var includeApps: [String] = []
    var excludeApps: [String] = ["Finder", "Spotlight"]
    var animate: Bool = false
    var animationDuration: Double = 0.1
    var autoSizeFromAerospace: Bool = true  // Read gap size from aerospace config
    
    enum BarPosition: String, Codable {
        case bottom, top, left, right
    }
    
    enum CodingKeys: String, CodingKey {
        case barHeight = "bar_height"
        case barColor = "bar_color"
        case barOpacity = "bar_opacity"
        case position
        case offset
        case includeApps = "include_apps"
        case excludeApps = "exclude_apps"
        case animate
        case animationDuration = "animation_duration"
        case autoSizeFromAerospace = "auto_size_from_aerospace"
    }
    
    /// Parse hex color string to RGB components
    func parseColor() -> (red: CGFloat, green: CGFloat, blue: CGFloat) {
        var hex = barColor.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        
        guard hex.count == 6, let hexInt = UInt64(hex, radix: 16) else {
            return (0, 1, 0) // Default green
        }
        
        let red = CGFloat((hexInt >> 16) & 0xFF) / 255.0
        let green = CGFloat((hexInt >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hexInt & 0xFF) / 255.0
        
        return (red, green, blue)
    }
    
    /// Check if app should show focus bar
    func shouldShowForApp(_ appName: String) -> Bool {
        // Check exclusions first
        if excludeApps.contains(appName) {
            return false
        }
        
        // If include list is empty, show for all (except excluded)
        if includeApps.isEmpty {
            return true
        }
        
        // Otherwise, only show for included apps
        return includeApps.contains(appName)
    }
}

/// Configuration manager
class ConfigManager {
    static let shared = ConfigManager()
    
    private(set) var config = Config()
    private(set) var aerospaceGaps = AerospaceGaps()
    private var configPath: URL?
    
    private init() {
        loadAerospaceGaps()
        loadConfig()
    }
    
    var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("aerospace-focus")
    }
    
    var configFile: URL {
        configDirectory.appendingPathComponent("config.toml")
    }
    
    var aerospaceConfigFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config")
            .appendingPathComponent("aerospace")
            .appendingPathComponent("aerospace.toml")
    }
    
    /// Load gap configuration from Aerospace config
    func loadAerospaceGaps() {
        let path = aerospaceConfigFile
        
        guard FileManager.default.fileExists(atPath: path.path) else {
            log("No aerospace config at \(path.path), using default gaps")
            return
        }
        
        do {
            let contents = try String(contentsOf: path, encoding: .utf8)
            let toml = try TOMLTable(string: contents)
            
            if let gaps = toml["gaps"] as? TOMLTable {
                if let inner = gaps["inner"] as? TOMLTable {
                    if let h = inner["horizontal"]?.int {
                        aerospaceGaps.innerHorizontal = CGFloat(h)
                    }
                    if let v = inner["vertical"]?.int {
                        aerospaceGaps.innerVertical = CGFloat(v)
                    }
                }
                if let outer = gaps["outer"] as? TOMLTable {
                    if let top = outer["top"]?.int {
                        aerospaceGaps.outerTop = CGFloat(top)
                    }
                    if let left = outer["left"]?.int {
                        aerospaceGaps.outerLeft = CGFloat(left)
                    }
                    if let bottom = outer["bottom"]?.int {
                        aerospaceGaps.outerBottom = CGFloat(bottom)
                    }
                    if let right = outer["right"]?.int {
                        aerospaceGaps.outerRight = CGFloat(right)
                    }
                }
            }
            
            log("Loaded aerospace gaps: inner=\(aerospaceGaps.innerVertical), outer.bottom=\(aerospaceGaps.outerBottom)")
        } catch {
            log("Failed to load aerospace config: \(error), using default gaps")
        }
    }
    
    func loadConfig() {
        let path = configFile
        configPath = path
        
        guard FileManager.default.fileExists(atPath: path.path) else {
            log("No config file at \(path.path), using defaults")
            return
        }
        
        do {
            let contents = try String(contentsOf: path, encoding: .utf8)
            let toml = try TOMLTable(string: contents)
            
            if let barHeight = toml["bar_height"]?.double {
                config.barHeight = CGFloat(barHeight)
            }
            if let barColor = toml["bar_color"]?.string {
                config.barColor = barColor
            }
            if let barOpacity = toml["bar_opacity"]?.double {
                config.barOpacity = barOpacity
            }
            if let position = toml["position"]?.string,
               let pos = Config.BarPosition(rawValue: position) {
                config.position = pos
            }
            if let offset = toml["offset"]?.double {
                config.offset = CGFloat(offset)
            }
            if let includeApps = toml["include_apps"]?.array {
                config.includeApps = includeApps.compactMap { $0.string }
            }
            if let excludeApps = toml["exclude_apps"]?.array {
                config.excludeApps = excludeApps.compactMap { $0.string }
            }
            if let animate = toml["animate"]?.bool {
                config.animate = animate
            }
            if let animDuration = toml["animation_duration"]?.double {
                config.animationDuration = animDuration
            }
            if let autoSize = toml["auto_size_from_aerospace"]?.bool {
                config.autoSizeFromAerospace = autoSize
            }
            
            log("Loaded config from \(path.path)")
        } catch {
            log("Failed to load config: \(error), using defaults")
        }
    }
    
    /// Get the effective bar height based on position and whether window is at screen edge
    func effectiveBarHeight(position: Config.BarPosition, isAtScreenEdge: Bool) -> CGFloat {
        // If explicit bar_height is set, use it
        if let explicit = config.barHeight {
            return explicit
        }
        
        // Auto-size from aerospace gaps
        switch position {
        case .bottom:
            return isAtScreenEdge ? aerospaceGaps.outerBottom : aerospaceGaps.innerVertical
        case .top:
            return isAtScreenEdge ? aerospaceGaps.outerTop : aerospaceGaps.innerVertical
        case .left:
            return isAtScreenEdge ? aerospaceGaps.outerLeft : aerospaceGaps.innerHorizontal
        case .right:
            return isAtScreenEdge ? aerospaceGaps.outerRight : aerospaceGaps.innerHorizontal
        }
    }
    
    func reload() {
        loadAerospaceGaps()
        loadConfig()
    }
    
    func ensureConfigDirectory() {
        let dir = configDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Simple logging
func log(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    fputs("[\(timestamp)] \(message)\n", stderr)
}
