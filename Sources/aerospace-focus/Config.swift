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

/// Floating app rules parsed from aerospace config
struct FloatingAppRules {
    var appIds: Set<String> = []
    private var appNamePatterns: [String] = []
    private var compiledAppNameRegexes: [NSRegularExpression] = []
    private var windowTitlePatterns: [String] = []
    
    /// Add an app name regex pattern, compiling it immediately
    /// - Parameter pattern: Regex pattern string
    mutating func addAppNamePattern(_ pattern: String) {
        appNamePatterns.append(pattern)
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            compiledAppNameRegexes.append(regex)
        } catch {
            log("Invalid floating rule regex '\(pattern)': \(error.localizedDescription)")
        }
    }
    
    /// Add a window title regex pattern
    /// - Parameter pattern: Regex pattern string
    mutating func addWindowTitlePattern(_ pattern: String) {
        windowTitlePatterns.append(pattern)
    }
    
    /// Check if an app matches floating rules
    /// - Parameters:
    ///   - bundleId: Optional bundle identifier
    ///   - appName: Application name
    /// - Returns: true if the app matches any floating rule
    func isFloating(bundleId: String?, appName: String) -> Bool {
        if let id = bundleId, appIds.contains(id) {
            return true
        }
        
        let range = NSRange(appName.startIndex..., in: appName)
        for regex in compiledAppNameRegexes {
            if regex.firstMatch(in: appName, range: range) != nil {
                return true
            }
        }
        
        return false
    }
}

/// Configuration for the focus bar
struct Config: Codable {
    var barHeight: CGFloat? = nil  // nil = auto from aerospace gaps
    var barColor: String = "#00ff00"
    var barOpacity: Double = 1.0
    var position: BarPosition = .bottom
    var offset: CGFloat = 0
    var includeApps: [String] = []
    var excludeApps: [String] = ["Spotlight"]  // Minimal default; floating apps auto-detected from aerospace
    var autoExcludeFloating: Bool = true       // Auto-exclude apps with 'layout floating' in aerospace config
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
        case autoExcludeFloating = "auto_exclude_floating"
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
    
    /// Check if app should show focus bar (basic check without floating rules)
    func shouldShowForApp(_ appName: String) -> Bool {
        return shouldShowForApp(appName, bundleId: nil, floatingRules: nil)
    }
    
    /// Check if app should show focus bar
    func shouldShowForApp(_ appName: String, bundleId: String?, floatingRules: FloatingAppRules?) -> Bool {
        // Check exclusions first
        if excludeApps.contains(appName) {
            return false
        }
        
        // Check if app is floating in aerospace (auto-exclude)
        if autoExcludeFloating, let rules = floatingRules {
            if rules.isFloating(bundleId: bundleId, appName: appName) {
                return false
            }
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
    private(set) var floatingRules = FloatingAppRules()
    private var configPath: URL?
    
    private init() {
        loadAerospaceConfig()
        loadConfig()
    }
    
    /// Load all aerospace-related config (gaps + floating rules)
    func loadAerospaceConfig() {
        let path = aerospaceConfigFile
        floatingRules = FloatingAppRules()
        
        guard FileManager.default.fileExists(atPath: path.path) else {
            log("No aerospace config at \(path.path), using default gaps")
            return
        }
        
        do {
            let contents = try String(contentsOf: path, encoding: .utf8)
            let toml = try TOMLTable(string: contents)
            
            // Parse gaps
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
                log("Loaded aerospace gaps: inner=\(aerospaceGaps.innerVertical), outer.bottom=\(aerospaceGaps.outerBottom)")
            }
            
            // Parse floating rules from [[on-window-detected]]
            if let windowRules = toml["on-window-detected"] as? TOMLArray {
                for item in windowRules {
                    guard let rule = item as? TOMLTable else { continue }
                    guard let runCommands = rule["run"] as? TOMLArray else { continue }
                    let isFloatingRule = runCommands.contains { cmd in
                        if let str = cmd.string {
                            return str == "layout floating" || str.contains("layout floating")
                        }
                        return false
                    }
                    guard isFloatingRule else { continue }
                    
                    if let ifTable = rule["if"] as? TOMLTable {
                        if let appId = ifTable["app-id"]?.string {
                            floatingRules.appIds.insert(appId)
                            log("Floating rule: app-id = \(appId)")
                        }
                        if let appNameRegex = ifTable["app-name-regex-substring"]?.string {
                            floatingRules.addAppNamePattern(appNameRegex)
                            log("Floating rule: app-name-regex = \(appNameRegex)")
                        }
                        if let windowTitleRegex = ifTable["window-title-regex-substring"]?.string {
                            floatingRules.addWindowTitlePattern(windowTitleRegex)
                            log("Floating rule: window-title-regex = \(windowTitleRegex)")
                        }
                    }
                }
            }
            
            log("Loaded floating rules: \(floatingRules.appIds.count) app IDs")
        } catch {
            log("Failed to load aerospace config: \(error), using default gaps")
        }
    }
    
    var configDirectory: URL {
        if let xdgConfig = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] {
            return URL(fileURLWithPath: xdgConfig).appendingPathComponent("aerospace-focus")
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
                config.barHeight = max(1, min(100, CGFloat(barHeight)))
            }
            if let barColor = toml["bar_color"]?.string {
                config.barColor = barColor
            }
            if let barOpacity = toml["bar_opacity"]?.double {
                config.barOpacity = max(0.0, min(1.0, barOpacity))
            }
            if let position = toml["position"]?.string,
               let pos = Config.BarPosition(rawValue: position) {
                config.position = pos
            }
            if let offset = toml["offset"]?.double {
                config.offset = max(0, min(50, CGFloat(offset)))
            }
            if let includeApps = toml["include_apps"]?.array {
                config.includeApps = includeApps.compactMap { $0.string }
            }
            if let excludeApps = toml["exclude_apps"]?.array {
                config.excludeApps = excludeApps.compactMap { $0.string }
            }
            if let autoExcludeFloating = toml["auto_exclude_floating"]?.bool {
                config.autoExcludeFloating = autoExcludeFloating
            }
            if let animate = toml["animate"]?.bool {
                config.animate = animate
            }
            if let animDuration = toml["animation_duration"]?.double {
                config.animationDuration = max(0.01, min(2.0, animDuration))
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
        loadAerospaceConfig()
        loadConfig()
    }
    
    func ensureConfigDirectory() {
        let dir = configDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}

/// Simple logging to stderr
private let logDateFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    return f
}()

func log(_ message: String) {
    let timestamp = logDateFormatter.string(from: Date())
    fputs("[\(timestamp)] \(message)\n", stderr)
}
