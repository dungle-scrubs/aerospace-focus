import Foundation

/// Unix socket server for IPC
class FocusServer {
    static let socketPath = "/tmp/aerospace-focus.sock"
    
    var onUpdate: (() -> Void)?
    var onHide: (() -> Void)?
    var onShow: (() -> Void)?
    var onReload: (() -> Void)?
    var onSetColor: ((String) -> Void)?
    var onQuit: (() -> Void)?
    
    private var serverSocket: Int32 = -1
    private var isRunning = false
    
    func start() {
        // Remove existing socket
        unlink(FocusServer.socketPath)
        
        // Create socket
        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            log("Failed to create socket: \(errno)")
            return
        }
        
        // Bind to path
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = FocusServer.socketPath.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }
        
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult == 0 else {
            log("Failed to bind socket: \(errno)")
            close(serverSocket)
            return
        }
        
        // Listen
        guard listen(serverSocket, 5) == 0 else {
            log("Failed to listen: \(errno)")
            close(serverSocket)
            return
        }
        
        isRunning = true
        log("Server listening on \(FocusServer.socketPath)")
        
        // Accept connections in background
        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop()
        }
    }
    
    private func acceptLoop() {
        while isRunning {
            let clientSocket = accept(serverSocket, nil, nil)
            guard clientSocket >= 0 else {
                if isRunning {
                    log("Accept failed: \(errno)")
                }
                continue
            }
            
            // Read command
            var buffer = [CChar](repeating: 0, count: 256)
            let bytesRead = read(clientSocket, &buffer, buffer.count - 1)
            
            if bytesRead > 0 {
                let command = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
                handleCommand(command)
            }
            
            close(clientSocket)
        }
    }
    
    private func handleCommand(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1)
        let cmd = String(parts.first ?? "")
        let arg = parts.count > 1 ? String(parts[1]) : nil
        
        DispatchQueue.main.async { [weak self] in
            switch cmd {
            case "update":
                self?.onUpdate?()
            case "hide":
                self?.onHide?()
            case "show":
                self?.onShow?()
            case "reload":
                self?.onReload?()
            case "color":
                if let color = arg {
                    self?.onSetColor?(color)
                }
            case "quit":
                self?.onQuit?()
            default:
                log("Unknown command: \(command)")
            }
        }
    }
    
    func stop() {
        isRunning = false
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        unlink(FocusServer.socketPath)
    }
}

/// Client to communicate with the daemon
class FocusClient {
    static func send(_ command: String) -> Bool {
        let clientSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard clientSocket >= 0 else {
            return false
        }
        
        defer { close(clientSocket) }
        
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            _ = FocusServer.socketPath.withCString { cstr in
                strcpy(ptr, cstr)
            }
        }
        
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                connect(clientSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard connectResult == 0 else {
            return false
        }
        
        // Send command
        _ = command.withCString { cstr in
            write(clientSocket, cstr, strlen(cstr))
        }
        
        return true
    }
    
    static func isDaemonRunning() -> Bool {
        return FileManager.default.fileExists(atPath: FocusServer.socketPath)
    }
}
