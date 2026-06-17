//
//  QuarantineManager.swift
//  ClamGUI
//
//  Manages quarantine of infected files
//

import Foundation
import AppKit

/// Check if a URL is on a local volume (not network)
private func isLocalVolume(_ url: URL) -> Bool {
    do {
        let values = try url.resourceValues(forKeys: [.volumeIsLocalKey])
        return values.volumeIsLocal ?? true
    } catch {
        return true
    }
}

/// Check if two URLs are on the same volume
private func isSameVolume(_ url1: URL, _ url2: URL) -> Bool {
    // Ensure both paths exist
    if !FileManager.default.fileExists(atPath: url1.path) {
        print("⚠️ isSameVolume: url1 doesn't exist: \(url1.path)")
        return false
    }
    if !FileManager.default.fileExists(atPath: url2.path) {
        try? FileManager.default.createDirectory(at: url2, withIntermediateDirectories: true)
    }
    
    do {
        let attr1 = try FileManager.default.attributesOfItem(atPath: url1.path)
        let attr2 = try FileManager.default.attributesOfItem(atPath: url2.path)
        
        // Use .systemNumber - unique volume ID (works on APFS too)
        guard let sysNum1 = attr1[.systemNumber] as? NSNumber,
              let sysNum2 = attr2[.systemNumber] as? NSNumber else {
            print("⚠️ isSameVolume: Could not get system number")
            return true  // Assume same volume if we can't check
        }
        
        let result = sysNum1.int64Value == sysNum2.int64Value
        print("🔍 isSameVolume: sysNum1=\(sysNum1.int64Value), sysNum2=\(sysNum2.int64Value), same=\(result)")
        return result
    } catch {
        print("⚠️ isSameVolume error: \(error.localizedDescription)")
        return true  // Assume same volume on error
    }
}

/// Format file size for display
func formatFileSize(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}

/// Get file size in bytes
func getFileSize(at url: URL) -> UInt64? {
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        return attrs[.size] as? UInt64
    } catch {
        return nil
    }
}

/// Manages quarantine operations for infected files
@MainActor
class QuarantineManager: ObservableObject {
    static let shared = QuarantineManager()
    
    @Published var isQuarantining = false
    @Published var quarantinedFiles: [QuarantinedFile] = []
    
    private init() {
        loadQuarantinedFiles()
    }
    
    // MARK: - Public Methods

    /// Quarantine an infected file
    /// Returns true on success, false on failure
    func quarantineFile(at path: String, threatName: String, progress: ((Double) -> Void)? = nil) async -> Bool {
        isQuarantining = true
        
        defer {
            isQuarantining = false
        }

        let sourceURL = URL(fileURLWithPath: path)
        let settings = SettingsManager.shared
        let quarantineDir = settings.quarantinePath
        let quarantineURL = URL(fileURLWithPath: quarantineDir)

        // Ensure quarantine directory exists
        try? FileManager.default.createDirectory(atPath: quarantineDir, withIntermediateDirectories: true)

        // Check if file is on network drive
        guard isLocalVolume(sourceURL) else {
            print("⚠️ Cannot quarantine file on network drive: \(path)")
            return false
        }

        // Check if cross-volume quarantine
        let isCrossVolume = !isSameVolume(sourceURL, quarantineURL)
        
        let fileName = sourceURL.lastPathComponent
        let quarantineId = UUID()
        let quarantinedFileName = "\(quarantineId.uuidString)_\(fileName)"
        let destinationURL = quarantineURL.appendingPathComponent(quarantinedFileName)

        do {
            if isCrossVolume {
                // Cross-volume: copy with progress, then delete original
                print("⚠️ Cross-volume quarantine detected: copying with progress...")
                try await copyFileWithProgress(
                    from: sourceURL,
                    to: destinationURL,
                    progress: progress
                )
                // Delete original after successful copy
                try FileManager.default.removeItem(at: sourceURL)
            } else {
                // Same volume: instant metadata-only move
                try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
                progress?(1.0)
            }

            hardenQuarantinedFile(at: destinationURL)

            // Record quarantine operation
            let quarantinedFile = QuarantinedFile(
                id: quarantineId,
                originalPath: path,
                quarantinePath: destinationURL.path,
                threatName: threatName,
                quarantineDate: Date(),
                fileSize: try destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            )

            saveQuarantinedFile(quarantinedFile)

            print("File quarantined: \(path) -> \(destinationURL.path)")
            return true

        } catch {
            print("Failed to quarantine file: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Check if file can be quarantined (not on network drive)
    func canQuarantineFile(at path: String) -> Bool {
        let sourceURL = URL(fileURLWithPath: path)
        return isLocalVolume(sourceURL)
    }
    
    /// Check if quarantine will be cross-volume
    func isCrossVolumeQuarantine(at path: String) -> Bool {
        let sourceURL = URL(fileURLWithPath: path)
        let quarantineURL = URL(fileURLWithPath: SettingsManager.shared.quarantinePath)
        return !isSameVolume(sourceURL, quarantineURL)
    }
    
    /// Restore a quarantined file to original location
    func restoreFile(_ quarantinedFile: QuarantinedFile) async -> Bool {
        let destinationURL = URL(fileURLWithPath: quarantinedFile.originalPath)
        let sourceURL = URL(fileURLWithPath: quarantinedFile.quarantinePath)
        
        // Ensure destination directory exists
        let destinationDir = destinationURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        
        do {
            guard FileManager.default.fileExists(atPath: sourceURL.path) else {
                removeQuarantinedFile(quarantinedFile)
                return false
            }

            guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
                print("Failed to restore file: destination already exists")
                return false
            }

            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
            removeQuarantinedFile(quarantinedFile)
            print("File restored: \(quarantinedFile.quarantinePath) -> \(quarantinedFile.originalPath)")
            return true
        } catch {
            print("Failed to restore file: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Delete a quarantined file permanently
    @discardableResult
    func deleteFile(_ quarantinedFile: QuarantinedFile) async -> Bool {
        let sourceURL = URL(fileURLWithPath: quarantinedFile.quarantinePath)
        
        do {
            if FileManager.default.fileExists(atPath: sourceURL.path) {
                try FileManager.default.removeItem(at: sourceURL)
            }
            removeQuarantinedFile(quarantinedFile)
            print("File deleted from quarantine: \(quarantinedFile.quarantinePath)")
            return true
        } catch {
            print("Failed to delete quarantined file: \(error.localizedDescription)")
            return false
        }
    }
    
    /// Delete all quarantined files
    func deleteAllFiles() async {
        for file in quarantinedFiles {
            await deleteFile(file)
        }
    }
    
    /// Get quarantine directory
    func getQuarantineDirectory() -> String {
        return SettingsManager.shared.quarantinePath
    }
    
    /// Open quarantine directory in Finder
    func openQuarantineDirectory() {
        let path = getQuarantineDirectory()
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    // MARK: - Private Methods
    
    /// Copy file with progress updates
    private func copyFileWithProgress(
        from sourceURL: URL,
        to destURL: URL,
        progress: ((Double) -> Void)?
    ) async throws {
        let fileSize = try FileManager.default.attributesOfItem(atPath: sourceURL.path)[.size] as? UInt64 ?? 0
        
        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? sourceHandle.close() }
        
        FileManager.default.createFile(atPath: destURL.path, contents: nil)
        let destHandle = try FileHandle(forWritingTo: destURL)
        defer { try? destHandle.close() }
        
        let chunkSize: UInt64 = 10 * 1024 * 1024 // 10MB chunks
        var bytesCopied: UInt64 = 0
        
        while true {
            let data = sourceHandle.readData(ofLength: Int(chunkSize))
            if data.isEmpty { break }
            
            try destHandle.write(contentsOf: data)
            bytesCopied += UInt64(data.count)
            
            let percent = Double(bytesCopied) / Double(fileSize)
            progress?(percent)
        }
    }
    
    private func hardenQuarantinedFile(at url: URL) {
        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path
            )
        } catch {
            print("Failed to harden quarantined file permissions: \(error.localizedDescription)")
        }
    }

    private var manifestURL: URL {
        let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
        return URL(fileURLWithPath: homeDir)
            .appendingPathComponent("Library/Application Support/ClamGUI/quarantine_manifest.json")
    }

    private func loadQuarantinedFiles() {
        let url = manifestURL
        guard let data = try? Data(contentsOf: url) else {
            quarantinedFiles = []
            return
        }

        do {
            quarantinedFiles = try JSONDecoder().decode([QuarantinedFile].self, from: data)
        } catch {
            print("Failed to load quarantine manifest: \(error.localizedDescription)")
            quarantinedFiles = []
        }
    }
    
    private func saveQuarantinedFile(_ file: QuarantinedFile) {
        quarantinedFiles.append(file)
        persistQuarantineManifest()
    }
    
    private func removeQuarantinedFile(_ file: QuarantinedFile) {
        quarantinedFiles.removeAll { $0.id == file.id }
        persistQuarantineManifest()
    }

    private func persistQuarantineManifest() {
        let url = manifestURL

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(quarantinedFiles)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Failed to save quarantine manifest: \(error.localizedDescription)")
        }
    }
}

// MARK: - Models

/// Represents a quarantined file
struct QuarantinedFile: Identifiable, Codable, Equatable {
    let id: UUID
    let originalPath: String
    let quarantinePath: String
    let threatName: String
    let quarantineDate: Date
    let fileSize: Int
}
