//
//  DirectoryWatcher.swift
//  ClamGUI
//
//  Watches a directory for file system changes using polling
//

import Foundation
import AppKit

/// Monitors a directory for new files using file polling
class DirectoryWatcher: ObservableObject {
    @Published var watchDirectory: String = ""
    @Published var isWatching = false
    @Published var recordCount: Int = 0
    @Published var threatsCount: Int = 0

    // Callbacks
    var onFileAdded: ((URL) -> Void)?
    var onFileModified: ((URL) -> Void)?
    var onFileDeleted: ((URL) -> Void)?
    var onScanExistingFiles: (() async -> Void)?
    var onDatabaseStatsUpdate: ((Int, Int) -> Void)?

    // Polling timer
    private var timer: Timer?
    private let pollInterval: TimeInterval = 2.0
    
    // Track known files for change detection
    private var knownFiles: [String: FileState] = [:]
    private let knownFilesLock = NSLock()

    // Debouncing for file modifications
    private var pendingModifications: Set<String> = []
    private let modificationLock = NSLock()
    private let modificationDebounceInterval: TimeInterval = 0.5

    deinit {
        stopWatching()
    }

    func startWatching() {
        guard !watchDirectory.isEmpty, !isWatching else { return }

        guard let initialFiles = snapshotFiles() else {
            print("Cannot watch unavailable directory: \(watchDirectory)")
            return
        }

        knownFilesLock.lock()
        knownFiles = initialFiles
        knownFilesLock.unlock()
        
        isWatching = true
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.performPoll()
        }

        Task { @MainActor in
            await onScanExistingFiles?()
        }
        
        print("Started watching: \(watchDirectory)")
    }

    func stopWatching() {
        timer?.invalidate()
        timer = nil
        isWatching = false
        knownFilesLock.lock()
        knownFiles.removeAll()
        knownFilesLock.unlock()
        print("Stopped watching")
    }

    private func performPoll() {
        guard let currentFiles = snapshotFiles() else {
            return
        }

        knownFilesLock.lock()
        
        for (path, state) in currentFiles {
            if let knownState = knownFiles[path] {
                if state.modificationDate > knownState.modificationDate || state.size != knownState.size {
                    handleFileModified(path: path)
                }
            } else {
                handleFileAdded(path: path)
            }
        }
        
        for path in knownFiles.keys where currentFiles[path] == nil {
            handleFileDeleted(path: path)
        }
        
        knownFiles = currentFiles
        knownFilesLock.unlock()
    }

    private func snapshotFiles() -> [String: FileState]? {
        let directoryURL = URL(fileURLWithPath: watchDirectory)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles],
            errorHandler: nil
        ) else { return nil }

        var files: [String: FileState] = [:]

        for case let fileURL as URL in enumerator {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) && isDirectory.boolValue {
                continue
            }

            guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path) else { continue }

            let modDate = attrs[.modificationDate] as? Date ?? Date.distantPast
            let fileSize = attrs[.size] as? UInt64 ?? 0

            files[fileURL.path] = FileState(modificationDate: modDate, size: fileSize)
        }

        return files
    }

    private func handleFileAdded(path: String) {
        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.asyncAfter(deadline: .now() + modificationDebounceInterval) { [weak self] in
            guard let self = self, FileManager.default.fileExists(atPath: path) else { return }
            // Don't enqueue here - let WatchdogView handle queueing via onFileAdded callback
            Task { @MainActor in self.onFileAdded?(url) }
        }
    }

    private func handleFileModified(path: String) {
        modificationLock.lock()
        let alreadyPending = pendingModifications.contains(path)
        if !alreadyPending { pendingModifications.insert(path) }
        modificationLock.unlock()
        guard !alreadyPending else { return }

        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.asyncAfter(deadline: .now() + modificationDebounceInterval) { [weak self] in
            guard let self = self else { return }
            self.modificationLock.lock()
            self.pendingModifications.remove(path)
            self.modificationLock.unlock()
            guard FileManager.default.fileExists(atPath: path) else { return }
            Task { @MainActor in self.onFileModified?(url) }
        }
    }

    private func handleFileDeleted(path: String) {
        let url = URL(fileURLWithPath: path)
        let folderId: Int64 = 1
        Task { @MainActor in
            await ScanResultsDatabase.shared.removeRecord(path: path, folderId: folderId)
            self.onFileDeleted?(url)
        }
    }

    func updateDatabaseStats() async {
        let folderId: Int64 = 1
        let count = ScanResultsDatabase.shared.getRecordCount(folderId: folderId)
        let threats = ScanResultsDatabase.shared.getInfectedFiles(folderId: folderId).count
        await MainActor.run {
            self.recordCount = count
            self.threatsCount = threats
            self.onDatabaseStatsUpdate?(count, threats)
        }
    }
}

private struct FileState: Equatable {
    let modificationDate: Date
    let size: UInt64
}
