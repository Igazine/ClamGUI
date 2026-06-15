//
//  ScanEngineManager.swift
//  ClamGUI
//
//  Selects and owns the active malware scanner backend.
//

import Foundation

actor ScanEngineManager {
    static let shared = ScanEngineManager()

    private let nativeScanner = LibClamAVScanner()
    private var activeScanner: MalwareScanner?

    private init() {}

    func prepareScanner() async -> ScannerPreparationStatus {
        do {
            try await nativeScanner.prepare()
            activeScanner = nativeScanner
            return ScannerPreparationStatus(
                isReady: true,
                isRuntimeAvailable: true,
                backend: .nativeLibClamAV,
                message: "Native libclamav scanner ready"
            )
        } catch {
            activeScanner = nil
            return ScannerPreparationStatus(
                isReady: false,
                isRuntimeAvailable: Self.isRuntimeAvailable(after: error),
                backend: nil,
                message: error.localizedDescription
            )
        }
    }

    func scanFile(at path: String, progressHandler: (@Sendable (ScanProgressUpdate) -> Void)? = nil) async -> ClamAVManager.ScanResult {
        guard let activeScanner else {
            return ClamAVManager.ScanResult(filePath: path, status: .error, threatName: "No scanner backend is ready", timestamp: Date())
        }

        return await activeScanner.scanFile(at: path, progressHandler: progressHandler)
    }

    func reloadSignatures() async throws {
        guard let activeScanner else {
            throw MalwareScannerError.unavailable("No scanner backend is ready")
        }

        try await activeScanner.reloadSignatures()
    }

    func shutdown() async {
        await activeScanner?.shutdown()
        activeScanner = nil
    }

    func activeBackend() async -> ScannerBackend? {
        activeScanner?.backend
    }

    private static func isRuntimeAvailable(after error: Error) -> Bool {
        guard let scannerError = error as? MalwareScannerError else {
            return false
        }

        switch scannerError {
        case .unavailable:
            return false
        case .initializationFailed, .signatureLoadFailed, .engineCompileFailed:
            return true
        }
    }
}
