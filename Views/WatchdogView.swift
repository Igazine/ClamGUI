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
    @StateObject private var directoryWatcher = DirectoryWatcher()
    @StateObject private var threatHandler = ThreatActionHandler.shared
    @State private var isWatching = false
    @State private var filesScanned: Int = 0
    @State private var filesSkipped: Int = 0
    @State private var threatsCount: Int = 0
    @State private var recordCount: Int = 0
    @State private var showingFoundThreats = false
    @State private var hasShownInitialModal = false  // Track if we've shown modal for initial scan threats
    
    // Junction n12 logic: If Daemon is running and Directory is set, start watching automatically
    @State private var shouldAutoStart = false

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
                    .disabled(settingsManager.watchDirectory.isEmpty)
            }
            
            // Daemon Gate / Junction n12 Logic
            .onChange(of: clamAVManager.isClamdRunning) { isRunning in
                if isRunning && !settingsManager.watchDirectory.isEmpty && !shouldAutoStart {
                    shouldAutoStart = true
                    isWatching = true
                }
            }
            
            // Ensure we check on appear too (in case it's already running)
            .onAppear {
                if clamAVManager.isClamdRunning && !settingsManager.watchDirectory.isEmpty && !shouldAutoStart {
                    shouldAutoStart = true
                    isWatching = true
                }
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
                }

                Spacer()

                // Queue status
                if isWatching {
                    HStack(spacing: 5) {
                        if queueStatus == .scanning {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Scanning...")
                                .foregroundColor(.blue)
                        } else if queueStatus == .suspended {
                            Image(systemName: "pause.fill")
                                .foregroundColor(.orange)
                            Text("Suspended")
                                .foregroundColor(.orange)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Idle")
                                .foregroundColor(.green)
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(isWatching ? Color.green.opacity(0.1) : Color.gray.opacity(0.1))
            .cornerRadius(8)

            // Currently scanning file display
            if isWatching, let currentFile = currentScanningFile {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Currently Scanning")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundColor(.blue)

                        Text(currentFile)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
                }
                .padding(.horizontal)
            }
        }
        .frame(maxWidth: 800)
        .padding()
        .onAppear {
            setupDirectoryWatcher()
        }
        .onChange(of: isWatching) { newValue in
            if newValue {
                directoryWatcher.startWatching()
            } else {
                directoryWatcher.stopWatching()
            }
        }
        .onChange(of: settingsManager.watchDirectory) { _ in
            setupDirectoryWatcher()
        }
        .sheet(isPresented: $showingFoundThreats) {
            FoundThreatsSheet()
        }
        .sheet(isPresented: $threatHandler.showingThreatModal) {
            ThreatActionModal()
        }
    }

    // MARK: - Computed Properties

    @State private var currentScanningFile: String?
    @State private var queueStatus: ScanQueueStatus = .idle

    private var statusText: String {
        if !isWatching {
            return "Watchdog inactive"
        }
        if queueStatus == .suspended {
            return "Queue suspended - waiting for action"
        }
        return isWatching ? "Watching for new files..." : "Watchdog inactive"
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
        guard !settingsManager.watchDirectory.isEmpty else { return }

        directoryWatcher.watchDirectory = settingsManager.watchDirectory

        // Handle new file added
        directoryWatcher.onFileAdded = { url in
            Task { @MainActor in
                await scanNewFile(at: url)
            }
        }

        // Handle file modified
        directoryWatcher.onFileModified = { url in
            Task { @MainActor in
                await handleModifiedFile(at: url)
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

        // Update UI with queue status
        updateQueueStatus()
    }

    /// Update queue status display and threat counts
    private func updateQueueStatus() {
        Task {
            while true {
                await MainActor.run {
                    currentScanningFile = QueueManager.shared.currentScanningFile
                    queueStatus = QueueManager.shared.scanStatus
                }
                try? await Task.sleep(nanoseconds: 500_000_000)  // Update every 500ms
                
                // Periodically refresh threats count
                if isWatching {
                    await updateThreatsCount()
                }
            }
        }
    }

    /// Update threats count and record count
    private func updateThreatsCount() {
        let folderId: Int64 = 1
        Task {
            let threats = await ScanResultsDatabase.shared.getInfectedFiles(folderId: folderId)
            let records = await ScanResultsDatabase.shared.getRecordCount(folderId: folderId)
            await MainActor.run {
                threatsCount = threats.count
                recordCount = records
            }
        }
    }

    /// Scan all existing files in the watched directory
    private func scanExistingFiles() async {
        guard let _ = URL(string: settingsManager.watchDirectory) else { return }
        let folderId: Int64 = 1  // Single folder, ID = 1

        let fileManager = FileManager.default
        var filesScannedCount = 0
        var filesSkippedCount = 0

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
                
                // Check if file needs scanning
                let needsScan = await ScanResultsDatabase.shared.needsScan(fileURL.path, folderId: folderId)

                if !needsScan {
                    filesSkippedCount += 1
                    continue
                }

                // Scan the file
                let result = await clamAVManager.scanFile(at: fileURL.path)
                print("🔍 scanExistingFiles: path=\(fileURL.path), status=\(result.status), threat=\(result.threatName ?? "nil")")
                filesScannedCount += 1
                
                // Record result in database (single table!)
                let status: ScanStatus = result.status == .clean ? .clean : (result.status == .infected ? .infected : .error)
                print("📝 Recording: path=\(fileURL.path), status=\(status.rawValue), folderId=\(folderId)")
                await ScanResultsDatabase.shared.recordScan(
                    path: fileURL.path,
                    folderId: folderId,
                    status: status,
                    threatName: result.threatName
                )
                
                // Verify record was created
                let stillNeedsScan = await ScanResultsDatabase.shared.needsScan(fileURL.path, folderId: folderId)
                print("🔍 After record: stillNeedsScan=\(stillNeedsScan)")
                
                // Check infected files
                let infected = await ScanResultsDatabase.shared.getInfectedFiles(folderId: folderId)
                print("🔍 After record: infected count=\(infected.count)")
                for inf in infected {
                    print("   - \(inf.path) -> \(inf.status.rawValue)")
                }
                
                // If infected, show modal (only once for initial scan)
                if case .infected = result.status {
                    print("🦠 scanExistingFiles: Infected! hasShownInitialModal=\(hasShownInitialModal)")
                    updateThreatsCount()
                    if !hasShownInitialModal {
                        hasShownInitialModal = true
                        print("🦠 scanExistingFiles: Calling handleThreatDetected")
                        await ThreatActionHandler.shared.handleThreatDetected(
                            filePath: fileURL.path,
                            threatName: result.threatName ?? "Unknown"
                        )
                    } else {
                        print("🦠 scanExistingFiles: NOT calling handleThreatDetected, already shown")
                    }
                }
            }
        }

        // Update counts
        await MainActor.run {
            self.filesScanned = filesScannedCount
            self.filesSkipped = filesSkippedCount
        }

        updateThreatsCount()

        print("Scanned \(filesScannedCount) existing files, skipped \(filesSkippedCount) unchanged files")
    }

    private func scanNewFile(at url: URL) async {
        let folderId: Int64 = 1  // Single folder, ID = 1

        // Check if file needs scanning
        let needsScan = await ScanResultsDatabase.shared.needsScan(url.path, folderId: folderId)

        if !needsScan {
            print("Skipping unchanged file: \(url.path)")
            await MainActor.run {
                filesSkipped += 1
            }
            return
        }

        // File needs scanning - update counter
        await MainActor.run {
            filesScanned += 1
        }
        
        let result = await clamAVManager.scanFile(at: url.path)
        let status: ScanStatus = result.status == .clean ? .clean : (result.status == .infected ? .infected : .error)
        await ScanResultsDatabase.shared.recordScan(
            path: url.path,
            folderId: folderId,
            status: status,
            threatName: result.threatName
        )

        if case .infected = result.status {
            if SettingsManager.shared.showNotifications {
                NotificationManager.shared.showThreatNotification(
                    fileName: url.lastPathComponent,
                    threatName: result.threatName ?? "Unknown"
                )
                MenuBarManager.shared.notifyThreatFound()
            }

            updateThreatsCount()
            await ThreatActionHandler.shared.handleThreatDetected(
                filePath: url.path,
                threatName: result.threatName ?? "Unknown"
            )
        }
    }

    private func handleModifiedFile(at url: URL) async {
        let folderId: Int64 = 1
        print("File modified: \(url.path)")

        let result = await clamAVManager.scanFile(at: url.path)
        let status: ScanStatus = result.status == .clean ? .clean : (result.status == .infected ? .infected : .error)
        await ScanResultsDatabase.shared.recordScan(
            path: url.path,
            folderId: folderId,
            status: status,
            threatName: result.threatName
        )

        if case .infected = result.status {
            if SettingsManager.shared.showNotifications {
                NotificationManager.shared.showThreatNotification(
                    fileName: url.lastPathComponent,
                    threatName: result.threatName ?? "Unknown"
                )
            }
            updateThreatsCount()
            await ThreatActionHandler.shared.handleThreatDetected(
                filePath: url.path,
                threatName: result.threatName ?? "Unknown"
            )
        }
    }

    private func handleDeletedFile(at url: URL) async {
        let folderId: Int64 = 1
        print("File deleted: \(url.path)")
        
        // Remove from database
        await ScanResultsDatabase.shared.removeRecord(path: url.path, folderId: folderId)
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

#Preview {
    WatchdogView()
        .environmentObject(ClamAVManager.shared)
        .environmentObject(SettingsManager.shared)
}
