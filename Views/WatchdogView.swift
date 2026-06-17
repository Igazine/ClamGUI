//
//  WatchdogView.swift
//  ClamGUI
//
//  UI for directory watching and automatic scanning
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct WatchdogView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var clamAVManager: ClamAVManager
    let onThreatCountChanged: ((Int) -> Void)?
    @StateObject private var directoryWatcher = DirectoryWatcher()
    @StateObject private var threatHandler = ThreatActionHandler.shared
    @State private var isWatching = false
    @State private var filesScanned: Int = 0
    @State private var filesSkipped: Int = 0
    @State private var filesChecked: Int = 0
    @State private var startupFilesScanned: Int = 0
    @State private var startupThreatsFound: Int = 0
    @State private var startupSkippedTooLarge: Int = 0
    @State private var startupSkippedPermission: Int = 0
    @State private var threatsCount: Int = 0
    @State private var recordCount: Int = 0
    @State private var showingFoundThreats = false
    @State private var scanQueue: [WatchdogScanRequest] = []
    @State private var queuedScanPaths: Set<String> = []
    @State private var isProcessingScanQueue = false
    @State private var isStartupScanActive = false
    @State private var startupSummary: String = ""
    @State private var diagnosticEvents: [WatchdogDiagnosticEvent] = []
    @State private var showingDiagnostics = false
    
    // Auto-start watching once a scanner backend is ready and a directory is set.
    @State private var shouldAutoStart = false

    init(onThreatCountChanged: ((Int) -> Void)? = nil) {
        self.onThreatCountChanged = onThreatCountChanged
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text("Watchdog")
                    .font(.title)
                    .fontWeight(.bold)

                Spacer()

                // Found Threats button
                Button(action: { showingFoundThreats = true }) {
                    HStack(spacing: 4) {
                        Label("Found Threats", systemImage: "exclamationmark.shield.fill")
                        
                        if threatsCount > 0 {
                            Text("\(threatsCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .clipShape(Circle())
                        }
                    }
                }
                .help("View detected threats")

                Button(action: { showingDiagnostics = true }) {
                    Label("Diagnostics", systemImage: "list.bullet.rectangle")
                }
                .help("View WatchDog diagnostic events")

                // Watch toggle
                Toggle("Active", isOn: $isWatching)
                    .toggleStyle(.switch)
                    .disabled(settingsManager.watchDirectory.isEmpty || !clamAVManager.isScannerReady)
            }
            // Directory selection
            VStack(alignment: .leading, spacing: 10) {
                Text("Watched Directory")
                    .font(.headline)

                HStack(spacing: 10) {
                    TextField("Select a directory to watch", text: $settingsManager.watchDirectory)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isWatching)

                    Button("Browse...") {
                        selectDirectory()
                    }
                    .disabled(isWatching)
                }

                if !settingsManager.watchDirectory.isEmpty {
                    Label(settingsManager.watchDirectory, systemImage: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Status
            HStack {
                StatusIndicator(isActive: isWatching)

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 10) {
                        Text("Scanned: \(filesScanned)")
                            .foregroundColor(.blue)
                        Text("•")
                        Text("Checked: \(filesChecked)")
                            .foregroundColor(.secondary)
                        Text("•")
                        Text("Skipped: \(filesSkipped)")
                            .foregroundColor(.green)
                        Text("•")
                        Text("Threats: \(threatsCount)")
                            .foregroundColor(threatsCount > 0 ? .red : .secondary)
                    }
                    .font(.caption2)
                    .foregroundColor(.secondary)

                    Text(activityDetailText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(height: 14, alignment: .leading)
                }

                Spacer()

                if isWatching {
                    HStack(spacing: 5) {
                        Image(systemName: activityStatusIcon)
                            .foregroundColor(activityStatusColor)
                            .frame(width: 12, height: 12)

                        Text(activityStatusText)
                            .foregroundColor(activityStatusColor)
                            .frame(minWidth: 54, alignment: .leading)
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(activityStatusColor.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(isWatching ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)
        }
        .frame(maxWidth: 800)
        .padding()
        .onAppear {
            setupDirectoryWatcher()
            autoStartWatchdogIfPossible()
        }
        .onChange(of: clamAVManager.isScannerReady) { isReady in
            if isReady {
                autoStartWatchdogIfPossible()
            } else if isWatching {
                recordDiagnostic("Scanner became unavailable, stopping WatchDog", category: .state)
                isWatching = false
                directoryWatcher.stopWatching()
            }
        }
        .onChange(of: isWatching) { newValue in
            if newValue {
                setupDirectoryWatcher()
                recordDiagnostic("Starting WatchDog", category: .state, path: settingsManager.watchDirectory)
                directoryWatcher.startWatching()
            } else {
                recordDiagnostic("Stopping WatchDog", category: .state, path: settingsManager.watchDirectory)
                directoryWatcher.stopWatching()
            }
        }
        .onChange(of: settingsManager.watchDirectory) { _ in
            let shouldResume = isWatching
            if isWatching {
                isWatching = false
                directoryWatcher.stopWatching()
            }
            recordDiagnostic("Watched directory changed", category: .state, path: settingsManager.watchDirectory)
            resetWatchdogCounters()
            setupDirectoryWatcher()
            if shouldResume, !settingsManager.watchDirectory.isEmpty, clamAVManager.isScannerReady {
                isWatching = true
                directoryWatcher.startWatching()
            }
        }
        .sheet(isPresented: $showingFoundThreats) {
            FoundThreatsSheet(onThreatsChanged: updateThreatsCount)
        }
        .sheet(isPresented: $threatHandler.showingThreatModal) {
            ThreatActionModal()
        }
        .sheet(isPresented: $showingDiagnostics) {
            WatchdogDiagnosticsSheet(
                events: diagnosticEvents,
                onCopy: copyDiagnostics,
                onExport: exportDiagnostics,
                onClear: { diagnosticEvents.removeAll() }
            )
        }
    }

    // MARK: - Computed Properties

    @State private var currentScanningFile: String?

    private var statusText: String {
        if !isWatching {
            return "Watchdog inactive"
        }
        if currentScanningFile != nil {
            return "Scanning changed files..."
        }
        return isWatching ? "Watching for new files..." : "Watchdog inactive"
    }

    private var activityDetailText: String {
        guard isWatching else {
            return " "
        }

        guard let currentScanningFile else {
            return startupSummary.isEmpty ? " " : startupSummary
        }

        return "Scanning \(URL(fileURLWithPath: currentScanningFile).lastPathComponent)"
    }

    private var activityStatusText: String {
        currentScanningFile == nil ? "Idle" : "Scanning"
    }

    private var activityStatusIcon: String {
        currentScanningFile == nil ? "checkmark.circle.fill" : "magnifyingglass"
    }

    private var activityStatusColor: Color {
        currentScanningFile == nil ? .green : .blue
    }

    // MARK: - Directory Selection

    private func selectDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select directory to watch"

        panel.begin { response in
            if response == .OK {
                settingsManager.watchDirectory = panel.url?.path ?? ""
                settingsManager.saveSettings()
            }
        }
    }

    private func setupDirectoryWatcher() {
        guard !settingsManager.watchDirectory.isEmpty else {
            return
        }

        directoryWatcher.watchDirectory = settingsManager.watchDirectory
        recordDiagnostic("Configured watcher", category: .state, path: settingsManager.watchDirectory)

        // Handle new file added
        directoryWatcher.onFileAdded = { url in
            Task { @MainActor in
                recordDiagnostic("Filesystem add event", category: .filesystem, path: url.path)
                enqueueScan(at: url, reason: .added)
            }
        }

        // Handle file modified
        directoryWatcher.onFileModified = { url in
            Task { @MainActor in
                recordDiagnostic("Filesystem modify event", category: .filesystem, path: url.path)
                enqueueScan(at: url, reason: .modified)
            }
        }

        // Handle file deleted
        directoryWatcher.onFileDeleted = { url in
            Task { @MainActor in
                recordDiagnostic("Filesystem delete event", category: .filesystem, path: url.path)
                await handleDeletedFile(at: url)
            }
        }

        // Scan existing files when watcher starts
        directoryWatcher.onScanExistingFiles = { [self] in
            await MainActor.run {
                recordDiagnostic("Startup scan requested", category: .state, path: settingsManager.watchDirectory)
            }
            await scanExistingFiles()
        }

        updateThreatsCount()
    }

    private func autoStartWatchdogIfPossible() {
        guard clamAVManager.isScannerReady,
              !settingsManager.watchDirectory.isEmpty,
              !shouldAutoStart else {
            return
        }

        shouldAutoStart = true
        setupDirectoryWatcher()
        recordDiagnostic("Auto-starting WatchDog", category: .state, path: settingsManager.watchDirectory)
        isWatching = true
        directoryWatcher.startWatching()
    }

    private func resetWatchdogCounters() {
        filesScanned = 0
        filesSkipped = 0
        filesChecked = 0
        startupFilesScanned = 0
        startupThreatsFound = 0
        startupSkippedTooLarge = 0
        startupSkippedPermission = 0
        threatsCount = 0
        recordCount = 0
        currentScanningFile = nil
        scanQueue.removeAll()
        queuedScanPaths.removeAll()
        isProcessingScanQueue = false
        isStartupScanActive = false
        startupSummary = ""
        shouldAutoStart = false
    }

    /// Update threats count and record count
    private func updateThreatsCount() {
        let folderId: Int64 = 1
        Task {
            let threats = ScanResultsDatabase.shared.getInfectedFiles(folderId: folderId)
            let records = ScanResultsDatabase.shared.getRecordCount(folderId: folderId)
            await MainActor.run {
                threatsCount = threats.count
                recordCount = records
                onThreatCountChanged?(threats.count)
            }
        }
    }

    /// Scan all existing files in the watched directory
    private func scanExistingFiles() async {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: settingsManager.watchDirectory, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            recordDiagnostic("Startup scan skipped because watch directory is unavailable", category: .skipped, path: settingsManager.watchDirectory)
            return
        }

        let fileManager = FileManager.default
        print("Scanning existing files in: \(settingsManager.watchDirectory)")
        recordDiagnostic("Checking existing files", category: .state, path: settingsManager.watchDirectory)
        isStartupScanActive = true
        startupSummary = "Checking existing files..."
        startupFilesScanned = 0
        startupThreatsFound = 0
        startupSkippedTooLarge = 0
        startupSkippedPermission = 0

        // Enumerate all files in directory
        if let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: settingsManager.watchDirectory),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            let files = Array(enumerator).compactMap { $0 as? URL }
            recordDiagnostic("Enumerated \(files.count) startup item(s)", category: .state, path: settingsManager.watchDirectory)

            for fileURL in files {
                // Skip directories - only scan actual files
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                    continue
                }

                enqueueScan(at: fileURL, reason: .existing)
            }
        }

        updateThreatsCount()

        if scanQueue.isEmpty, !isProcessingScanQueue {
            finishStartupScanIfNeeded()
        }

        print("Queued existing files for Watchdog scan")
    }

    private func enqueueScan(at url: URL, reason: WatchdogScanReason) {
        guard settingsManager.autoScanOnFileAdded else {
            print("Auto-scan disabled, ignoring file: \(url.path)")
            recordDiagnostic("Auto-scan disabled", category: .skipped, path: url.path)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            recordDiagnostic("File no longer exists before queueing", category: .skipped, path: url.path)
            return
        }

        if isDirectory.boolValue {
            recordDiagnostic("Queueing directory contents", category: .queued, path: url.path)
            enqueueDirectoryContents(at: url, reason: reason)
            return
        }

        guard !settingsManager.shouldIgnoreFileForScanning(url) else {
            recordDiagnostic("Ignored by extension rules", category: .ignored, path: url.path)
            return
        }

        guard queuedScanPaths.insert(url.path).inserted else {
            recordDiagnostic("Already queued", category: .skipped, path: url.path)
            return
        }

        scanQueue.append(WatchdogScanRequest(url: url, reason: reason))
        recordDiagnostic("Queued \(reason.label) scan", category: .queued, path: url.path)
        processScanQueueIfNeeded()
    }

    private func enqueueDirectoryContents(at directoryURL: URL, reason: WatchdogScanReason) {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            recordDiagnostic("Could not enumerate directory", category: .skipped, path: directoryURL.path)
            return
        }

        var queuedCount = 0
        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                continue
            }

            queuedCount += 1
            enqueueScan(at: fileURL, reason: reason)
        }
        recordDiagnostic("Processed directory with \(queuedCount) file candidate(s)", category: .queued, path: directoryURL.path)
    }

    private func processScanQueueIfNeeded() {
        guard !isProcessingScanQueue else {
            return
        }

        isProcessingScanQueue = true

        Task { @MainActor in
            while !scanQueue.isEmpty {
                let request = scanQueue.removeFirst()
                queuedScanPaths.remove(request.url.path)
                await scanQueuedFile(request)
            }

            isProcessingScanQueue = false
            finishStartupScanIfNeeded()
        }
    }

    private func scanQueuedFile(_ request: WatchdogScanRequest) async {
        let url = request.url

        guard FileManager.default.fileExists(atPath: url.path) else {
            recordDiagnostic("Queued file disappeared before scan", category: .skipped, path: url.path)
            return
        }

        guard !settingsManager.shouldIgnoreFileForScanning(url) else {
            recordDiagnostic("Ignored by extension rules before scan", category: .ignored, path: url.path)
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            recordDiagnostic("Queued item is directory, expanding contents", category: .queued, path: url.path)
            enqueueDirectoryContents(at: url, reason: request.reason)
            return
        }

        let folderId: Int64 = 1
        if request.reason == .existing,
           let record = ScanResultsDatabase.shared.getRecord(url.path, folderId: folderId),
           record.status == .clean,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            print("Skipping unchanged existing file: \(url.path)")
            recordDiagnostic("Checked unchanged known-clean file", category: .checked, path: url.path)
            filesChecked += 1
            return
        }

        if request.reason == .added,
           let record = ScanResultsDatabase.shared.getRecord(url.path, folderId: folderId),
           record.status == .clean,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            print("Skipping unchanged clean file: \(url.path)")
            recordDiagnostic("Skipped unchanged clean file", category: .skipped, path: url.path)
            filesSkipped += 1
            return
        }

        if request.reason.requiresStabilityCheck,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            recordDiagnostic("Skipped unchanged file", category: .skipped, path: url.path)
            return
        }

        if request.reason.requiresStabilityCheck {
            guard await waitForStableFile(at: url) else {
                recordDiagnostic("File disappeared during stability check", category: .skipped, path: url.path)
                return
            }
        }

        recordDiagnostic("Started \(request.reason.label) scan", category: .scan, path: url.path)
        currentScanningFile = url.path
        let result = await clamAVManager.scanFile(at: url.path)
        currentScanningFile = nil
        switch result.status {
        case .clean:
            filesScanned += 1
            if request.reason == .existing {
                startupFilesScanned += 1
            }
        case .infected:
            filesScanned += 1
            if request.reason == .existing {
                startupFilesScanned += 1
                startupThreatsFound += 1
            }
        case .skippedTooLarge:
            filesSkipped += 1
            if request.reason == .existing {
                startupSkippedTooLarge += 1
            }
        case .skippedPermission:
            filesSkipped += 1
            if request.reason == .existing {
                startupSkippedPermission += 1
            }
        case .error:
            break
        }
        await recordWatchdogScanResult(
            result,
            showNotification: request.reason != .existing,
            showModal: request.reason != .existing
        )
    }

    private func waitForStableFile(at url: URL) async -> Bool {
        var lastState = fileState(at: url)

        for _ in 0..<4 {
            try? await Task.sleep(nanoseconds: 150_000_000)

            guard let currentState = fileState(at: url) else {
                return false
            }

            if let lastState, currentState == lastState {
                return true
            }

            lastState = currentState
        }

        return true
    }

    private func fileState(at url: URL) -> WatchdogFileState? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return nil
        }

        return WatchdogFileState(
            size: attrs[.size] as? UInt64 ?? 0,
            modificationDate: attrs[.modificationDate] as? Date ?? .distantPast
        )
    }

    private func recordWatchdogScanResult(
        _ result: ClamAVManager.ScanResult,
        showNotification: Bool,
        showModal: Bool
    ) async {
        let folderId: Int64 = 1
        print("Watchdog scan result: \(result.filePath) status=\(result.status) threat=\(result.threatName ?? "none")")
        recordDiagnostic(
            "Scan finished: \(result.status.diagnosticLabel)\(result.threatName.map { " (\($0))" } ?? "")",
            category: result.status.diagnosticCategory,
            path: result.filePath
        )

        await ScanResultsDatabase.shared.recordScan(
            path: result.filePath,
            folderId: folderId,
            status: result.databaseStatus,
            threatName: result.threatName
        )

        guard case .infected = result.status else {
            updateThreatsCount()
            return
        }

        if showNotification, SettingsManager.shared.showNotifications {
            let fileName = URL(fileURLWithPath: result.filePath).lastPathComponent
            NotificationManager.shared.showThreatNotification(
                fileName: fileName,
                threatName: result.threatName ?? "Unknown"
            )
            MenuBarManager.shared.notifyThreatFound()
        }

        updateThreatsCount()

        if showModal {
            await ThreatActionHandler.shared.handleThreatDetected(
                filePath: result.filePath,
                threatName: result.threatName ?? "Unknown"
            )
        }
    }

    private func finishStartupScanIfNeeded() {
        guard isStartupScanActive else {
            return
        }

        isStartupScanActive = false

        var parts: [String] = []
        if filesChecked > 0 {
            parts.append("checked \(filesChecked) known clean")
        }
        if startupFilesScanned > 0 {
            parts.append("scanned \(startupFilesScanned) changed")
        }
        if startupThreatsFound > 0 {
            parts.append("found \(startupThreatsFound) threat\(startupThreatsFound == 1 ? "" : "s")")
        }

        if startupSkippedTooLarge > 0 {
            parts.append("skipped \(startupSkippedTooLarge) oversized")
        }
        if startupSkippedPermission > 0 {
            parts.append("skipped \(startupSkippedPermission) unreadable")
        }

        startupSummary = parts.isEmpty ? "Startup check complete" : "Startup check: \(parts.joined(separator: ", "))"
        recordDiagnostic(startupSummary, category: .state, path: settingsManager.watchDirectory)
    }

    private func handleDeletedFile(at url: URL) async {
        print("File deleted: \(url.path)")
        updateThreatsCount()
    }

    private func recordDiagnostic(_ message: String, category: WatchdogDiagnosticCategory, path: String? = nil) {
        diagnosticEvents.append(
            WatchdogDiagnosticEvent(
                timestamp: Date(),
                category: category,
                message: message,
                path: path
            )
        )

        if diagnosticEvents.count > 500 {
            diagnosticEvents.removeFirst(diagnosticEvents.count - 500)
        }
    }

    private func diagnosticsText() -> String {
        if diagnosticEvents.isEmpty {
            return "No WatchDog diagnostic events recorded."
        }

        return diagnosticEvents.map(\.exportLine).joined(separator: "\n")
    }

    private func copyDiagnostics() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(diagnosticsText(), forType: .string)
    }

    private func exportDiagnostics() {
        let panel = NSSavePanel()
        panel.title = "Export WatchDog Diagnostics"
        panel.nameFieldStringValue = "ClamGUI-WatchDog-Diagnostics.log"
        panel.allowedContentTypes = [.plainText]
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                return
            }

            do {
                try diagnosticsText().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                recordDiagnostic("Failed to export diagnostics: \(error.localizedDescription)", category: .error)
            }
        }
    }
}

// MARK: - Subviews

struct StatusIndicator: View {
    let isActive: Bool

    var body: some View {
        Circle()
            .fill(isActive ? Color.green : Color.gray)
            .frame(width: 12, height: 12)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
    }
}

private struct WatchdogDiagnosticsSheet: View {
    let events: [WatchdogDiagnosticEvent]
    let onCopy: () -> Void
    let onExport: () -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WatchDog Diagnostics")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Text("\(events.count) event\(events.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if events.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 38))
                        .foregroundColor(.secondary)

                    Text("No diagnostic events recorded")
                        .font(.headline)
                    Text("WatchDog events will appear here after monitoring starts.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(events.reversed()) { event in
                            WatchdogDiagnosticRow(event: event)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Divider()

            HStack {
                Button("Clear", role: .destructive, action: onClear)
                    .disabled(events.isEmpty)

                Spacer()

                Button("Copy", action: onCopy)
                    .disabled(events.isEmpty)
                Button("Export...", action: onExport)
                    .disabled(events.isEmpty)
            }
        }
        .padding()
        .frame(width: 720, height: 520)
    }
}

private struct WatchdogDiagnosticRow: View {
    let event: WatchdogDiagnosticEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.category.icon)
                .foregroundColor(event.category.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(event.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(event.category.label)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(event.category.color)
                }

                Text(event.message)
                    .font(.caption)
                    .foregroundColor(.primary)

                if let path = event.path, !path.isEmpty {
                    Text(path)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(6)
    }
}

private struct WatchdogDiagnosticEvent: Identifiable {
    let id = UUID()
    let timestamp: Date
    let category: WatchdogDiagnosticCategory
    let message: String
    let path: String?

    var exportLine: String {
        let pathSuffix = path.map { " path=\"\($0)\"" } ?? ""
        return "[\(timestamp.ISO8601Format())] [\(category.rawValue)] \(message)\(pathSuffix)"
    }
}

private enum WatchdogDiagnosticCategory: String {
    case state
    case filesystem
    case queued
    case scan
    case clean
    case threat
    case checked
    case skipped
    case ignored
    case error

    var label: String {
        switch self {
        case .state: return "State"
        case .filesystem: return "Filesystem"
        case .queued: return "Queued"
        case .scan: return "Scan"
        case .clean: return "Clean"
        case .threat: return "Threat"
        case .checked: return "Checked"
        case .skipped: return "Skipped"
        case .ignored: return "Ignored"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .state: return "switch.2"
        case .filesystem: return "folder.badge.gearshape"
        case .queued: return "tray.and.arrow.down"
        case .scan: return "magnifyingglass"
        case .clean: return "checkmark.shield"
        case .threat: return "exclamationmark.triangle.fill"
        case .checked: return "checkmark.circle"
        case .skipped: return "forward.end"
        case .ignored: return "eye.slash"
        case .error: return "xmark.octagon"
        }
    }

    var color: Color {
        switch self {
        case .state, .filesystem, .queued, .scan:
            return .blue
        case .clean, .checked:
            return .green
        case .threat:
            return .red
        case .skipped, .ignored:
            return .secondary
        case .error:
            return .orange
        }
    }
}

private enum WatchdogScanReason {
    case existing
    case added
    case modified

    var label: String {
        switch self {
        case .existing:
            return "startup"
        case .added:
            return "added"
        case .modified:
            return "modified"
        }
    }

    var requiresStabilityCheck: Bool {
        switch self {
        case .existing:
            return false
        case .added, .modified:
            return true
        }
    }
}

private struct WatchdogScanRequest {
    let url: URL
    let reason: WatchdogScanReason
}

private struct WatchdogFileState: Equatable {
    let size: UInt64
    let modificationDate: Date
}

private extension ClamAVManager.ScanResult.ScanStatus {
    var diagnosticLabel: String {
        switch self {
        case .clean:
            return "clean"
        case .infected:
            return "infected"
        case .skippedTooLarge:
            return "not scanned, oversized"
        case .skippedPermission:
            return "not scanned, unreadable"
        case .error:
            return "error"
        }
    }

    var diagnosticCategory: WatchdogDiagnosticCategory {
        switch self {
        case .clean:
            return .clean
        case .infected:
            return .threat
        case .skippedTooLarge, .skippedPermission:
            return .skipped
        case .error:
            return .error
        }
    }
}

#if DEBUG
#Preview {
    WatchdogView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
#endif
