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
            case error
        }
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - ClamAV Installation Check

    func checkClamAVInstallation() async {
        let status = await ScanEngineManager.shared.prepareScanner()

        if status.isReady {
            isClamAVInstalled = true
            isScannerReady = true
            activeScannerName = status.backend?.rawValue ?? "Unknown"
            scannerStatusMessage = status.message
            return
        }

        isClamAVInstalled = false
        isScannerReady = false
        activeScannerName = "Unavailable"
        scannerStatusMessage = status.message
        print("Native scanner unavailable: \(status.message)")
    }

    func openClamAVInstallationPage() {
        if let url = URL(string: "https://docs.clamav.net/manual/Installing.html") {
            NSWorkspace.shared.open(url)
        }
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
