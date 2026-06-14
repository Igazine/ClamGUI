//
//  QueueManager.swift
//  ClamGUI
//
//  Manages the scan queue and communicates with clamd daemon.
//  Supports prioritized commands: SCAN, RELOAD, STATS, VERSION, SHUTDOWN.
//

import Foundation
import Darwin

/// Manages the command queue and communicates with clamd daemon
class QueueManager: @unchecked Sendable {
    static let shared = QueueManager()
    
    private var queue: [QueueCommand] = []
    private let queueLock = NSLock()
    
    private var socketHandle: Int32 = -1
    private var isConnected: Bool = false
    private var isProcessing: Bool = false
    private var shouldContinueProcessing: Bool = true
    private var isSuspended: Bool = false
    private var isQueueStarted: Bool = false
    
    // Currently scanning file (for UI display)
    @MainActor var currentScanningFile: String? = nil
    @MainActor var scanStatus: ScanQueueStatus {
        return isSuspended ? .suspended : (isProcessing ? .scanning : .idle)
    }
    
    // Socket path
    private let socketPath: String = {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI/clamd.sock")
            .path
    }()
    
    private init() {
        // Queue is paused by default. 
        // Call start() after Daemon connection is verified.
    }
    
    /// Start the queue processing loop
    /// Called only after Daemon is confirmed running
    func start() {
        guard !isQueueStarted else {
            print("⚠️ QueueManager.start() called but already started")
            return
        }
        
        isQueueStarted = true
        if !shouldContinueProcessing {
            shouldContinueProcessing = true
        }
        
        Task {
            await startProcessingLoop()
        }
        print("▶️ CommandQueue started")
    }
    
    // MARK: - Public API: Backward Compatibility Wrappers

    /// Async wrapper for scanFile (used by ClamAVManager.scanFile)
    func scanFile(at path: String) async -> ClamAVManager.ScanResult {
        return await withCheckedContinuation { continuation in
            scanFile(path) { result in
                continuation.resume(returning: result)
            }
        }
    }

    /// Void wrapper for background scan (used by Watchdog)
    func scanFileBackground(_ filePath: String) {
        scanFileBackground(filePath) { _ in }
    }

    // MARK: - Public API: Manual Scanning
    
    /// Add a file to the scan queue with high priority
    func scanFile(_ filePath: String, completion: @escaping (ClamAVManager.ScanResult) -> Void) {
        let command = ScanCommand(priority: .normal, filePath: filePath, completion: completion)
        enqueue(command)
    }
    
    /// Add a file to the scan queue with background priority
    func scanFileBackground(_ filePath: String, completion: @escaping (ClamAVManager.ScanResult?) -> Void) {
        // We wrap the scan result in an optional to match existing signatures, 
        // but internally we treat it as a definite result.
        let cmd = ScanCommand(priority: .low, filePath: filePath) { result in
            completion(result)
        }
        enqueue(cmd)
    }
    
    // MARK: - Public API: Control Commands
    
    /// Add a control command (Reload, Version, Stats, etc.)
    func enqueueControlCommand(type: ControlCommand.CommandType, priority: CommandPriority = .high, completion: ((String) -> Void)? = nil) {
        let command = ControlCommand(priority: priority, type: type, completion: completion)
        enqueue(command)
    }
    
    /// Add a command to the queue
    func enqueue(_ command: QueueCommand) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Insert based on priority (Higher priority = lower index)
        var insertIndex = queue.count
        for (index, existingCommand) in queue.enumerated() {
            if command.priority < existingCommand.priority {
                insertIndex = index
                break
            }
        }
        
        queue.insert(command, at: insertIndex)
        print("📥 Enqueued: \(command.description) (priority: \(command.priority))")
    }
    
    /// Remove a command by ID (if possible) or path
    func removeFile(_ path: String) {
        queueLock.lock()
        defer { queueLock.unlock() }
        
        // Remove ScanCommands matching the path
        queue.removeAll { cmd in
            if let scan = cmd as? ScanCommand {
                return scan.filePath == path
            }
            return false
        }
        print("🗑️ Removed queued scans for: \(path)")
    }
    
    /// Stop processing and send shutdown (if requested)
    func stopProcessing() {
        shouldContinueProcessing = false
        disconnect()
    }
    
    func suspendQueue() {
        isSuspended = true
        print("⏸️ Queue suspended")
    }
    
    func resumeQueue() {
        isSuspended = false
        print("▶️ Queue resumed")
    }
    
    // MARK: - Processing Loop
    
    /// Main processing loop - runs continuously
    private func startProcessingLoop() async {
        while shouldContinueProcessing {
            if isSuspended {
                try? await Task.sleep(nanoseconds: 100_000_000)
                continue
            }
            
            if !isProcessing {
                if let command = dequeue() {
                    isProcessing = true
                    await executeCommand(command)
                    isProcessing = false
                } else {
                    // No commands, wait a bit
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
    
    /// Get next command from queue
    private func dequeue() -> QueueCommand? {
        queueLock.lock()
        defer { queueLock.unlock() }
        return queue.isEmpty ? nil : queue.removeFirst()
    }
    
    /// Execute a command
    private func executeCommand(_ command: QueueCommand) async {
        // Update UI if it's a scan
        if let scanCmd = command as? ScanCommand {
            await MainActor.run {
                currentScanningFile = scanCmd.filePath
            }
            print("🔍 Scanning: \(scanCmd.filePath) (priority: \(scanCmd.priority))")
        } else {
            print("⚙️ Executing: \(command.description)")
        }

        // Ensure connection
        if !isConnected {
            if !connectToDaemon() {
                print("❌ Cannot connect to daemon")
                // Notify failure
                if let scanCmd = command as? ScanCommand {
                    let errorResult = ClamAVManager.ScanResult(filePath: scanCmd.filePath, status: .error, threatName: "Cannot connect to daemon", timestamp: Date())
                    scanCmd.completion(errorResult)
                }
                return
            }
        }

        // Execute based on type
        switch command {
        case let scanCmd as ScanCommand:
            await executeScan(scanCmd)
            
        case let ctrlCmd as ControlCommand:
            await executeControl(ctrlCmd)
            
        default:
            break
        }
        
        // Clear UI if it was a scan
        if command is ScanCommand {
            await MainActor.run {
                currentScanningFile = nil
            }
            print("✅ Completed: \(command.description)")
        }
    }
    
    // MARK: - Execution Logic
    
    /// Execute a SCAN command
    private func executeScan(_ cmd: ScanCommand) async {
        // Send command
        let commandStr = "nSCAN \(cmd.filePath)"
        let response = await sendCommand(commandStr)
        
        // Parse response
        let result = parseSCANResponse(response, filePath: cmd.filePath)
        
        // Call completion
        cmd.completion(result)
    }
    
    /// Execute a Control command (VERSION, STATS, etc)
    private func executeControl(_ cmd: ControlCommand) async {
        var commandStr = ""
        var expectClose = false
        
        switch cmd.type {
        case .shutdown:
            commandStr = "nSHUTDOWN"
            expectClose = true
        case .reload:
            commandStr = "nRELOAD"
        case .stats:
            commandStr = "nSTATS"
        case .version:
            commandStr = "nVERSION"
        case .ping:
            commandStr = "nPING"
        }
        
        // If SHUTDOWN, the daemon closes the connection. 
        // We send and don't expect a readable response (read will return 0).
        if expectClose {
            _ = sendCommandAsync(commandStr)
            disconnect()
            print("📤 Sent SHUTDOWN, closing connection")
            shouldContinueProcessing = false
            return
        }
        
        let response = await sendCommand(commandStr)
        cmd.completion?(response)
    }

    // MARK: - Socket Communication

    /// Connect to clamd daemon
    private func connectToDaemon() -> Bool {
        disconnect() // Ensure clean state

        socketHandle = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        if socketHandle == -1 { return false }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        _ = socketPath.withCString { ptr in
            memcpy(&addr.sun_path, ptr, socketPath.count)
        }

        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result == 0 {
            isConnected = true
            print("✅ Connected to clamd")
            return true
        } else {
            socketHandle = -1
            return false
        }
    }
    
    /// Disconnect
    private func disconnect() {
        if socketHandle != -1 {
            close(socketHandle)
            socketHandle = -1
        }
        isConnected = false
    }
    
    /// Send command and wait for response (Sync)
    private func sendCommand(_ command: String) async -> String {
        // Send
        let data = (command + "\n").data(using: .utf8)!
        let sent = data.withUnsafeBytes {
            Darwin.write(socketHandle, $0.baseAddress, data.count)
        }
        guard sent > 0 else { return "ERROR: Write failed" }
        
        // Receive
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        
        while true {
            let read = Darwin.read(socketHandle, &buffer, buffer.count)
            if read > 0 {
                response.append(buffer, count: read)
                // Check for newline (end of response)
                if buffer[read-1] == 0x0A {
                    break
                }
            } else {
                // Connection closed or error
                break
            }
        }
        
        return String(data: response, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
    
    /// Send command without waiting (for shutdown)
    private func sendCommandAsync(_ command: String) {
        let data = (command + "\n").data(using: .utf8)!
        _ = data.withUnsafeBytes {
            Darwin.write(socketHandle, $0.baseAddress, data.count)
        }
    }
    
    // MARK: - Parsing
    
    private func parseSCANResponse(_ response: String, filePath: String) -> ClamAVManager.ScanResult {
        if response.isEmpty { return ClamAVManager.ScanResult(filePath: filePath, status: .error, threatName: "Empty response", timestamp: Date()) }
        if response.hasSuffix(": OK") || response == "OK" {
            return ClamAVManager.ScanResult(filePath: filePath, status: .clean, threatName: nil, timestamp: Date())
        }
        if response.contains(" FOUND") {
            let name = response.replacingOccurrences(of: " FOUND", with: "").split(separator: ": ").last?.trimmingCharacters(in: .whitespaces) ?? "Unknown"
            return ClamAVManager.ScanResult(filePath: filePath, status: .infected, threatName: name, timestamp: Date())
        }
        return ClamAVManager.ScanResult(filePath: filePath, status: .error, threatName: response, timestamp: Date())
    }
}
