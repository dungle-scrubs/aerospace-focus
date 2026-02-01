import ArgumentParser
import Foundation

/// Main CLI entry point
struct AerospaceFocus: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "aerospace-focus",
        abstract: "A focus indicator bar for Aerospace window manager",
        version: "0.1.0",
        subcommands: [
            Daemon.self,
            Update.self,
            Hide.self,
            Show.self,
            Reload.self,
            SetCommand.self,
            Quit.self,
            Status.self,
        ],
        defaultSubcommand: Update.self
    )
}

/// Start the daemon process
struct Daemon: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Start the focus bar daemon"
    )
    
    func run() throws {
        // Check if already running
        if FocusClient.isDaemonRunning() {
            print("Daemon is already running")
            throw ExitCode.failure
        }
        
        // Start daemon (blocks)
        runDaemon()
    }
}

/// Update the bar position (notify daemon)
struct Update: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Update bar position for focused window"
    )
    
    func run() throws {
        if FocusClient.send("update") {
            // Success, daemon handled it
        } else {
            // Daemon not running, start it in background and then update
            print("Daemon not running. Start it with: aerospace-focus daemon")
            throw ExitCode.failure
        }
    }
}

/// Hide the bar
struct Hide: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Hide the focus bar"
    )
    
    func run() throws {
        if !FocusClient.send("hide") {
            print("Daemon not running")
            throw ExitCode.failure
        }
    }
}

/// Show the bar
struct Show: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Show the focus bar"
    )
    
    func run() throws {
        if !FocusClient.send("show") {
            print("Daemon not running")
            throw ExitCode.failure
        }
    }
}

/// Reload configuration
struct Reload: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Reload configuration from file"
    )
    
    func run() throws {
        if !FocusClient.send("reload") {
            print("Daemon not running")
            throw ExitCode.failure
        }
        print("Configuration reloaded")
    }
}

/// Set command with subcommands
struct SetCommand: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Set bar properties",
        subcommands: [SetColor.self]
    )
}

/// Set bar color
struct SetColor: ParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "color",
        abstract: "Set bar color (hex format, e.g., #ff0000)"
    )
    
    @Argument(help: "Color in hex format (e.g., #00ff00)")
    var color: String
    
    func run() throws {
        if !FocusClient.send("color \(color)") {
            print("Daemon not running")
            throw ExitCode.failure
        }
    }
}

/// Stop the daemon
struct Quit: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Stop the daemon"
    )
    
    func run() throws {
        if !FocusClient.send("quit") {
            print("Daemon not running")
            throw ExitCode.failure
        }
        print("Daemon stopped")
    }
}

/// Check daemon status
struct Status: ParsableCommand {
    static var configuration = CommandConfiguration(
        abstract: "Check if daemon is running"
    )
    
    func run() throws {
        if FocusClient.isDaemonRunning() {
            print("Daemon is running")
            print("Socket: \(FocusServer.socketPath)")
        } else {
            print("Daemon is not running")
        }
    }
}
