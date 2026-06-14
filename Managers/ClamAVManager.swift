//
//  ClamAVManager.swift
//  ClamGUI
//
//  Manages ClamGUI's active ClamAV scanner runtime.
//

import Foundation
import AppKit

/// Manages scanner availability and UI-facing scan state.
@MainActor
class ClamAVManager: ObservableObject {
    static let shared = ClamAVManager()

    // MARK: - Published Properties

    @Published var isClamAVInstalled = false
    @Published var isClamdRunning = false
    @Published var isScannerReady = false
    @Published var isScanning = false
    @Published var lastScanResult: ScanResult?
    @Published var virusDefinitionsVersion: String = "Unknown"
    @Published var virusDefinitionsOutdated = false
    @Published var isStartingClamd = false
    @Published var clamdStartError: String? = nil
    @Published var activeScannerName: String = "Unavailable"
    @Published var scannerStatusMessage: String = "Scanner not initialized"
    @Published var isUpdatingVirusDefinitions = false
    @Published var virusDefinitionsUpdateMessage: String?

    /// ClamGUI's custom socket path (exclusive to ClamGUI)
    /// This socket is created by our custom clamd.conf
    static var clamGUISocketPath: String {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI/clamd.sock")
            .path
    }

    /// Custom clamd.conf path for ClamGUI
    static var clamGUIConfigPath: String {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path
        return URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI/clamd.conf")
            .path
    }

    // MARK: - Scan Result Model

    struct ScanResult: Identifiable {
        let id = UUID()
        let filePath: String
        let status: ScanStatus
        let threatName: String?
        let timestamp: Date

        enum ScanStatus {
            case clean
            case infected
            case error
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - ClamAV Installation Check

    func checkClamAVInstallation() async {
        let clamdSocketExists = fileExists(at: Self.clamGUISocketPath)
        let status = await ScanEngineManager.shared.preparePreferredScanner(clamdSocketExists: clamdSocketExists)

        if status.isReady {
            isClamAVInstalled = true
            isScannerReady = true
            isClamdRunning = status.backend == .clamd
            activeScannerName = status.backend?.rawValue ?? "Unknown"
            scannerStatusMessage = status.message
            return
        }

        // Check for clamd binary at common installation paths
        let clamdPaths = [
            "/opt/homebrew/sbin/clamd",      // Homebrew ARM64 (Apple Silicon)
            "/usr/local/sbin/clamd",         // Homebrew x86_64 (Intel)
            "/opt/homebrew/bin/clamd",
            "/usr/local/bin/clamd",
            "/usr/sbin/clamd",
            "/usr/bin/clamd"
        ]

        for path in clamdPaths {
            if fileExists(at: path) {
                isClamAVInstalled = true
                isClamdRunning = false
                isScannerReady = false
                activeScannerName = "Unavailable"
                scannerStatusMessage = status.message
                print("ClamAV daemon binary found at: \(path), but ClamGUI daemon not running")
                return
            }
        }

        // Also check if clamscan command exists as fallback indicator
        if commandExists("clamscan") {
            isClamAVInstalled = true
            isClamdRunning = false
            isScannerReady = false
            activeScannerName = "Unavailable"
            scannerStatusMessage = status.message
            print("ClamAV installed (clamscan found) but ClamGUI daemon not running")
            return
        }

        isClamAVInstalled = false
        isClamdRunning = false
        isScannerReady = false
        activeScannerName = "Unavailable"
        scannerStatusMessage = status.message
        print("ClamAV not detected on system")
    }

    func openClamAVInstallationPage() {
        if let url = URL(string: "https://docs.clamav.net/manual/Installing.html") {
            NSWorkspace.shared.open(url)
        }
    }

    func openClamAVDaemonInstructions() {
        if let url = URL(string: "https://docs.clamav.net/manual/Installing.html#_on_macos") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Socket Connection
    // Note: Socket connection is now handled by QueueManager

    /// Close the active scanner backend.
    func closeSocketConnection() {
        Task {
            await ScanEngineManager.shared.shutdown()
        }
    }

    /// Shut down the active scanner runtime without probing or starting fallbacks.
    func shutdownScannerRuntime() async {
        if clamdProcess?.isRunning == true {
            await stopClamd()
            return
        }

        await ScanEngineManager.shared.shutdown()
        isScannerReady = false
        isClamdRunning = false
        activeScannerName = "Unavailable"
        scannerStatusMessage = "Scanner shut down"
    }

    // MARK: - File Scanning

    /// Scan a single file using the SCAN command
    /// For manual scans - waits for result and returns it
    func scanFile(at path: String) async -> ScanResult {
        isScanning = true
        defer {
            isScanning = false
        }

        let result = await ScanEngineManager.shared.scanFile(at: path)

        lastScanResult = result

        return result
    }

    /// Remove a file from the scan queue
    func removeFileFromQueue(at path: String) {
        // TODO: Implement remove in new QueueManager if needed
    }
    
    /// Get queue statistics
    func getQueueStats() async -> (pending: Int, scanning: Int, total: Int) {
        return await ScanQueue.shared.getStats()
    }
    
    /// Get all queue items
    func getQueueItems() async -> [ScanQueueItem] {
        return await ScanQueue.shared.getAllItems()
    }

    /// Parse INSTREAM scan response
    /// Format: "stream: OK" or "stream: VirusName FOUND" or "stream: ERROR: message"
    private func parseINSTREAMResponse(_ response: String, filePath: String) -> ScanResult {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        print("ClamAV response (trimmed): '\(trimmed)'")

        // Check for OK (clean file) - handle various formats
        if trimmed == "stream: OK" || trimmed == "OK" || trimmed.hasSuffix(" OK") {
            return ScanResult(
                filePath: filePath,
                status: .clean,
                threatName: nil,
                timestamp: Date()
            )
        }
        
        // Check for FOUND (threat detected)
        if trimmed.contains(" FOUND") {
            // Extract virus name - format is "stream: VirusName FOUND" or just "VirusName FOUND"
            var virusName = trimmed
            virusName = virusName.replacingOccurrences(of: "stream: ", with: "")
            virusName = virusName.replacingOccurrences(of: " FOUND", with: "")
            return ScanResult(
                filePath: filePath,
                status: .infected,
                threatName: virusName.trimmingCharacters(in: .whitespaces),
                timestamp: Date()
            )
        }
        
        // Check for ERROR
        if trimmed.hasPrefix("stream: ERROR:") || trimmed.hasPrefix("ERROR:") {
            let errorMessage = trimmed
                .replacingOccurrences(of: "stream: ", with: "")
                .replacingOccurrences(of: "ERROR: ", with: "")
                .trimmingCharacters(in: .whitespaces)
            return ScanResult(
                filePath: filePath,
                status: .error,
                threatName: errorMessage,
                timestamp: Date()
            )
        }

        // Unknown response - but if it contains "OK" anywhere, treat as clean
        if trimmed.contains("OK") {
            print("Treating unknown response with OK as clean: \(trimmed)")
            return ScanResult(
                filePath: filePath,
                status: .clean,
                threatName: nil,
                timestamp: Date()
            )
        }
        
        // Unknown response
        return ScanResult(
            filePath: filePath,
            status: .error,
            threatName: "Unknown response: \(trimmed)",
            timestamp: Date()
        )
    }

    // MARK: - Virus Definitions

    func checkVirusDefinitions() async {
        let status = await SignatureDatabaseManager.shared.status()
        virusDefinitionsVersion = status.versionDescription
        virusDefinitionsOutdated = status.isOutdated
    }

    func updateVirusDefinitions() {
        guard !isUpdatingVirusDefinitions else {
            return
        }

        isUpdatingVirusDefinitions = true
        virusDefinitionsUpdateMessage = nil

        Task {
            do {
                let result = try await SignatureDatabaseManager.shared.updateDefinitions()
                try? await ScanEngineManager.shared.reloadSignatures()
                await checkVirusDefinitions()
                await checkClamAVInstallation()
                virusDefinitionsUpdateMessage = result.output.isEmpty ? "Virus definitions updated." : result.output
            } catch {
                virusDefinitionsUpdateMessage = error.localizedDescription
                await checkVirusDefinitions()
            }

            isUpdatingVirusDefinitions = false
        }
    }

    // MARK: - Other ClamAV Commands
    // Note: These commands require direct socket communication which is now handled by QueueManager
    // They are kept for API compatibility but return stub values

    func getPingResponse() async -> String {
        return "PONG"
    }

    func getStats() async -> String {
        return "Stats unavailable"
    }

    func reloadDatabase() async -> String {
        do {
            try await ScanEngineManager.shared.reloadSignatures()
            return "Signature database reloaded"
        } catch {
            return error.localizedDescription
        }
    }

    func shutdown() async -> String {
        await ScanEngineManager.shared.shutdown()
        return "Scanner shut down"
    }

    // MARK: - Daemon Management (Direct Process, No launchd)

    /// Get the actual home directory path (not sandboxed)
    private func getActualHomeDirectory() -> String {
        if let home = ProcessInfo.processInfo.environment["HOME"] {
            return home
        }
        return FileManager.default.homeDirectoryForCurrentUser.path
    }

    /// Ensure ClamGUI support directory exists
    private func ensureSupportDirectory() throws {
        let homeDir = getActualHomeDirectory()
        let supportDir = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI")
        
        // Create directory with proper permissions
        try FileManager.default.createDirectory(
            at: supportDir,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]  // rwx------ (owner only)
        )
        print("ClamGUI support directory: \(supportDir.path)")
    }

    /// Direct process reference for clamd
    private var clamdProcess: Process?

    /// Install ClamGUI's custom clamd configuration
    func installClamGUIConfig() async throws {
        try ensureSupportDirectory()

        let homeDir = getActualHomeDirectory()
        let logPath = URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI/clamd.log")
            .path
        let socketPath = Self.clamGUISocketPath

        // Remove stale socket file if it exists
        if FileManager.default.fileExists(atPath: socketPath) {
            try? FileManager.default.removeItem(atPath: socketPath)
            print("Removed stale socket file: \(socketPath)")
        }

        // Minimal config with only essential, universally supported options
        let configTemplate = """
        # ClamGUI Custom ClamAV Daemon Configuration
        LogFile \(logPath)
        LogTime yes
        LocalSocket \(socketPath)
        LocalSocketMode 600
        MaxConnectionQueueLength 30
        MaxThreads 10
        ReadTimeout 600
        ScanPE yes
        ScanELF yes
        ScanOLE2 yes
        ScanMail yes
        ScanPDF yes
        ScanHTML yes
        ScanArchive yes
        MaxFileSize 2048M
        MaxScanSize 4096M
        MaxFiles 15000
        MaxRecursion 20
        """

        try configTemplate.write(toFile: Self.clamGUIConfigPath, atomically: true, encoding: .utf8)
        print("ClamGUI config installed at: \(Self.clamGUIConfigPath)")
    }

    /// Find clamd binary location
    private func findClamdPath() -> String? {
        let clamdPaths = [
            "/opt/homebrew/sbin/clamd",
            "/usr/local/sbin/clamd",
            "/opt/homebrew/bin/clamd",
            "/usr/local/bin/clamd",
            "/usr/sbin/clamd",
            "/usr/bin/clamd"
        ]

        for path in clamdPaths {
            if fileExists(at: path) {
                return path
            }
        }
        return nil
    }

    /// Start ClamGUI's clamd daemon directly (no launchd)
    func startClamd() async {
        await startClamdWithSudo(false)
    }

    /// Start ClamGUI's clamd daemon with optional sudo
    func startClamdWithSudo(_ useSudo: Bool) async {
        // Check if already running or starting
        if clamdProcess != nil && clamdProcess?.isRunning == true {
            print("ClamGUI clamd daemon is already running")
            await checkClamAVInstallation()
            return
        }
        
        if isStartingClamd {
            print("ClamGUI clamd daemon is already starting")
            return
        }

        isStartingClamd = true
        clamdStartError = nil

        do {
            // Install config
            try await installClamGUIConfig()

            // Find clamd binary
            guard let clamdPath = findClamdPath() else {
                clamdStartError = "clamd binary not found. Please install ClamAV via Homebrew."
                isStartingClamd = false
                print("ERROR: clamd binary not found")
                return
            }

            // Create process
            let process = Process()
            process.executableURL = URL(fileURLWithPath: clamdPath)
            process.arguments = ["--config-file=\(Self.clamGUIConfigPath)", "--foreground"]

            // Capture output for debugging
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            // Read output
            pipe.fileHandleForReading.readabilityHandler = { fileHandle in
                let data = fileHandle.availableData
                if let output = String(data: data, encoding: .utf8), !output.isEmpty {
                    print("clamd: \(output.trimmingCharacters(in: .newlines))")
                }
            }

            try process.run()
            clamdProcess = process

            print("ClamGUI clamd daemon started (PID: \(process.processIdentifier))")

            // Wait for socket to be created with 30 second timeout
            let socketPath = Self.clamGUISocketPath
            let maxAttempts = 60  // 30 seconds / 0.5 second intervals
            var attempts = 0
            
            while attempts < maxAttempts {
                try await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
                attempts += 1
                
                // Check if socket exists
                if FileManager.default.fileExists(atPath: socketPath) {
                    print("ClamAV socket created after \(Double(attempts) * 0.5) seconds")
                    break
                }
                
                // Check if process is still running
                if !process.isRunning {
                    clamdStartError = "clamd process exited unexpectedly"
                    isStartingClamd = false
                    clamdProcess = nil
                    return
                }
            }
            
            // Check if we timed out
            if attempts >= maxAttempts {
                clamdStartError = "Timeout: clamd did not start within 30 seconds"
                isStartingClamd = false
                print("ERROR: Timeout waiting for clamd socket")
                // Kill the process
                process.terminate()
                clamdProcess = nil
                return
            }

            // Verify it started successfully
            try? await ScanEngineManager.shared.useLegacyClamdScanner()
            isClamAVInstalled = true
            isScannerReady = true
            isClamdRunning = true
            activeScannerName = ScannerBackend.clamd.rawValue
            scannerStatusMessage = "Legacy clamd scanner ready"
            
            isStartingClamd = false

        } catch {
            clamdStartError = "Failed to start clamd: \(error.localizedDescription)"
            isStartingClamd = false
            print("Failed to start clamd: \(error.localizedDescription)")
            clamdProcess = nil
        }
    }

    /// Stop ClamGUI's clamd daemon
    func stopClamd() async {
        guard let process = clamdProcess, process.isRunning else {
            print("ClamGUI clamd daemon is not running")
            // Even if not running, we should check status and maybe stop queue
            isClamdRunning = false
            QueueManager.shared.suspendQueue()
            await checkClamAVInstallation()
            return
        }

        // Gracefully terminate
        process.terminate()
        
        // Suspend queue immediately as daemon is going down
        QueueManager.shared.suspendQueue()
        await ScanEngineManager.shared.shutdown()

        // Wait up to 5 seconds for clean exit
        var waitCount = 0
        while process.isRunning && waitCount < 50 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waitCount += 1
        }

        // Force kill if still running
        if process.isRunning {
            process.interrupt()
            try? await Task.sleep(nanoseconds: 500_000_000)

            if process.isRunning {
                process.terminate()
            }
        }

        clamdProcess = nil
        print("ClamGUI clamd daemon stopped")

        // Clean up socket
        if FileManager.default.fileExists(atPath: Self.clamGUISocketPath) {
            try? FileManager.default.removeItem(atPath: Self.clamGUISocketPath)
        }

        // Re-check status
        await checkClamAVInstallation()
    }

    /// Restart ClamGUI's clamd daemon
    func restartClamd() async {
        await stopClamd()
        try? await Task.sleep(nanoseconds: 500_000_000)
        await startClamd()
    }

    // MARK: - Helper Methods

    private func fileExists(at path: String) -> Bool {
        return FileManager.default.fileExists(atPath: path)
    }

    private func commandExists(_ name: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = [name]

        let pipe = Pipe()
        process.standardOutput = pipe

        try? process.run()
        process.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return !output.isEmpty
    }
}
