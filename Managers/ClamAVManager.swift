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

    @Published var isScannerRuntimeAvailable = false
    @Published var isScannerReady = false
    @Published var isScanning = false
    @Published var currentScanProgress: ScanProgressUpdate?
    @Published var currentScanProgressMessage: String = ""
    @Published var lastScanResult: ScanResult?
    @Published var virusDefinitionsVersion: String = "Unknown"
    @Published var virusDefinitionsOutdated = false
    @Published var activeScannerName: String = "Unavailable"
    @Published var scannerStatusMessage: String = "Scanner not initialized"
    @Published var isUpdatingVirusDefinitions = false
    @Published var virusDefinitionsUpdateMessage: String?

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
            case skippedTooLarge
            case error
        }
    }

    static let maxScannableFileSizeBytes: UInt64 = 2 * 1024 * 1024 * 1024

    private enum ScanPreflightFailure {
        case error(String)
        case skippedTooLarge(String)

        var status: ScanResult.ScanStatus {
            switch self {
            case .error:
                return .error
            case .skippedTooLarge:
                return .skippedTooLarge
            }
        }

        var message: String {
            switch self {
            case .error(let message), .skippedTooLarge(let message):
                return message
            }
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - ClamAV Installation Check

    func checkClamAVInstallation() async {
        try? await SignatureDatabaseManager.shared.bootstrapBundledDatabaseIfNeeded()
        let status = await ScanEngineManager.shared.prepareScanner()

        if status.isReady {
            isScannerRuntimeAvailable = true
            isScannerReady = true
            activeScannerName = status.backend?.rawValue ?? "Unknown"
            scannerStatusMessage = status.message
            return
        }

        isScannerRuntimeAvailable = status.isRuntimeAvailable
        isScannerReady = false
        activeScannerName = "Unavailable"
        scannerStatusMessage = status.message
        print("Native scanner unavailable: \(status.message)")
    }

    /// Shut down the active scanner runtime without probing or starting fallbacks.
    func shutdownScannerRuntime() async {
        await ScanEngineManager.shared.shutdown()
        isScannerReady = false
        activeScannerName = "Unavailable"
        scannerStatusMessage = "Scanner shut down"
    }

    // MARK: - File Scanning

    /// Scan a single file and wait for the result.
    func scanFile(at path: String) async -> ScanResult {
        if let preflightFailure = validateScannableFile(at: path) {
            let result = ScanResult(
                filePath: path,
                status: preflightFailure.status,
                threatName: preflightFailure.message,
                timestamp: Date()
            )
            lastScanResult = result
            return result
        }

        isScanning = true
        currentScanProgress = ScanProgressUpdate(inspectedObjects: 0, recursionLevel: 0, fileType: nil)
        currentScanProgressMessage = currentScanProgress?.displayMessage ?? "Preparing scan..."
        defer {
            isScanning = false
            currentScanProgress = nil
            currentScanProgressMessage = ""
        }

        let result = await ScanEngineManager.shared.scanFile(at: path) { [weak self] update in
            Task { @MainActor in
                guard let self, self.isScanning else { return }
                self.currentScanProgress = update
                self.currentScanProgressMessage = update.displayMessage
            }
        }

        lastScanResult = result

        return result
    }

    private func validateScannableFile(at path: String) -> ScanPreflightFailure? {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false

        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return .error("File does not exist")
        }

        guard !isDirectory.boolValue else {
            return .error("Manual scan expects a file, not a directory")
        }

        guard fileManager.isReadableFile(atPath: path) else {
            return .error("ClamGUI cannot read this file with current permissions")
        }

        if let size = (try? fileManager.attributesOfItem(atPath: path)[.size]) as? UInt64,
           size > Self.maxScannableFileSizeBytes {
            return .skippedTooLarge("Not scanned: exceeds ClamAV's 2 GB engine limit")
        }

        return nil
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
}

extension ClamAVManager.ScanResult {
    var databaseStatus: ClamGUI.ScanStatus {
        switch status {
        case .clean:
            return .clean
        case .infected:
            return .infected
        case .skippedTooLarge:
            return .skippedTooLarge
        case .error:
            return .error
        }
    }
}
