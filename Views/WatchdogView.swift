//
//  WatchdogView.swift
//  ClamGUI
//
//  UI for directory watching and automatic scanning
//

import SwiftUI
import UniformTypeIdentifiers

struct WatchdogView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var clamAVManager: ClamAVManager
    let onThreatCountChanged: ((Int) -> Void)?
    @StateObject private var directoryWatcher = DirectoryWatcher()
    @StateObject private var threatHandler = ThreatActionHandler.shared
    @State private var isWatching = false
    @State private var filesScanned: Int = 0
    @State private var filesSkipped: Int = 0
    @State private var threatsCount: Int = 0
    @State private var recordCount: Int = 0
    @State private var showingFoundThreats = false
    @State private var hasShownInitialModal = false  // Track if we've shown modal for initial scan threats
    @State private var scanQueue: [WatchdogScanRequest] = []
    @State private var queuedScanPaths: Set<String> = []
    @State private var isProcessingScanQueue = false
    
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
                isWatching = false
                directoryWatcher.stopWatching()
            }
        }
        .onChange(of: isWatching) { newValue in
            if newValue {
                setupDirectoryWatcher()
                directoryWatcher.startWatching()
            } else {
                directoryWatcher.stopWatching()
            }
        }
        .onChange(of: settingsManager.watchDirectory) { _ in
            let shouldResume = isWatching
            if isWatching {
                isWatching = false
                directoryWatcher.stopWatching()
            }
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
            return " "
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

        // Handle new file added
        directoryWatcher.onFileAdded = { url in
            Task { @MainActor in
                enqueueScan(at: url, reason: .added)
            }
        }

        // Handle file modified
        directoryWatcher.onFileModified = { url in
            Task { @MainActor in
                enqueueScan(at: url, reason: .modified)
            }
        }

        // Handle file deleted
        directoryWatcher.onFileDeleted = { url in
            Task { @MainActor in
                await handleDeletedFile(at: url)
            }
        }

        // Scan existing files when watcher starts
        directoryWatcher.onScanExistingFiles = { [self] in
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
        isWatching = true
        directoryWatcher.startWatching()
    }

    private func resetWatchdogCounters() {
        filesScanned = 0
        filesSkipped = 0
        threatsCount = 0
        recordCount = 0
        currentScanningFile = nil
        scanQueue.removeAll()
        queuedScanPaths.removeAll()
        isProcessingScanQueue = false
        hasShownInitialModal = false
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
              isDirectory.boolValue else { return }

        let fileManager = FileManager.default
        print("Scanning existing files in: \(settingsManager.watchDirectory)")

        // Enumerate all files in directory
        if let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: settingsManager.watchDirectory),
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) {
            let files = Array(enumerator).compactMap { $0 as? URL }

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

        print("Queued existing files for Watchdog scan")
    }

    private func enqueueScan(at url: URL, reason: WatchdogScanReason) {
        guard settingsManager.autoScanOnFileAdded else {
            print("Auto-scan disabled, ignoring file: \(url.path)")
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return
        }

        if isDirectory.boolValue {
            enqueueDirectoryContents(at: url, reason: reason)
            return
        }

        guard !settingsManager.shouldIgnoreFileForScanning(url) else {
            return
        }

        guard queuedScanPaths.insert(url.path).inserted else {
            return
        }

        scanQueue.append(WatchdogScanRequest(url: url, reason: reason))
        processScanQueueIfNeeded()
    }

    private func enqueueDirectoryContents(at directoryURL: URL, reason: WatchdogScanReason) {
        guard let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else {
            return
        }

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
                continue
            }

            enqueueScan(at: fileURL, reason: reason)
        }
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
        }
    }

    private func scanQueuedFile(_ request: WatchdogScanRequest) async {
        let url = request.url

        guard FileManager.default.fileExists(atPath: url.path) else {
            return
        }

        guard !settingsManager.shouldIgnoreFileForScanning(url) else {
            return
        }

        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            enqueueDirectoryContents(at: url, reason: request.reason)
            return
        }

        let folderId: Int64 = 1
        if request.reason == .existing,
           let record = ScanResultsDatabase.shared.getRecord(url.path, folderId: folderId),
           record.status == .clean,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            print("Skipping unchanged existing file: \(url.path)")
            filesSkipped += 1
            return
        }

        if request.reason == .added,
           let record = ScanResultsDatabase.shared.getRecord(url.path, folderId: folderId),
           record.status == .clean,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            print("Skipping unchanged clean file: \(url.path)")
            filesSkipped += 1
            return
        }

        if request.reason.requiresStabilityCheck,
           !ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId) {
            return
        }

        if request.reason.requiresStabilityCheck {
            guard await waitForStableFile(at: url) else {
                return
            }
        }

        currentScanningFile = url.path
        let result = await clamAVManager.scanFile(at: url.path)
        currentScanningFile = nil
        if result.status == .skippedTooLarge {
            filesSkipped += 1
        } else if result.status != .error {
            filesScanned += 1
        }
        await recordWatchdogScanResult(
            result,
            showNotification: request.reason != .existing,
            limitInitialModal: request.reason == .existing
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
        limitInitialModal: Bool
    ) async {
        let folderId: Int64 = 1
        print("Watchdog scan result: \(result.filePath) status=\(result.status) threat=\(result.threatName ?? "none")")

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

        if limitInitialModal {
            if !hasShownInitialModal {
                hasShownInitialModal = true
                await ThreatActionHandler.shared.handleThreatDetected(
                    filePath: result.filePath,
                    threatName: result.threatName ?? "Unknown"
                )
            }
        } else {
            await ThreatActionHandler.shared.handleThreatDetected(
                filePath: result.filePath,
                threatName: result.threatName ?? "Unknown"
            )
        }
    }

    private func handleDeletedFile(at url: URL) async {
        print("File deleted: \(url.path)")
        updateThreatsCount()
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

private enum WatchdogScanReason {
    case existing
    case added
    case modified

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

#Preview {
    WatchdogView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
